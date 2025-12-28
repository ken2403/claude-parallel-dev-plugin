#!/usr/bin/env bash
set -euo pipefail

# Auto-detect project name from git repository
get_project_name() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$repo_root" ]; then
    basename "$repo_root"
  else
    echo "unknown-project"
  fi
}

# Get base branch (default: main, fallback: master)
get_base_branch() {
  if git show-ref --verify --quiet refs/heads/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master; then
    echo "master"
  else
    git branch --show-current
  fi
}

PROJECT_NAME="$(get_project_name)"
BASE_BRANCH="$(get_base_branch)"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <branch1> [branch2] ..."
  echo ""
  echo "Detected settings:"
  echo "  project_name: $PROJECT_NAME"
  echo "  base_branch:  $BASE_BRANCH"
  exit 1
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Error: run this inside a git repository."
  exit 1
}

# worktreeの作成先を「リポジトリの親」に固定
REPO_ROOT="$(git rev-parse --show-toplevel)"
PARENT_DIR="$(dirname "$REPO_ROOT")"

echo "Project: $PROJECT_NAME"
echo "Base branch: $BASE_BRANCH"
echo "Repo: $REPO_ROOT"
echo "Worktree parent: $PARENT_DIR"
echo ""

for wt in "$@"; do
  safe_wt="${wt//\//-}"                 # feature/foo -> feature-foo
  dir="${PARENT_DIR}/wt-${safe_wt}"     # 1段上に作る（絶対パス）
  session="${PROJECT_NAME}__${safe_wt}"

  if [ ! -d "$dir" ]; then
    if git show-ref --verify --quiet "refs/heads/$wt"; then
      git worktree add "$dir" "$wt"
    else
      git worktree add "$dir" -b "$wt" "$BASE_BRANCH"
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
