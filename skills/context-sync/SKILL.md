---
name: context-sync
description: Extract learnings from recent Claude Code sessions and persist them to the project's .claude/learnings.md file for future sessions.
---

# Context Sync

Extracts valuable learnings from your Claude Code sessions and saves them to the project repository, so future sessions start with accumulated context.

## When This Skill Applies

- User invokes `/context-sync`
- User asks to "sync context" or "extract learnings"
- User wants to save what was learned in a session

## Arguments

- `--dry-run`: Show extracted learnings without committing
- No arguments: Extract, commit, and push

## Workflow

### 1. Find Session Data

```bash
# Get current project path
PROJECT_PATH=$(pwd)

# Encode path for Claude's session directory
# /data/repos/codebox -> -data-repos-codebox
ENCODED_PATH=$(echo "$PROJECT_PATH" | sed 's|/|-|g')

# Session directory
SESSION_DIR="$HOME/.claude/projects/$ENCODED_PATH"
```

Check if session directory exists:
```bash
if [ ! -d "$SESSION_DIR" ]; then
    echo "No sessions found for this project."
    exit 0
fi
```

### 2. Read Session Index

```bash
# Read sessions-index.json
SESSION_INDEX="$SESSION_DIR/sessions-index.json"
if [ ! -f "$SESSION_INDEX" ]; then
    echo "No session index found."
    exit 0
fi
```

### 3. Filter Recent Sessions

Get sessions from the last 4 hours, excluding active ones (modified < 60s ago):

```bash
# Current time in seconds
NOW=$(date +%s)
FOUR_HOURS_AGO=$((NOW - 14400))
ONE_MINUTE_AGO=$((NOW - 60))

# Filter sessions using jq
jq -r --argjson start "$FOUR_HOURS_AGO" --argjson end "$ONE_MINUTE_AGO" '
  .entries[]
  | select((.fileMtime / 1000) > $start and (.fileMtime / 1000) < $end)
  | .fullPath
' "$SESSION_INDEX"
```

### 4. Extract Conversation Content

For each session file, extract user messages and assistant text responses:

```bash
extract_conversation() {
    local session_file="$1"
    jq -r '
      select(.type == "user" and (.message.content | type) == "string")
      | "USER: " + .message.content
    ' "$session_file"

    jq -r '
      select(.type == "assistant")
      | .message.content[]?
      | select(.type == "text")
      | "ASSISTANT: " + .text
    ' "$session_file"
}
```

### 5. Generate Learnings

Pass the extracted conversation to Claude with this prompt:

```
Review this Claude Code session and extract learnings that would help
a future session on this project. Focus on:

- Architecture decisions and their rationale
- Non-obvious patterns in the codebase
- Gotchas and pitfalls discovered
- Configuration/deployment knowledge
- Dependencies and their quirks

Skip:
- Specific line numbers or temporary fixes
- Debugging steps that led nowhere
- Routine operations (git commands, file reads)
- Any actual data values, credentials, or secrets

Format as a bullet list. Be concise - each learning should be 1-2 sentences.
If there are no meaningful learnings, respond with "No new learnings."
```

### 6. Security Scan

Before committing, scan the extracted learnings for potential secrets:

```bash
check_for_secrets() {
    local content="$1"

    # API key patterns (20+ alphanumeric chars)
    if echo "$content" | grep -qE '[A-Za-z0-9_-]{32,}'; then
        echo "WARNING: Possible API key detected"
        return 1
    fi

    # AWS access keys
    if echo "$content" | grep -qE 'AKIA[0-9A-Z]{16}'; then
        echo "WARNING: Possible AWS access key detected"
        return 1
    fi

    # Private keys
    if echo "$content" | grep -q 'PRIVATE KEY'; then
        echo "WARNING: Private key detected"
        return 1
    fi

    # Password patterns
    if echo "$content" | grep -qiE 'password\s*[:=]\s*\S{8,}'; then
        echo "WARNING: Possible password detected"
        return 1
    fi

    return 0
}
```

If secrets are detected:
1. Show the warning
2. Display the offending content
3. Abort and suggest manual review

### 7. Check CLAUDE.md Integration

Ensure the project's `.claude/CLAUDE.md` includes the learnings directive:

```bash
CLAUDE_MD=".claude/CLAUDE.md"
LEARNINGS_DIRECTIVE="Always read \`.claude/learnings.md\`"

if [ -f "$CLAUDE_MD" ]; then
    if ! grep -q "learnings.md" "$CLAUDE_MD"; then
        echo ""
        echo "NOTE: Add this to your .claude/CLAUDE.md to auto-load learnings:"
        echo ""
        echo "## Accumulated Learnings"
        echo ""
        echo "Always read \`.claude/learnings.md\` at the start of each session for"
        echo "context from previous work on this project."
    fi
fi
```

### 8. Persist Learnings

If not `--dry-run`:

```bash
# Create .claude directory if needed
mkdir -p .claude

# Get machine name
MACHINE=$(hostname | cut -d. -f1)
DATE=$(date +%Y-%m-%d)

# Append to learnings.md
{
    echo ""
    echo "## $DATE ($MACHINE)"
    echo ""
    echo "$LEARNINGS"
} >> .claude/learnings.md

# Git operations with retry
retry_push() {
    local attempts=0
    local max_attempts=3
    local delay=2

    while [ $attempts -lt $max_attempts ]; do
        if git push; then
            return 0
        fi
        attempts=$((attempts + 1))
        if [ $attempts -lt $max_attempts ]; then
            echo "Push failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
            git pull --rebase
        fi
    done

    echo "ERROR: Push failed after $max_attempts attempts"
    echo "Changes committed locally. Run 'git push' manually."
    return 1
}

git add .claude/learnings.md
git commit -m "sync: learnings from $MACHINE $DATE"
retry_push
```

## Output

**On success:**
```
Extracted N learnings from M sessions.
Committed to .claude/learnings.md
Pushed to origin.
```

**On dry-run:**
```
=== Extracted Learnings (dry-run) ===

- Learning 1
- Learning 2
- Learning 3

Run without --dry-run to commit and push.
```

**On no learnings:**
```
No new learnings found in recent sessions.
```

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No sessions exist | Exit with message |
| No recent sessions | Exit with message |
| Corrupted JSONL | Skip bad lines, continue |
| Secrets detected | Abort, show warning |
| No learnings extracted | Exit without commit |
| Git push fails | Retry 3x, save locally if all fail |

## Installation

Run the install script from the agent-context repo:

```bash
~/agent-context/skills/context-sync/scripts/install.sh
```

This copies the skill to `~/.claude/skills/context-sync/`.
