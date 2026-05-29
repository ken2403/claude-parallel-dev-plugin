#!/usr/bin/env bash
# ==============================================================================
# Snapshot of hive background agents + their PRs, as machine-readable text.
#
# Joins `claude agents --json` (live background sessions) with `gh pr list`
# (PR + CI state) so the /hive:status skill can build one table without
# re-deriving either source. Degrades gracefully when a tool is missing.
#
# Usage: agents-status.sh [name-prefix]   # default prefix: "hive/"
# ==============================================================================
set -uo pipefail
PREFIX="${1:-hive/}"

echo "=== HIVE AGENTS (claude agents --json) ==="
if command -v claude >/dev/null 2>&1; then
  # Filter to hive-launched agents by name prefix when jq is available.
  if command -v jq >/dev/null 2>&1; then
    claude agents --json 2>/dev/null \
      | jq -r --arg p "$PREFIX" \
        '.[]? | select((.name // "") | startswith($p)) | "\(.name)\t\(.status)\t\(.sessionId)\t\(.cwd)"' \
      2>/dev/null || echo "(no agents or unable to parse)"
  else
    claude agents --json 2>/dev/null || echo "(install jq for filtered view)"
  fi
else
  echo "(claude CLI not found)"
fi

echo
echo "=== OPEN PRs (gh pr list) ==="
if command -v gh >/dev/null 2>&1; then
  gh pr list --state open --limit 50 \
    --json number,title,headRefName,isDraft,statusCheckRollup,reviewDecision \
    --jq '.[] | "#\(.number)\t\(.headRefName)\t\(.reviewDecision // "PENDING")\t\(.title)"' \
    2>/dev/null || echo "(no PRs or gh not authenticated)"
else
  echo "(gh CLI not found)"
fi
