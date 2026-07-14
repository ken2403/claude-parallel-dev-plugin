#!/usr/bin/env bash
# ==============================================================================
# Worktree cleanup script for the @@PLUGIN@@ plugin.
@@CLEAN_HEADER_TAIL@@
# Scans linked worktrees via `git worktree list` and removes EVERY worktree —
# regardless of location — whose branch has been merged. This is intentionally
# repo-wide: it reclaims ha/sa/ca worktrees and any other merged worktree, so a
# single run cleans them all. The main checkout is always preserved; the current
# worktree is removed too if its branch is merged. An unmerged branch is never
# deleted.
@@CLEAN_GUARDRAIL_BLOCK@@
# Usage:
#   scripts/clean.sh [branch | path | all-merged | --all]
#     (no arg / all-merged / --all) → consider every worktree
#     (a name/branch/path) → only that one
#
# Safety:
#   - Considers every worktree in `git worktree list` (any path).
#   - NEVER deletes a worktree whose branch has NOT been merged.
#   - NEVER deletes the main checkout. The CURRENT worktree IS removed if its
#     branch is merged (done from the main checkout, since git refuses to remove
#     the worktree you stand in); skipped only if there is no separate main dir.
#   - NEVER uses `git worktree remove --force` — a worktree with uncommitted
#     changes is skipped and reported, not destroyed.
#   - `git branch -d` (not -D) — refuses to delete an unmerged branch.
# ==============================================================================
set -e

echo "=== Worktree Cleanup ==="

INPUT_ARG="${1:-}"

# Detect git repository
GIT_ROOT=""
if git rev-parse --show-toplevel &>/dev/null; then
  GIT_ROOT=$(git rev-parse --show-toplevel)
else
  for dir in . */; do
    if [ -d "$dir/.git" ] || git -C "$dir" rev-parse --show-toplevel &>/dev/null 2>&1; then
      GIT_ROOT=$(cd "$dir" && git rev-parse --show-toplevel)
      break
    fi
  done
fi

if [ -z "$GIT_ROOT" ]; then
  echo "ERROR: No git repository found"
  exit 1
fi

cd "$GIT_ROOT"
echo "Repository: $GIT_ROOT"

# Helper scripts are co-located in this skill's own scripts/ dir (self-contained).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Base branch detection
BASE_BRANCH=$("$SCRIPT_DIR/detect-base-branch.sh" 2>/dev/null || echo "main")
echo "Base branch: $BASE_BRANCH"

# ============================================================
# Pre-cleanup sync: bring local <base> up to origin/<base> BEFORE
# any deletion decision so the user can verify merges locally
# (e.g. `git log main`) once the command finishes.
# ============================================================
echo ""
echo "=== Syncing $BASE_BRANCH with origin ==="

if ! git fetch origin "$BASE_BRANCH" --prune --quiet; then
  echo "WARNING: git fetch origin $BASE_BRANCH failed."
  echo "  Continuing, but local state may be stale."
  echo "  Merge verification will still use 'gh pr' as the authoritative source."
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ]; then
  if git pull --ff-only origin "$BASE_BRANCH" --quiet; then
    echo "Local $BASE_BRANCH fast-forwarded to origin/$BASE_BRANCH"
  else
    echo "WARNING: Local $BASE_BRANCH could not be fast-forwarded (diverged?)."
    echo "  Continuing; 'gh pr' will still drive merge verification."
  fi
else
  if git fetch origin "$BASE_BRANCH:$BASE_BRANCH" --quiet 2>/dev/null; then
    echo "Local $BASE_BRANCH ref fast-forwarded to origin/$BASE_BRANCH"
  else
    echo "WARNING: Local $BASE_BRANCH ref could not be fast-forwarded (checked out elsewhere or diverged)."
    echo "  Continuing; 'gh pr' will still drive merge verification."
  fi
fi

# Parse arguments
CLEANUP_ALL=false
{ [ -z "$INPUT_ARG" ] || [ "$INPUT_ARG" = "--all" ] || [ "$INPUT_ARG" = "all-merged" ]; } && CLEANUP_ALL=true

# Source canonical merge verification (defines is_branch_merged)
source "$SCRIPT_DIR/merge-check.sh"

