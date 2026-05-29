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

# Source canonical base branch detection
# (single source of truth: scripts/detect-base-branch.sh)
source "$(dirname "$0")/detect-base-branch.sh"

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

if [ $# -lt 1 ]; then
  echo "Usage: $0 <branch1> [branch2] ..."
  echo ""
  echo "Detected settings:"
  echo "  git_repo:     $REPO_ROOT"
  echo "  project_name: $PROJECT_NAME"
  echo "  base_branch:  $BASE_BRANCH"
  exit 1
fi

# Worktree directory: inside repo (consistent with wt-j)
WORKTREES_DIR="${REPO_ROOT}/worktrees"
mkdir -p "$WORKTREES_DIR"

echo "Project: $PROJECT_NAME"
echo "Base branch: $BASE_BRANCH"
echo "Repo: $REPO_ROOT"
echo "Worktrees dir: $WORKTREES_DIR"
echo ""

for wt in "$@"; do
  safe_wt="${wt//\//-}"                 # feature/foo -> feature-foo
  # Sanitize session name for tmux (remove problematic characters)
  safe_session="${safe_wt//[.:]/_}"     # Replace . and : with _
  WORKTREE_PATH="${WORKTREES_DIR}/${safe_wt}"
  session="${PROJECT_NAME}__${safe_session}"

  if [ ! -d "$WORKTREE_PATH" ]; then
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$wt"; then
      git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" "$wt"
    else
      git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" -b "$wt" "$BASE_BRANCH"
    fi
  fi

  # Copy Claude local settings if present
  if [ -f "${REPO_ROOT}/.claude/settings.local.json" ]; then
    mkdir -p "${WORKTREE_PATH}/.claude"
    cp "${REPO_ROOT}/.claude/settings.local.json" "${WORKTREE_PATH}/.claude/settings.local.json"
  fi

  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$WORKTREE_PATH"
  fi

  echo "Session: $session (dir: $WORKTREE_PATH)"
done

echo ""
echo "All sessions created. Attach with: tmux attach -t <session_name>"
echo "List sessions: tmux list-sessions"
