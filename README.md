# agent-context

Extract and sync learnings from Claude Code sessions across machines.

## Problem

Claude Code sessions are local. When you switch machines or start a new session, you lose the context from previous work. This tool extracts valuable learnings and persists them in your project repos.

## How It Works

1. You finish a Claude Code session
2. Run `/context-sync` to extract learnings
3. Learnings are saved to `.claude/learnings.md` in your project
4. Future sessions read this file and start with accumulated context

## Installation

```bash
# Clone this repo
git clone git@github.com:dtbuchholz/agent-context.git ~/agent-context

# Install the skill
~/agent-context/skills/context-sync/scripts/install.sh
```

## Usage

### Extract Learnings

After finishing a session, run:

```
/context-sync
```

This will:
1. Find recent sessions (last 4 hours)
2. Extract conversation content
3. Generate learnings using Claude
4. Append to `.claude/learnings.md`
5. Commit and push

### Preview Without Committing

```
/context-sync --dry-run
```

Shows what learnings would be extracted without making any changes.

## Project Setup

For each project where you want to use context sync, add this to `.claude/CLAUDE.md`:

```markdown
## Accumulated Learnings

Always read `.claude/learnings.md` at the start of each session for
context from previous work on this project.
```

The skill will remind you to add this on first run.

## What Gets Extracted

The skill extracts learnings that would help a future session:

- Architecture decisions and rationale
- Non-obvious codebase patterns
- Gotchas and pitfalls
- Configuration/deployment knowledge
- Dependency quirks

It skips:

- Specific line numbers or temporary fixes
- Debugging steps
- Routine operations
- Data values or credentials

## Learnings Format

Learnings are appended with timestamp and machine name:

```markdown
## 2026-02-01 (vm)

- Webhook server in `webhook/main.go` handles Telegram replies
- Deploy with `make deploy`, not `fly deploy` directly

## 2026-01-31 (laptop)

- The `.env.example` file is the source of truth for env vars
```

## Security

Before committing, the skill scans for potential secrets:

- API keys (long alphanumeric strings)
- AWS access keys
- Private keys
- Password patterns

If detected, the commit is aborted and you're prompted to review.

## Updating

To update the skill after changes to this repo:

```bash
cd ~/agent-context
git pull
./skills/context-sync/scripts/install.sh
```

## Requirements

- Claude Code CLI
- `jq` for JSON parsing
- Git

## Future Plans

See [PLAN.md](./PLAN.md) for the full design document and v2 roadmap:

- Cron-based automatic sync
- Cross-project patterns
- Multi-machine conflict resolution
- Staleness detection
