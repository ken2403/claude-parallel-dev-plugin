# Claude review contract (ca_claude_review.v1)

The Claude reviewer returns a single JSON object to `--out`. The loop reads `verdict` and the
`blocking` flag on each finding. Treat any missing/malformed output as `verdict: "blocked"`.

```json
{
  "schema_version": "ca_claude_review.v1",
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
  ]
}
```

`mode` is optional and echoes the requested review mode; absent means `"final"`.

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
