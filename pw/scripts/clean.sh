#!/usr/bin/env bash
# ==============================================================================
# Worktree cleanup script for the pw plugin.
#
# Safely removes worktree environments created by /pw:wt-j after PRs are merged.
#
# Usage:
#   scripts/clean.sh [job-name|--all]
#
# Safety: NEVER deletes a worktree whose branch has NOT been merged.
# ==============================================================================
set -e

echo "=== Worktree Job Cleanup ==="

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

# Locate plugin directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PD="$(dirname "$SCRIPT_DIR")"
[ -d "${PW_PLUGIN_DIR:-}/scripts" ] && _PD="$PW_PLUGIN_DIR"

# Base branch detection
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
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
  # On the base branch: use pull --ff-only to advance the working tree.
  if git pull --ff-only origin "$BASE_BRANCH" --quiet; then
    echo "Local $BASE_BRANCH fast-forwarded to origin/$BASE_BRANCH"
  else
    echo "WARNING: Local $BASE_BRANCH could not be fast-forwarded (diverged?)."
    echo "  Continuing; 'gh pr' will still drive merge verification."
  fi
else
  # On a feature/worktree branch: update the local base ref without checkout
  # via the refspec form. Safe inside worktrees.
  if git fetch origin "$BASE_BRANCH:$BASE_BRANCH" --quiet; then
    echo "Local $BASE_BRANCH ref fast-forwarded to origin/$BASE_BRANCH"
  else
    echo "WARNING: Local $BASE_BRANCH ref could not be fast-forwarded (diverged?)."
    echo "  Continuing; 'gh pr' will still drive merge verification."
  fi
fi

WORKTREES_DIR="${GIT_ROOT}/worktrees"

if [ ! -d "$WORKTREES_DIR" ]; then
  echo "No worktrees directory found at: $WORKTREES_DIR"
  echo "Nothing to clean up."
  exit 0
fi

# Parse arguments
CLEANUP_ALL=false
if [ "$INPUT_ARG" = "--all" ]; then
  CLEANUP_ALL=true
fi

echo ""
echo "=== Scanning Worktrees ==="

# Track results
MERGED_JOBS=()
UNMERGED_JOBS=()
UNKNOWN_JOBS=()
CLEANED_JOBS=()
FAILED_JOBS=()

# Source canonical merge verification
source "$_PD/scripts/merge-check.sh"

# ============================================================
# Resolve branch name from worktree metadata/git state.
# Returns branch name via echo. Returns empty string if unknown.
# NEVER guesses or fabricates branch names.
# ============================================================
resolve_branch_name() {
  local job_dir="$1"
  local job_name="$2"
  local result=""

  # Method 1: Read from .wtj-meta metadata file (most reliable)
  if [ -f "$job_dir/.wtj-meta" ]; then
    result=$(grep "^BRANCH_NAME=" "$job_dir/.wtj-meta" | cut -d'"' -f2)
    if [ -n "$result" ]; then
      echo "$result"
      return 0
    fi
  fi

  # Method 2: Get from git worktree directly
  if [ -d "$job_dir/.git" ] || [ -f "$job_dir/.git" ]; then
    result=$(git -C "$job_dir" branch --show-current 2>/dev/null || echo "")
    if [ -n "$result" ]; then
      echo "$result"
      return 0
    fi
  fi

  # Method 3: Check git worktree list for this path
  local abs_job_dir=""
  abs_job_dir=$(cd "$job_dir" 2>/dev/null && pwd || echo "$job_dir")
  result=$(git worktree list --porcelain 2>/dev/null | grep -A2 "^worktree $abs_job_dir\$" | grep "^branch " | sed 's|^branch refs/heads/||')
  if [ -n "$result" ]; then
    echo "$result"
    return 0
  fi

  # Method 4: Infer from job name — but ONLY if the branch actually exists
  for prefix in feature fix; do
    local test_branch="${prefix}/${job_name}"
    if git show-ref --verify --quiet "refs/heads/$test_branch" 2>/dev/null; then
      echo "$test_branch"
      return 0
    fi
  done

  # SAFETY: Do NOT guess. Return empty to signal "unknown".
  echo ""
  return 1
}

