#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.local.yaml"

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

# 環境変数 > 設定ファイル > デフォルト値 の優先順位
PROJECT_NAME="${PROJECT_NAME:-$(get_config "project_name" "my-project")}"
WARP_SCHEME="${WARP_SCHEME:-$(get_config "warp_scheme" "warp")}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <worktree1> [worktree2] ..."
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
PARENT_DIR="$(dirname "$REPO_ROOT")"

LAUNCH_DIR="$HOME/.warp/launch_configurations"
mkdir -p "$LAUNCH_DIR"

ts="$(date +%Y%m%d_%H%M%S)"
LC_NAME="${PROJECT_NAME}_spinup_${ts}"
yaml_path="${LAUNCH_DIR}/${LC_NAME}.yaml"

# docs準拠：layout直下に cwd / commands を置く
{
  echo "---"
  echo "name: ${LC_NAME}"
  echo "windows:"
  echo "  - tabs:"
  for wt in "$@"; do
    safe_wt="${wt//\//-}"
    dir="${PARENT_DIR}/wt-${safe_wt}"
    session="${PROJECT_NAME}__${safe_wt}"
    cmd="tmux attach -t ${session} || tmux new -s ${session}"

    # dir が存在しないとcwdが効かず / になるので念のためチェック
    if [ ! -d "$dir" ]; then
      echo "Error: worktree dir not found: $dir" >&2
      exit 1
    fi

    echo "      - title: ${safe_wt}"
    echo "        layout:"
    echo "          cwd: ${dir}"
    echo "          commands:"
    echo "            - exec: \"${cmd}\""
  done
} > "$yaml_path"

# Launch configを起動（URI scheme）
open "${WARP_SCHEME}://launch/${LC_NAME}"

echo "Launch config written:"
echo "  ${yaml_path}"
echo "Launching:"
echo "  ${WARP_SCHEME}://launch/${LC_NAME}"
