---
name: clean-worktrees
description: @@DESCRIPTION@@
license: MIT
argument-hint: '[feature ids / branches to clean, or all-merged]'
model: haiku
disable-model-invocation: true
effort: low
allowed-tools: Read, Bash, Grep, Glob
---

# Clean worktrees

## Input
$ARGUMENTS

Worktrees accumulate and each consumes disk, so reclaim them once their work has
landed. This command is **repo-wide**: it cleans **every** merged worktree in
`git worktree list` regardless of location (@@PLUGINS_SLASH_SELF_FIRST@@ and any
other), so a single run reclaims them all. The hard rule: **never destroy work
that hasn't been merged.** A leftover worktree is cheap; a deleted unmerged
branch is lost work. The main checkout is always preserved; the current worktree
is removed too if its branch is merged.

## Context (auto-injected)
- Worktrees: !`git worktree list 2>/dev/null`
- Merged branches: !`gh pr list --state merged --json number,headRefName --jq '.[].headRefName' 2>/dev/null`

## Step 1 — Decide the scope

**Default is repo-wide.** Unless the user named specific feature ids/branches in
`$ARGUMENTS`, clean **every** merged worktree in the whole repo — @@PLUGINS_SELF_FIRST@@,
and any other, regardless of location. Do **not** narrow to
`.claude/worktrees/@@PLUGIN@@/` just because this is the @@PLUGIN@@ command; a
single run of any of the three cleans them all. Only when `$ARGUMENTS` names
specific targets do you scope to those.

@@FRAGMENT:cleanability_rule@@

## Step 2 — Remove (delegate to the script — single source of truth)

Don't run removals inline; the script owns the guardrails in one place. **With no
`$ARGUMENTS`, pass `all-merged`** so it sweeps the entire repo; pass a specific
`<branch>`/name only when the user named one:

```bash
CLAUDE_SKILL_@@PLUGIN_UPPER@@_DIR="${CLAUDE_SKILL_DIR}"
# no target given → clean EVERY merged worktree repo-wide (@@PLUGINS_SLASH_SELF_FIRST@@ and any other):
bash "$CLAUDE_SKILL_@@PLUGIN_UPPER@@_DIR/scripts/clean.sh" all-merged
# or, only when the user named specific targets:
# bash "$CLAUDE_SKILL_@@PLUGIN_UPPER@@_DIR/scripts/clean.sh" "<branch>"
```

@@FRAGMENT:clean_script_behavior@@

Two more rules the script owns: a merged worktree still locked by a **dead**
claude session (`claude session ... (pid N)` whose pid is gone) is unlocked and
removed — any other lock is an absolute barrier and is only reported. And orphan
directories under `.claude/worktrees/` that are no longer registered worktrees
are removed when **empty**, reported (never deleted) when they still have content.

## Step 3 — Report

```
| feature | branch | PR | action | skipped (reason) |
|---------|--------|----|--------|------------------|
```

result: cleaned <n> landed features; skipped <m> (unmerged / changes present).
