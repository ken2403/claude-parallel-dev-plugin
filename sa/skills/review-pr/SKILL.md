---
name: review-pr
description: Critically reviews a PR for correctness, security, and codebase consistency — an independent second opinion, not a rubber stamp. Use to review a simple feature's PR before merging. Posts inline comments with --comment.
argument-hint: '<pr-number> [--comment]'
model: opus
effort: high
allowed-tools: Read, Grep, Glob, Bash, Agent, WebFetch
---

# Review PR

## Input
$ARGUMENTS

`simple-feature` opens PRs fast without an internal review, so this is the precision
guardrail: an **independent second opinion**. Assume nothing the PR claims; try to find
what it missed. A review that only confirms is worth little; one that surfaces a real
defect before merge is worth everything.

## Step 1 — Load the PR

```bash
PR="<number>"
gh pr view "$PR" --json title,body,headRefName,additions,deletions,files,reviewDecision,statusCheckRollup
gh pr diff "$PR"
```

Read the diff fully. Pull the design intent from the PR body (and any linked issue) so you
review against what it was *supposed* to do, not just what it does.

## Step 2 — Apply the standards (hybrid: delegate generic, keep context-critical in main)

The `code-review` skill is your lens (it auto-activates; quality, security, consistency).
Split the work:

- **Delegate to `verifier` subagents** (parallel, opus/high; keeps heavy reading out of
  main): broad correctness scan, style/quality, mechanical security patterns (injection,
  hardcoded secrets), and hunting missed call sites. They return findings, not dumps.
- **Keep in main** (judgment needs this repo's guidance or live context): compliance with
  `CLAUDE.md` and the repo's conventions, security-critical decisions, architectural fit
  and design intent, and **consistency beyond the diff** (a renamed symbol not propagated,
  a contract other code relies on, logic that should reuse an existing helper).

Axis: needs this repo's specific guidance or live context → main; generic diff-only check
a fresh agent can do → subagent.

## Step 3 — Verify with evidence

Run targeted read-only checks where they settle a question — tests, `git grep` for missed
call sites, type checks. **Security is non-negotiable**; never wave it through. Evidence
beats opinion.

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

Only **APPROVE** when the blocking list is empty and verification passed. "Looks fine"
without having tried to break it is not approval.

If `--comment` was passed, post the summary as a review:

```bash
gh pr review "$PR" --comment --body "<summary>"
```

Hand off: changes requested → `/sa:apply-feedback <n>`.
