---
allowed-tools: Read, Grep, Glob, Bash, WebFetch
argument-hint: '[#issue-number | "specification text" | @file-reference]'
description: Analyze requirements from GitHub Issue or specification, create implementation design, and decompose into parallel-executable subtasks
model: opus
---

# Design Phase

## Input Specification
$ARGUMENTS

## Input Processing

Determine input type and extract requirements:

### 1. GitHub Issue Reference (#number)
```bash
gh issue view $1 --json title,body,labels,assignees
```

### 2. File Reference (@path)
Read the referenced specification file.

### 3. Direct Text
Parse the specification as provided.

## Current Project Context
- Repository: !`git remote get-url origin 2>/dev/null | sed 's/.*\///' | sed 's/\.git$//' || basename $(pwd)`
- Branch: !`git branch --show-current`
- Project structure: !`ls -la | head -15`

## Base Branch Detection

Detect the base branch from workspace configuration (NOT always main/master):
```bash
# Find plugin directory for shared scripts
PLUGIN_DIR=""
for d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin "$HOME"/.claude/plugins/cache/claude-parallel-dev-plugin/pw/*; do
  [ -d "$d/scripts" ] && PLUGIN_DIR="$d" && break
done 2>/dev/null
[ -n "${PW_PLUGIN_DIR:-}" ] && PLUGIN_DIR="$PW_PLUGIN_DIR"

# Base branch detection (using shared script)
BASE_BRANCH=$("${PLUGIN_DIR}/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
echo "Base branch: $BASE_BRANCH"
```

## Automatic Subagent Usage

**MANDATORY**: Before creating any design, you MUST use subagents:

1. **ALWAYS** use `explorer` subagent first to understand the codebase structure
2. For complex architectural decisions, use `analyzer` subagent to assess impact
3. Never skip exploration - it ensures accurate design decisions

## Design Process

### Step 1: Understand Requirements
Use explorer subagent to understand the codebase context:
```
Use explorer subagent to find existing patterns and architecture relevant to this task
```

Parse the specification to identify:
- Primary objectives
- Functional requirements
- Non-functional requirements (performance, security, etc.)
- Constraints and dependencies

### Step 2: Analyze Existing Codebase
- Identify affected components
- Find similar existing implementations
- Understand current patterns and conventions

### Step 3: Create Design Document

Output format:
```markdown
# Design: [Feature/Task Name]

## Overview
[Brief description of what will be implemented]

## Requirements Summary
### Must Have
- [Requirement 1]
- [Requirement 2]

### Nice to Have
- [Optional requirement]

## Architecture

### Affected Components
| Component | Changes Required |
|-----------|------------------|
| [Component] | [Description] |

### New Components
| Component | Purpose |
|-----------|---------|
| [Component] | [Purpose] |

## Implementation Plan

### Files to Create
- `path/to/new/file.py` - [Purpose]

### Files to Modify
- `path/to/existing/file.py` - [Changes needed]

## Candidate Subtasks for Parallel Execution

### Subtask 1: [Name]
- **Branch**: feature/[name]
- **Scope**: [Description]
- **Files**: [List]
- **Dependencies**: None | [List]

### Subtask 2: [Name]
...

## Execution Recommendation
- **Parallel execution possible**: Yes/No
- **Recommended workers**: [N]
- **Sequential dependencies**: [List if any]

## Risks and Mitigations
| Risk | Mitigation |
|------|------------|
| [Risk] | [Mitigation] |
```

## Step 4: Task Decomposition

After the design document is created, decompose the task into parallel-executable subtasks.

### Decomposition Rules

#### Independence Criteria
Each subtask MUST satisfy ALL of these:
1. **File isolation**: No two subtasks modify the same file
2. **Logical completeness**: Each subtask produces working, testable code
3. **PR-ready**: Each subtask can be merged independently
4. **Clear scope**: Boundaries are unambiguous

#### Optimal Worker Count
| Task Size | Workers | Pattern |
|-----------|---------|---------|
| Small | 2 | Core + Tests |
| Medium | 3 | Core + Tests + Docs |
| Large | 4-5 | By component/layer |

#### Anti-patterns (AVOID)
- Splitting by arbitrary line count
- Creating circular dependencies between subtasks
- Having subtasks touch same files
- Over-granular decomposition (>5 subtasks)

#### Task Splitting Patterns

**Pattern A: Feature-Based Split**
```
Worker 1: Authentication (src/auth/)
Worker 2: Dashboard (src/dashboard/)
Worker 3: API layer (src/api/)
```

**Pattern B: Layer-Based Split**
```
Worker 1: Frontend (components/, pages/)
Worker 2: Backend (server/, api/)
Worker 3: Tests (tests/)
```

**Pattern C: Task-Type Split**
```
Worker 1: New implementation
Worker 2: Refactoring
Worker 3: Test additions
```

### Decomposition Process

#### Step 4.1: Identify Natural Boundaries
Use explorer subagent to understand file structure:
```
Use explorer subagent to find module boundaries and file organization
```

#### Step 4.2: Define Subtasks

For each subtask, specify:
- Clear name and scope
- Target files/directories
- Prohibited files (what NOT to touch)
- Success criteria
- Dependencies (if any)

#### Step 4.3: Validate Independence

Check for conflicts:
- File overlap between subtasks
- Shared state dependencies
- Import/dependency conflicts

### Decomposition Output Format

Include the following in the design document:

```markdown
## Task Decomposition

### Summary
- **Total subtasks**: N
- **Parallel execution**: Full / Partial / Sequential
- **Estimated complexity**: Low / Medium / High

### Subtasks

#### Subtask 1: [Name]
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

#### Subtask 2: [Name]
- **Branch**: `feature/[descriptive-name]`
...

### Execution Order
```
Phase 1 (Parallel):
  - Subtask 1: feature/xxx
  - Subtask 2: feature/yyy
  - Subtask 3: feature/zzz

Phase 2 (After Phase 1):
  - Subtask 4: feature/integration (if needed)
```

### Worker Commands

Copy-paste ready commands for orchestration:

#### Start Workers
```bash
cd [repository]

# Find plugin directory
PLUGIN_DIR=""
for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin "$HOME"/.claude/plugins/cache/claude-parallel-dev-plugin/pw/*; do
  [ -d "$_d/scripts" ] && PLUGIN_DIR="$_d" && break
done 2>/dev/null
[ -n "${PW_PLUGIN_DIR:-}" ] && PLUGIN_DIR="$PW_PLUGIN_DIR"

"${PLUGIN_DIR}/scripts/spinup.sh" feature/xxx feature/yyy feature/zzz
```

#### Assign Tasks
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

### Worker Instruction Template

When assigning tasks, use this template format:

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
Create a git commit and open a PR. Detect base branch from workspace settings.
```

## Next Steps
After design and decomposition approval:
1. Run `/pw:orchestrate` with the branch names to start parallel execution
