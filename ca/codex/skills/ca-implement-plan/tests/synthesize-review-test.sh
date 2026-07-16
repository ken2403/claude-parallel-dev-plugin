#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
SCRIPT="$ROOT/ca/codex/skills/ca-implement-plan/scripts/synthesize-review.sh"
TMP="${TMPDIR:-/tmp}/synthesize-review-test.$$"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/out"

PLAN="$TMP/plan.md"
BLIND="$TMP/blind.json"
SECOND="$TMP/codex.json"
printf '# Plan\n' > "$PLAN"
cat > "$BLIND" <<'JSON'
{"schema_version":"ca_claude_review.v1","round":1,"mode":"final","verdict":"request_changes","summary":"blind","findings":[{"id":"C001","blocking":true,"severity":"major","title":"blind blocker"}],"verification":[]}
JSON
cat > "$SECOND" <<'JSON'
{"schema_version":"ca_codex_review.v1","summary":"codex","coverage":"full","findings":[{"id":"X001","blocking":true,"severity":"major","title":"codex claim","evidence":"e","recommended_fix":"fix"}]}
JSON

make_claude() {
  local mode="$1"
  cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${CLAUDE_MODE:-valid}" in
  valid)
    printf '%s\n' "$*" >"${CLAUDE_CAPTURE_PROMPT:?}"
    cat >"${CA_OUT:?}" <<'JSON'
{"schema_version":"ca_claude_review.v1","producer":"synthesis","round":1,"mode":"final","verdict":"approve","summary":"synth","findings":[],"verification":[],"second_opinion":{"provider":"codex","status":"used","coverage":"full","ledger":[{"id":"X001","adjudication":"refuted","evidence":"checked"}],"prior_findings_rechecked":true},"resolved_blind_findings":[{"id":"C001","reason":"false positive","evidence":"checked","new_severity":"none"}]}
JSON
    ;;
  invalid)
    printf '%s\n' "$*" >"${CLAUDE_CAPTURE_PROMPT:?}"
    printf '{"verdict":"approve","findings":[]}\n' >"${CA_OUT:?}"
    ;;
  nofile)
    printf '%s\n' "$*" >"${CLAUDE_CAPTURE_PROMPT:?}"
    ;;
  *) echo "bad CLAUDE_MODE" >&2; exit 9;;
esac
SH
  chmod +x "$TMP/bin/claude"
  export CLAUDE_BIN="$TMP/bin/claude" CLAUDE_MODE="$mode" CLAUDE_CAPTURE_PROMPT="$TMP/out/prompt.txt"
}

expect_status() {
  local want="$1"
  shift
  set +e
  "$@"
  local got=$?
  set -e
  if [ "$got" -ne "$want" ]; then
    echo "expected status $want, got $got: $*" >&2
    exit 1
  fi
}

make_claude valid
"$SCRIPT" --blind "$BLIND" --second-opinion "$SECOND" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/synth.json"
python3 - "$TMP/out/synth.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["producer"] == "synthesis"
assert d["second_opinion"]["status"] == "used"
PY
grep -q '/ca:synthesize-review' "$TMP/out/prompt.txt"

make_claude invalid
expect_status 1 "$SCRIPT" --blind "$BLIND" --second-opinion "$SECOND" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/invalid.json"

make_claude nofile
expect_status 1 "$SCRIPT" --blind "$BLIND" --second-opinion "$SECOND" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/nofile.json"

expect_status 2 "$SCRIPT" --blind "$BLIND" --second-opinion "$SECOND" --plan "$PLAN" --pr 12 --round 1 --out "$TMP/out/usage.json"

echo "synthesize-review-test.sh: ok"
