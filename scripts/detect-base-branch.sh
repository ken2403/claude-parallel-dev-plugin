#!/usr/bin/env bash
# ==============================================================================
# Canonical base branch detection for the pw plugin.
#
# This is the SINGLE SOURCE OF TRUTH for base branch detection logic.
# All commands and scripts should use this implementation.
#
# Usage (standalone):
#   BASE_BRANCH=$(path/to/detect-base-branch.sh [repo-root])
#
# Usage (sourced):
#   source path/to/detect-base-branch.sh
#   BASE_BRANCH=$(get_base_branch [repo-root])
#
# Detection priority:
#   1. CLAUDE.md settings (base.branch / default.branch / primary.branch)
#   2. git symbolic-ref refs/remotes/origin/HEAD
#   3. First existing common branch: main, master, develop, dev
#   4. Fallback: "main"
# ==============================================================================

get_base_branch() {
  local repo_root="${1:-.}"
  local base_branch=""

  # 1. Check CLAUDE.md for base branch specification
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

# If run as standalone script (not sourced), execute and output
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  get_base_branch "${1:-.}"
fi
