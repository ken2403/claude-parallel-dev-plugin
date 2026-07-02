---
name: merge-pr
description: Merge a reviewed PR after confirming it is genuinely ready — open, not draft, approved, green CI, up to date with base, no unresolved blocking feedback. Use once /ha:review-pr approves a feature's PR. Refuses to merge on red checks, missing review, or conflicts. Invoke explicitly with /ha:merge-pr.
argument-hint: '<pr-number> [--squash | --merge | --rebase]'
model: haiku
disable-model-invocation: true
effort: low
allowed-tools: Read, Bash, Grep, Glob
---

# Merge an ha PR

## Input
$ARGUMENTS

Merging is the one irreversible step in the pipeline, so it gets a real gate.
Confirm readiness with evidence before merging — never merge on assumption.

## Step 1 — Preflight (all must pass)

```bash
PR="<number>"
gh pr view "$PR" --json state,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,headRefName,isDraft
```

Block the merge and report if any of these hold:

- `state` is not OPEN, or `isDraft` is true.
- `reviewDecision` is not APPROVED (an ha PR should have a `/ha:review-pr` pass).
- CI (`statusCheckRollup`) is not all-green.
- `mergeable` is false / `mergeStateStatus` indicates conflicts or out-of-date —
  in that case update from base first: run `/ha:resolve-conflicts <pr>` (it merges
  the base in the feature's isolated worktree and re-verifies), then re-run this skill.
- There is unresolved blocking review feedback.

If anything fails, stop and say exactly what's missing — do not "force" it.

## Step 2 — Merge

Default to the repo's convention (squash is common; respect any branch-protection
rule). Delete the remote branch on merge to keep things tidy:

```bash
gh pr merge "$PR" --squash --delete-branch   # or --merge / --rebase per repo norm
```

This follows `superpowers:finishing-a-development-branch`'s ordering — **merge
first, then reclaim the worktree** (the next step), and never delete a branch that
still has unmerged work.

## Step 3 — Confirm and hand off

```bash
gh pr view "$PR" --json state,mergedAt
```

result: PR #<n> merged.

Remind the user that once the PR is merged, its isolated worktree and local branch
can be reclaimed with **`/ha:clean-worktrees`** (it removes only worktrees whose PR
is verified merged).
