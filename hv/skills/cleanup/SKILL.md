---
name: cleanup
description: Reclaim hv resources after features land — stop and remove finished background agents, and prune merged feature worktrees and branches. Use once a feature's PR is merged (or abandoned). Safe by default — it refuses to remove anything tied to an unmerged, still-open PR unless forced.
argument-hint: '[feature ids / branches to clean, or "all-merged"]'
model: opus
allowed-tools: Read, Bash, Grep, Glob
---

# Hv cleanup

## Input
$ARGUMENTS

Background agents and worktrees accumulate and each consumes quota and disk, so
clean them up once their work has landed. The hard rule: **never destroy work
that hasn't been merged.** A leftover worktree is cheap; a deleted unmerged
branch is lost work.

## Context (auto-injected)
```
!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/agents-status.sh" hv/ 2>/dev/null`
```
- Worktrees: !`git worktree list 2>/dev/null`

## Step 1 — Decide what is safe to clean

For each candidate feature/branch, confirm it is **merged or intentionally
abandoned**:

```bash
gh pr list --state merged --json number,headRefName --jq '.[].headRefName'
```

A branch is safe to clean only if its PR is MERGED, or there is no PR and the
user explicitly asked to abandon it. If a PR is still OPEN, skip it and say why
(unless the user passed `--force` for a deliberate abandon).

## Step 2 — Stop and remove finished agents

```bash
# For each merged feature's agent (name hv/<id>):
claude stop "<session-id>" 2>/dev/null || true
claude rm "<session-id>" 2>/dev/null || true
```

Look up session ids from the snapshot above (`claude agents --json`).

## Step 3 — Prune merged worktrees and branches

Background-agent worktrees live under `.claude/worktrees/`. Remove only the ones
tied to merged features:

```bash
# Never --force: a plain `remove` fails on uncommitted changes, which is the
# signal that there is unsaved work to inspect — not work to destroy.
git worktree remove "<path>" || {
  echo "hv: worktree '<path>' has uncommitted changes — inspect and remove it manually."
}
git branch -d "<branch>" 2>/dev/null || true     # -d refuses unmerged branches
git worktree prune
```

Two deliberate safety choices: no `git worktree remove --force` (it would delete
uncommitted work without asking), and `git branch -d` not `-D` (it refuses to
delete an unmerged branch). Let git be the backstop against losing unlanded work.

## Step 4 — Report

```
| feature | PR | action taken | skipped (reason) |
|---------|----|--------------|------------------|
```

result: cleaned <n> merged features; skipped <m> still-open.
