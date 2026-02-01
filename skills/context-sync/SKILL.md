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

### 1. Extract Session Content

Run the extract script to get conversation content from recent sessions:

```bash
~/.claude/skills/context-sync/scripts/extract.sh
```

Or for dry-run mode:

```bash
~/.claude/skills/context-sync/scripts/extract.sh --dry-run
```

The script will:
- Find the session directory for the current project
- Filter sessions from the last 4 hours (excluding active ones)
- Extract user messages and assistant text responses
- Handle corrupted JSONL lines gracefully
- Output the conversation content for analysis

### 2. Generate Learnings

Analyze the extracted session content and generate learnings using this prompt:

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

### 3. Security Scan

Before committing, scan the learnings for potential secrets:

```bash
~/.claude/skills/context-sync/scripts/extract.sh --scan-only "LEARNINGS_TEXT_HERE"
```

The script checks for:
- AWS access keys (`AKIA...`)
- Private key markers
- API key assignments
- Password assignments
- Bearer tokens
- GitHub tokens

If secrets are detected:
1. The script exits with code 1
2. Show the user the warning
3. Ask them to review and remove sensitive data

### 4. Check CLAUDE.md Integration

Check if the project's `.claude/CLAUDE.md` includes the learnings directive:

```bash
if [ -f ".claude/CLAUDE.md" ]; then
    if ! grep -q "learnings.md" ".claude/CLAUDE.md"; then
        echo "NOTE: Add this to your .claude/CLAUDE.md to auto-load learnings:"
        echo ""
        echo "## Accumulated Learnings"
        echo ""
        echo "Always read \`.claude/learnings.md\` at the start of each session for"
        echo "context from previous work on this project."
    fi
fi
```

### 5. Persist Learnings

If not `--dry-run` and no secrets detected, commit the learnings:

```bash
~/.claude/skills/context-sync/scripts/extract.sh --commit "LEARNINGS_TEXT_HERE"
```

The script will:
- Create `.claude/` directory if needed
- Append learnings to `.claude/learnings.md` with timestamp and machine name
- Git add and commit
- Push with retry (3 attempts, exponential backoff)

## Script Reference

The `extract.sh` script supports three modes:

| Mode | Command | Description |
|------|---------|-------------|
| Extract | `extract.sh` | Output session content for analysis |
| Scan | `extract.sh --scan-only "text"` | Check text for secrets |
| Commit | `extract.sh --commit "learnings"` | Save learnings and push |

Add `--dry-run` to extract mode to note that changes won't be made.

## Output

**On success:**
```
Found 2 recent session(s).
Extracted learnings:
- Learning 1
- Learning 2

No secrets detected.
Appended learnings to .claude/learnings.md
Committed changes.
Pushed to origin.
```

**On dry-run:**
```
Found 2 recent session(s).

=== SESSION CONTENT FOR ANALYSIS ===
[conversation content]
=== END SESSION CONTENT ===

[dry-run mode - no changes will be made]
```

**On secrets detected:**
```
WARNING: Possible API key assignment detected

SECRET SCAN FAILED - Review the learnings and remove sensitive data before committing.
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
| Corrupted JSONL | Skip bad lines, log warning, continue |
| Secrets detected | Abort, show warning, suggest manual review |
| No learnings extracted | Exit without commit |
| Git push fails | Retry 3x with exponential backoff, save locally if all fail |

## Installation

Run the install script from the agent-context repo:

```bash
~/agent-context/skills/context-sync/scripts/install.sh
```

This copies the skill to `~/.claude/skills/context-sync/`.
