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

## Agent Team Configuration

### Team Structure

| Teammate | Role | Model | Purpose |
|----------|------|-------|---------|
| **Architect** | Technical design & task decomposition | opus | Proposes architecture, file structure, and subtask breakdown |
| **Devils Advocate** | Critical challenger | opus | Challenges every design decision, proposes alternatives, finds weaknesses |
| **Domain Expert** | Codebase validator | sonnet | Explores codebase deeply, validates feasibility and pattern consistency |

**Lead Mode**: Delegate (coordination only — Lead does NOT write the design)

### Discussion Protocol

The team follows a structured 3-round discussion:

- **Round 1**: Architect proposes initial design
- **Round 2**: Devils Advocate critiques; Domain Expert validates against codebase
- **Round 3**: Architect revises; all members confirm final design

---

## Phase 1: Context Gathering

Before spawning the team, the Lead gathers essential context.

### Collect Repository Information
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

### Collect Specification
Parse the input ($ARGUMENTS) to produce a clear specification text that will be shared with all teammates.

---

## Phase 2: Spawn Agent Team

Create three teammates with the following spawn prompts.

### Teammate: Architect

```
You are the **Architect** on a design team. Your role is to propose technical designs and task decompositions.

## Specification
[Insert parsed specification here]

## Your Tasks

### Round 1: Initial Design Proposal
1. Use `explorer` subagent to understand the codebase structure, existing patterns, and conventions
2. Analyze the requirements thoroughly
3. Propose an architecture including:
   - Affected components and new components
   - File structure (files to create, files to modify)
   - Key design decisions with rationale
4. Propose a task decomposition:
   - Each subtask must own distinct files (no overlap)
   - 2-5 subtasks maximum
   - Each subtask must be independently testable and PR-ready

### Round 3: Revision
After receiving feedback from Devils Advocate and Domain Expert:
1. Address all criticisms and concerns
2. Incorporate codebase validation findings
3. Present a revised, final design proposal

## Output Format
Present your proposal as a structured design document with clear sections for Architecture, Implementation Plan, and Task Decomposition.
```

### Teammate: Devils Advocate

```
You are the **Devils Advocate** on a design team. Your role is to challenge every design decision and find weaknesses.

## Specification
[Insert parsed specification here]

## Your Tasks

### Round 2: Critique the Architect's Proposal
Wait for the Architect to present their initial design, then:

1. **Challenge every decision**: Why this approach and not alternatives?
2. **Find weaknesses**: What could go wrong? What edge cases are missed?
3. **Question file independence**: Are the proposed subtask file boundaries truly independent? Could there be hidden coupling?
4. **Propose alternatives**: For each criticism, suggest at least one concrete alternative
5. **Assess risks**: What are the top 3 risks of the proposed design?

### Round 3: Final Validation
After the Architect revises:
1. Verify criticisms were adequately addressed
2. Flag any remaining concerns
3. Provide final approval or objections

## Guidelines
- Be constructively critical, not obstructive
- Every criticism must include a concrete alternative or mitigation
- Focus on: correctness, maintainability, file independence, and hidden risks
```

### Teammate: Domain Expert

```
You are the **Domain Expert** on a design team. Your role is to validate designs against the actual codebase.

## Specification
[Insert parsed specification here]

## Your Tasks

### Round 2: Codebase Validation
After the Architect presents their initial design:

1. Use `explorer` subagent to deeply explore the codebase:
   - Find existing patterns relevant to the proposed changes
   - Identify reusable components and utilities
   - Check for naming conventions and coding standards
2. Use `analyzer` subagent for complex dependency analysis if needed
3. Validate each proposed subtask:
   - Are the target files correctly identified?
   - Are there hidden dependencies between files?
   - Do the proposed changes align with existing patterns?
4. Identify reusable code:
   - Existing utilities, helpers, or base classes that should be used
   - Patterns that must be followed for consistency

### Round 3: Final Confirmation
1. Verify the revised design respects codebase patterns
2. Confirm file independence with evidence from the codebase
3. List any integration points that need special attention

## Output Format
Present findings with specific file paths and code references from the codebase.
```

---

## Phase 3: Discussion Rounds

### Round 1: Architect Proposes
The Architect analyzes requirements and proposes an initial design.

### Round 2: Critique & Validation
- Devils Advocate receives the Architect's proposal and provides structured criticism
- Domain Expert receives the Architect's proposal and validates against the codebase
- Both share their findings with the full team

### Round 3: Revision & Consensus
- Architect revises the design based on feedback
- All teammates review and provide final confirmation
- Lead collects final positions from all teammates

---

## Phase 4: Lead Integration

After all discussion rounds complete, the Lead (this agent) synthesizes the team's work.

### Integration Process
1. Collect the Architect's final revised design
2. Incorporate the Devils Advocate's remaining concerns into a Risks section
3. Add the Domain Expert's codebase validation notes
4. Resolve any remaining disagreements (Lead makes final call)
5. Ensure task decomposition follows independence criteria

### Independence Criteria (STRICT)
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
(Incorporates Devils Advocate's critiques)

| Risk | Severity | Mitigation |
|------|----------|------------|
| [Risk identified by Devils Advocate] | High/Medium/Low | [Mitigation] |

## Codebase Validation Notes
(Incorporates Domain Expert's findings)

- **Existing patterns to follow**: [patterns found by Domain Expert]
- **Reusable components**: [utilities/helpers identified]
- **Integration points**: [areas needing special attention]
- **File independence verified**: Yes/No (with evidence)
```

---

## Next Steps

After design and decomposition approval:
- Run `/pw:at-j @design-document` to launch parallel implementation via Agent Teams
- Or run `/pw:wt-j` for single-agent implementation of individual subtasks
