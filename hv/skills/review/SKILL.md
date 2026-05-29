---
name: review
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

## Step 2 — Apply the standards

The `code-quality`, `security-review`, and `codebase-consistency` skills activate
here — use them as your lenses. Pay special attention to **consistency beyond the
diff**: a change can be locally correct yet break the wider codebase (a renamed
symbol not propagated, a contract other code relies on, duplicated logic that
should reuse an existing helper).

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

Hand off: clean review → `/hv:merge <n>`; changes requested → `/hv:fix <n>`.
