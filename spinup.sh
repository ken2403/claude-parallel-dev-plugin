#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"

# 設定ファイルからYAML値を取得する関数
get_config() {
  local key="$1"
  local default="${2:-}"
  if [ -f "$CONFIG_FILE" ]; then
    local value
    value=$(grep "^${key}:" "$CONFIG_FILE" | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' | tr -d '\r')
    if [ -n "$value" ]; then
      echo "$value"
      return
    fi
  fi
  echo "$default"
}

# 設定を読み込み
PROJECT_NAME="$(get_config "project_name" "my-project")"
BASE_BRANCH="$(get_config "base_branch" "main")"
UI_MODE="$(get_config "ui_mode" "warp")"
WARP_SCHEME="$(get_config "warp_scheme" "warp")"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <worktree1> [worktree2] ..."
  echo ""
  echo "Config: $CONFIG_FILE"
  echo "  project_name: $PROJECT_NAME"
  echo "  base_branch:  $BASE_BRANCH"
  echo "  ui_mode:      $UI_MODE"
  echo "  warp_scheme:  $WARP_SCHEME"
  exit 1
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Error: run this inside a git repository."
  exit 1
}

# worktreeの作成先を「リポジトリの親」に固定
REPO_ROOT="$(git rev-parse --show-toplevel)"
PARENT_DIR="$(dirname "$REPO_ROOT")"

for wt in "$@"; do
  safe_wt="${wt//\//-}"                 # feature/foo 対策
  dir="${PARENT_DIR}/wt-${safe_wt}"     # 1段上に作る（絶対パス）
  session="${PROJECT_NAME}__${safe_wt}" # : を使わない

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

# UI_MODEに応じてWarpを起動するか決定
if [ "$UI_MODE" = "warp" ]; then
  PROJECT_NAME="$PROJECT_NAME" WARP_SCHEME="$WARP_SCHEME" "${SCRIPT_DIR}/open-warp-windows.sh" "$@"
else
  echo ""
  echo "tmux mode: sessions created in background"
  echo "Attach with: tmux attach -t <session_name>"
fi
