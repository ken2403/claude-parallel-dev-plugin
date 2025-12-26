#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-kiddleton-dataplatform}"
KEEP_BRANCHES=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  teardown.sh [--keep-branches] [--dry-run] <worktree1> [worktree2] ...

Examples:
  ./scripts/teardown.sh test1 test2
  ./scripts/teardown.sh --keep-branches test1 test2
  ./scripts/teardown.sh --dry-run test1 test2
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

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Error: run this inside a git repository."
  exit 1
}

REPO_ROOT="$(git rev-parse --show-toplevel)"
PARENT_DIR="$(dirname "$REPO_ROOT")"

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

echo "PROJECT_NAME: $PROJECT_NAME"
echo "Repo: $REPO_ROOT"
echo "Worktree parent: $PARENT_DIR"
echo "WORKTREES: ${ARGS[*]}"
echo "KEEP_BRANCHES: $KEEP_BRANCHES"
echo "DRY_RUN: $DRY_RUN"
echo

for wt in "${ARGS[@]}"; do
  safe_wt="${wt//\//-}"
  dir="${PARENT_DIR}/wt-${safe_wt}"
  session="${PROJECT_NAME}__${safe_wt}"
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
    run "git worktree remove --force '$dir' 2>/dev/null || true"
    run "rm -rf '$dir' 2>/dev/null || true"
    echo "removed worktree dir: $dir"
  else
    # ディレクトリが無くても登録だけ残っている場合があるので一応試す
    run "git worktree remove --force '$dir' 2>/dev/null || true"
    echo "worktree dir not found (attempted detach anyway): $dir"
  fi

  # 3) delete branch (optional)
  if ! $KEEP_BRANCHES; then
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      # 他worktreeで使用中なら削除しない
      if git worktree list --porcelain | awk -v b="refs/heads/$branch" '
        /^branch /{br=$2}
        br==b {found=1}
        END{exit found?0:1}
      '; then
        echo "branch is still used by a worktree, skip delete: $branch"
      else
        run "git branch -D '$branch'"
        echo "deleted branch: $branch"
      fi
    else
      echo "branch not found: $branch"
    fi
  else
    echo "keep branches: $branch"
  fi

  echo
done

echo "Done. (teardown)"
