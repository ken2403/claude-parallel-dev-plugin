---
name: watch-merges
description: Arrange for hv feature cleanup to run automatically when a PR is merged — by installing a Cloud Routine (GitHub merge trigger) or, as a fallback, an in-session /loop poll. Use after a feature's PR is open to wire up hands-off cleanup, or once at the repo level so every hv feature auto-cleans on merge. It only triggers cleanup; the actual removal is done by /hv:clean-agents.
argument-hint: '[<pr-number | branch> | --repo (standing) | --loop [interval]]'
model: opus
disable-model-invocation: true
allowed-tools: Read, Bash, Grep, Glob
---

# Watch merges → auto-clean

This skill is a **thin trigger**. It owns no cleanup logic: when a merge is
detected it runs **`/hv:clean-agents`**, which delegates the actual removal to the
`janitor` subagent. That keeps the merge→clean→reclaim chain in one line and the
guardrails in one place.

## Input
$ARGUMENTS

- `<pr|branch>` — watch one feature's PR (typically called by `/hv:build-feature`
  as its final step, right after opening the PR).
- `--repo` — install a **standing** repo-level watcher so *every* hv PR auto-cleans
  on merge (set up once; nothing to do per feature thereafter).
- `--loop [interval]` — use the in-session poller instead of a Routine.

## Mode A — Cloud Routine (recommended, low cost, durable)

A Cloud Routine with a GitHub `pull_request` trigger filtered to `is_merged: true`
fires **once per merge**, on Anthropic infrastructure, with no session kept alive —
the cheapest and most reliable option. Its command is `/hv:clean-agents <branch>`.

Use the bundled template at `${CLAUDE_PLUGIN_ROOT}/routines/cleanup-on-merge.json`.

```bash
# Show the template the routine should use (fill in repo + branch filter):
cat "${CLAUDE_PLUGIN_ROOT}/routines/cleanup-on-merge.json"
```

If a CLI/API to create routines programmatically is available in this version,
register it directly. **If not, do not fake it** — print the template plus the
exact steps for the user to add the routine once (repo, `is_merged:true` filter,
command `/hv:clean-agents <branch>`), and tell them that after that one-time setup
every merged hv PR cleans up automatically. Never resort to spawning a nested
`claude` session to emulate this.

## Mode B — `/loop` fallback (no cloud setup; costs tokens while alive)

When Cloud Routines aren't available, poll from a live session:

```
/loop 10m check merged hv PRs and clean them
```

On each tick the loop should: `gh pr list --state merged --json headRefName` →
for any newly-merged hv branch not yet cleaned, run `/hv:clean-agents <branch>`.

State the cost honestly to the user: a poll consumes tokens **every tick** and
needs a session to stay alive (7-day `/loop` limit), so prefer Mode A for anything
long-running. Pick a coarse interval (≥5m).

## Guardrail

Whichever mode, cleanup only ever runs through `/hv:clean-agents` → `janitor`,
which **re-checks that the agent is not still running and the PR is merged** before
removing anything. This skill never deletes resources itself.

result: wired merge→clean for <pr|branch|repo> via <Routine|loop>.
