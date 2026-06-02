---
allowed-tools: Read, Bash, Grep, Glob, WebFetch
argument-hint: '[#issue-number | "specification text" | @file-reference]'
description: Launch agent team to discuss specs and decompose into tasks
model: opus
---

# Agent Team Design Phase

Launch an agent team to collaboratively discuss, critique, and validate a specification before decomposing it into parallel-executable tasks.

## Input
$ARGUMENTS

## Prerequisites

```bash
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]; then
  echo "ERROR: Agent Teams not enabled. Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json"
  exit 1
fi
echo "Agent Teams: ENABLED"
```

## Gather Context

Determine the input type and collect all necessary context before creating the team.

- **#issue-number**: Fetch via `gh issue view [number] --json title,body,labels,assignees`.
- **@file-reference**: Read the referenced specification file.
- **Direct text**: Use the specification as provided.

Collect repository context:

```bash
echo "Remote: $(git remote get-url origin 2>/dev/null || echo 'local')"
echo "Branch: $(git branch --show-current)"
echo "Base branch: $(_PD=""; for _d in "${PW_PLUGIN_DIR:-}" "${CLAUDE_PLUGIN_ROOT:-}" ./pw ../pw ../../pw; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -d "${PW_PLUGIN_DIR:-}/scripts" ] && _PD="$PW_PLUGIN_DIR"; "$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")"
ls -la | head -15
git log --oneline -5
```

## Create Agent Team

Create an agent team to discuss this specification like a **scientific debate**. Each teammate actively tries to find weaknesses in the others' proposals and disprove assumptions. The goal is that only ideas that survive rigorous challenge make it into the final design.

Adapt team composition to the spec's nature and complexity. Common useful perspectives:

- **Architecture** — propose technical design, file structure, and task decomposition
- **Critical review** — challenge every decision, identify risks, propose concrete alternatives
- **Codebase validation** — explore existing code deeply, verify feasibility and pattern consistency

A simple utility may only need two perspectives. A cross-cutting redesign benefits from all three or more.

### How the Team Should Work

- Each teammate has 5-6 tasks in the shared task list.
- Teammates message each other directly to debate. The architect shares proposals; others actively challenge them with evidence.
- Teammates don't just flag weaknesses — they propose **concrete alternatives** for every criticism.
- Use plan approval before finalizing the task decomposition.
- The lead synthesizes once all tasks complete, resolving remaining disagreements and producing the final design document.
- Clean up the team after synthesis is complete.

## Output

Generate the final design document in this format (compatible with `/pw:at-j` input):

```markdown
# Design: [Feature/Task Name]

## Overview
[Brief description]

## Requirements Summary
### Must Have
- [Requirement 1]
### Nice to Have
- [Optional]

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
- **Total tasks**: N
- **Parallel execution**: Full / Partial / Sequential

### Tasks

#### Task 1: [Name]
- **Scope**: [Clear description]
- **Target files**: `path/to/file1`, `path/to/file2`
- **Do NOT modify**: `path/to/shared/` (other workers' territory)
- **Success criteria**: [criteria]
- **Dependencies**: None / Task N

### Execution Order
Phase 1 (Parallel): Task 1, Task 2
Phase 2 (After Phase 1): Integration task

## Risks and Mitigations
| Risk | Severity | Mitigation |
|------|----------|------------|
| [Risk] | High/Medium/Low | [Mitigation] |

## Codebase Validation
- **Existing patterns to follow**: [patterns found in codebase exploration]
- **Reusable components**: [utilities/helpers identified]
- **Integration points**: [areas needing special attention]
- **File independence verified**: Yes/No (with evidence)
```

## Next Steps

- Run `/pw:at-j @design-document` to launch parallel implementation via Agent Teams
- Or run `/pw:wt-j` for single-agent implementation of individual tasks
