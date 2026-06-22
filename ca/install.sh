#!/usr/bin/env bash
# Install the ca (Cooperate Agents) plugins.
#
#   ca/install.sh [--codex] [--claude] [--force] [--dry-run]
#
# --codex   (default) Copy the Codex skill into $CODEX_HOME/skills (default ~/.codex/skills),
#           so a Codex session discovers $ca-implement-plan. Restart Codex afterwards.
# --claude  Print how to install the Claude Code plugin (marketplace or --plugin-dir).
# --force   Overwrite an existing installed skill directory.
# --dry-run Print planned actions without changing anything.
#
# With no flag, --codex is assumed.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"            # .../ca
SKILL_SRC="$HERE/codex/skills/ca-implement-plan"
CONTRACT_SRC="$HERE/claude/skills/review-diff/references/review-contract.md"
DEST_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
DEST="$DEST_ROOT/ca-implement-plan"

do_codex=0 do_claude=0 force=0 dry=0
while [ $# -gt 0 ]; do case "$1" in
  --codex) do_codex=1; shift;; --claude) do_claude=1; shift;;
  --force) force=1; shift;; --dry-run) dry=1; shift;;
  -h|--help) sed -n '2,12p' "$0"; exit 0;;
  *) echo "unknown arg: $1" >&2; exit 2;; esac; done
[ "$do_codex" = 0 ] && [ "$do_claude" = 0 ] && do_codex=1

[ -f "$SKILL_SRC/SKILL.md" ] || { echo "ca skill not found at $SKILL_SRC" >&2; exit 1; }

if [ "$do_codex" = 1 ]; then
  echo "[ca] Codex skill: $SKILL_SRC -> $DEST"
  if [ "$dry" = 1 ]; then
    echo "[ca] (dry-run) would sync contract + copy skill"
  else
    # keep the bundled contract in sync with the canonical Claude-side copy
    [ -f "$CONTRACT_SRC" ] && cp "$CONTRACT_SRC" "$SKILL_SRC/references/review-contract.md"
    if [ -e "$DEST" ] && [ "$force" = 0 ]; then
      echo "[ca] $DEST already exists; pass --force to overwrite." >&2; exit 1
    fi
    mkdir -p "$DEST_ROOT"; rm -rf "$DEST"; cp -R "$SKILL_SRC" "$DEST"
    echo "[ca] installed. Restart Codex to pick up new skills."
  fi
fi

if [ "$do_claude" = 1 ]; then
  echo "[ca] Claude Code plugin install options:"
  echo "    /plugin install ca@claude-parallel-dev-plugin"
  echo "    # or, for local dev:"
  echo "    claude --plugin-dir \"$HERE/claude\""
fi
