#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-kiddleton-dataplatform}"
WARP_SCHEME="${WARP_SCHEME:-warp}" # Warp Previewなら warppreview

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

# docs準拠：layout直下に cwd / commands を置く :contentReference[oaicite:1]{index=1}
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

# Launch configを起動（URI scheme） :contentReference[oaicite:2]{index=2}
open "${WARP_SCHEME}://launch/${LC_NAME}"

echo "Launch config written:"
echo "  ${yaml_path}"
echo "Launching:"
echo "  ${WARP_SCHEME}://launch/${LC_NAME}"
