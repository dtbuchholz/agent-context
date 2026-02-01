#!/usr/bin/env bash
set -euo pipefail

# extract.sh - Extract learnings from Claude Code sessions
#
# Usage:
#   extract.sh [--dry-run] [--scan-only <text>] [--commit <learnings>]
#
# Modes:
#   (no args)           Extract session content for Claude to analyze
#   --dry-run           Same as above, but note that no changes will be made
#   --scan-only <text>  Scan text for secrets, exit 1 if found
#   --commit <learn>    Commit learnings to .claude/learnings.md and push
#
# This script is called by the /context-sync skill.

# Parse arguments
MODE="extract"
DRY_RUN=false
SCAN_TEXT=""
LEARNINGS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --scan-only)
            MODE="scan"
            SCAN_TEXT="$2"
            shift 2
            ;;
        --commit)
            MODE="commit"
            LEARNINGS="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# =============================================================================
# Secret Scanning
# =============================================================================

check_for_secrets() {
    local content="$1"
    local found_secrets=false

    # AWS access keys
    if echo "$content" | grep -qE 'AKIA[0-9A-Z]{16}'; then
        echo "WARNING: Possible AWS access key detected" >&2
        found_secrets=true
    fi

    # Private keys
    if echo "$content" | grep -q 'PRIVATE KEY'; then
        echo "WARNING: Private key marker detected" >&2
        found_secrets=true
    fi

    # Generic API keys (32+ char alphanumeric, common patterns)
    if echo "$content" | grep -qE '(api[_-]?key|apikey|secret[_-]?key|access[_-]?token)["\x27]?\s*[:=]\s*["\x27]?[A-Za-z0-9_-]{20,}' ; then
        echo "WARNING: Possible API key assignment detected" >&2
        found_secrets=true
    fi

    # Password assignments
    if echo "$content" | grep -qiE 'password\s*[:=]\s*["\x27]?[^\s"'\'']{8,}'; then
        echo "WARNING: Possible password assignment detected" >&2
        found_secrets=true
    fi

    # Bearer tokens
    if echo "$content" | grep -qiE 'bearer\s+[A-Za-z0-9_-]{20,}'; then
        echo "WARNING: Possible bearer token detected" >&2
        found_secrets=true
    fi

    # GitHub tokens
    if echo "$content" | grep -qE 'gh[pousr]_[A-Za-z0-9_]{36,}'; then
        echo "WARNING: Possible GitHub token detected" >&2
        found_secrets=true
    fi

    if [[ "$found_secrets" == "true" ]]; then
        return 1
    fi
    return 0
}

# Handle scan-only mode
if [[ "$MODE" == "scan" ]]; then
    if check_for_secrets "$SCAN_TEXT"; then
        echo "No secrets detected."
        exit 0
    else
        echo ""
        echo "SECRET SCAN FAILED - Review the learnings and remove sensitive data before committing."
        exit 1
    fi
fi

# =============================================================================
# Commit Mode
# =============================================================================

if [[ "$MODE" == "commit" ]]; then
    if [[ -z "$LEARNINGS" ]]; then
        echo "Error: No learnings provided to commit."
        exit 1
    fi

    # Create .claude directory if needed
    mkdir -p .claude

    # Get machine name and date
    MACHINE=$(hostname | cut -d. -f1)
    DATE=$(date +%Y-%m-%d)

    # Append to learnings.md
    {
        echo ""
        echo "## $DATE ($MACHINE)"
        echo ""
        echo "$LEARNINGS"
    } >> .claude/learnings.md

    echo "Appended learnings to .claude/learnings.md"

    # Git operations with retry
    retry_git_push() {
        local attempts=0
        local max_attempts=3
        local delay=2

        while [[ $attempts -lt $max_attempts ]]; do
            if git push 2>/dev/null; then
                return 0
            fi

            attempts=$((attempts + 1))

            if [[ $attempts -lt $max_attempts ]]; then
                echo "Push failed, retrying in ${delay}s... (attempt $attempts/$max_attempts)"
                sleep "$delay"
                delay=$((delay * 2))

                # Try to pull and rebase before retrying
                git pull --rebase 2>/dev/null || true
            fi
        done

        echo "ERROR: Push failed after $max_attempts attempts."
        echo "Changes committed locally. Run 'git push' manually."
        return 1
    }

    # Stage and commit
    git add .claude/learnings.md

    if git diff --cached --quiet; then
        echo "No changes to commit."
        exit 0
    fi

    git commit -m "sync: learnings from $MACHINE $DATE"
    echo "Committed changes."

    # Push with retry
    if retry_git_push; then
        echo "Pushed to origin."
    fi

    exit 0
