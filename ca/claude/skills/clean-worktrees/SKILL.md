---
name: clean-worktrees
description: Reclaim ca worktrees after features land — remove merged feature worktrees and delete their merged branches. Use once a ca PR is merged. Safe by default — never removes a worktree with uncommitted changes and never deletes an unmerged branch. Invoke explicitly with /ca:clean-worktrees.
license: MIT
argument-hint: '[feature ids / branches to clean, or all-merged]'
disable-model-invocation: true
effort: low
allowed-tools: Read, Bash, Grep, Glob
---

# Clean worktrees

## Input
$ARGUMENTS

ca worktrees accumulate under `.claude/worktrees/ca/` and each consumes disk, so
reclaim them once their work has landed. The hard rule: **never destroy work that
hasn't been merged.** A leftover worktree is cheap; a deleted unmerged branch is
lost work. This only touches **worktrees and branches** under
`.claude/worktrees/ca/`.

## Context (auto-injected)
- Worktrees: !`git worktree list 2>/dev/null`
- Merged branches: !`gh pr list --state merged --json number,headRefName --jq '.[].headRefName' 2>/dev/null`

## Step 1 — Decide what is safe to clean

A worktree/branch is cleanable only if its PR is **MERGED** (confirm via
`gh pr list --state merged`, or `bash "${CLAUDE_SKILL_DIR}/scripts/merge-check.sh"`),
or there is no PR and the user explicitly asked to abandon it. If a PR is still
OPEN (including a draft still in the ca loop), skip it and say why.

## Step 2 — Remove (delegate to the script — single source of truth)

Don't run removals inline; the script owns the guardrails in one place:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/clean.sh" "<branch | all-merged>"
```

`clean.sh` considers **only** worktrees under `.claude/worktrees/ca/`, uses
`git worktree list` to find them, `git worktree remove` **without `--force`**
(uncommitted changes ⇒ skip + report), and `git branch -d` (**never `-D`**). It
never removes the main checkout or the current worktree, syncs the base branch
with origin before deciding, and `git worktree prune`s at the end.

## Step 3 — Report

```
| feature | branch | PR | action | skipped (reason) |
|---------|--------|----|--------|------------------|
```

result: cleaned <n> landed features; skipped <m> (unmerged / changes present).
