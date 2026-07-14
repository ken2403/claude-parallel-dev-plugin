---
name: merge-pr
description: @@DESCRIPTION@@
license: MIT
argument-hint: '[pr-number] [--squash | --merge | --rebase]'
model: haiku
disable-model-invocation: true
effort: low
allowed-tools: Read, Bash, Grep, Glob
---

# @@MERGE_PR_TITLE@@

## Input
$ARGUMENTS

Merging is the one irreversible step in the @@MERGE_PR_LOOP_NOUN@@, so it gets a
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

@@FRAGMENT:preflight_state_rules@@
- CI (`statusCheckRollup`) is not all-green.
- `mergeable` is false / `mergeStateStatus` indicates conflicts or out-of-date —
  @@RESOLVE_CONFLICTS_NOTE@@
- There is unresolved blocking review feedback.

If anything fails, stop and say exactly what's missing — do not "force" it.

## Step 2 — Merge

Default to the repo's convention (squash is common; respect any branch-protection
rule). Delete the remote branch on merge to keep things tidy:

```bash
gh pr merge "$PR" --squash --delete-branch   # or --merge / --rebase per repo norm
```

@@FRAGMENT:merge_ordering_note@@

## Step 3 — Confirm and hand off

```bash
gh pr view "$PR" --json state,mergedAt
```

result: PR #<n> merged.

Remind the user that once the PR is merged, its isolated worktree and local
branch can be reclaimed with **`/@@PLUGIN@@:clean-worktrees`** (it removes only
worktrees whose PR is verified merged).
