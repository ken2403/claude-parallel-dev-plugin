#!/usr/bin/env bash
set -euo pipefail

# Check required dependencies
if ! command -v tmux >/dev/null 2>&1; then
  echo "Error: tmux is not installed." >&2
  echo "Please install tmux first:" >&2
  echo "  macOS:  brew install tmux" >&2
  echo "  Ubuntu: sudo apt install tmux" >&2
  exit 1
fi

# Source canonical base branch detection
# (single source of truth: scripts/detect-base-branch.sh)
source "$(dirname "$0")/detect-base-branch.sh"

# Find git repository
# 1. If current directory is inside a git repo, use it
# 2. Otherwise, look for a git repo in immediate subdirectories
find_git_repo() {
  # First, check if we're inside a git repo
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return 0
  fi

  # Not in a git repo - look for git repos in immediate subdirectories
  # Note: We check for .git as a DIRECTORY to exclude worktrees (which have .git as a file)
  local found_repos=()
  for dir in */; do
    # Skip if glob didn't match anything (no subdirectories)
    [ "$dir" = "*/" ] && continue
    # Only detect actual repos (not worktrees) - .git must be a directory
    if [ -d "${dir}.git" ]; then
      found_repos+=("$(cd "$dir" && pwd)")
    fi
  done

  if [ ${#found_repos[@]} -eq 0 ]; then
    echo "Error: No git repository found in current directory or subdirectories." >&2
    return 1
  elif [ ${#found_repos[@]} -eq 1 ]; then
    echo "${found_repos[0]}"
    return 0
  else
    # Multiple repos found - let user know
    echo "Error: Multiple git repositories found:" >&2
    for repo in "${found_repos[@]}"; do
      echo "  - $repo" >&2
    done
    echo "Please run from inside the target repository or specify GIT_REPO environment variable." >&2
    return 1
  fi
}

# Auto-detect project name from git repository
get_project_name() {
  local repo_root="$1"
  basename "$repo_root"
}

# Source canonical merge verification
# (single source of truth: scripts/merge-check.sh)
source "$(dirname "$0")/merge-check.sh"

KEEP_BRANCHES=false
DRY_RUN=false
SKIP_MERGE_CHECK=false

usage() {
  cat <<'EOF'
Usage:
  teardown.sh [--keep-branches] [--dry-run] [--skip-merge-check] <branch1> [branch2] ...

Options:
  --keep-branches    Keep local branches, only remove worktrees and sessions
  --dry-run          Show what would be done without executing
  --skip-merge-check Skip merge verification before branch deletion
                     (use only when caller has already verified merge status)

Examples:
  ./scripts/teardown.sh feature/task1 feature/task2
  ./scripts/teardown.sh --keep-branches feature/task1 feature/task2
  ./scripts/teardown.sh --dry-run feature/task1 feature/task2
  ./scripts/teardown.sh --skip-merge-check feature/task1 feature/task2
EOF
}

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-branches) KEEP_BRANCHES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --skip-merge-check) SKIP_MERGE_CHECK=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [ ${#ARGS[@]} -lt 1 ]; then
  usage
  exit 1
fi

# Allow override via environment variable
if [ -n "${GIT_REPO:-}" ]; then
  # Validate GIT_REPO is an actual git repository
  if [ ! -d "$GIT_REPO" ]; then
    echo "Error: GIT_REPO path does not exist: $GIT_REPO" >&2
    exit 1
  fi
  if [ ! -d "$GIT_REPO/.git" ] && ! git -C "$GIT_REPO" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: GIT_REPO is not a git repository: $GIT_REPO" >&2
    exit 1
  fi
  REPO_ROOT="$GIT_REPO"
else
  REPO_ROOT="$(find_git_repo)" || exit 1
fi

PROJECT_NAME="$(get_project_name "$REPO_ROOT")"
BASE_BRANCH="$(get_base_branch "$REPO_ROOT")"
WORKTREES_DIR="${REPO_ROOT}/worktrees"

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

echo "Project: $PROJECT_NAME"
echo "Base branch: $BASE_BRANCH"
echo "Repo: $REPO_ROOT"
echo "Worktrees dir: $WORKTREES_DIR"
echo "Branches: ${ARGS[*]}"
echo "Keep branches: $KEEP_BRANCHES"
echo "Skip merge check: $SKIP_MERGE_CHECK"
echo "Dry run: $DRY_RUN"
echo ""

SKIPPED_BRANCHES=()

for wt in "${ARGS[@]}"; do
  safe_wt="${wt//\//-}"
  # Sanitize session name for tmux (must match spinup.sh logic)
  safe_session="${safe_wt//[.:]/_}"
  WORKTREE_PATH="${WORKTREES_DIR}/${safe_wt}"
  session="${PROJECT_NAME}__${safe_session}"
  branch="$wt"

  echo "=== teardown: $wt ==="

  # 1) tmux session kill
  if tmux has-session -t "$session" 2>/dev/null; then
    run "tmux kill-session -t '$session'"
    echo "killed tmux session: $session"
  else
    echo "tmux session not found: $session"
  fi

  # 2) remove worktree
  if [ -d "$WORKTREE_PATH" ]; then
    run "git -C '$REPO_ROOT' worktree remove --force '$WORKTREE_PATH' 2>/dev/null || true"
    run "rm -rf '$WORKTREE_PATH' 2>/dev/null || true"
    echo "removed worktree dir: $WORKTREE_PATH"
  else
    # Directory may not exist but registration could remain
    run "git -C '$REPO_ROOT' worktree remove --force '$WORKTREE_PATH' 2>/dev/null || true"
    echo "worktree dir not found (attempted detach anyway): $WORKTREE_PATH"
  fi

  # 3) delete branch (with merge verification)
  if ! $KEEP_BRANCHES; then
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
      # Check if branch is still used by another worktree
      if git -C "$REPO_ROOT" worktree list --porcelain | awk -v b="refs/heads/$branch" '
        /^branch /{br=$2}
        br==b {found=1}
        END{exit found?0:1}
      '; then
        echo "branch is still used by a worktree, skip delete: $branch"
      else
        # SAFETY: Verify branch is merged before deletion (unless explicitly skipped)
        if ! $SKIP_MERGE_CHECK; then
          echo "Checking merge status for: $branch"
          if is_branch_merged "$branch" "$BASE_BRANCH" "$REPO_ROOT"; then
            # Use -d (safe delete, only merged branches) instead of -D
            run "git -C '$REPO_ROOT' branch -d '$branch'"
            echo "deleted branch (verified merged): $branch"
          else
            echo "SAFETY BLOCK: Branch '$branch' is NOT confirmed merged into $BASE_BRANCH"
            echo "  Skipping branch deletion to prevent data loss."
            echo "  To force delete: git branch -D $branch"
            SKIPPED_BRANCHES+=("$branch")
          fi
        else
          # Caller has already verified — use -d for git-level safety
          if run "git -C '$REPO_ROOT' branch -d '$branch'"; then
            echo "deleted branch (skip-merge-check): $branch"
          else
            echo "WARNING: git branch -d failed for $branch (branch may not be merged). Skipping."
            SKIPPED_BRANCHES+=("$branch")
          fi
        fi
      fi
    else
      echo "branch not found: $branch"
    fi
  else
    echo "keep branches: $branch"
  fi

  echo ""
done

# Remove empty worktrees directory
if [ -d "$WORKTREES_DIR" ] && [ -z "$(ls -A "$WORKTREES_DIR")" ]; then
  run "rmdir '$WORKTREES_DIR'"
  echo "Removed empty worktrees directory"
fi

# Report skipped branches
if [ ${#SKIPPED_BRANCHES[@]} -gt 0 ]; then
  echo ""
  echo "=== WARNING: ${#SKIPPED_BRANCHES[@]} branch(es) NOT deleted (unmerged) ==="
  for b in "${SKIPPED_BRANCHES[@]}"; do
    echo "  - $b"
  done
  echo ""
  echo "To resolve:"
  echo "  1. Merge the PR first: /pw:merge <pr-number>"
  echo "  2. Or force delete: git branch -D <branch-name>"
fi

echo "Done. (teardown)"
