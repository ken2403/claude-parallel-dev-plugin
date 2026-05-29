#!/usr/bin/env bash
# ==============================================================================
# Canonical base-branch detection for the hive plugin (self-contained).
#
# Usage (standalone):  BASE_BRANCH=$(path/to/detect-base-branch.sh [repo-root])
# Usage (sourced, bash only):  source detect-base-branch.sh; BASE_BRANCH=$(get_base_branch)
# All plugin callers invoke it standalone via `bash <script>`, which is portable.
#
# Priority: CLAUDE.md hint -> origin/HEAD local ref -> remote HEAD -> common
#           branch (main/master/develop/dev) -> "main".
# ==============================================================================

get_base_branch() {
  local repo_root="${1:-.}"
  local base_branch=""

  if [ -f "${repo_root}/CLAUDE.md" ]; then
    base_branch=$(grep -i "base.branch\|default.branch\|primary.branch" "${repo_root}/CLAUDE.md" 2>/dev/null | head -1 | grep -oE "(main|master|develop|dev|release[^[:space:]]*)" | head -1 || echo "")
  fi
  if [ -z "$base_branch" ]; then
    base_branch=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
  fi
  if [ -z "$base_branch" ]; then
    base_branch=$(git -C "$repo_root" ls-remote --symref origin HEAD 2>/dev/null | grep '^ref:' | sed 's@ref: refs/heads/@@' | sed 's@[[:space:]].*@@' || echo "")
  fi
  if [ -z "$base_branch" ]; then
    for branch in main master develop dev; do
      if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        base_branch="$branch"; break
      fi
    done
  fi
  echo "${base_branch:-main}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  get_base_branch "${1:-.}"
fi
