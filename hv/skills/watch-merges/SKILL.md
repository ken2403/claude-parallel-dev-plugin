---
name: watch-merges
description: Watch one feature's PR in the background and auto-clean its agent, worktree, and branch once it merges. Use after a feature's PR is open to wire hands-off cleanup on merge (typically called by /hv:build-feature as its final step). It polls GitHub with exponential backoff and only triggers cleanup — the actual removal is done by /hv:clean-agents.
argument-hint: '<pr-number | branch> [--initial S] [--cap S] [--max H]'
model: opus
disable-model-invocation: true
allowed-tools: Read, Bash, Grep, Glob
---

# Watch merges → auto-clean

A **thin watcher**. It polls one PR until it merges, then runs
**`/hv:clean-agents`**, which delegates the actual removal to the `janitor`
subagent. All cleanup guardrails live there — this skill never deletes anything
itself.

## Input
$ARGUMENTS

`<pr|branch>` — the feature PR to watch (typically passed by `/hv:build-feature`
as its final step, right after opening the PR). Optional tuning:
`--initial S` (first poll gap, default 30s), `--factor N` (backoff multiplier,
default 2), `--cap S` (max gap, default 600s), `--max H` (give up after H hours,
default 24).

## Step 1 — Launch the background watcher

Poll the PR in the **background** so no live session is tied to the wait. The
bundled script backs off exponentially — quick polls right after the PR opens,
when a merge is most likely imminent, widening to `--cap` for the long tail —
and stops on merge, close, or the `--max` deadline:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/watch-merge.sh" <pr|branch>
```

Run it with **Bash's background mode** so it keeps polling across turns and
re-invokes you when it exits. Its final stdout line is one of:

- `MERGED <branch>`          → go to Step 2 and clean.
- `CLOSED_UNMERGED <branch>` → the PR was closed without merging; **clean
  nothing** (never destroy unmerged work) — just report it.
- `TIMEOUT <branch>`         → still open after `--max`; report that it's still
  open and suggest re-running `/hv:watch-merges <pr>` (or cleaning manually once
  it lands).
- `ERROR <message>`          → bad target or `gh` not authenticated; surface it.

## Step 2 — On merge, hand off to clean-agents

When (and only when) the watcher reports `MERGED`, run:

```
/hv:clean-agents <branch>
```

## Guardrail

Cleanup only ever runs through `/hv:clean-agents` → `janitor`, which **re-checks
that the agent is not still running and the PR is merged** before removing
anything. This skill watches and triggers; it never deletes resources itself.

result: watched <pr|branch> → <merged: cleaned | closed-unmerged: skipped | timeout: still open>.
