#!/usr/bin/env bash
# Create an isolated worktree for a plan and print the command to start Codex inside it.
# The worktree (not the model) owns isolation, per the ca design. Run from the repo.
set -euo pipefail
PLAN="${1:?usage: new-worktree.sh <plan.md>}"
[ -f "$PLAN" ] || { echo "plan not found: $PLAN" >&2; exit 1; }

# Resolve the ORIGINAL plan to an absolute path; its basename is the stable feature id.
# (Always pass this original path to the skill — never the staged copy, whose basename
# would collapse the id to "plan".)
ABS_PLAN="$(cd "$(dirname "$PLAN")" && pwd)/$(basename "$PLAN")"
ID="$(basename "$PLAN" .md)"
ROOT="$(git -C "$(dirname "$ABS_PLAN")" rev-parse --show-toplevel 2>/dev/null || git rev-parse --show-toplevel)"
BASE="${CA_BASE:-main}"
WT="$ROOT/.claude/ca/$ID"          # isolated worktree, inside the repo under .claude/ca/
BR="ca/$ID"

git -C "$ROOT" fetch origin "$BASE" >/dev/null 2>&1 || true
mkdir -p "$ROOT/.claude/ca"
if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BR"; then
  git -C "$ROOT" worktree add "$WT" "$BR"
else
  git -C "$ROOT" worktree add -b "$BR" "$WT" "origin/$BASE" 2>/dev/null \
    || git -C "$ROOT" worktree add -b "$BR" "$WT" "$BASE"
fi

RUN="$WT/.ca/runs/$ID"; mkdir -p "$RUN"
cp "$ABS_PLAN" "$RUN/plan.md"
shasum -a 256 "$ABS_PLAN" | awk '{print $1}' > "$RUN/plan.sha256"

echo "worktree ready: $WT  (branch $BR)"
echo
echo "Start Codex inside it and invoke the skill (pass the ORIGINAL plan path):"
echo "  codex -C \"$WT\""
echo "  # then in the session:  \$ca-implement-plan  PLAN=$ABS_PLAN"
