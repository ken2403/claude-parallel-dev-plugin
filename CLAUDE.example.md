# Parallel Task Execution Guide

This document provides guidance for running multiple Claude agents in parallel to efficiently process tasks.

## Toolkit Location

Parallel execution scripts are located in `.paralell/` directory:

- `spinup.sh` - Start parallel environment
- `teardown.sh` - Terminate parallel environment
- `config.local.yaml` - Configuration file

## Quick Start

**IMPORTANT**: Scripts must be executed from within the target Git repository using relative paths.

```bash
# Navigate to target repository
cd <target-repository>

# Start parallel environment (e.g., 3 workers)
../.paralell/spinup.sh feature/task1 feature/task2 feature/task3

# Teardown environment
../.paralell/teardown.sh feature/task1 feature/task2 feature/task3
```

---

## Orchestrator Responsibilities

When receiving large-scale tasks, follow this workflow for parallel processing.

### 1. Task Analysis

Criteria for parallelization:

- [ ] Can the task be split into independent subtasks?
- [ ] Do subtasks target different files/directories?
- [ ] Will parallelization provide meaningful time savings?

**Good candidates for parallelization**:
- Multiple independent feature implementations
- Changes to different modules
- Simultaneous test additions and refactoring

**Poor candidates for parallelization**:
- Concurrent changes to shared files required
- Sequential dependencies between changes
- Small-scale single-file modifications

### 2. Start Workers

```bash
cd <target-repository>
../.paralell/spinup.sh <branch1> <branch2> <branch3>
```

### 3. Assign Tasks

Send `claude -p` commands via `tmux send-keys`:

```bash
tmux send-keys -t '<project>__<branch>' \
  'claude -p "<task instructions>"' Enter
```

### 4. Monitor Progress

```bash
# List sessions
tmux list-sessions

# Check specific session output
tmux capture-pane -t '<session>' -p | tail -50
```

### 5. Integration & Merge

After all branches complete, merge into main branch.

### 6. Cleanup

```bash
../.paralell/teardown.sh <branch1> <branch2> <branch3>
```

---

## Guardrails

### MUST (Required)

1. **Define Scope Clearly**: Specify target files/directories for each worker
2. **Set Boundaries**: Indicate files that other workers must not touch
3. **Specify Completion Criteria**: Define exactly what "done" means
4. **Specify Base Branch**: Always indicate the base branch for PR creation

### MUST NOT (Prohibited)

1. **No Concurrent Shared File Edits**: Multiple workers must not edit the same file
2. **No Ignoring Dependencies**: Do not parallelize if sequential dependencies exist
3. **No Unsupervised Execution**: Monitor progress regularly
4. **No Ignoring Conflicts**: Address conflicts immediately when detected

### SHOULD (Recommended)

1. Distribute task sizes evenly across workers
2. Assign commit message prefixes to each worker
3. Intervene early when problems arise
4. Review changes in each branch before merging

---

## Task Splitting Patterns

### Pattern A: Feature-Based Split

```
Worker 1: Authentication (src/auth/)
Worker 2: Dashboard (src/dashboard/)
Worker 3: API layer (src/api/)
```

### Pattern B: Layer-Based Split

```
Worker 1: Frontend (components/, pages/)
Worker 2: Backend (server/, api/)
Worker 3: Tests (tests/)
```

### Pattern C: Task-Type Split

```
Worker 1: New implementation
Worker 2: Refactoring
Worker 3: Test additions
```

---

## Worker Instruction Template

```
You are responsible for "<task-name>".

## Scope
- Target: `<directory>/`
- Do not modify: `<shared-directory>/`

## Implementation
1. <specific task 1>
2. <specific task 2>

## Completion Criteria
- Implementation complete
- Tests pass
- Lint/type check pass

## On Completion
Create a git commit and open a PR. Base branch is `<base-branch>`.
```

---

## Conflict Resolution

```bash
# Send conflict resolution instructions
tmux send-keys -t '<session>' \
  'claude -p "Merge main branch and resolve conflicts, then push again."' Enter
```

---

## Troubleshooting

### Session Not Found

```bash
tmux list-sessions
```

### Check Worktree Status

```bash
git worktree list
```

### Force Cleanup

```bash
git worktree remove --force /path/to/worktree
tmux kill-session -t <session>
```

---

## Configuration

Configure in `.paralell/config.local.yaml`:

| Option | Description |
|--------|-------------|
| `project_name` | Prefix for tmux session names |
| `base_branch` | Branch to derive new branches from |
| `ui_mode` | `warp` (open tabs) or `tmux` (background only) |
| `warp_scheme` | Warp URI scheme |
