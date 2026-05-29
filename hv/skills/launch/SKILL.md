---
name: launch
description: Dispatch the hv — start one isolated background agent per feature from a /hv:design manifest, each running /hv:worker to drive its feature to a PR. Use after design when you're ready to run features in parallel. Respects dependencies, so independent features start now and dependent ones wait. Each agent auto-isolates in its own git worktree, so features never interfere.
argument-hint: '[@manifest.json | paste manifest | feature ids to (re)launch]'
model: opus
allowed-tools: Read, Bash, Grep, Glob
---

# Launch the hv

## Input
$ARGUMENTS

You turn a feature manifest into a fleet of independent background agents. Each
feature becomes one `claude --bg` session that runs `/hv:worker`; Claude Code
moves every background session into its own `.claude/worktrees/` checkout before
it edits, so the features run **fully isolated and non-interfering**. You do not
need tmux.

## Context (auto-injected)
- Repo: !`basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null`
- Base branch: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-base-branch.sh" 2>/dev/null`
- Background agents available: !`command -v claude >/dev/null 2>&1 && echo yes || echo "NO — claude CLI not on PATH"`
- Existing hv agents: !`claude agents --json 2>/dev/null | { command -v jq >/dev/null 2>&1 && jq -r '[.[]?|select((.name//"")|startswith("hv/"))]|length' || cat; } 2>/dev/null || echo 0`

## Step 1 — Load and validate the manifest

Parse the manifest (from `@file`, pasted JSON, or the previous `/hv:design`
output). Before dispatching anything, validate:

- Every feature has `id`, `branch`, `scope`, `target_files`, `success_criteria`.
- **No two features share a file** across `target_files` — if they do, stop and
  report the overlap; launching them in parallel would defeat isolation.
- `depends_on` references resolve and contain no cycles.

If the input is a list of feature ids, (re)launch only those.

## Step 2 — Plan the launch order

Group features into waves by `depends_on`: wave 1 = no dependencies, wave 2 =
depends only on wave 1, and so on. Independent features all go in wave 1 and
start together. Tell the user the wave plan before launching.

## Step 3 — Ensure the base is current

```bash
BASE="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-base-branch.sh")"
git fetch origin "$BASE" 2>/dev/null || true
```

## Step 4 — Dispatch one background agent per feature

For each feature in the current wave, hand the worker the **feature's JSON
object**. Do **not** interpolate the JSON straight into the prompt string — it
contains `"` and `{}` that break shell quoting. Instead write the feature object
to a spec file and pass its path, which is shell-safe. Use a `hv/<id>` name so
`/hv:status` and `/hv:cleanup` can find these agents:

```bash
# FEATURE_JSON = the single feature object, compact JSON
SPEC_DIR="$(git rev-parse --show-toplevel)/.hv/specs"
mkdir -p "$SPEC_DIR"
SPEC_FILE="$SPEC_DIR/<id>.json"
printf '%s\n' "$FEATURE_JSON" > "$SPEC_FILE"

claude --bg \
  --name "hv/<id>" \
  --model claude-opus-4-8 \
  --permission-mode acceptEdits \
  "/hv:worker $SPEC_FILE"
```

The prompt is now just `/hv:worker <path>` — no special characters — and the
worker reads the spec from the file.

Notes:
- **Permissions for hands-off runs.** `acceptEdits` auto-accepts file edits;
  background agents auto-deny any *other* prompt. If a worker needs `git push` /
  `gh pr create` without prompts, the user must have those allowed in settings
  (or accept `bypassPermissions` once interactively, then relaunch with
  `--dangerously-skip-permissions`). Surface this so a run doesn't silently stall.
- Dispatch the whole wave in one step, then move on — agents survive terminal
  close and keep running.
- Only launch the next wave once its prerequisites have **open/merged PRs** (check
  with `/hv:status`); don't start a dependent feature against unlanded work.

## Step 5 — Record and hand off

Print a launch table:

```
| feature | branch | agent name | wave | status |
|---------|--------|-----------|------|--------|
```

Then tell the user:
- Watch progress with **`/hv:status`** (or the native `claude agents` view).
- Review finished PRs with **`/hv:review <pr>`**, fix feedback with
  **`/hv:fix`**, merge with **`/hv:merge`**, and reclaim worktrees/agents with
  **`/hv:cleanup`** once merged.

result: launched <n> hv agents (<wave summary>).