# Scan worktrees directory
for job_dir in "$WORKTREES_DIR"/*/; do
  if [ ! -d "$job_dir" ]; then
    continue
  fi

  job_name=$(basename "$job_dir")

  # Skip if specific job requested and this isn't it
  if [ "$CLEANUP_ALL" = false ] && [ -n "$INPUT_ARG" ] && [ "$job_name" != "$INPUT_ARG" ]; then
    continue
  fi

  echo ""
  echo "--- Job: $job_name ---"

  # Resolve branch name — NEVER guess
  branch_name=$(resolve_branch_name "$job_dir" "$job_name")

  if [ -z "$branch_name" ]; then
    echo "Branch: UNKNOWN (could not determine)"
    echo "  *** SAFETY BLOCK: Cannot determine branch name for '$job_name' ***"
    echo "  *** Treating as NOT MERGED (safe default) ***"
    echo "  To resolve: git -C $job_dir branch"
    UNKNOWN_JOBS+=("$job_name:UNKNOWN")
    continue
  fi

  echo "Branch: $branch_name"

  # Check merge status
  if is_branch_merged "$branch_name" "$BASE_BRANCH"; then
    echo "Status: MERGED into $BASE_BRANCH"
    MERGED_JOBS+=("$job_name:$branch_name")
  else
    echo "Status: NOT MERGED"
    echo "  *** ALERT: Branch '$branch_name' has NOT been merged! ***"
    echo "  To resolve: merge the PR first, or abandon with git branch -D $branch_name"
    UNMERGED_JOBS+=("$job_name:$branch_name")
  fi
done

echo ""
echo "=== Summary ==="
echo "Merged (safe to delete): ${#MERGED_JOBS[@]}"
echo "Not merged (BLOCKED):    ${#UNMERGED_JOBS[@]}"
echo "Unknown (BLOCKED):       ${#UNKNOWN_JOBS[@]}"

BLOCKED_COUNT=$(( ${#UNMERGED_JOBS[@]} + ${#UNKNOWN_JOBS[@]} ))

# Report blocked worktrees
if [ $BLOCKED_COUNT -gt 0 ]; then
  echo ""
  echo "*** BLOCKED WORKTREES ***"
  if [ ${#UNMERGED_JOBS[@]} -gt 0 ]; then
    echo "Not merged:"
    for item in "${UNMERGED_JOBS[@]}"; do
      echo "  - ${item%%:*} (${item##*:})"
    done
  fi
  if [ ${#UNKNOWN_JOBS[@]} -gt 0 ]; then
    echo "Unknown branch:"
    for item in "${UNKNOWN_JOBS[@]}"; do
      echo "  - ${item%%:*}"
    done
  fi
  echo ""
  echo "These worktrees will NOT be deleted."

  if [ "$CLEANUP_ALL" = false ] && [ -n "$INPUT_ARG" ] && [ "$INPUT_ARG" != "--all" ]; then
    exit 1
  fi
fi

# Clean up merged jobs
if [ ${#MERGED_JOBS[@]} -eq 0 ]; then
  echo ""
  echo "No merged worktrees to clean up."
  exit 0
fi

echo ""
echo "=== Cleaning Merged Worktrees ==="

for item in "${MERGED_JOBS[@]}"; do
  job="${item%%:*}"
  branch="${item##*:}"
  job_path="${WORKTREES_DIR}/${job}"

  echo ""
  echo "Cleaning: $job"

  # Remove worktree
  if git worktree remove "$job_path" 2>/dev/null; then
    echo "  Worktree removed"
  elif git worktree remove --force "$job_path" 2>/dev/null; then
    echo "  Worktree force removed"
  else
    echo "  Failed to remove worktree"
    FAILED_JOBS+=("$job")
    continue
  fi

  # Delete local branch if it exists
  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    if git branch -d "$branch" 2>/dev/null; then
      echo "  Local branch deleted"
    else
      echo "  Could not delete local branch (may need -D)"
    fi
  else
    echo "  Local branch already gone"
  fi

  CLEANED_JOBS+=("$job")
done

# Prune worktree references
git worktree prune 2>/dev/null || true

# Remove empty worktrees directory
if [ -d "$WORKTREES_DIR" ] && [ -z "$(ls -A "$WORKTREES_DIR")" ]; then
  rmdir "$WORKTREES_DIR"
  echo ""
  echo "Removed empty worktrees directory"
fi

echo ""
echo "=== Cleanup Complete ==="
echo "Cleaned: ${#CLEANED_JOBS[@]}"
echo "Failed: ${#FAILED_JOBS[@]}"
echo "Blocked (unmerged): ${#UNMERGED_JOBS[@]}"
echo "Blocked (unknown):  ${#UNKNOWN_JOBS[@]}"
echo "Default branch ($BASE_BRANCH) was synced with origin before cleanup."
