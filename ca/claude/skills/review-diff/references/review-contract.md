# Claude review contract (ca_claude_review.v1)

The Claude reviewer returns a single JSON object to `--out`. The loop reads `verdict` and the
`blocking` flag on each finding. Treat any missing/malformed output as `verdict: "blocked"`.

```json
{
  "schema_version": "ca_claude_review.v1",
  "round": 1,
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

Loop gate:
- `verdict == "approve"` **or** no finding has `blocking: true` → proceed to PR.
- Otherwise address every `blocking: true` finding, then request another review round.
- Non-blocking findings are advisory; record them but they do not block the PR.
