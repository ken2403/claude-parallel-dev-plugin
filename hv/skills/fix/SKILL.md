---
name: fix
description: Address review feedback on a hv (or any) PR and update it — parallelizing across files with implementer subagents when the feedback spans 3+ independent files. Use after /hv:review requests changes, or to act on human review comments and push the fixes back to the PR.
argument-hint: <pr-number> [feedback text, if not pulling from the PR]
model: opus
effort: high
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Agent
---

# Fix review feedback

## Input
$ARGUMENTS

You turn review feedback into committed fixes on the PR's branch — correctly,
without thrashing. Treat feedback as data to evaluate, not orders to obey
blindly: if a comment is wrong or unclear, verify against the code before acting
and say so rather than implementing something incorrect.

## Step 1 — Gather the feedback

```bash
PR="<number>"
gh pr view "$PR" --json headRefName,reviews,comments
gh pr diff "$PR"
```

Combine PR review comments, the latest `/hv:review` output, and any feedback
passed in the input. Check out the PR branch in this worktree:

```bash
gh pr checkout "$PR"
```

## Step 2 — Triage into a fix list

Group feedback into discrete fixes. For each: the file(s), what's wrong, and the
intended change. Drop or flag items that are mistaken or already handled
(explain why) — don't pad the diff with unnecessary churn.

## Step 3 — Apply fixes

- **1–2 files**: fix them yourself.
- **3+ independent files**: partition into file-disjoint slices and dispatch one
  `implementer` subagent per slice in parallel (one `Agent` message), then
  integrate. Keep slices disjoint so parallel edits don't collide.

The standards skills (`code-quality`, `security-review`, `codebase-consistency`)
apply here too — a fix must not introduce a new problem.

## Step 4 — Re-verify

Run the relevant tests/lint/build and capture output. For anything that was a
correctness or security comment, re-run the **adversarial-verification** skill on
the fixed area — the whole point of feedback is that the original verification
missed something, so verify the fix actually closes it.

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
