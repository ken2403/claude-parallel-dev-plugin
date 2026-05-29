---
allowed-tools: Bash
argument-hint: '[job-name | branch | path | --all]'
description: Remove merged worktrees across the repo (pw jobs and .claude/worktrees/) after PRs are merged
---

# Cleanup Worktrees

Scan **every** linked worktree of the repository and remove the ones whose branch
has been merged. This covers both pw's own `worktrees/<job>` and Claude Code's
`.claude/worktrees/*` background-agent worktrees. With no argument (or `--all`)
it considers all of them; pass a job name, branch, or path to target just one.

## Input
$ARGUMENTS

## Safety Rules

- **NEVER delete a worktree whose branch has NOT been merged** (verified via `gh pr` / merge-base).
- **NEVER delete the main checkout or the worktree you are currently in.**
- **NEVER use `git worktree remove --force`** — a worktree with uncommitted changes is skipped and reported, not destroyed.
- If merge status cannot be confirmed (detached/unknown branch), treat as NOT MERGED and skip.
- When in doubt, REFUSE to delete.
- Removing a `.claude/worktrees/*` worktree does **not** stop its background agent session — use `/hv:clean-agents` for agent lifecycle.

## Pre-cleanup Sync (automatic)

Before any deletion decision, `clean.sh` fetches `origin/<base>` and fast-forwards the
local default branch to match. This keeps local state in sync with remote so the user
can verify merges with `git log` after the command finishes.

## Execute Cleanup

```bash
#!/bin/bash
# Locate plugin directory
_PD=""; for _d in "${PW_PLUGIN_DIR:-}" "${CLAUDE_PLUGIN_ROOT:-}" ./pw ../pw ../../pw "$HOME"/.claude/plugins/cache/claude-parallel-dev-plugin/pw/*; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"

if [ -z "$_PD" ] || [ ! -f "$_PD/scripts/clean.sh" ]; then
  echo "ERROR: parallel-workflow plugin not found"
  exit 1
fi

INPUT_ARG=$(echo "$ARGUMENTS" | awk '{print $1}')
"$_PD/scripts/clean.sh" ${INPUT_ARG:+"$INPUT_ARG"}
```

## Output

Report the cleanup results as a concise summary table:

| Job Name | Branch | Status |
|----------|--------|--------|

Include next steps for any blocked worktrees.
