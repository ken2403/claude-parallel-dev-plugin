---
allowed-tools: Read, Bash, Grep, Glob
argument-hint: [branch1 branch2 ...] or [decomposition output]
description: Start parallel workers and assign tasks based on decomposition
model: opus
---

# Orchestration

## Input
$ARGUMENTS

## Current State
- Repository: !`basename $(git rev-parse --show-toplevel 2>/dev/null) || echo "unknown"`
- Current branch: !`git branch --show-current`
- Clean state: !`git status --short | head -5 || echo "clean"`
- Open PRs: !`gh pr list --state open --limit 10 2>/dev/null || echo "Cannot fetch PRs"`
- Active tmux sessions: !`tmux list-sessions 2>/dev/null || echo "No active sessions"`

## Plugin Location

Locate the parallel-workflow plugin scripts:
```bash
# Find plugin directory (check common locations)
if [ -d ".paralell-workflow-plugin/scripts" ]; then
  PLUGIN_DIR=".paralell-workflow-plugin"
elif [ -d "../.paralell-workflow-plugin/scripts" ]; then
  PLUGIN_DIR="../.paralell-workflow-plugin"
elif [ -n "$PW_PLUGIN_DIR" ]; then
  PLUGIN_DIR="$PW_PLUGIN_DIR"
else
  echo "Error: parallel-workflow plugin not found"
  echo "Set PW_PLUGIN_DIR environment variable or place plugin in .paralell-workflow-plugin/"
  exit 1
fi
```

## Prerequisites Check

Before starting workers:
```bash
# Ensure main is up to date
git fetch origin main

# Check for uncommitted changes
git status --short
```

## Orchestration Process

### Step 1: Parse Input

If input contains branch names:
- Extract branch names for worker creation

If input is decomposition output:
- Parse subtask definitions
- Extract branch names and task descriptions

### Step 2: Create Worker Environments

Use the plugin's spinup script:
```bash
# Using plugin scripts
"${PLUGIN_DIR}/scripts/spinup.sh" [branch1] [branch2] [branch3]
```

The spinup script will:
1. Create git worktrees for each branch
2. Start tmux sessions for each worker
3. Configure based on `config.local.yaml`

### Step 3: Assign Tasks to Workers

For each worker, construct and send the task command:

```bash
# Get project name from plugin config
PROJECT_NAME=$(grep "project_name:" "${PLUGIN_DIR}/config.local.yaml" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo "my-project")

# Convert branch name to session name (replace / with -)
# Example: feature/auth -> feature-auth
# Session name format: ${PROJECT_NAME}__${branch_with_dash}

# Worker 1
tmux send-keys -t "${PROJECT_NAME}__[branch1-safe]" \
  'claude -p "/pw:worker [Task 1 detailed description in English]"' Enter

# Worker 2
tmux send-keys -t "${PROJECT_NAME}__[branch2-safe]" \
  'claude -p "/pw:worker [Task 2 detailed description in English]"' Enter
```

**CRITICAL**: Always write task prompts in English for consistent parsing.

### Step 4: Provide Monitoring Commands

```bash
# Check all sessions
tmux list-sessions

# Check specific worker
tmux capture-pane -t '[session]' -p | tail -50

# Check PR status
gh pr list --state open
```

## Output Format

```markdown
# Orchestration Started

## Plugin Location
- Plugin directory: [PLUGIN_DIR path]
- Config file: [config.local.yaml path]

## Workers Created
| Session | Branch | Worktree | Status |
|---------|--------|----------|--------|
| [session1] | feature/xxx | /path/to/wt-feature-xxx | Started |
| [session2] | feature/yyy | /path/to/wt-feature-yyy | Started |
| [session3] | feature/zzz | /path/to/wt-feature-zzz | Started |

## Task Assignments
- **Worker 1** (feature/xxx): [Task description]
- **Worker 2** (feature/yyy): [Task description]
- **Worker 3** (feature/zzz): [Task description]

## Monitoring Commands
```bash
# Check all workers
/pw:status

# Check specific worker
tmux capture-pane -t '[session]' -p | tail -50
```

## Next Steps
1. Monitor progress with `/pw:status`
2. When PRs are ready, review with `/pw:review [pr-number]`
3. After all PRs merged, cleanup with `/pw:cleanup [branches]`
```

## Critical Rules
- **NEVER** run teardown until all PRs are merged
- **ALWAYS** write worker prompts in English
- **MONITOR** workers periodically for blockers
- **INTERVENE** early when problems arise
