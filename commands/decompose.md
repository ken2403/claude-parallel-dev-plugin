---
allowed-tools: Read, Grep, Glob, Bash
argument-hint: [design output or task description]
description: Decompose a large task into parallel-executable subtasks with branch names
model: opus
---

# Task Decomposition

## Input
$ARGUMENTS

## Decomposition Rules

### Independence Criteria
Each subtask MUST satisfy ALL of these:
1. **File isolation**: No two subtasks modify the same file
2. **Logical completeness**: Each subtask produces working, testable code
3. **PR-ready**: Each subtask can be merged independently
4. **Clear scope**: Boundaries are unambiguous

### Optimal Worker Count
| Task Size | Workers | Pattern |
|-----------|---------|---------|
| Small | 2 | Core + Tests |
| Medium | 3 | Core + Tests + Docs |
| Large | 4-5 | By component/layer |

### Anti-patterns (AVOID)
- Splitting by arbitrary line count
- Creating circular dependencies between subtasks
- Having subtasks touch same files
- Over-granular decomposition (>5 subtasks)

## Decomposition Process

### Step 1: Identify Natural Boundaries
Use explorer subagent to understand file structure:
```
Use explorer subagent to find module boundaries and file organization
```

### Step 2: Define Subtasks

For each subtask, specify:
- Clear name and scope
- Target files/directories
- Prohibited files (what NOT to touch)
- Success criteria
- Dependencies (if any)

### Step 3: Validate Independence

Check for conflicts:
- File overlap between subtasks
- Shared state dependencies
- Import/dependency conflicts

## Output Format

```markdown
# Task Decomposition: [Task Name]

## Summary
- **Total subtasks**: N
- **Parallel execution**: Full / Partial / Sequential
- **Estimated complexity**: Low / Medium / High

## Subtasks

### Subtask 1: [Name]
- **Branch**: `feature/[descriptive-name]`
- **Scope**: [Clear description of what to implement]
- **Target files**:
  - `path/to/file1.py`
  - `path/to/file2.py`
- **Do NOT modify**:
  - `path/to/shared/` (other workers' territory)
- **Success criteria**:
  - [ ] [Criterion 1]
  - [ ] [Criterion 2]
  - [ ] Tests pass
  - [ ] Lint/type check pass
- **Dependencies**: None

### Subtask 2: [Name]
- **Branch**: `feature/[descriptive-name]`
...

## Execution Order
```
Phase 1 (Parallel):
  - Subtask 1: feature/xxx
  - Subtask 2: feature/yyy
  - Subtask 3: feature/zzz

Phase 2 (After Phase 1):
  - Subtask 4: feature/integration (if needed)
```

## Worker Commands

Copy-paste ready commands for orchestration:

### Start Workers
```bash
cd [repository]

# Find plugin directory
if [ -d ".paralell-workflow-plugin/scripts" ]; then
  PLUGIN_DIR=".paralell-workflow-plugin"
elif [ -d "../.paralell-workflow-plugin/scripts" ]; then
  PLUGIN_DIR="../.paralell-workflow-plugin"
fi

"${PLUGIN_DIR}/scripts/spinup.sh" feature/xxx feature/yyy feature/zzz
```

### Assign Tasks
```bash
# Worker 1
tmux send-keys -t '[project]__feature-xxx' \
  'claude -p "/pw:worker [Subtask 1 description]"' Enter

# Worker 2
tmux send-keys -t '[project]__feature-yyy' \
  'claude -p "/pw:worker [Subtask 2 description]"' Enter

# Worker 3
tmux send-keys -t '[project]__feature-zzz' \
  'claude -p "/pw:worker [Subtask 3 description]"' Enter
```
```

## Next Step
Run `/pw:orchestrate` with the branch names to start parallel execution.
