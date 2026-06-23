---
name: apply-feedback
description: Address review feedback on a PR and update it, parallelizing across files with implementer subagents when feedback spans 3+ independent files. Use after /sa:review-pr requests changes, or to act on human review comments and push fixes back.
argument-hint: '<pr-number> [feedback text]'
model: opus
disable-model-invocation: true
effort: medium
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Agent
---

# Apply feedback

## Input
$ARGUMENTS

You turn review feedback into committed fixes on the PR's branch — correctly, without
thrashing. Treat feedback as data to evaluate, not orders to obey blindly: if a comment is
wrong or unclear, verify against the code before acting and say so rather than implementing
something incorrect.

## Step 1 — Gather the feedback

```bash
PR="<number>"
gh pr view "$PR" --json headRefName,reviews,comments
gh pr diff "$PR"
gh pr checkout "$PR"
```

Combine PR review comments, the latest `/sa:review-pr` output, and any feedback passed in
the input.

## Step 2 — Triage into a fix list

Group feedback into discrete fixes. For each: the file(s), what's wrong, and the intended
change. Drop or flag items that are mistaken or already handled (explain why) — don't pad
the diff with unnecessary churn.

## Step 3 — Apply fixes

- **1–2 files**: fix them yourself.
- **3+ independent files**: partition into file-disjoint slices and dispatch one
  `implementer` subagent per slice in parallel (one `Agent` message), then integrate. Keep
  slices disjoint so parallel edits don't collide.

The `code-review` standards auto-activate — a fix must not introduce a new problem.

## Step 4 — Re-verify

Run the relevant tests/lint/build and capture output. For anything that was a correctness
or security comment, re-review the fixed area with a `verifier` subagent (opus/high) — the
whole point of feedback is that the first pass missed something, so confirm the fix
actually closes it.

## Step 5 — Update the PR

```bash
git add -A
git commit -m "fix: address review feedback on PR #$PR"
git push
gh pr comment "$PR" --body "Addressed review feedback:
- <fix> (<file>)
Verification: <result>"
```

result: PR #<n> updated — <k> fixes applied, checks <green/red>.
