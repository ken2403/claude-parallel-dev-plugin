---
allowed-tools: Read, Bash, Grep, Glob, WebFetch
argument-hint: [#issue-number | "specification text" | @file-reference]
description: Launch agent team to discuss specs and decompose into tasks
model: opus
---

# Agent Team Design Phase

Launch an agent team of three specialists to collaboratively discuss, critique, and validate a specification before decomposing it into parallel-executable subtasks.

## Input
$ARGUMENTS

## Agent Teams Prerequisite Check

```bash
echo "=== Agent Teams Prerequisite Check ==="
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]; then
  echo "ERROR: Agent Teams feature is not enabled."
  echo ""
  echo "To enable, add to your settings.json:"
  echo '  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }'
  echo ""
  echo "Or set the environment variable:"
  echo "  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
  exit 1
fi
echo "Agent Teams: ENABLED"
```

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

```bash
# Plugin discovery + Base branch detection (canonical pattern from PR15)
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
echo "Base branch: $BASE_BRANCH"
```

---

## Context Gathering

Collect repository context before the team begins.

```bash
echo "=== Repository Context ==="
echo "Remote: $(git remote get-url origin 2>/dev/null || echo 'local')"
echo "Current branch: $(git branch --show-current)"
echo ""
echo "=== Project Structure ==="
ls -la | head -20
echo ""
echo "=== Recent Commits ==="
git log --oneline -10
```

Parse the input ($ARGUMENTS) to produce a clear specification text shared with all teammates.

---

## Agent Team Configuration

### Teammates

| Teammate | Model | Role |
|----------|-------|------|
| **Architect** | opus | Proposes technical design, file structure, and task decomposition based on deep codebase exploration |
| **Critic** | opus | Challenges every design decision, finds weaknesses, proposes alternatives. Constructively critical, not obstructive. |
| **Codebase Validator** | sonnet | Explores codebase deeply, validates feasibility and pattern consistency, identifies reusable components |

### Shared Task List

**Architect tasks:**
1. Explore codebase structure and identify relevant patterns
2. Propose architecture covering affected and new components
3. Define file structure (files to create and modify)
4. Decompose implementation into parallel subtasks with clear file ownership
5. Draft full implementation plan
6. Refine proposal based on Critic and Codebase Validator feedback

**Critic tasks:**
1. Review the Architect's initial architecture proposal
2. Identify risks, weaknesses, and edge cases in the design
3. Challenge proposed file boundaries and task independence claims
4. Propose concrete alternatives for each identified issue
5. Validate that the final revised plan adequately addresses all concerns

**Codebase Validator tasks:**
1. Explore modules relevant to the specification
2. Check naming conventions and coding standards in affected areas
3. Verify that proposed file boundaries are truly independent, with evidence
4. Identify reusable utilities, helpers, or base classes
5. Confirm integration points and flag areas needing special attention

### Coordination

- Teammates message each other directly for discussion and debate.
- Architect shares the initial proposal with both Critic and Codebase Validator.
- Critic and Codebase Validator share their findings with the Architect and each other.
- Use plan approval before finalizing the task decomposition.
- Lead synthesizes once all tasks are complete, resolving any remaining disagreements and producing the final design document.

---

## Output Format

Generate the final design document in this format (compatible with at-j input):

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
- `path/to/new/file` - [Purpose]

### Files to Modify
- `path/to/existing/file` - [Changes needed]

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
  - `path/to/file1`
  - `path/to/file2`
- **Do NOT modify**:
  - `path/to/shared/` (other workers' territory)
- **Success criteria**:
  - [ ] [Criterion 1]
  - [ ] [Criterion 2]
  - [ ] Tests pass
  - [ ] Lint/type check pass
- **Dependencies**: None

#### Subtask 2: [Name]
...

### Execution Order
Phase 1 (Parallel):
  - Subtask 1
  - Subtask 2
Phase 2 (After Phase 1, if needed):
  - Integration subtask

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| [Risk] | High/Medium/Low | [Mitigation] |

## Codebase Validation

- **Existing patterns to follow**: [patterns found by Codebase Validator]
- **Reusable components**: [utilities/helpers identified]
- **Integration points**: [areas needing special attention]
- **File independence verified**: Yes/No (with evidence)
```

---

## Next Steps

After design and decomposition approval:
- Run `/pw:at-j @design-document` to launch parallel implementation via Agent Teams
- Or run `/pw:wt-j` for single-agent implementation of individual subtasks
