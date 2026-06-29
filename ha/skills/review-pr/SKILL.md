---
name: review-pr
description: Critically review a PR for correctness, security, architecture, testing, and codebase consistency — an independent, adversarial second opinion, not a rubber stamp. Use to review an ha feature's PR before merging, or any PR you want high confidence in; pass --comment to post findings inline. Invoke explicitly with /ha:review-pr.
argument-hint: '<pr-number> [--comment]'
effort: high
allowed-tools: Read, Grep, Glob, Bash, Agent, WebFetch
---

# Review PR

## Input
$ARGUMENTS

`implement` already runs its own whole-diff review before opening the PR, so this
skill is the **independent second opinion** — a different reviewer, assuming
nothing the PR or its author claims, trying to find what they missed. A review
that only confirms is worth little; one that surfaces a real defect before merge
is worth everything. Requires the `superpowers` plugin.

## Step 1 — Load the PR

```bash
PR="<number>"
gh pr view "$PR" --json title,body,headRefName,additions,deletions,files,reviewDecision,statusCheckRollup
gh pr diff "$PR"
```

Read the diff fully. Pull the design intent from the PR body (and any linked
issue or plan) so you review against what it was *supposed* to do.

## Step 2 — Apply the standards (hybrid: delegate generic, keep context-critical in main)

The `code-review` skill is your lens (it auto-activates — quality, security,
consistency). Split the work:

- **Delegate to `verifier` subagents** (parallel; keeps heavy reading out of main):
  broad correctness scan, style/quality, mechanical security patterns (injection,
  hardcoded secrets), and hunting missed call sites. They return findings, not dumps.
- **Keep in main** (judgment needs this repo's guidance or live context):
  compliance with `CLAUDE.md` and repo conventions, security-critical decisions,
  architectural fit and design intent, and **consistency beyond the diff** (a
  renamed symbol not propagated, a contract other code relies on, logic that
  should reuse an existing helper).

## Step 3 — Cover the code-reviewer dimensions

Beyond the diff-level scan, judge the change against the five review dimensions
from `superpowers:requesting-code-review` (its `code-reviewer.md` rubric — apply
it, don't re-paste it):

1. **Plan alignment** — matches the plan/requirements; deviations justified.
2. **Code quality** — separation of concerns, error handling, type safety, DRY
   without premature abstraction, edge cases.
3. **Architecture** — sound design, scalability/performance, security, clean
   integration.
4. **Testing** — tests real behavior (not mocks), edge cases, integration where
   it matters, all passing.
5. **Production readiness** — migration/back-compat if schema changed, docs
   complete, no obvious bugs.

## Step 4 — Adversarially verify the central claims

Run `adversarial-verification` on the PR's load-bearing claims (correctness,
safety, completeness, no-regression). Dispatch refute-oriented `verifier`s with
distinct lenses; for a high-stakes change use 3+ and take a majority. A claim the
panel can't uphold is a blocking issue.

## Step 5 — Verify with evidence

**REQUIRED SUB-SKILL:** Use `superpowers:verification-before-completion` — settle
open questions with fresh, read-only evidence (targeted tests, `git grep` for
missed call sites, type checks) before asserting a verdict. **Security is
non-negotiable**; never wave it through. Evidence beats opinion.

## Step 6 — Report (and optionally comment)

```
## Review: PR #<n> — APPROVE | REQUEST CHANGES | COMMENT

## Blocking issues (must fix before merge)
- path:line — <issue> — <why it matters> — <fix>

## Non-blocking suggestions
- path:line — <suggestion>

## Verification
- <claims checked, verifier verdicts, evidence>
```

Only **APPROVE** when the blocking list is empty AND adversarial verification
passed. "Looks fine" without having tried to break it is not approval.

If `--comment` was passed, post the summary:

```bash
gh pr review "$PR" --comment --body "<summary>"
```

Hand off: changes requested → `/ha:apply-feedback <n>`; clean → `/ha:merge-pr <n>`.
