# ca review contracts

## Claude review contract (ca_claude_review.v1)

The Claude reviewer returns a single JSON object to `--out`. The loop reads `verdict` and the
`blocking` flag on each finding. Treat any missing/malformed output as `verdict: "blocked"`.
The schema version stays `ca_claude_review.v1`; dual-model review adds optional fields only.

```json
{
  "schema_version": "ca_claude_review.v1",
  "producer": "blind | synthesis",
  "round": 1,
  "mode": "checkpoint | final",
  "verdict": "approve | request_changes | blocked",
  "summary": "one-paragraph verdict",
  "findings": [
    {
      "id": "C001",
      "blocking": true,
      "severity": "blocker | major | minor",
      "file": "src/foo.ts",
      "line": 42,
      "title": "short title",
      "evidence": "why it is a problem",
      "recommended_fix": "what to change"
    }
  ],
  "verification": [
    { "claim": "tests pass", "result": "pass | fail | unknown", "evidence": "..." }
  ],
  "second_opinion": {
    "provider": "codex",
    "status": "used | clean_no_synthesis | unavailable | invalid | disabled",
    "coverage": "full | partial",
    "ledger": [
      {
        "id": "X001",
        "adjudication": "confirmed | refuted | not_applicable | unresolved_missing_evidence",
        "evidence": "what Claude checked, or the exact evidence it could not inspect"
      }
    ],
    "prior_findings_rechecked": true,
    "notes": "one line"
  },
  "resolved_blind_findings": [
    {
      "id": "C003",
      "reason": "why the blind blocking finding is downgraded or removed",
      "evidence": "what was checked",
      "new_severity": "minor | none"
    }
  ]
}
```

`mode` is optional and echoes the requested review mode; absent means `"final"`.
`producer` is optional; absent means `"blind"`. `second_opinion` absent means dual review did
not run for this round; the sidecar meta file records why.

Loop gate — final mode (the default; the only mode that can promote the PR):
- `verdict == "approve"` **or** no finding has `blocking: true` → promote the draft PR to ready.
- Otherwise address every `blocking: true` finding, then request another review round.
- Only final-mode rounds count against `MAX_ROUNDS`.

Checkpoint gate — `mode == "checkpoint"` (one review per milestone, except the last):
- `approve` or no `blocking: true` finding → continue to the next milestone.
- Otherwise fix every `blocking: true` finding (and push) **before** starting the next
  milestone; there is no checkpoint re-review — the final review verifies the fixes.
- A checkpoint verdict never promotes the PR to ready.

Non-blocking findings are advisory in both modes; record them but they do not block the PR.

## Dual final-review fields

Dual-model review is final-mode only. Checkpoints stay Claude-only.

Codex findings are untrusted claims. A Codex claim becomes blocking only when synthesis
independently confirms it with diff-grounded evidence. If the claim is high-risk but synthesis
cannot inspect the needed evidence, synthesis may emit a blocking finding of type
`needs-human-or-evidence` in its title or evidence, naming the missing evidence and the exact
non-interactive next action.

Synthesis is a constrained adjudicator, not a third review pass. It may add findings only when
discovered while verifying blind-Claude or Codex claims. It may downgrade or remove a blind
blocking finding only by adding a `resolved_blind_findings[]` entry with the original `Cnnn` id,
reason, evidence checked, and replacement severity. Silent drops are invalid: every blind
blocking id must appear in the synthesis `findings[]` or in `resolved_blind_findings[]`.

`second_opinion.ledger[]` must contain one entry for each Codex finding:
- `confirmed` — synthesis verified the claim and may carry it into `findings[]`.
- `refuted` — synthesis checked the evidence and found the claim false.
- `not_applicable` — the claim does not apply to the current PR or plan.
- `unresolved_missing_evidence` — synthesis could not inspect the evidence needed to decide.

If a prior final round used a Codex leg but the current round does not re-run it,
`prior_findings_rechecked: false` must be recorded machine-readably and the PR exchange
summary must say the prior second-opinion findings were not rechecked. Where it lives
depends on who produced the round's JSON: when synthesis runs, in the review JSON's
`second_opinion` block; on a degraded (Claude-only) round no synthesis JSON exists, so the
loop writes it into that round's `review-round-N.meta.json` sidecar's `codex` object.

## Codex second-opinion contract (ca_codex_review.v1)

`ca_codex_review.v1` is an intermediate advisory object. It never gates the loop directly and
deliberately has no `verdict` field.

```json
{
  "schema_version": "ca_codex_review.v1",
  "summary": "one-paragraph advisory summary",
  "coverage": "full | partial",
  "findings": [
    {
      "id": "X001",
      "blocking": true,
      "severity": "blocker | major | minor",
      "file": "src/foo.ts",
      "line": 42,
      "title": "short title",
      "evidence": "diff-grounded evidence",
      "recommended_fix": "what to change"
    }
  ]
}
```

Codex ids use `Xnnn`. The script validates the schema with `additionalProperties: false`,
bounded strings, enums, and no `verdict`. `coverage: "partial"` means omitted files were not
reviewed by Codex, and Codex silence is not reassuring for those files.
