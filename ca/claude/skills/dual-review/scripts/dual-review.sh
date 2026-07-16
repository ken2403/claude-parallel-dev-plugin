#!/usr/bin/env bash
# Standalone dual-model review orchestrator: Codex second opinion + blind Claude
# review in PARALLEL, then a separate Claude synthesis call adjudicates — the
# same two-call-blind flow as the ca implement loop's final review, invokable
# on any PR at any time (including re-reviews after the loop finished).
#
# Flow:
#   codex-review.sh (offline, background) ──┐   exit!=0 → visible degrade,
#   claude-review.sh (blind, foreground) ───┤   blind JSON becomes final
#                                           ▼
#   synthesize-review.sh → final ca_claude_review.v1 (producer: synthesis)
#   Clean full-coverage Codex output with zero findings skips synthesis.
#
# Outputs in --out-dir (round N):
#   review-round-N.json         the gating verdict (final)
#   review-round-N.blind.json   the blind Claude review (kept for audit)
#   review-round-N.codex.json   the Codex second opinion (when produced)
#   review-round-N.meta.json    leg statuses / degrade reasons (never gates)
#
# Differences from the loop wiring, both deliberate:
#   - Legs run in PARALLEL (the loop runs Codex first): standalone latency
#     matters and the blind review cannot read a file that is being produced
#     concurrently by another process it never opens.
#   - codex-review.sh exit 4 (input fetch failed) DEGRADES here instead of
#     stopping: the blind leg fetched the same PR successfully in parallel, so
#     an asymmetric fetch failure is transient — the meta sidecar records it.
#
# Preconditions: `claude` on PATH (or CLAUDE_BIN) with the ca plugin resolvable
# (install it, or set CA_CLAUDE_PLUGIN_DIR); network + authenticated `gh`.
# `codex` (or CODEX_BIN) is OPTIONAL — absent means Claude-only with a note.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR="" PLAN="" WT="" ROUND="1" OUTDIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) PR="$2"; shift 2;;
    --plan) PLAN="$2"; shift 2;;
    --worktree) WT="$2"; shift 2;;
    --round) ROUND="$2"; shift 2;;
    --out-dir) OUTDIR="$2"; shift 2;;
    *) echo "dual-review: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$PR" ] && [ -n "$PLAN" ] && [ -n "$WT" ] && [ -n "$OUTDIR" ] || {
  echo "usage: dual-review.sh --pr N --plan P --worktree W [--round N] --out-dir D" >&2
  exit 2
}
[ -f "$PLAN" ] || { echo "dual-review: plan/intent file not found: $PLAN" >&2; exit 2; }
[ -d "$WT" ] || { echo "dual-review: worktree not found: $WT" >&2; exit 2; }
mkdir -p "$OUTDIR"

FINAL="$OUTDIR/review-round-$ROUND.json"
BLIND="$OUTDIR/review-round-$ROUND.blind.json"
CODEX="$OUTDIR/review-round-$ROUND.codex.json"
META="$OUTDIR/review-round-$ROUND.meta.json"

# Contract: if an earlier round produced a Codex leg and this round degrades,
# prior_findings_rechecked:false must be machine-readable in the meta sidecar.
PRIOR_RECHECK=""
for prior in "$OUTDIR"/review-round-*.codex.json; do
  [ -f "$prior" ] && [ "$prior" != "$CODEX" ] && PRIOR_RECHECK=',"prior_findings_rechecked":false'
done

# --- Both legs in parallel; the blind review never sees the Codex output -----
set +e
bash "$SCRIPT_DIR/codex-review.sh" \
  --plan "$PLAN" --pr "$PR" --worktree "$WT" --round "$ROUND" --out "$CODEX" \
  > "$OUTDIR/review-round-$ROUND.codex-leg.log" 2>&1 &
CODEX_JOB=$!
bash "$SCRIPT_DIR/claude-review.sh" \
  --plan "$PLAN" --pr "$PR" --worktree "$WT" --mode final --round "$ROUND" --out "$BLIND"
BLIND_RC=$?
wait "$CODEX_JOB"
CODEX_RC=$?
set -e

if [ "$BLIND_RC" -ne 0 ]; then
  echo "dual-review: the blind Claude review failed (rc=$BLIND_RC) — no verdict can be produced." >&2
  echo "  (see claude-review.sh output above; the Codex leg exited $CODEX_RC)" >&2
  exit 1
fi

json_field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],sys.argv[3]))' "$@"; }

case "$CODEX_RC" in
  0)
    COVERAGE="$(json_field "$CODEX" coverage partial)"
    NFINDINGS="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("findings",[])))' "$CODEX")"
    if [ "$COVERAGE" = "full" ] && [ "$NFINDINGS" = "0" ]; then
      printf '{"dual_review":true,"codex":{"status":"clean_no_synthesis","coverage":"full"},"synthesis":{"status":"skipped_clean"}}\n' > "$META"
      cp "$BLIND" "$FINAL"
    else
      printf '{"dual_review":true,"codex":{"status":"used","coverage":"%s"},"synthesis":{"status":"pending"}}\n' "$COVERAGE" > "$META"
      bash "$SCRIPT_DIR/synthesize-review.sh" \
        --blind "$BLIND" --second-opinion "$CODEX" --plan "$PLAN" \
        --pr "$PR" --worktree "$WT" --round "$ROUND" --out "$FINAL"
      printf '{"dual_review":true,"codex":{"status":"used","coverage":"%s"},"synthesis":{"status":"used"}}\n' "$COVERAGE" > "$META"
    fi
    ;;
  1)
    printf '{"dual_review":true,"codex":{"status":"invalid","reason":"schema_validation_failed"%s},"synthesis":{"status":"skipped_codex_invalid"}}\n' "$PRIOR_RECHECK" > "$META"
    cp "$BLIND" "$FINAL"
    ;;
  4)
    printf '{"dual_review":true,"codex":{"status":"unavailable","reason":"input_fetch_failed"%s},"synthesis":{"status":"skipped_codex_unavailable"}}\n' "$PRIOR_RECHECK" > "$META"
    cp "$BLIND" "$FINAL"
    ;;
  *)
    printf '{"dual_review":true,"codex":{"status":"unavailable","reason":"codex_unavailable_or_oversized"%s},"synthesis":{"status":"skipped_codex_unavailable"}}\n' "$PRIOR_RECHECK" > "$META"
    cp "$BLIND" "$FINAL"
    ;;
esac

VERDICT="$(json_field "$FINAL" verdict unknown)"
echo ""
echo "dual-review: verdict=$VERDICT"
echo "  final: $FINAL"
echo "  meta:  $(cat "$META")"
