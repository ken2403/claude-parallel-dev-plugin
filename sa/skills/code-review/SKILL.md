---
name: code-review
description: Standards for writing and reviewing code — quality, security, and codebase consistency. Use whenever implementing, changing, or reviewing code, or when checking a PR or diff for bugs, vulnerabilities, missed propagation, or style drift.
allowed-tools: Read, Grep, Glob, Bash
---

# Code review standards

The single source of engineering standards for `sa`. It applies in two modes:

- **While implementing** (in `simple-implement` / `implementer`): follow these as you
  write, so the change is clean, safe, and consistent the first time.
- **While reviewing** (in `review-pr` / `verifier` / `apply-feedback`): check the diff
  against these and report findings as `severity — file:line — issue — suggestion`.

The existing codebase convention always takes precedence over a general rule — confirm
with `Grep`/`Glob` before flagging something as wrong.

## Three dimensions

- **Quality** — readability, maintainability, simplicity, type safety, error handling,
  performance, tests, matching existing style. A behavior change without a covering test
  is a **High/blocking** finding unless the PR states why it is untestable.
  → [references/code-quality.md](references/code-quality.md)
- **Security** (non-negotiable; must never regress) — injection (SQL/command/path/template),
  authn/authz, secrets, crypto, unsafe deserialization, SSRF, sensitive data in logs,
  dependency risk. → [references/security.md](references/security.md)
- **Consistency beyond the diff** — missed propagation on rename/schema/API/config
  changes, stale references, reinvented logic, docs/types/configs drift, cross-layer
  coherence. → [references/consistency.md](references/consistency.md)

## How to apply

1. Understand existing patterns first (`Glob`/`Grep`/`Read`) — style is contextual.
2. Apply the three dimensions; for a review, split work: generic diff-only checks can go
   to parallel `verifier` subagents, repo-specific/security-critical judgment stays in main.
3. Verify findings against the codebase before reporting (a flagged pattern may be
   mitigated by middleware, a framework, or an established convention).

## Report format (when reviewing)

For each finding:
- **Severity**: Critical / High / Medium / Low
- **Location**: file:line
- **Issue**: brief description
- **Suggestion**: specific fix or secure alternative
