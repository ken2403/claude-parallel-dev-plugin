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
if [ -d ".claude-paralell-dev-plugin/scripts" ]; then
  PLUGIN_DIR=".claude-paralell-dev-plugin"
elif [ -d "../.claude-paralell-dev-plugin/scripts" ]; then
  PLUGIN_DIR="../.claude-paralell-dev-plugin"
elif [ -n "$PW_PLUGIN_DIR" ]; then
  PLUGIN_DIR="$PW_PLUGIN_DIR"
else
  echo "Error: parallel-workflow plugin not found"
  echo "Set PW_PLUGIN_DIR environment variable or place plugin in .claude-paralell-dev-plugin/"
  exit 1
fi
```

## Git Repository Detection

The scripts automatically detect the git repository:
1. If running inside a git repository, use it
2. If running from a parent directory, detect git repo in subdirectories
3. If multiple repos found, specify with `GIT_REPO` environment variable

This allows running from a parent directory:
```
/workspace/              ← Claude session here
├── my-project/          ← Git repo (auto-detected)
├── wt-feature-auth/     ← worktree (auto-created)
└── wt-feature-api/      ← worktree (auto-created)
```

## Base Branch Detection

Detect the base branch from workspace configuration (NOT always main/master):
```bash
# Check CLAUDE.md for base branch specification
BASE_BRANCH=""
if [ -f "CLAUDE.md" ]; then
  BASE_BRANCH=$(grep -i "base.branch\|default.branch\|primary.branch" CLAUDE.md | head -1 | grep -oE "(main|master|develop|dev|release[^[:space:]]*)" || echo "")
fi

# Fallback: check git remote HEAD or common branches
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
fi

# Final fallback: check which exists
if [ -z "$BASE_BRANCH" ]; then
  for branch in main master develop dev; do
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      BASE_BRANCH="$branch"
      break
    fi
  done
fi

echo "Base branch: ${BASE_BRANCH:-main}"
```

## Prerequisites Check

Before starting workers:
```bash
# Ensure base branch is up to date
git fetch origin ${BASE_BRANCH:-main}

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
3. Auto-detect project name from git repository

### Step 3: Assign Tasks to Workers

For each worker, construct and send the task command:

```bash
# Project name is auto-detected from git repository name
PROJECT_NAME=$(basename $(git rev-parse --show-toplevel))

# Convert branch name to session name (replace / with -)
# Example: feature/auth -> feature-auth
# Session name format: ${PROJECT_NAME}__${branch_with_dash}

# Worker 1 - Use -l flag to send literal characters (avoids quote escaping issues)
TASK1="[Task 1 detailed description in English]"
tmux send-keys -t "${PROJECT_NAME}__[branch1-safe]" -l "claude -p \"/pw:worker ${TASK1}\""
tmux send-keys -t "${PROJECT_NAME}__[branch1-safe]" Enter

# Worker 2
TASK2="[Task 2 detailed description in English]"
tmux send-keys -t "${PROJECT_NAME}__[branch2-safe]" -l "claude -p \"/pw:worker ${TASK2}\""
tmux send-keys -t "${PROJECT_NAME}__[branch2-safe]" Enter
```

**NOTE**: The `-l` flag sends characters literally, avoiding issues with special characters like quotes, `$`, and backticks in task descriptions.

**CRITICAL**: Always write task prompts in English for consistent parsing.

### Step 4: Start Background Monitoring

After assigning tasks, start the status-monitor subagent in background:

```
Use status-monitor subagent in background to monitor worker progress
```

The `status-monitor` subagent will:
- Check worker status every **30 seconds**
- Detect PR creation, errors, and completion
- Run for up to 30 minutes automatically
- Report when all workers complete or encounter errors

This allows the orchestrator to continue with other tasks while monitoring runs in the background.

#### Manual Status Check (Alternative)

If you prefer manual monitoring, run `/pw:status` periodically:

