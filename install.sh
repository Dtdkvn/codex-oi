#!/usr/bin/env bash
#
# codex-oi installer — symlinks this repo into ~/.claude/skills/codex-oi/
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/skills/codex-oi"

echo "codex-oi installer"
echo "  source: $SCRIPT_DIR"
echo "  target: $TARGET_DIR"
echo

if [ -e "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
  echo "Target already exists. Remove or back up first:"
  echo "  rm '$TARGET_DIR'"
  exit 1
fi

mkdir -p "$(dirname "$TARGET_DIR")"

if ln -s "$SCRIPT_DIR" "$TARGET_DIR" 2>/dev/null; then
  echo "Linked: $TARGET_DIR -> $SCRIPT_DIR"
else
  echo "Symlink failed — copying instead (Windows / restricted FS)."
  cp -r "$SCRIPT_DIR" "$TARGET_DIR"
  echo "Copied: $TARGET_DIR"
  echo "Note: re-run installer after every update to refresh the copy."
fi

chmod +x "$SCRIPT_DIR/scripts/codex-oi.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/scripts/stream-parser.py" 2>/dev/null || true

echo
echo "Done. Test with:"
echo "  $SCRIPT_DIR/scripts/codex-oi.sh --help"
echo
echo "In Claude Code, the skill will be picked up as 'codex-oi' next session."
