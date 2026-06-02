---
name: launch-agents
description: Prepare a parallel launch from a /hv:plan-features manifest — validate it, write a self-contained spec file per feature, and emit ready-to-paste `claude --bg` commands grouped into dependency waves for the human to run. Use after design when you're ready to run features in parallel. Does not spawn sessions itself (a session launching sessions is unsupported); it produces the exact launch commands. Each launched agent auto-isolates in its own git worktree.
argument-hint: '[@manifest.json | paste manifest | feature ids to (re)launch]'
model: opus
disable-model-invocation: true
allowed-tools: Read, Bash, Grep, Glob
---

# Launch the hv

## Input
$ARGUMENTS

You turn a feature manifest into a **ready-to-run launch plan**. Each feature
becomes one `claude --bg` session running `/hv:build-feature`; Claude Code moves
every background session into its own `.claude/worktrees/` checkout before it
edits, so features run **fully isolated and non-interfering** (no tmux).

You do **not** spawn those sessions yourself — a Claude session launching other
Claude sessions is not a supported pattern (auth/environment are not guaranteed to
carry over). Instead you validate the manifest, write each feature's spec, and
**emit the exact commands** for the human to paste (in the terminal, or as prompts
in the `claude agents` view). That keeps launching on the supported, human-initiated
path while you do all the preparation.

## Context (auto-injected)
- Repo: !`basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null`
- Base branch: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-base-branch.sh" 2>/dev/null`
- Background agents available: !`command -v claude >/dev/null 2>&1 && echo yes || echo "NO — claude CLI not on PATH"`
- Existing hv agents: !`claude agents --json 2>/dev/null | { command -v jq >/dev/null 2>&1 && jq -r '[.[]?|select((.name//"")|startswith("hv/"))]|length' || cat; } 2>/dev/null || echo 0`

## Step 1 — Load and validate the manifest

Parse the manifest (from `@file`, pasted JSON, or the previous `/hv:plan-features`
output), then validate it **mechanically** before dispatching anything. File
overlap and dependency cycles are the two errors that silently corrupt a
parallel run, so check them with a script rather than by eye:

```bash
# Write the manifest to a file (if not already one), then validate it.
MANIFEST="$(git rev-parse --show-toplevel)/.hv/manifest.json"
mkdir -p "$(dirname "$MANIFEST")"
# ... write the parsed manifest JSON to "$MANIFEST" ...
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate_manifest.py" "$MANIFEST"
```

The script confirms every feature has `id`, `branch`, `scope`, `target_files`,
and `success_criteria`; that **no two features share a `target_files` entry**
(file-disjointness is what lets them run in separate worktrees without
interfering); and that `depends_on` references resolve with no cycles. If it
exits non-zero, **stop and report the listed problems** — do not launch an
invalid manifest. (If `python3` is unavailable, fall back to checking those same
three conditions by hand, but prefer the script.)

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

## Step 4 — Write each feature's self-contained spec

For each feature, write a spec file that carries **the whole picture + its own
slice**, so a worker understands the epic and its place in it without the rest of
the manifest. Each spec = the feature object **plus** the manifest's `epic_summary`
and `shared_contracts`:

```bash
ROOT="$(git rev-parse --show-toplevel)"
SPEC_DIR="$ROOT/.hv/specs"
mkdir -p "$SPEC_DIR"
# For each feature, merge epic_summary + shared_contracts into the feature object
# and write compact JSON to "$SPEC_DIR/<id>.json" (jq if available, else construct it).
```

The spec path (not inline JSON) is what gets passed to the worker — a path has no
`"`/`{}` to break shell quoting.

## Step 5 — Emit the launch commands (per wave, for the human to run)

Do **not** run these yourself. Print them for the human to paste — in the terminal,
or as prompts in the `claude agents` view. Use a `hv/<id>` name so `/hv:agent-status`
and `/hv:clean-agents` can correlate the agent with its PR and worktree:

```bash
# Wave 1 (independent features) — paste each line:
claude --bg --name "hv/<id>" --model opus --permission-mode acceptEdits \
  "/hv:build-feature $ROOT/.hv/specs/<id>.json"
# ... one per feature in the wave ...
```

Agent-view equivalent (type as a new-session prompt): `@<repo> /hv:build-feature <abs spec path>`.

Notes to surface:
- **Permissions for hands-off runs.** `acceptEdits` auto-accepts edits; background
  agents auto-deny *other* prompts. If a worker needs `git push` / `gh pr create`
  without prompts, those must be allowed in settings (or relaunch with
  `--dangerously-skip-permissions` after a one-time interactive accept) — otherwise
  the run stalls silently.
- **Waves**: emit wave 1 now; only start a later wave once its prerequisites have
  **open/merged PRs** (check `/hv:agent-status`) — don't build a dependent feature
  against unlanded work.

## Step 6 — Overview and hand off

Show current state and flag leftovers:
```
!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/agents-status.sh" hv/ 2>/dev/null`
```
Print the launch plan table:
```
| feature | branch | agent name (hv/<id>) | wave | launch command emitted |
|---------|--------|----------------------|------|------------------------|
```
Then tell the user: watch with **`/hv:agent-status`**; review with **`/hv:review-pr <pr>`**,
fix with **`/hv:apply-feedback`**, merge with **`/hv:merge-pr`**; reclaim merged
features with **`/hv:clean-agents`** (or auto-clean each PR on merge via **`/hv:watch-merges <pr>`**).
If the overview shows finished/merged leftovers, suggest cleaning them now.

result: prepared <n> features in <w> wave(s); launch commands emitted for the human to run.