fi

# =============================================================================
# Extract Mode (default)
# =============================================================================

# Get current project path
PROJECT_PATH="$(pwd)"

# Encode path for Claude's session directory
# /data/repos/codebox -> -data-repos-codebox
ENCODED_PATH=$(echo "$PROJECT_PATH" | sed 's|^/||; s|/|-|g')
ENCODED_PATH="-$ENCODED_PATH"

# Session directory
SESSION_DIR="$HOME/.claude/projects/$ENCODED_PATH"

# Check if session directory exists
if [[ ! -d "$SESSION_DIR" ]]; then
    echo "No sessions found for this project at: $SESSION_DIR"
    exit 0
fi

# Check for session index
SESSION_INDEX="$SESSION_DIR/sessions-index.json"
if [[ ! -f "$SESSION_INDEX" ]]; then
    echo "No session index found at: $SESSION_INDEX"
    exit 0
fi

# Time calculations
NOW=$(date +%s)
FOUR_HOURS_AGO=$((NOW - 14400))
ONE_MINUTE_AGO=$((NOW - 60))

# Find recent sessions (last 4 hours, excluding active ones)
get_session_files() {
    # Note: using 'cutoff' instead of 'end' to avoid jq reserved word issues
    jq -r --argjson start "$FOUR_HOURS_AGO" --argjson cutoff "$ONE_MINUTE_AGO" '
        .entries[]
        | select((.fileMtime / 1000) > $start and (.fileMtime / 1000) < $cutoff)
        | .fullPath
    ' "$SESSION_INDEX" 2>/dev/null || true
}

SESSION_FILES=$(get_session_files)

if [[ -z "$SESSION_FILES" ]]; then
    echo "No recent sessions found (looking for sessions from the last 4 hours)."
    echo ""
    echo "Tip: Run this after completing a session, not during one."
    exit 0
fi

# Count sessions
SESSION_COUNT=$(echo "$SESSION_FILES" | wc -l | tr -d ' ')
echo "Found $SESSION_COUNT recent session(s)."
echo ""

# Extract conversation content from session files
extract_conversation() {
    local session_file="$1"
    local line_num=0
    local errors=0

    if [[ ! -f "$session_file" ]]; then
        echo "Warning: Session file not found: $session_file" >&2
        return
    fi

    # Process JSONL line by line to handle corrupted lines gracefully
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Try to parse the line as JSON
        if ! echo "$line" | jq -e '.' >/dev/null 2>&1; then
            errors=$((errors + 1))
            if [[ $errors -le 3 ]]; then
                echo "Warning: Skipping corrupted line $line_num in $session_file" >&2
            fi
            continue
        fi

        # Extract user messages (string content only)
        echo "$line" | jq -r '
            select(.type == "user")
            | .message.content
            | if type == "string" then "USER: " + . else empty end
        ' 2>/dev/null || true

        # Extract assistant text responses
        echo "$line" | jq -r '
            select(.type == "assistant")
            | .message.content[]?
            | select(type == "object" and .type == "text")
            | "ASSISTANT: " + .text
        ' 2>/dev/null || true

    done < "$session_file"

    if [[ $errors -gt 3 ]]; then
        echo "Warning: Skipped $errors corrupted lines in $session_file" >&2
    fi
}

# Collect all conversation content
CONVERSATION=""
while IFS= read -r session_file; do
    if [[ -n "$session_file" ]]; then
        content=$(extract_conversation "$session_file")
        if [[ -n "$content" ]]; then
            CONVERSATION+="$content"$'\n'
        fi
    fi
done <<< "$SESSION_FILES"

if [[ -z "$CONVERSATION" ]]; then
    echo "No conversation content found in recent sessions."
    exit 0
fi

# Output for Claude to analyze
echo "=== SESSION CONTENT FOR ANALYSIS ==="
echo ""
echo "$CONVERSATION"
echo ""
echo "=== END SESSION CONTENT ==="

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "[dry-run mode - no changes will be made]"
fi
