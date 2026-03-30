---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: [task description or @design-document or #issue-number]
description: Spawn agent team to implement a task in the current directory
model: opus
---

# Agent Team Implementation

Implement a task using an agent team in the current directory. No worktree creation, no automatic commits — the lead asks before shipping.

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

## Current Context
- Branch: !`git branch --show-current`
- Last commit: !`git log --oneline -1`
- Working directory: !`pwd`

## Implement with Agent Team

### Goal

Explore the codebase, decompose the task, and create an agent team to implement it in parallel. Autonomously decide team size and specialization based on the actual work required.

**Input handling**:
- **@design-document**: Parse for file lists, task scopes, and success criteria.
- **#issue-number**: Fetch issue details via `gh issue view`.
- **Text description**: Explore the codebase first, then decompose.

### Adaptive Team Size

- **1-2 affected files**: Use a single teammate — team overhead is not justified.
- **3+ affected files**: Create a team. Group files by directory or module, max 5 teammates.

### Task List

Use the shared task list with task dependencies. Aim for several focused tasks per teammate rather than one monolithic assignment — this keeps teammates productive and lets them self-claim work as they finish.

### Safety Context for ALL Teammates

**CRITICAL**: Teammates do not inherit the lead's conversation history. Every spawn prompt MUST include:

> **Safety Rules** (include in every spawn prompt):
> - Only modify files in your assigned file list
> - Do NOT modify files assigned to other teammates
> - NEVER run `git commit`, `git push`, or switch branches
> - Follow existing code patterns and style

Also include in each spawn prompt: the specific files this teammate owns, files they must NOT touch (other teammates' territory), and task context scoped to their work.

### File Ownership

- Each file belongs to exactly **one** teammate. No file appears in multiple scopes.
- Shared files (entry points, index files, barrel exports) are reserved for the **lead** to handle after all teammates complete.

### Coordination

- Teammates **self-claim** tasks from the shared task list as they finish earlier work.
- Teammates **message each other directly** to resolve API contracts or shared type questions.
- The lead **monitors progress** and redirects approaches that aren't working.
- **Wait for ALL teammates** to complete before proceeding to verification.
- The lead handles integration files after all teammates finish.

---

## Verify and Report

After all teammates complete:

1. Verify no files were changed outside assigned scope.
2. Handle integration files (entry points, barrel exports, wiring).
3. Run project checks:

```bash
echo "=== Project Checks ==="
if [ -f "Makefile" ] && grep -q "check" Makefile; then
  make check
elif [ -f "package.json" ]; then
  npm test 2>/dev/null || npm run test 2>/dev/null || true
elif [ -f "pyproject.toml" ]; then
  uv run pytest 2>/dev/null || uv run mypy . 2>/dev/null || true
fi
```

4. If failures: have the responsible teammate fix, then re-verify.
5. Clean up the team.
6. Report changes to the user:

```markdown
## Implementation Complete

### What was done
[Summary of changes]

### Files changed
- `path/to/file` - [description]

### Checks
- [pass/fail status]
```

## Commit & Push

**MANDATORY**: Ask the user via AskUserQuestion: **"Commit and push these changes?"**

If confirmed:

```bash
git add .
git commit -m "$(cat <<'EOF'
[prefix]: [task description]

Implemented by at-impl (Agent Teams).

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push
```

If declined, leave changes unstaged for the user to review with `git diff`.
