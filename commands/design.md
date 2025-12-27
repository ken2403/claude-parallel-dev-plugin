---
allowed-tools: Read, Grep, Glob, Bash, WebFetch
argument-hint: [#issue-number | "specification text" | @file-reference]
description: Analyze requirements from GitHub Issue or specification and create implementation design
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

## Next Steps
After design approval:
1. Run `/pw:decompose` to formalize task decomposition
2. Run `/pw:orchestrate` to start parallel workers
