---
name: clean-agents
description: Reclaim hv resources after features land — stop and remove finished background agents, and prune merged feature worktrees and branches. Use once a feature's PR is merged (or abandoned). Safe by default — it refuses to remove anything tied to an unmerged, still-open PR unless forced.
argument-hint: '[feature ids / branches to clean, or "all-merged"]'
model: opus
disable-model-invocation: true
allowed-tools: Read, Bash, Grep, Glob, Agent
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

## Step 2 — Delegate the destructive work to the `janitor` subagent

Don't run the removals inline — dispatch the **`janitor`** subagent with the list
of safe-to-clean feature keys (branch / `hv/<id>` / PR). It owns the removal
commands and the guardrails in one place, and returns a report, so this skill's
main context stays clean. Pass it the candidates and whether this is normal
merged-cleanup or an explicit `--abandon`.

`janitor` re-verifies safety before touching anything: a feature is cleaned only
if its PR is **MERGED** (or `--abandon`) **and** its agent is **not running**. It
uses `git worktree remove` (no `--force`) and `git branch -d` (not `-D`), and
identifies worktrees by their **checked-out branch** (`feat/<id>`), not the
host-assigned directory name. Worktrees with uncommitted changes are skipped, not
forced.

## Step 3 — Context-aware roles (who runs this matters)

- **From the parent / launcher session**: full reclaim — stop+`rm` the child
  session, remove its worktree and branch, delete its spec.
- **From inside a child feature session**: you may clean your **own** worktree,
  branch, and spec, and tidy already-merged siblings — but `janitor` must operate
  with `git -C <main-checkout>` / absolute paths (a `cd` doesn't persist between its
  Bash calls, and you can't remove the worktree you're standing in otherwise). The
  one thing a child does **not** do is `claude rm` **its own session record** —
  leave that to the parent.
- **Absolute guard, every path**: never stop or remove an agent that is still
  `running`/working, even if its PR shows merged.

## Step 4 — Report

```
| feature | PR | action taken | skipped (reason) |
|---------|----|--------------|------------------|
```

result: cleaned <n> landed features; skipped <m> (still running / unmerged / changes present).
