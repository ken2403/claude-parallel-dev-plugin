#!/usr/bin/env bash
# Call the Claude reviewer (claude -p /ca:review-pr) and return a validated ca_claude_review.v1 JSON.
#
# TWO PRECONDITIONS — both must hold or no review is produced:
#  1. The `/ca:review-pr` skill must be resolvable by `claude -p`. That means EITHER the ca
#     Claude plugin is installed in the user's Claude config (`/plugin install ca@...`), OR you
#     set CA_CLAUDE_PLUGIN_DIR to the `ca/claude` plugin dir so this script passes --plugin-dir.
#  2. NETWORK + gh: `claude -p` reaches the Anthropic API, and the review fetches the PR via
#     `gh pr diff`, so both network and an authenticated `gh` are required. Codex's default
#     `-s workspace-write` sandbox BLOCKS network, so inside a sandboxed Codex session the call
#     fails. Run the review where network is allowed and `gh` is authenticated (network-permitted
#     Codex launch/approval, or a host terminal).
# Fail-closed: if no valid review is produced, exit 1 (the loop treats it as blocked) and print an
# actionable reason naming BOTH possible causes — never silently pass, never guess a single cause.
set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CA_CLAUDE_PLUGIN_DIR="${CA_CLAUDE_PLUGIN_DIR:-}"   # optional: load /ca:review-pr without a global install
PLAN="" PR="" WT="" ROUND="1" OUT="" MODE="final"
while [ $# -gt 0 ]; do case "$1" in
  --plan) PLAN="$2"; shift 2;; --pr) PR="$2"; shift 2;;
  --worktree) WT="$2"; shift 2;; --round) ROUND="$2"; shift 2;;
  --mode) MODE="$2"; shift 2;;
  --out) OUT="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 2;; esac; done
[ -n "$PLAN" ] && [ -n "$PR" ] && [ -n "$OUT" ] || {
  echo "usage: claude-review.sh --plan P --pr N --worktree W --round N [--mode checkpoint|final] --out O" >&2; exit 2; }
case "$MODE" in checkpoint|final) ;; *) echo "claude-review: bad --mode '$MODE' (checkpoint|final)" >&2; exit 2;; esac

command -v "$CLAUDE_BIN" >/dev/null 2>&1 || {
  echo "claude-review: '$CLAUDE_BIN' not found on PATH. Set CLAUDE_BIN or install Claude Code." >&2
  exit 1; }

rm -f "$OUT"          # ensure a stale file from a prior round can't masquerade as this review
export CA_OUT="$OUT"
# Invoke the /ca:review-pr plugin skill; it writes the JSON to CA_OUT (also passed explicitly).
PROMPT="/ca:review-pr
plan=$PLAN
pr=$PR
worktree=$WT
round=$ROUND
mode=$MODE
out=$OUT
Review the PR against the plan for correctness, security, and codebase consistency.
Use web search if a claim needs external grounding. Mark a finding blocking:true only for
must-fix issues. Write a single ca_claude_review.v1 JSON object to: $OUT"

ERR="${OUT%.json}.stderr"
CLAUDE_ARGS=( -p )
[ -n "$CA_CLAUDE_PLUGIN_DIR" ] && CLAUDE_ARGS+=( --plugin-dir "$CA_CLAUDE_PLUGIN_DIR" )
"$CLAUDE_BIN" "${CLAUDE_ARGS[@]}" "$PROMPT" >/dev/null 2>>"$ERR" || true

if [ ! -s "$OUT" ]; then
  {
    echo "claude-review: no review JSON was produced at $OUT. One of these is the cause:"
    echo "  (a) the /ca:review-pr skill did not resolve — install the ca Claude plugin"
    echo "      ('/plugin install ca@claude-parallel-dev-plugin') or set CA_CLAUDE_PLUGIN_DIR"
    echo "      to the ca/claude dir so this script can pass --plugin-dir; or"
    echo "  (b) the Anthropic API was unreachable, or 'gh' is unauthenticated/offline (Codex's"
    echo "      workspace-write sandbox blocks network) — run the review where network + gh work."
    [ -n "$CA_CLAUDE_PLUGIN_DIR" ] && echo "  (CA_CLAUDE_PLUGIN_DIR is set to: $CA_CLAUDE_PLUGIN_DIR)" \
      || echo "  (CA_CLAUDE_PLUGIN_DIR is not set — relying on a global ca plugin install)"
    echo "  claude stderr: ${ERR}"
  } >&2
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
