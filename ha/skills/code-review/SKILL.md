---
name: code-review
description: Standards for writing and reviewing code — quality, test rigor, security, and codebase consistency. Use whenever implementing, changing, or reviewing code, or when checking a PR or diff for bugs, missing test coverage, vulnerabilities, missed propagation, or style drift.
allowed-tools: Read, Grep, Glob, Bash
---

# Code review standards

The single source of engineering standards for `ha`. It applies in two modes:

- **While implementing** (in `implement` / the work subagents): follow these as you
  write, so the change is clean, safe, and consistent the first time.
- **While reviewing** (in `review-pr` / `verifier` / `apply-feedback`): check the diff
  against these and report findings as `severity — file:line — issue — suggestion`.

The existing codebase convention always takes precedence over a general rule — confirm
with `Grep`/`Glob` before flagging something as wrong.

## Four dimensions

- **Quality** — readability, maintainability, simplicity, type safety, error handling,
  performance, matching existing style. → [references/code-quality.md](references/code-quality.md)
- **Test rigor** — behavior coverage of the change: every changed behavior has a test
  that fails without it (boundaries, error paths, state transitions — not line coverage).
  A behavior change without a covering test is a **High/blocking** finding unless the
  author states why it is untestable (in the PR Notes — or in the report, when no PR
  exists yet). → [references/test-rigor.md](references/test-rigor.md)
- **Security** (non-negotiable; must never regress) — injection (SQL/command/path/template),
  authn/authz, secrets, crypto, unsafe deserialization, SSRF, sensitive data in logs,
  dependency risk. → [references/security.md](references/security.md)
- **Consistency beyond the diff** — missed propagation on rename/schema/API/config
  changes, stale references, reinvented logic, docs/types/configs drift, cross-layer
  coherence. → [references/consistency.md](references/consistency.md)

## Risky surfaces (canonical list)

A change is **risky** when it touches: authn/authz/sessions/tokens; crypto/secrets;
money/billing; external-input parsing (HTTP handlers, deserialization, file uploads);
data migration/deletion; permissions; or SQL/shell string construction.
ha's risk-scaled gates (the analyzer's risk grade driving `implement`'s pre-PR
adversarial gate, and `adversarial-verification`'s activation triggers) key off this
list — other ha skills defer to it and must never define a competing list
(illustrative examples in a skill's trigger description are fine; this list decides).

## How to apply

1. Understand existing patterns first (`Glob`/`Grep`/`Read`) — style is contextual.
2. Apply the four dimensions; for a review, split work: generic diff-only checks can go
   to parallel `verifier` subagents, repo-specific/security-critical judgment stays in main.
3. Verify findings against the codebase before reporting (a flagged pattern may be
   mitigated by middleware, a framework, or an established convention).

## Report format (when reviewing)

For each finding:
- **Severity**: Critical / High / Medium / Low
- **Location**: file:line
- **Issue**: brief description
- **Suggestion**: specific fix or secure alternative
