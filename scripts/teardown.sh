#!/usr/bin/env bash
set -euo pipefail

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

KEEP_BRANCHES=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  teardown.sh [--keep-branches] [--dry-run] <branch1> [branch2] ...

Options:
  --keep-branches  Keep local branches, only remove worktrees and sessions
  --dry-run        Show what would be done without executing

Examples:
  ./scripts/teardown.sh feature/task1 feature/task2
  ./scripts/teardown.sh --keep-branches feature/task1 feature/task2
  ./scripts/teardown.sh --dry-run feature/task1 feature/task2
EOF
}

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-branches) KEEP_BRANCHES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
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
PARENT_DIR="$(dirname "$REPO_ROOT")"

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

echo "Project: $PROJECT_NAME"
echo "Repo: $REPO_ROOT"
echo "Worktree parent: $PARENT_DIR"
echo "Branches: ${ARGS[*]}"
echo "Keep branches: $KEEP_BRANCHES"
echo "Dry run: $DRY_RUN"
echo ""

for wt in "${ARGS[@]}"; do
  safe_wt="${wt//\//-}"
  # Sanitize session name for tmux (must match spinup.sh logic)
  safe_session="${safe_wt//[.:]/_}"
  dir="${PARENT_DIR}/wt-${safe_wt}"
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
  if [ -d "$dir" ]; then
    run "git -C '$REPO_ROOT' worktree remove --force '$dir' 2>/dev/null || true"
    run "rm -rf '$dir' 2>/dev/null || true"
    echo "removed worktree dir: $dir"
  else
    # ディレクトリが無くても登録だけ残っている場合があるので一応試す
    run "git -C '$REPO_ROOT' worktree remove --force '$dir' 2>/dev/null || true"
    echo "worktree dir not found (attempted detach anyway): $dir"
  fi

  # 3) delete branch (optional)
  if ! $KEEP_BRANCHES; then
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
      # 他worktreeで使用中なら削除しない
      if git -C "$REPO_ROOT" worktree list --porcelain | awk -v b="refs/heads/$branch" '
        /^branch /{br=$2}
        br==b {found=1}
        END{exit found?0:1}
      '; then
        echo "branch is still used by a worktree, skip delete: $branch"
      else
        run "git -C '$REPO_ROOT' branch -D '$branch'"
        echo "deleted branch: $branch"
      fi
    else
      echo "branch not found: $branch"
    fi
  else
    echo "keep branches: $branch"
  fi

  echo ""
done

echo "Done. (teardown)"
