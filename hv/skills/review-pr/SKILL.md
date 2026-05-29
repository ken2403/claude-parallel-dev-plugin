---
name: review-pr
description: Critically review a hv (or any) PR for correctness, security, and codebase consistency, using adversarial verification rather than a rubber stamp. Use to review a feature's PR before merging, or whenever you want a high-confidence review of a pull request. Posts inline comments with --comment.
argument-hint: <pr-number> [--comment]
model: opus
effort: high
allowed-tools: Read, Grep, Glob, Bash, Agent, WebFetch
---

# Hv PR review

## Input
$ARGUMENTS

A hv worker already self-verified before opening its PR. Your job here is an
**independent second opinion** — assume nothing the PR claims, and try to find
what the worker (and its verifiers) missed. A review that only confirms is worth
little; a review that surfaces a real defect before merge is worth everything.

## Step 1 — Load the PR

```bash
PR="<number>"
gh pr view "$PR" --json title,body,headRefName,additions,deletions,files,reviewDecision,statusCheckRollup
gh pr diff "$PR"
```

Read the diff fully. Pull the design intent from the PR body (and linked issue)
so you review against what it was *supposed* to do, not just what it does.

## Step 2 — Apply the standards (hybrid: delegate generic, keep context-critical in main)

The `code-quality`, `security-review`, and `codebase-consistency` skills are your
lenses. Split the work to stay both thorough and context-clean:

- **Delegate to subagents** (generic, diff-only, parallelizable — keeps the heavy
  reading out of your main context): broad correctness scan, style/quality review,
  mechanical security-pattern checks (injection, hardcoded secrets), and hunting
  missed call sites. Dispatch these in parallel; they return findings, not dumps.
- **Keep in main** (judgment needs this repo's guidance or the live context):
  compliance with `CLAUDE.md` and the repo's security guide / contributing rules,
  security-critical decisions, architectural fit and design intent, and
  **consistency beyond the diff** (a renamed symbol not propagated, a contract
  other code relies on, logic that should reuse an existing helper).

The axis: *does judging this correctly require this repo's specific guidance
(CLAUDE.md / security guide) or the live conversation context? → main. Is it a
generic check a fresh agent can do from the diff alone? → subagent.* Apply it
flexibly per finding.

## Step 3 — Adversarially verify

Invoke the **adversarial-verification** skill against the PR's central claims
(correct, safe, complete, consistent, no-regression). Scale rigor to the change's
risk. Run targeted read-only checks (tests, `git grep` for missed call sites,
type checks) where they settle a question — evidence beats opinion.

## Step 4 — Report (and optionally comment)

```
## Review: PR #<n> — APPROVE | REQUEST CHANGES | COMMENT

## Blocking issues (must fix before merge)
- path:line — <issue> — <why it matters> — <fix>

## Non-blocking suggestions
- path:line — <suggestion>

## Verification
- <claims checked, verdicts, evidence>
```

Only **APPROVE** when the blocking list is empty and verification passed.
"Looks fine" without having tried to break it is not approval.

If `--comment` was passed, post the blocking issues as inline review comments:

```bash
gh pr review "$PR" --comment --body "<summary>"
# inline: gh api ... or gh pr comment for line-specific notes
```

Hand off: clean review → `/hv:merge-pr <n>`; changes requested → `/hv:apply-feedback <n>`.
