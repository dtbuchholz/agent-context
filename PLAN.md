# Context Sync - Implementation Plan

## Problem

You have 3 machines (VM, laptop, Takopi/phone) running Claude Code on the same projects. Sessions are local, paths differ across machines, and there's no native sync. Valuable learnings from one session don't carry over to the next.

## Solution

Extract high-value learnings from sessions and persist them in project repos, making them available to future sessions via CLAUDE.md.

---

## v1 Scope (Minimal Viable)

Keep it simple. One skill, one script, manual invocation.

### What's In

- `/context-sync` skill - extract learnings from recent sessions
- Append to `.claude/learnings.md` in the project repo
- Git commit and push
- Secret scanning before commit
- Dry-run mode for review

### What's Deferred to v2

- Cron jobs / automated scheduling
- Multi-machine conflict resolution
- Consolidation / deduplication pass
- Cross-project patterns directory
- Post-push git hooks
- config.toml per-machine settings

---

## Architecture

### Repository Structure

```
agent-context/
├── README.md                      # Setup & usage
├── skills/
│   └── context-sync/
│       ├── SKILL.md              # The skill definition
│       └── scripts/
│           ├── install.sh        # Copy skill to ~/.claude/skills/
│           └── extract.sh        # Core extraction logic
└── .gitignore
```

### Per-Project Structure

```
your-project/
├── .claude/
│   ├── CLAUDE.md                 # Project instructions (add learnings directive)
│   └── learnings.md              # Accumulated learnings (auto-generated)
```

---

## The Skill: `/context-sync`

### Invocation

```bash
/context-sync              # Extract and commit
/context-sync --dry-run    # Show learnings without committing
```

### Workflow

```
1. FIND SESSION DATA
   - Get project path from cwd
   - Encode path to find ~/.claude/projects/<encoded>/
   - Read sessions-index.json

2. FILTER SESSIONS
   - Last 4 hours (or all if first run)
   - Skip active sessions (modified < 60s ago)

3. EXTRACT CONTENT
   - Parse JSONL files
   - Keep user messages + assistant text
   - Skip tool calls and tool results

4. GENERATE LEARNINGS
   - Pass conversation to Claude with extraction prompt
   - Heuristic: "What would future-me wish they knew?"

5. SECURITY SCAN
   - Check for API key patterns
   - Check for password/secret patterns
   - Abort if secrets detected

6. PERSIST (unless --dry-run)
   - Create .claude/ directory if needed
   - Append to learnings.md with timestamp + machine
   - Git add, commit, push (3x retry with backoff)
```

### Extraction Prompt

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

### Learnings Format

```markdown
<!-- .claude/learnings.md -->

## 2026-02-01 (vm)

- Webhook server in `webhook/main.go` handles Telegram replies
- Shell scripts use `set -euo pipefail` pattern
- Deploy with `make deploy`, not `fly deploy` directly

## 2026-01-31 (laptop)

- The `.env.example` file is the source of truth for env vars
- API rate limiting is handled in `middleware/ratelimit.go`
```

---

## CLAUDE.md Integration

Each project's `.claude/CLAUDE.md` should include:

```markdown
## Accumulated Learnings

Always read `.claude/learnings.md` at the start of each session for
context from previous work on this project.
```

The skill will check for this directive and add it if missing.

---

## Security Considerations

### Secret Detection

Before committing, scan extracted learnings for:

```
- API keys: /[A-Za-z0-9_-]{20,}/
- AWS keys: /AKIA[0-9A-Z]{16}/
- Private keys: /-----BEGIN.*PRIVATE KEY-----/
- Passwords: /password\s*[:=]\s*\S+/i
- Tokens: /bearer\s+[A-Za-z0-9_-]+/i
```

If detected:
1. Show warning with the offending line
2. Abort commit
3. Suggest manual edit

### Extraction Prompt Safety

The extraction prompt explicitly instructs Claude to:
- Skip actual data values
- Skip credentials and secrets
- Focus on patterns, not specifics

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No sessions exist | Exit with message: "No sessions found" |
| Corrupted JSONL | Skip bad lines, log warning, continue |
| learnings.md missing | Create `.claude/` directory and file |
| CLAUDE.md missing | Create with learnings directive |
| Git push fails | Retry 3x with exponential backoff |
| Active session | Skip files modified in last 60 seconds |
| No new learnings | Exit with message, no commit |

---

## Session Data Format

Claude Code stores sessions in `~/.claude/projects/<encoded-path>/`:

### sessions-index.json

```json
{
  "version": 1,
  "entries": [
    {
      "sessionId": "726bf96e-...",
      "fullPath": "/path/to/session.jsonl",
      "fileMtime": 1769913080104,
      "firstPrompt": "Help me with...",
      "messageCount": 24,
      "created": "2026-02-01T02:19:56.565Z",
      "modified": "2026-02-01T02:31:20.105Z",
      "projectPath": "/data/repos/codebox"
    }
  ],
  "originalPath": "/data/repos/codebox"
}
```

### Session JSONL

Each line is a JSON object with:
- `type`: "user", "assistant", "tool_result", etc.
- `message.content`: The actual content
- `timestamp`: ISO timestamp

Path encoding: `/data/repos/codebox` → `-data-repos-codebox`

---

## Installation

```bash
# 1. Clone agent-context
git clone git@github.com:you/agent-context.git ~/agent-context

# 2. Install the skill
~/agent-context/skills/context-sync/scripts/install.sh

# 3. Add learnings directive to your projects' CLAUDE.md files
# (The skill will prompt you to do this on first run)
```

---

## Files to Create

1. `skills/context-sync/SKILL.md` - Skill definition
2. `skills/context-sync/scripts/install.sh` - Installation script
3. `skills/context-sync/scripts/extract.sh` - Core extraction logic
4. `README.md` - Setup and usage documentation
5. `.gitignore` - Ignore local config files

---

## Future Enhancements (v2)

- **Cron consolidation**: Daily job to dedupe/merge learnings
- **Cross-project patterns**: `patterns/` directory for universal learnings
- **Multi-machine sync**: Handle conflicts when same project edited on multiple machines
- **Hooks integration**: Auto-sync on git push
- **Staleness detection**: Flag outdated learnings when code changes significantly
