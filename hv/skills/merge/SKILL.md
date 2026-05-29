---
name: merge
description: Merge a reviewed hv (or any) PR after confirming it is genuinely ready — approved, green CI, up to date with base, no unresolved blocking feedback. Use once /hv:review approves a feature's PR. Refuses to merge on red checks or missing review.
argument-hint: <pr-number> [--squash|--merge|--rebase]
model: opus
allowed-tools: Read, Bash, Grep, Glob
---

# Merge a hv PR

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
- `reviewDecision` is not APPROVED (a hv PR should have a `/hv:review` pass).
- CI (`statusCheckRollup`) is not all-green.
- `mergeable` is false / `mergeStateStatus` indicates conflicts or out-of-date —
  in that case, update from base first (rebase/merge base, re-run checks); if
  conflicts are non-trivial, resolve them in the feature's worktree (a fresh
  `/hv:fix` pass can help) and re-run this skill.
- There is unresolved blocking review feedback.

If anything fails, stop and say exactly what's missing — do not "force" it.

## Step 2 — Merge

Default to the repo's convention (squash is common; respect any branch-protection
rule). Delete the remote branch on merge to keep things tidy:

```bash
gh pr merge "$PR" --squash --delete-branch   # or --merge / --rebase per repo norm
```

## Step 3 — Confirm and hand off

```bash
gh pr view "$PR" --json state,mergedAt
```

result: PR #<n> merged.

Remind the user that once a feature's PR is merged, its background agent and
worktree can be reclaimed with **`/hv:cleanup`**, and any features that
`depends_on` this one are now safe to launch.
