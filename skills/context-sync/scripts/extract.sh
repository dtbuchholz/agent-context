#!/usr/bin/env bash
set -euo pipefail

# extract.sh - Extract learnings from Claude Code sessions
#
# Usage:
#   extract.sh [--dry-run]
#
# This script is called by the /context-sync skill. It:
# 1. Finds recent session files for the current project
# 2. Extracts user/assistant conversation content
# 3. Outputs the content for Claude to analyze

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

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

    if [[ ! -f "$session_file" ]]; then
        echo "Warning: Session file not found: $session_file" >&2
        return
    fi

    # Extract user messages (string content only)
    jq -r '
        select(.type == "user")
        | .message.content
        | if type == "string" then "USER: " + . else empty end
    ' "$session_file" 2>/dev/null || true

    # Extract assistant text responses
    jq -r '
        select(.type == "assistant")
        | .message.content[]?
        | select(type == "object" and .type == "text")
        | "ASSISTANT: " + .text
    ' "$session_file" 2>/dev/null || true
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
