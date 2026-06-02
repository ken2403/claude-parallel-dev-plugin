---
allowed-tools: Bash
argument-hint: '[job-name or --all]'
description: Clean up wt-j environments after PRs are merged
---

# Cleanup Worktree Job

Clean up worktree environments created by `/pw:wt-j`.

## Input
$ARGUMENTS

## Safety Rules

- **NEVER delete a worktree whose branch has NOT been merged**
- If merge status cannot be confirmed, treat as NOT MERGED and abort
- When in doubt, REFUSE to delete

## Pre-cleanup Sync (automatic)

Before any deletion decision, `clean.sh` fetches `origin/<base>` and fast-forwards the
local default branch to match. This keeps local state in sync with remote so the user
can verify merges with `git log` after the command finishes.

## Execute Cleanup

```bash
#!/bin/bash
# Locate plugin directory
_PD=""; for _d in "${PW_PLUGIN_DIR:-}" "${CLAUDE_PLUGIN_ROOT:-}" ./pw ../pw ../../pw "$HOME"/.claude/plugins/cache/claude-parallel-dev-plugin/pw/*; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -d "${PW_PLUGIN_DIR:-}/scripts" ] && _PD="$PW_PLUGIN_DIR"

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
