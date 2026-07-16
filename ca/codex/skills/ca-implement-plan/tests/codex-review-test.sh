#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
SCRIPT="$ROOT/ca/codex/skills/ca-implement-plan/scripts/codex-review.sh"
TMP="${TMPDIR:-/tmp}/codex-review-test.$$"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/out"

PLAN="$TMP/plan.md"
printf '# Plan\n\nDo the thing.\n' > "$PLAN"

make_gh() {
  local diff_file="$1"
  local view_status="${2:-ok}"
  cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "pr view")
    [ "${GH_VIEW_STATUS:-ok}" = ok ] || exit 1
    cat <<'JSON'
{"number":12,"title":"feat: demo","state":"OPEN","isDraft":true,"baseRefName":"main","headRefName":"ca/demo","url":"https://example.invalid/pr/12"}
JSON
    ;;
  "pr diff")
    if [ "${3:-}" = "--name-only" ]; then
      printf 'src/app.py\nREADME.md\n'
    elif [ "${3:-}" = "--stat" ]; then
      printf ' src/app.py | 2 ++\n README.md | 1 +\n'
    else
      cat "$GH_DIFF_FILE"
    fi
    ;;
  *) echo "unexpected gh args: $*" >&2; exit 9;;
esac
SH
  chmod +x "$TMP/bin/gh"
  export GH_BIN="$TMP/bin/gh" GH_DIFF_FILE="$diff_file" GH_VIEW_STATUS="$view_status"
}

make_codex() {
  local mode="$1"
  cat > "$TMP/bin/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${CODEX_MODE:-valid}" in
  valid)
    cat >"${CODEX_CAPTURE_PROMPT:?}"
    cat <<'JSON'
{"schema_version":"ca_codex_review.v1","summary":"No issues found.","coverage":"full","findings":[]}
JSON
    ;;
  invalid)
    cat >"${CODEX_CAPTURE_PROMPT:?}"
    printf '{"schema_version":"wrong"}\n'
    ;;
  nonzero)
    cat >"${CODEX_CAPTURE_PROMPT:?}"
    echo "boom" >&2
    exit 42
    ;;
  nofile)
    cat >"${CODEX_CAPTURE_PROMPT:?}"
    ;;
  *) echo "bad CODEX_MODE" >&2; exit 9;;
esac
SH
  chmod +x "$TMP/bin/codex"
  export CODEX_BIN="$TMP/bin/codex" CODEX_MODE="$mode" CODEX_CAPTURE_PROMPT="$TMP/out/prompt.txt"
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

assert_json_field() {
  local file="$1" expr="$2" want="$3"
  local got
  got="$(python3 - "$file" "$expr" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
cur = d
for part in sys.argv[2].split("."):
    cur = cur[int(part)] if isinstance(cur, list) else cur[part]
print(cur)
PY
)"
  [ "$got" = "$want" ] || { echo "expected $expr=$want, got $got" >&2; exit 1; }
}

small_diff="$TMP/small.diff"
printf 'diff --git a/src/app.py b/src/app.py\n+ok\n' > "$small_diff"
make_gh "$small_diff"
make_codex valid

dry="$TMP/out/dry-run.txt"
"$SCRIPT" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/review.json" --dry-run > "$dry"
grep -q 'ca_codex_review.v1' "$dry"
grep -q 'Coverage: full' "$dry"

"$SCRIPT" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/review.json"
assert_json_field "$TMP/out/review.json" schema_version ca_codex_review.v1
assert_json_field "$TMP/out/review.json" coverage full

large_diff="$TMP/large.diff"
python3 - "$large_diff" <<'PY'
import sys
open(sys.argv[1], "w").write("diff --git a/README.md b/README.md\n" + "+" * 200)
PY
make_gh "$large_diff"
make_codex valid
CA_CODEX_REVIEW_FULL_DIFF_BYTES=20 "$SCRIPT" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/partial.json"
grep -q 'Coverage: partial' "$TMP/out/prompt.txt"
grep -q 'full diff omitted' "$TMP/out/prompt.txt"

make_gh "$small_diff" fail
make_codex valid
expect_status 4 "$SCRIPT" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/fetch.json"

make_gh "$small_diff"
rm -f "$TMP/bin/codex"
export CODEX_BIN="$TMP/bin/codex"
expect_status 3 "$SCRIPT" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/missing.json"

make_codex nonzero
expect_status 3 "$SCRIPT" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/nonzero.json"

make_codex invalid
expect_status 1 "$SCRIPT" --plan "$PLAN" --pr 12 --worktree "$ROOT" --round 1 --out "$TMP/out/invalid.json"

expect_status 2 "$SCRIPT" --plan "$PLAN" --pr 12 --round 1 --out "$TMP/out/usage.json"

echo "codex-review-test.sh: ok"
