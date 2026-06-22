#!/usr/bin/env bash
# Call the host-side Claude reviewer and return a validated ca_claude_review.v1 JSON.
# Runs OUTSIDE Codex's sandbox (the Codex skill invokes it via the shell tool), so Claude
# has its own network/web-search. Fail-closed: malformed output -> exit 1 (treat as blocked).
set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
PLAN="" DIFF="" WT="" ROUND="1" OUT=""
while [ $# -gt 0 ]; do case "$1" in
  --plan) PLAN="$2"; shift 2;; --diff) DIFF="$2"; shift 2;;
  --worktree) WT="$2"; shift 2;; --round) ROUND="$2"; shift 2;;
  --out) OUT="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 2;; esac; done
[ -n "$PLAN" ] && [ -n "$DIFF" ] && [ -n "$OUT" ] || {
  echo "usage: claude-review.sh --plan P --diff D --worktree W --round N --out O" >&2; exit 2; }

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

"$CLAUDE_BIN" -p "$PROMPT" >/dev/null 2>>"${OUT%.json}.stderr" || true

# Validate (stdlib only). Missing/malformed -> blocked.
python3 - "$OUT" <<'PY' || { echo "review missing/invalid -> blocked" >&2; exit 1; }
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
