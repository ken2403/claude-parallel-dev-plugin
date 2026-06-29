#!/usr/bin/env bash
# ==============================================================================
# Create an isolated worktree for an ha feature AFTER the human approved the plan.
# Ported from sa/skills/simple-implement/scripts/new-worktree.sh (sa->ha) plus a
# superpowers:using-git-worktrees "Step 0" detection: if we are already inside a
# linked worktree, reuse it instead of nesting another.
#
# Usage: new-worktree.sh <branch> [base-branch]
# Prints (stdout, machine-parseable):
#   WORKTREE_PATH=<absolute path>
#   BRANCH=<branch>
#   REUSED=0|1
# All progress/log noise goes to stderr so stdout stays clean for `eval`.
#
# Safety: refuses (non-zero) if the branch already exists (local or remote) or
# the target worktree path is already taken. Worktrees live under
# .claude/worktrees/ha/<slug> so cleanup can target only ha's own worktrees.
#
# Note: ha uses script-created PERSISTENT worktrees here (not the native
# EnterWorktree), because the worktree must outlive the session until the PR
# merges and must live at a predictable path that /ha:clean-worktrees can find.
# ==============================================================================
set -euo pipefail

BRANCH="${1:?usage: new-worktree.sh <branch> [base-branch]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"

# --- Step 0: detect existing isolation (superpowers:using-git-worktrees) -------
# If GIT_DIR != GIT_COMMON we are in a linked worktree — but that is also true
# inside a submodule, so guard with show-superproject-working-tree.
GIT_DIR="$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null || echo)"
GIT_COMMON="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null || echo)"
SUPER="$(git -C "$ROOT" rev-parse --show-superproject-working-tree 2>/dev/null || echo)"
if [ -n "$GIT_DIR" ] && [ "$GIT_DIR" != "$GIT_COMMON" ] && [ -z "$SUPER" ]; then
  CUR="$(git -C "$ROOT" branch --show-current 2>/dev/null || echo)"
  echo "note: already inside a linked worktree ($ROOT on '$CUR') — reusing it" >&2
  echo "WORKTREE_PATH=$ROOT"
  echo "BRANCH=$CUR"
  echo "REUSED=1"
  exit 0
fi

# Base branch: explicit arg wins, else canonical detection (co-located script).
BASE="${2:-$(bash "$SCRIPT_DIR/detect-base-branch.sh" "$ROOT")}"

# Slug: flatten the branch into a safe single directory name.
SLUG="$(printf '%s' "$BRANCH" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-')"
WT_DIR="$ROOT/.claude/worktrees/ha/$SLUG"

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

mkdir -p "$ROOT/.claude/worktrees/ha"
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
echo "REUSED=0"
