#!/usr/bin/env bash
# Call the Claude reviewer (claude -p /ca:review-diff) and return a validated ca_claude_review.v1 JSON.
#
# NETWORK REQUIRED: `claude -p` reaches the Anthropic API. Codex's default sandbox
# (`-s workspace-write`) BLOCKS network, so when this runs inside a sandboxed Codex
# session the call fails and no review is produced. Run it where network is allowed:
#   - launch Codex for ca work with network permitted for this command (approval/profile), or
#   - run this script in a normal host terminal between rounds and point the loop at $OUT.
# Fail-closed: if no valid review is produced, exit 1 (the loop treats it as blocked) and
# print an actionable reason — never silently pass.
set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
PLAN="" DIFF="" WT="" ROUND="1" OUT=""
while [ $# -gt 0 ]; do case "$1" in
  --plan) PLAN="$2"; shift 2;; --diff) DIFF="$2"; shift 2;;
  --worktree) WT="$2"; shift 2;; --round) ROUND="$2"; shift 2;;
  --out) OUT="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 2;; esac; done
[ -n "$PLAN" ] && [ -n "$DIFF" ] && [ -n "$OUT" ] || {
  echo "usage: claude-review.sh --plan P --diff D --worktree W --round N --out O" >&2; exit 2; }

command -v "$CLAUDE_BIN" >/dev/null 2>&1 || {
  echo "claude-review: '$CLAUDE_BIN' not found on PATH. Set CLAUDE_BIN or install Claude Code." >&2
  exit 1; }

rm -f "$OUT"          # ensure a stale file from a prior round can't masquerade as this review
export CA_OUT="$OUT"
# Invoke the /ca:review-diff plugin skill; it writes the JSON to CA_OUT (also passed explicitly).
PROMPT="/ca:review-diff
plan=$PLAN
diff=$DIFF
worktree=$WT
round=$ROUND
out=$OUT
Review the diff against the plan for correctness, security, and codebase consistency.
Use web search if a claim needs external grounding. Mark a finding blocking:true only for
must-fix issues. Write a single ca_claude_review.v1 JSON object to: $OUT"

ERR="${OUT%.json}.stderr"
"$CLAUDE_BIN" -p "$PROMPT" >/dev/null 2>>"$ERR" || true

if [ ! -s "$OUT" ]; then
  echo "claude-review: no review file was produced at $OUT." >&2
  echo "  Most likely the Anthropic API was unreachable (Codex sandbox blocks network)." >&2
  echo "  Run this review step where network is allowed (see the header of this script)." >&2
  echo "  claude stderr: ${ERR}" >&2
  exit 1
fi

# Validate (stdlib only, self-contained). Malformed -> blocked.
python3 - "$OUT" <<'PY' || { echo "claude-review: output failed schema validation -> treat as blocked" >&2; exit 1; }
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"parse error: {e}", file=sys.stderr); sys.exit(1)
if d.get("verdict") not in ("approve", "request_changes", "blocked"):
    print("bad verdict", file=sys.stderr); sys.exit(1)
if not isinstance(d.get("findings"), list):
    print("findings not a list", file=sys.stderr); sys.exit(1)
for f in d["findings"]:
    if not isinstance(f.get("blocking"), bool):
        print("finding.blocking not bool", file=sys.stderr); sys.exit(1)
print(d["verdict"])
PY
