#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
VALIDATOR="$ROOT/ca/claude/skills/review-pr/scripts/validate-review.py"
TMP="${TMPDIR:-/tmp}/validate-review-test.$$"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP"

write_json() {
  local path="$1"
  shift
  printf '%s\n' "$*" > "$path"
}

expect_status() {
  local want="$1"
  shift
  set +e
  "$@" >/dev/null 2>"$TMP/err"
  local got=$?
  set -e
  if [ "$got" -ne "$want" ]; then
    echo "expected status $want, got $got: $*" >&2
    cat "$TMP/err" >&2
    exit 1
  fi
}

blind="$TMP/blind.json"
write_json "$blind" '{
  "schema_version": "ca_claude_review.v1",
  "round": 1,
  "mode": "final",
  "verdict": "request_changes",
  "summary": "Blind review",
  "findings": [
    {"id": "C001", "blocking": true, "severity": "major", "title": "Blind blocker"}
  ],
  "verification": []
}'

synth="$TMP/synth.json"
write_json "$synth" '{
  "schema_version": "ca_claude_review.v1",
  "producer": "synthesis",
  "round": 1,
  "mode": "final",
  "verdict": "approve",
  "summary": "Synthesized review",
  "findings": [],
  "verification": [],
  "second_opinion": {
    "provider": "codex",
    "status": "used",
    "coverage": "full",
    "ledger": [
      {"id": "X001", "adjudication": "refuted", "evidence": "Diff shows no issue."}
    ],
    "prior_findings_rechecked": true,
    "notes": "ok"
  },
  "resolved_blind_findings": [
    {"id": "C001", "reason": "false positive", "evidence": "Checked file.", "new_severity": "none"}
  ]
}'
python3 "$VALIDATOR" "$synth" "$blind" >/dev/null

silent_drop="$TMP/silent-drop.json"
write_json "$silent_drop" '{
  "schema_version": "ca_claude_review.v1",
  "producer": "synthesis",
  "round": 1,
  "mode": "final",
  "verdict": "approve",
  "summary": "Dropped blind blocker",
  "findings": [],
  "verification": [],
  "second_opinion": {
    "provider": "codex",
    "status": "used",
    "coverage": "full",
    "ledger": [],
    "prior_findings_rechecked": true
  },
  "resolved_blind_findings": []
}'
expect_status 1 python3 "$VALIDATOR" "$silent_drop" "$blind"

bad_ledger="$TMP/bad-ledger.json"
write_json "$bad_ledger" '{
  "schema_version": "ca_claude_review.v1",
  "producer": "synthesis",
  "round": 1,
  "mode": "final",
  "verdict": "approve",
  "summary": "Bad ledger",
  "findings": [{"id": "C001", "blocking": true, "severity": "major", "title": "Still present"}],
  "verification": [],
  "second_opinion": {
    "provider": "codex",
    "status": "used",
    "coverage": "full",
    "ledger": [
      {"id": "X001", "adjudication": "maybe", "evidence": "nope"}
    ],
    "prior_findings_rechecked": true
  },
  "resolved_blind_findings": []
}'
expect_status 1 python3 "$VALIDATOR" "$bad_ledger" "$blind"

blind_missing_id="$TMP/blind-missing-id.json"
write_json "$blind_missing_id" '{
  "schema_version": "ca_claude_review.v1",
  "round": 1,
  "mode": "final",
  "verdict": "request_changes",
  "summary": "Blind review",
  "findings": [
    {"blocking": true, "severity": "major", "title": "Blind blocker"}
  ],
  "verification": []
}'
expect_status 1 python3 "$VALIDATOR" "$synth" "$blind_missing_id"

# Plain (non-synthesis) reviews may omit finding ids entirely...
plain_no_ids="$TMP/plain-no-ids.json"
write_json "$plain_no_ids" '{
  "schema_version": "ca_claude_review.v1",
  "round": 1,
  "mode": "final",
  "verdict": "request_changes",
  "summary": "plain review without ids",
  "findings": [
    {"blocking": true, "severity": "major", "title": "No id, still valid"}
  ],
  "verification": []
}'
expect_status 0 python3 "$VALIDATOR" "$plain_no_ids"

# ...but a present id must still match the pattern,
plain_bad_id="$TMP/plain-bad-id.json"
write_json "$plain_bad_id" '{
  "schema_version": "ca_claude_review.v1",
  "verdict": "approve",
  "summary": "bad id format",
  "findings": [
    {"id": "BOGUS-1", "blocking": false, "title": "Malformed id"}
  ],
  "verification": []
}'
expect_status 1 python3 "$VALIDATOR" "$plain_bad_id"

# ...and synthesis output still requires ids on every finding.
synth_missing_finding_id="$TMP/synth-missing-finding-id.json"
write_json "$synth_missing_finding_id" '{
  "schema_version": "ca_claude_review.v1",
  "producer": "synthesis",
  "verdict": "approve",
  "summary": "synthesis without finding ids",
  "findings": [
    {"blocking": false, "title": "Missing id on synthesis output"}
  ],
  "verification": [],
  "second_opinion": {"provider": "codex", "status": "used", "coverage": "full", "ledger": []}
}'
expect_status 1 python3 "$VALIDATOR" "$synth_missing_finding_id"

echo "validate-review-test.sh: ok"
