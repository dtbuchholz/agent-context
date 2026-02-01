#!/usr/bin/env bash
set -euo pipefail

# Install context-sync skill to ~/.claude/skills/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_DIR="$HOME/.claude/skills/context-sync"

echo "Installing context-sync skill..."

# Create target directory
mkdir -p "$TARGET_DIR"
mkdir -p "$TARGET_DIR/scripts"

# Copy skill files
cp "$SKILL_DIR/SKILL.md" "$TARGET_DIR/SKILL.md"
cp "$SKILL_DIR/scripts/extract.sh" "$TARGET_DIR/scripts/extract.sh"

# Make scripts executable
chmod +x "$TARGET_DIR/scripts/extract.sh"

echo "Installed to $TARGET_DIR"
echo ""
echo "Usage:"
echo "  /context-sync           Extract and commit learnings"
echo "  /context-sync --dry-run Preview learnings without committing"
