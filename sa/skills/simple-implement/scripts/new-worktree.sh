#!/usr/bin/env bash
# ==============================================================================
# Create an isolated worktree for an sa feature AFTER the human approved the plan.
#
# Usage: new-worktree.sh <branch> [base-branch]
# Prints (stdout, machine-parseable):
#   WORKTREE_PATH=<absolute path>
#   BRANCH=<branch>
# All progress/log noise goes to stderr so stdout stays clean for `eval`.
#
# Safety: refuses (non-zero) if the branch already exists (local or remote) or
# the target worktree path is already taken. Worktrees live under
# .claude/worktrees/sa/<slug> so cleanup can target only sa's own worktrees.
# ==============================================================================
set -euo pipefail

BRANCH="${1:?usage: new-worktree.sh <branch> [base-branch]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"

# Base branch: explicit arg wins, else canonical detection (co-located script).
BASE="${2:-$(bash "$SCRIPT_DIR/detect-base-branch.sh" "$ROOT")}"

# Slug: flatten the branch into a safe single directory name.
SLUG="$(printf '%s' "$BRANCH" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-')"
WT_DIR="$ROOT/.claude/worktrees/sa/$SLUG"

# --- Safety checks (change nothing, fail loud) --------------------------------
git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" \
  && { echo "error: local branch '$BRANCH' already exists" >&2; exit 1; }
git -C "$ROOT" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1 \
  && { echo "error: remote branch 'origin/$BRANCH' already exists" >&2; exit 1; }
[ -e "$WT_DIR" ] && { echo "error: worktree path '$WT_DIR' already exists" >&2; exit 1; }

# Create off the freshest base we can reach.
git -C "$ROOT" fetch origin "$BASE" --quiet 2>/dev/null || true
if git -C "$ROOT" show-ref --verify --quiet "refs/remotes/origin/$BASE"; then
  START="origin/$BASE"
else
  START="$BASE"
fi

mkdir -p "$ROOT/.claude/worktrees/sa"
git -C "$ROOT" worktree add -b "$BRANCH" "$WT_DIR" "$START" >&2

# Never hand back a worktree that somehow landed on the base branch.
ON="$(git -C "$WT_DIR" branch --show-current)"
[ "$ON" = "$BASE" ] && { echo "error: worktree ended up on base '$BASE'" >&2; exit 1; }

# Carry local settings into the worktree if present.
if [ -f "$ROOT/.claude/settings.local.json" ]; then
  mkdir -p "$WT_DIR/.claude"
  cp "$ROOT/.claude/settings.local.json" "$WT_DIR/.claude/settings.local.json" 2>/dev/null || true
fi

echo "WORKTREE_PATH=$WT_DIR"
echo "BRANCH=$BRANCH"
