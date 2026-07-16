#!/usr/bin/env bash
# Generated from common/src/scripts/attach-or-create-worktree.sh; edit common/src and run common/sync.sh.
# ==============================================================================
# Resolve an ISOLATED worktree for applying feedback to an EXISTING branch
# (typically a PR's head branch) — never the main checkout.
# Ported from sa/skills/apply-feedback/scripts/attach-or-create-worktree.sh (sa->ca).
#
# Usage: attach-or-create-worktree.sh <branch>
# Prints (stdout, machine-parseable):
#   WORKTREE_PATH=<absolute path>
#   BRANCH=<branch>
#   REUSED=1   (an existing isolated worktree was found) | 0 (one was created)
# All progress/log noise goes to stderr so stdout stays clean for `eval`.
#
# Behavior:
#   1. If <branch> is already checked out in a linked worktree (e.g. the one
#      ca:implement created under .claude/worktrees/ca/<slug>), REUSE it.
#   2. If <branch> is checked out in the MAIN working copy, refuse (exit 1) —
#      this skill must not edit the user's main checkout.
#   3. Otherwise create a fresh worktree under .claude/worktrees/ca/<slug>,
#      attaching the existing local branch or tracking origin/<branch>.
# ==============================================================================
set -euo pipefail

BRANCH="${1:?usage: attach-or-create-worktree.sh <branch>}"
ROOT="$(git rev-parse --show-toplevel)"

# Identify the main checkout so we never treat it as a reusable isolated worktree.
COMMON_GIT_DIR="$(git rev-parse --git-common-dir 2>/dev/null || echo "")"
case "$COMMON_GIT_DIR" in
  "") MAIN_WT="" ;;
  /*) MAIN_WT="$(cd "$(dirname "$COMMON_GIT_DIR")" 2>/dev/null && pwd || echo "")" ;;
  *)  MAIN_WT="$(cd "$ROOT/$(dirname "$COMMON_GIT_DIR")" 2>/dev/null && pwd || echo "")" ;;
esac

# --- 1. Is BRANCH already checked out in a worktree? ---------------------------
existing_path=""
existing_is_main=0
while IFS=$'\t' read -r wt_path wt_branch; do
  [ -z "$wt_path" ] && continue
  if [ "$wt_branch" = "$BRANCH" ]; then
    existing_path="$wt_path"
    [ -n "$MAIN_WT" ] && [ "$wt_path" = "$MAIN_WT" ] && existing_is_main=1
    break
  fi
done < <(git worktree list --porcelain 2>/dev/null | awk '
  /^worktree /{ if (have) print path "\t" branch; path=substr($0,10); branch="DETACHED"; have=1 }
  /^branch /{ branch=$2; sub(/^refs\/heads\//,"",branch) }
  END{ if (have) print path "\t" branch }
')

if [ -n "$existing_path" ]; then
  if [ "$existing_is_main" = 1 ]; then
    echo "error: branch '$BRANCH' is checked out in your MAIN working copy ($existing_path)." >&2
    echo "  this skill will not edit the main checkout. Switch it off the branch" >&2
    echo "  (e.g. 'git -C \"$existing_path\" switch -') and re-run so an isolated worktree is used." >&2
    exit 1
  fi
  echo "reusing existing isolated worktree for '$BRANCH': $existing_path" >&2
  # Shell-quote so `eval "$(...)"` survives paths containing spaces.
  printf 'WORKTREE_PATH=%q\nBRANCH=%q\nREUSED=%q\n' "$existing_path" "$BRANCH" "1"
  exit 0
fi

# --- 2. None exists — create one under .claude/worktrees/ca/<slug> -------------
SLUG="$(printf '%s' "$BRANCH" | tr '/' '-' | tr -cs 'A-Za-z0-9._-' '-')"
WT_DIR="$ROOT/.claude/worktrees/ca/$SLUG"
[ -e "$WT_DIR" ] && {
  echo "error: path '$WT_DIR' already exists but is not a registered worktree on '$BRANCH' — inspect it." >&2
  exit 1
}

git -C "$ROOT" fetch origin "$BRANCH" --quiet 2>/dev/null || true
mkdir -p "$ROOT/.claude/worktrees/ca"

if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  # Local branch exists (and isn't checked out anywhere) — attach it.
  git -C "$ROOT" worktree add "$WT_DIR" "$BRANCH" >&2
elif git -C "$ROOT" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  # Only the remote branch exists — create a local tracking branch in the worktree.
  git -C "$ROOT" worktree add -b "$BRANCH" "$WT_DIR" "origin/$BRANCH" >&2
else
  echo "error: branch '$BRANCH' not found locally or on origin — cannot apply feedback." >&2
  exit 1
fi

# Confirm we landed on the intended branch.
ON="$(git -C "$WT_DIR" branch --show-current)"
[ "$ON" = "$BRANCH" ] || { echo "error: worktree ended up on '$ON', not '$BRANCH'" >&2; exit 1; }

# Carry local settings into the worktree if present.
if [ -f "$ROOT/.claude/settings.local.json" ]; then
  mkdir -p "$WT_DIR/.claude"
  cp "$ROOT/.claude/settings.local.json" "$WT_DIR/.claude/settings.local.json" 2>/dev/null || true
fi

echo "created isolated worktree for '$BRANCH': $WT_DIR" >&2
# Shell-quote so `eval "$(...)"` survives paths containing spaces.
printf 'WORKTREE_PATH=%q\nBRANCH=%q\nREUSED=%q\n' "$WT_DIR" "$BRANCH" "0"
