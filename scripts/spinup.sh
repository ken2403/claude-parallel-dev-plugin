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

# Get base branch from workspace configuration
# Priority: CLAUDE.md settings > git remote HEAD > common branch names
get_base_branch() {
  local repo_root="$1"
  local base_branch=""

  # 1. Check CLAUDE.md for base branch specification (in repo root)
  if [ -f "${repo_root}/CLAUDE.md" ]; then
    base_branch=$(grep -i "base.branch\|default.branch\|primary.branch" "${repo_root}/CLAUDE.md" 2>/dev/null | head -1 | grep -oE "(main|master|develop|dev|release[^[:space:]]*)" || echo "")
  fi

  # 2. Fallback: check git remote HEAD
  if [ -z "$base_branch" ]; then
    base_branch=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
  fi

  # 3. Final fallback: check which common branch exists
  if [ -z "$base_branch" ]; then
    for branch in main master develop dev; do
      if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        base_branch="$branch"
        break
      fi
    done
  fi

  # Default to main if nothing found
  echo "${base_branch:-main}"
}

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

# Worktree directory: parent of repo (so worktrees are siblings of the repo)
PARENT_DIR="$(dirname "$REPO_ROOT")"

echo "Project: $PROJECT_NAME"
echo "Base branch: $BASE_BRANCH"
echo "Repo: $REPO_ROOT"
echo "Worktree parent: $PARENT_DIR"
echo ""

for wt in "$@"; do
  safe_wt="${wt//\//-}"                 # feature/foo -> feature-foo
  # Sanitize session name for tmux (remove problematic characters)
  safe_session="${safe_wt//[.:]/_}"     # Replace . and : with _
  dir="${PARENT_DIR}/wt-${safe_wt}"     # sibling of repo (絶対パス)
  session="${PROJECT_NAME}__${safe_session}"

  if [ ! -d "$dir" ]; then
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$wt"; then
      git -C "$REPO_ROOT" worktree add "$dir" "$wt"
    else
      git -C "$REPO_ROOT" worktree add "$dir" -b "$wt" "$BASE_BRANCH"
    fi
  fi

  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$dir"
  fi

  echo "Session: $session (dir: $dir)"
done

echo ""
echo "All sessions created. Attach with: tmux attach -t <session_name>"
echo "List sessions: tmux list-sessions"
