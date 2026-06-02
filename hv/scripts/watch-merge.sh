#!/usr/bin/env bash
# watch-merge.sh — poll one PR until it merges (or closes / times out), with
# exponential backoff, then print a single status token the watch-merges skill
# acts on. This script ONLY watches; the destructive cleanup is the janitor's
# job, reached via /hv:clean-agents. It never removes anything itself.
#
# Usage:
#   watch-merge.sh <pr-number|branch|url> [--repo OWNER/REPO]
#                  [--initial S] [--factor N] [--cap S] [--max H]
#
# Backoff: sleep starts at --initial seconds and multiplies by --factor each
# poll, capped at --cap, so a merge right after the PR opens is caught quickly
# while a long-lived PR is polled sparingly. Gives up after --max hours.
#
# Final stdout line (machine-readable; everything else goes to stderr):
#   MERGED <branch>           exit 0  -> caller runs /hv:clean-agents <branch>
#   CLOSED_UNMERGED <branch>  exit 2  -> caller cleans nothing (work not landed)
#   TIMEOUT <branch>          exit 3  -> still open after --max; caller reports
#   ERROR <message>           exit 4  -> bad target / gh not authed (first poll)
set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ]; then echo "ERROR missing <pr|branch> argument"; exit 4; fi
shift

REPO=""
INITIAL=30        # first sleep, seconds
FACTOR=2          # backoff multiplier (>=1; fractional allowed)
CAP=600           # max sleep between polls, seconds (10 min)
MAX_HOURS=24      # give up after this many hours still-open

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    REPO="${2:-}"; shift 2 ;;
    --initial) INITIAL="${2:-}"; shift 2 ;;
    --factor)  FACTOR="${2:-}"; shift 2 ;;
    --cap)     CAP="${2:-}"; shift 2 ;;
    --max)     MAX_HOURS="${2:-}"; shift 2 ;;
    *) echo "ERROR unknown argument: $1"; exit 4 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "ERROR gh CLI not found on PATH"; exit 4; }

# Safe empty-array expansion under `set -u` (macOS bash 3.2 compatible).
repo_args=()
if [ -n "$REPO" ]; then repo_args=(--repo "$REPO"); fi

read_pr() {
  gh pr view "$TARGET" ${repo_args[@]+"${repo_args[@]}"} \
     --json state,mergedAt,headRefName \
     --jq '[.state, .headRefName, (.mergedAt // "")] | @tsv' 2>/dev/null
}

start=$(date +%s)
max_seconds=$(( MAX_HOURS * 3600 ))
interval="$INITIAL"
BRANCH=""

while :; do
  line="$(read_pr || true)"
  if [ -n "$line" ]; then
    IFS=$'\t' read -r state branch mergedat <<<"$line"
    if [ -n "${branch:-}" ]; then BRANCH="$branch"; fi
    if [ "${state:-}" = "MERGED" ] || [ -n "${mergedat:-}" ]; then
      echo "MERGED ${BRANCH:-$TARGET}"; exit 0
    fi
    if [ "${state:-}" = "CLOSED" ]; then
      echo "CLOSED_UNMERGED ${BRANCH:-$TARGET}"; exit 2
    fi
    # OPEN -> keep waiting
  elif [ -z "$BRANCH" ]; then
    # The very first poll failed: bad target, no such PR, or gh not authed.
    echo "ERROR cannot read PR '$TARGET' (not found, or gh not authenticated)"
    exit 4
  fi
  # A transient read failure after a good first poll is tolerated: keep polling.

  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -ge "$max_seconds" ]; then
    echo "TIMEOUT ${BRANCH:-$TARGET}"; exit 3
  fi

  # Never overshoot --max by more than necessary.
  remaining=$(( max_seconds - elapsed ))
  if [ "$interval" -gt "$remaining" ]; then interval="$remaining"; fi

  echo "[watch-merge] ${BRANCH:-$TARGET} still open; elapsed ${elapsed}s, next poll in ${interval}s" >&2
  sleep "$interval"

  # Exponential backoff, capped (awk handles fractional --factor).
  interval="$(awk -v i="$interval" -v f="$FACTOR" -v c="$CAP" \
    'BEGIN{ n=int(i*f+0.5); if(n>c)n=c; if(n<1)n=1; print n }')"
done
