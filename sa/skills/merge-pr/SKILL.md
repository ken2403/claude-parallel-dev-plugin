---
name: merge-pr
description: Merge a reviewed sa PR after confirming it is genuinely ready — open, not draft, no changes requested, green CI, mergeable. Use once /sa:review-pr (or a human review) approves the PR and you want it merged from the CLI. Refuses to merge on red checks, changes-requested reviews, or conflicts. Invoke explicitly with /sa:merge-pr.
license: MIT
argument-hint: '[pr-number] [--squash | --merge | --rebase]'
model: haiku
disable-model-invocation: true
effort: low
allowed-tools: Read, Bash, Grep, Glob
---

# Merge an sa PR

## Input
$ARGUMENTS

Merging is the one irreversible step in the pipeline, so it gets a
real gate. Confirm readiness with evidence before merging — never merge on
assumption.

## Step 1 — Preflight (all must pass)

```bash
PR="<pr-number from the arguments, or empty to auto-detect>"
[ -n "$PR" ] || PR="$(gh pr view --json number --jq .number 2>/dev/null)"  # no number given -> current branch's PR
[ -n "$PR" ] || { echo "no PR number given and none found for the current branch" >&2; exit 1; }
gh pr view "$PR" --json state,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,headRefName,isDraft
```

Block the merge and report if any of these hold:

- `state` is not OPEN, or `isDraft` is true.
- `reviewDecision` is CHANGES_REQUESTED (a human requested changes on GitHub).
  Do NOT require APPROVED: a `/sa:review-pr` APPROVE is a process gate that lands
  as a PR *comment* — it never sets `reviewDecision` (and the PR's own author
  cannot approve it on GitHub), so requiring APPROVED would block solo use forever.
- CI (`statusCheckRollup`) is not all-green.
- `mergeable` is false / `mergeStateStatus` indicates conflicts or out-of-date —
  run `/sa:resolve-conflicts <pr>` first (it merges the base in the feature's
  isolated worktree and re-verifies), then re-run this skill.
- There is unresolved blocking review feedback.

If anything fails, stop and say exactly what's missing — do not "force" it.

## Step 2 — Merge

Default to the repo's convention (squash is common; respect any branch-protection
rule). Delete the remote branch on merge to keep things tidy:

```bash
gh pr merge "$PR" --squash --delete-branch   # or --merge / --rebase per repo norm
```

Merge first, then reclaim the worktree (the next step) — never delete a branch
that still has unmerged work.

## Step 3 — Confirm and hand off

```bash
gh pr view "$PR" --json state,mergedAt
```

result: PR #<n> merged.

Remind the user that once the PR is merged, its isolated worktree and local
branch can be reclaimed with **`/sa:clean-worktrees`** (it removes only
worktrees whose PR is verified merged).
