---
name: review-diff
description: Review a code worktree diff against the implementation plan it was built from, then emit a structured ca_claude_review.v1 JSON verdict (approve / request_changes / blocked) with blocking findings. Use when the ca loop or a user asks to review a Codex-built diff before a PR exists, or says things like "review this diff against the plan", "review what you built", "is this implementation correct", or invokes /ca:review-diff. Reviews the diff itself; does not edit code.
license: MIT
model: opus
effort: high
allowed-tools: Read, Grep, Glob, Bash, WebFetch
disable-model-invocation: true
---

# review-diff

Review a worktree diff against its plan and return a single `ca_claude_review.v1` JSON object. You are the reviewer half of the ca (Cooperate Agents) loop: Codex implemented; you judge, adversarially, before a PR exists.

## Important — inputs and output

The invocation passes (as plain `key=value` lines): `plan=<path>`, `diff=<path>`, `worktree=<path>`, `round=<n>`, and an output path (env `CA_OUT`, else an `out=<path>` line). Write the JSON object to that path and to nothing else. Do not modify code under `worktree`.

## Step 1 — Gather context

1. Read the plan file and the diff file in full.
2. From `worktree`, read the surrounding code the diff touches (callers, callees, tests, configs) — enough to judge integration, not just the diff in isolation. Use `Grep`/`Glob`.
3. Use `WebFetch`/web search only when a claim needs external grounding (a library contract, a CVE, a spec).

## Step 2 — Review (be adversarial, evidence-based)

Judge along these axes; for each problem you assert, cite file:line evidence — never "looks fine" without proof:

- **Plan conformance:** every plan task implemented; no scope creep; success criteria met.
- **Correctness:** logic, edge cases, error handling, off-by-one, async/concurrency, resource cleanup.
- **Security:** input validation, authz/authn, injection (SQL/command/path/XSS), secrets, SSRF, unsafe deserialization, sensitive-data logging. Assume hostile input; trace untrusted data to sinks.
- **Codebase consistency:** matches existing conventions; renames propagated everywhere; no stale references or duplicated logic; docs/types/config in sync.
- **Tests & evidence:** tests exist and actually exercise the change; build/lint/typecheck pass (check the diff's test output if present, or note it's unverified).

Mark a finding `blocking: true` ONLY for must-fix issues (wrong behavior, security holes, missing required functionality, broken build). Style/nits are non-blocking. Default to skepticism on risky areas (auth, data loss, money, external input): if you cannot confirm safety, treat it as blocking.

## Step 3 — Emit the verdict JSON

Write a single object conforming to `references/review-contract.md`:
- `verdict`: `approve` (nothing blocking), `request_changes` (blocking findings the author can fix), or `blocked` (cannot proceed / cannot verify a risky claim).
- `findings[]`: each with `id`, `blocking`, `severity` (`blocker|major|minor`), `title`, and where known `file`, `line`, `evidence`, `recommended_fix`.
- Include `round` (echo the input) and a one-paragraph `summary`.

## Step 4 — Validate before returning (required)

Run the bundled validator and fix your output until it passes. Resolve the script from the plugin
root (the working directory when this skill runs is the user's project, not this skill folder):

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/review-diff/scripts/validate-review.py" "$CA_OUT"
```

It prints the verdict and exits 0 on success; on a non-zero exit, correct the JSON (the loop treats missing/malformed output as `blocked`).

## References

- `references/review-contract.md` — the exact `ca_claude_review.v1` shape, enums, and how `blocking` gates the loop.