```bash
PROJECT_NAME=$(basename $(git rev-parse --show-toplevel))

echo "=== Status Check $(date) ==="

# Check each worker session
for session in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${PROJECT_NAME}__"); do
  echo "--- $session ---"
  OUTPUT=$(tmux capture-pane -t "$session" -p 2>/dev/null | tail -20)
  echo "$OUTPUT" | tail -5

  # Detect status
  if echo "$OUTPUT" | grep -qi "error\|failed\|exception\|traceback"; then
    echo "⚠️  STATUS: ERROR DETECTED"
  elif echo "$OUTPUT" | grep -qi "pull request\|pr created\|https://github.com.*pull"; then
    echo "✅ STATUS: PR CREATED"
  elif echo "$OUTPUT" | grep -qi "committed\|git commit"; then
    echo "🔄 STATUS: COMMITTED (PR pending)"
  else
    echo "⏳ STATUS: IN PROGRESS"
  fi
  echo ""
done

# Check PRs
echo "=== Open PRs ==="
gh pr list --state open 2>/dev/null || echo "Cannot fetch PRs"
```

#### Completion Detection

Track expected branches and check for PR creation:

```bash
# Expected branches (from orchestration input)
EXPECTED_BRANCHES="[branch1] [branch2] [branch3]"
EXPECTED_COUNT=$(echo "$EXPECTED_BRANCHES" | wc -w | tr -d ' ')

# Count PRs from these branches
CREATED_PRS=$(gh pr list --state open --json headRefName --jq '.[].headRefName' 2>/dev/null)
CREATED_COUNT=0

for branch in $EXPECTED_BRANCHES; do
  if echo "$CREATED_PRS" | grep -q "^${branch}$"; then
    CREATED_COUNT=$((CREATED_COUNT + 1))
  fi
done

echo "Progress: $CREATED_COUNT / $EXPECTED_COUNT PRs created"

if [ "$CREATED_COUNT" -eq "$EXPECTED_COUNT" ]; then
  echo "🎉 ALL WORKERS COMPLETED - Ready for review"
fi
```

#### Error Response

If error detected in a worker:

1. **Capture full error log**:
   ```bash
   tmux capture-pane -t "$session" -p -S -1000 > /tmp/worker_error_${session}.log
   ```

2. **Alert and suggest action**:
   - Display error summary
   - Suggest: retry, manual fix, or skip

3. **Options**:
   - Restart worker: `tmux send-keys -t "$session" 'claude -p "/pw:fix [error description]"' Enter`
   - Kill and recreate: teardown + spinup for that branch only

### Step 5: Transition to Review

When all PRs are created:

1. List all PRs for review:
   ```bash
   gh pr list --state open --json number,title,headRefName
   ```

2. Start review process:
   ```
   For each PR, run: /pw:rv [pr-number]
   ```

3. After all reviews approved and merged:
   ```
   Run: /pw:cleanup [branches]
   ```

## Output Format

### Initial Output (after worker startup)

```markdown
# Orchestration Started

## Workers Created
| Session | Branch | Worktree | Status |
|---------|--------|----------|--------|
| [project]__feature-xxx | feature/xxx | /path/to/wt-feature-xxx | Started |
| [project]__feature-yyy | feature/yyy | /path/to/wt-feature-yyy | Started |
| [project]__feature-zzz | feature/zzz | /path/to/wt-feature-zzz | Started |

## Task Assignments
- **Worker 1** (feature/xxx): [Task description]
- **Worker 2** (feature/yyy): [Task description]
- **Worker 3** (feature/zzz): [Task description]

## Monitoring Started
Checking status every 60 seconds...
```

### Monitoring Output (periodic updates)

```markdown
# Status Update [HH:MM:SS]

| Worker | Branch | Status | Last Activity |
|--------|--------|--------|---------------|
| Worker 1 | feature/xxx | 🔄 WORKING | Editing src/auth.py |
| Worker 2 | feature/yyy | ✅ PR CREATED | PR #45 |
| Worker 3 | feature/zzz | ⚠️ ERROR | Test failed |

## Progress: 1/3 PRs created

## Actions Needed
- Worker 3: Error detected. Review error and run `/pw:fix` or restart.
```

### Completion Output

```markdown
# 🎉 All Workers Completed

## PRs Ready for Review
| PR # | Branch | Title |
|------|--------|-------|
| #45 | feature/xxx | feat: Add authentication |
| #46 | feature/yyy | feat: Add API endpoints |
| #47 | feature/zzz | test: Add integration tests |

## Next Steps
1. Review each PR: `/pw:rv 45`, `/pw:rv 46`, `/pw:rv 47`
2. After all approved and merged: `/pw:cleanup feature/xxx feature/yyy feature/zzz`
```

## Critical Rules
- **NEVER** run teardown until all PRs are merged
- **ALWAYS** write worker prompts in English
- **MONITOR** workers periodically for blockers
- **INTERVENE** early when problems arise