# ============================================================
# The main checkout is NEVER removed. The current worktree CAN be removed if it
# is merged — but git refuses to remove the worktree you are standing in, so we
# run all removals from the main checkout. When there is no separate main
# checkout to relocate to, the current worktree is skipped (fail-safe).
# ============================================================
CURRENT_WT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
COMMON_GIT_DIR="$(git rev-parse --git-common-dir 2>/dev/null || echo "")"
case "$COMMON_GIT_DIR" in
  "") MAIN_WT="" ;;
  /*) MAIN_WT="$(cd "$(dirname "$COMMON_GIT_DIR")" 2>/dev/null && pwd || echo "")" ;;
  *)  MAIN_WT="$(cd "$GIT_ROOT/$(dirname "$COMMON_GIT_DIR")" 2>/dev/null && pwd || echo "")" ;;
esac

# Removals run from REMOVE_FROM. Using the main checkout lets us also remove the
# current worktree; fall back to GIT_ROOT (and skip the current worktree) when
# there is no separate main checkout.
REMOVE_FROM="$GIT_ROOT"
CAN_REMOVE_CURRENT=false
if [ -n "$MAIN_WT" ] && [ "$MAIN_WT" != "$CURRENT_WT" ]; then
  REMOVE_FROM="$MAIN_WT"
  CAN_REMOVE_CURRENT=true
fi

echo ""
echo "=== Scanning all worktrees ==="

MERGED_JOBS=()     # entries: "<path>\t<branch>"
UNMERGED_JOBS=()   # "<name>:<branch>"
UNKNOWN_JOBS=()    # "<name>:<reason>"
CLEANED_JOBS=()
FAILED_JOBS=()

while IFS=$'\t' read -r wt_path wt_branch; do
  [ -z "$wt_path" ] && continue
  name="$(basename "$wt_path")"

  # Never touch the main checkout.
  if [ -n "$MAIN_WT" ] && [ "$wt_path" = "$MAIN_WT" ]; then
    continue
  fi
  # The current worktree is only skipped when we cannot relocate the removal to a
  # separate main checkout; otherwise it is evaluated (and removed if merged)
  # like any other worktree.
  if [ "$wt_path" = "$CURRENT_WT" ] && [ "$CAN_REMOVE_CURRENT" = false ]; then
    echo ""
    echo "--- $name --- skip: current worktree (no separate main checkout to remove it from)"
    continue
  fi

  # If a specific target was given, only act on the matching worktree.
  if [ "$CLEANUP_ALL" = false ]; then
    case "$INPUT_ARG" in
      "$name"|"$wt_branch"|"$wt_path") ;;
      *) continue ;;
    esac
  fi

  echo ""
  echo "--- $name ($wt_path) ---"

  if [ -z "$wt_branch" ] || [ "$wt_branch" = "DETACHED" ]; then
    echo "Branch: UNKNOWN/detached"
    echo "  *** SAFETY BLOCK: no branch to verify — treating as NOT MERGED ***"
    UNKNOWN_JOBS+=("$name:detached")
    continue
  fi

  echo "Branch: $wt_branch"
  if is_branch_merged "$wt_branch" "$BASE_BRANCH"; then
    echo "Status: MERGED into $BASE_BRANCH"
    MERGED_JOBS+=("$wt_path"$'\t'"$wt_branch")
  else
    echo "Status: NOT MERGED"
    echo "  *** ALERT: '$wt_branch' is not merged — will NOT be deleted ***"
    UNMERGED_JOBS+=("$name:$wt_branch")
  fi
done < <(git worktree list --porcelain 2>/dev/null | awk '
  /^worktree /{ if (have) print path "\t" branch; path=substr($0,10); branch="DETACHED"; have=1 }
  /^branch /{ branch=$2; sub(/^refs\/heads\//,"",branch) }
  END{ if (have) print path "\t" branch }
')

echo ""
echo "=== Summary ==="
echo "Merged (safe to delete): ${#MERGED_JOBS[@]}"
echo "Not merged (BLOCKED):    ${#UNMERGED_JOBS[@]}"
echo "Unknown/detached (BLOCKED): ${#UNKNOWN_JOBS[@]}"

if [ ${#UNMERGED_JOBS[@]} -gt 0 ]; then
  echo ""
  echo "*** BLOCKED (not merged) — left untouched ***"
  for item in "${UNMERGED_JOBS[@]}"; do echo "  - ${item%%:*} (${item##*:})"; done
fi
if [ ${#UNKNOWN_JOBS[@]} -gt 0 ]; then
  echo ""
  echo "*** BLOCKED (unknown branch) — left untouched ***"
  for item in "${UNKNOWN_JOBS[@]}"; do echo "  - ${item%%:*}"; done
fi

if [ ${#MERGED_JOBS[@]} -eq 0 ]; then
  echo ""
  echo "No merged worktrees to clean up."
  exit 0
fi

echo ""
echo "=== Cleaning Merged Worktrees ==="
# Run every removal from REMOVE_FROM (the main checkout when available) so the
# current worktree can be removed too. cd there so post-removal git calls and
# `git worktree prune` keep working even if the cwd's worktree was just removed.
cd "$REMOVE_FROM" 2>/dev/null || true
CURRENT_WT_REMOVED=false
for item in "${MERGED_JOBS[@]}"; do
  wt_path="${item%%$'\t'*}"
  branch="${item##*$'\t'}"
  name="$(basename "$wt_path")"

  echo ""
  echo "Cleaning: $name ($wt_path)"

  # NEVER --force: a plain remove fails on uncommitted changes, which is the
  # signal to inspect — not to destroy.
  if git -C "$REMOVE_FROM" worktree remove "$wt_path" 2>/dev/null; then
    echo "  Worktree removed"
    if [ "$wt_path" = "$CURRENT_WT" ]; then CURRENT_WT_REMOVED=true; fi
  else
    echo "  SKIP: uncommitted changes or locked — inspect and remove manually (no --force)"
    FAILED_JOBS+=("$name")
    continue
  fi

  if git -C "$REMOVE_FROM" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    if git -C "$REMOVE_FROM" branch -d "$branch" 2>/dev/null; then
      echo "  Local branch '$branch' deleted"
    else
      echo "  Local branch '$branch' kept (not fully merged locally)"
    fi
  else
    echo "  Local branch already gone"
  fi

  CLEANED_JOBS+=("$name")
done

git -C "$REMOVE_FROM" worktree prune 2>/dev/null || true

echo ""
echo "=== Cleanup Complete ==="
echo "Cleaned: ${#CLEANED_JOBS[@]}"
echo "Skipped (uncommitted/locked): ${#FAILED_JOBS[@]}"
echo "Blocked (not merged): ${#UNMERGED_JOBS[@]}"
echo "Blocked (unknown):    ${#UNKNOWN_JOBS[@]}"
echo "Default branch ($BASE_BRANCH) was synced with origin before cleanup."

if [ "$CURRENT_WT_REMOVED" = true ]; then
  echo ""
  echo "NOTE: the worktree you were in was merged and has been removed."
  echo "      cd to the main checkout: $REMOVE_FROM"
fi
