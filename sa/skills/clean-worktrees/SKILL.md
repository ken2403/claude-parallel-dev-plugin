---
name: clean-worktrees
description: Reclaims worktrees after features land — removes every merged worktree in the repo (sa/ha/ca and any other, regardless of location) and deletes their merged branches. Use once a feature PR is merged. Safe by default — never removes a worktree with uncommitted changes, never deletes an unmerged branch, and never touches the main checkout or current worktree.
argument-hint: '[feature ids / branches to clean, or all-merged]'
model: haiku
disable-model-invocation: true
effort: low
allowed-tools: Read, Bash, Grep, Glob
---

# Clean worktrees

## Input
$ARGUMENTS

Worktrees accumulate and each consumes disk, so reclaim them once their work has landed.
This command is **repo-wide**: it cleans **every** merged worktree in `git worktree list`
regardless of location (sa/ha/ca and any other), so a single run reclaims them all. The
hard rule: **never destroy work that hasn't been merged.** A leftover worktree is cheap; a
deleted unmerged branch is lost work. The main checkout and the current worktree are always
preserved.

## Context (auto-injected)
- Worktrees: !`git worktree list 2>/dev/null`
- Merged branches: !`gh pr list --state merged --json number,headRefName --jq '.[].headRefName' 2>/dev/null`

## Step 1 — Decide what is safe to clean

A worktree/branch is cleanable only if its PR is **MERGED** (confirm via
`gh pr list --state merged`, or, after `CLAUDE_SKILL_SA_DIR="${CLAUDE_SKILL_DIR}"`,
`bash "$CLAUDE_SKILL_SA_DIR/scripts/merge-check.sh"`), or there is no PR and the user
explicitly asked to abandon it. If a PR is still OPEN, skip it and say why.

## Step 2 — Remove (delegate to the script — single source of truth)

Don't run removals inline; the script owns the guardrails in one place:

```bash
CLAUDE_SKILL_SA_DIR="${CLAUDE_SKILL_DIR}"
bash "$CLAUDE_SKILL_SA_DIR/scripts/clean.sh" "<branch | all-merged>"
```

`clean.sh` considers **every** worktree in `git worktree list` (any path), uses
`git worktree remove` **without `--force`** (uncommitted
changes ⇒ skip + report), and `git branch -d` (**never `-D`**). It never removes the main
checkout or the current worktree, and it syncs the base branch with origin before deciding.

## Step 3 — Report

```
| feature | branch | PR | action | skipped (reason) |
|---------|--------|----|--------|------------------|
```

result: cleaned <n> landed features; skipped <m> (unmerged / changes present).
