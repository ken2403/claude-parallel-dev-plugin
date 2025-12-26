#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="kiddleton-dataplatform"
BASE_BRANCH="dev"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <worktree1> [worktree2] ..."
  exit 1
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Error: run this inside a git repository."
  exit 1
}

# ★ worktreeの作成先を「リポジトリの親」に固定
REPO_ROOT="$(git rev-parse --show-toplevel)"
PARENT_DIR="$(dirname "$REPO_ROOT")"

for wt in "$@"; do
  safe_wt="${wt//\//-}"                 # feature/foo 対策
  dir="${PARENT_DIR}/wt-${safe_wt}"     # ★ 1段上に作る（絶対パス）
  session="${PROJECT_NAME}__${safe_wt}" # ★ : を使わない

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

# ★ Warp起動は Launch Configuration 方式に切り替える
PROJECT_NAME="$PROJECT_NAME" ../.paralell/open-warp-windows.sh "$@"
