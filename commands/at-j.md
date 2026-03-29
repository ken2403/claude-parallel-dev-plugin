---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Skill
argument-hint: [task description or @design-document] [--feature|--fix]
description: Create worktree and spawn agent team for parallel implementation
model: opus
---

# Agent Team Worktree Job

Create an isolated git worktree, then create an agent team to implement the task in parallel. Run autonomously through PR creation without requiring user approval.

## Input
$ARGUMENTS

## Step 1: Create Worktree

```bash
#!/bin/bash
set -e

# Plugin discovery
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"

# Prerequisite check
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]; then
  echo "ERROR: Agent Teams not enabled. Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json"
  exit 1
fi

# Run shared worktree setup
"$_PD/scripts/setup-worktree.sh" "$ARGUMENTS" "Agent Team Worktree Job"
```

## Step 2: Create Agent Team and Implement

After the worktree is set up, load the metadata from `.wtj-meta` and create an agent team to implement the task.

### Goal

Analyze the task, explore the codebase, decompose it into file-isolated work, and create an agent team to implement everything in parallel. Claude decides the team size (2-5 teammates) and specialization based on the work required.

### Input Handling

- **@design-document**: Parse the design document for file lists, task scopes, and success criteria.
- **#issue-number**: Fetch issue details via `gh issue view`.
- **Text description**: Explore the codebase first, then decompose.

### Task List Design

Create 5-6 tasks per teammate in the shared task list. Use task dependencies to enforce ordering (e.g., type definitions must complete before implementation). Example tasks:

- "Explore existing patterns in [module]"
- "Define interfaces/types for [feature]" (no dependencies)
- "Implement [handler]" (depends on types task)
- "Write tests for [handler]" (depends on implementation task)
- "Handle edge cases" (depends on implementation task)

### File Ownership

Each file belongs to exactly one teammate. Shared files (entry points, index files, barrel exports) are reserved for the lead to handle after all teammates complete.

### Safety Context for ALL Teammates

**CRITICAL**: Every teammate spawn prompt MUST include these rules verbatim, because teammates do not inherit the lead's conversation history:

> **Safety Rules** (include in every spawn prompt):
> - Work ONLY within the worktree directory: `[WORKTREE_PATH]`
> - NEVER modify files outside the worktree
> - NEVER run `git commit` or `git push` — the lead handles all commits
> - NEVER switch branches
> - Only modify files in your assigned file list
> - Do NOT modify files assigned to other teammates

Also include in each spawn prompt:
- The worktree path from `.wtj-meta`
- The specific files this teammate owns and the files they must NOT touch
- Task context scoped to their work
- Available tools: `explorer` and `analyzer` subagents, `/pw:code-quality` and `/pw:security-review` skills

### Plan Approval

Require plan approval before implementation begins. Each teammate proposes their approach first (key decisions, API shapes, notable tradeoffs). The lead reviews all proposals, resolves conflicts between teammates (e.g., shared type definitions), and approves before anyone writes code.

### Coordination

- Teammates self-claim tasks from the shared task list as they finish earlier work.
- Teammates message each other directly to resolve API contracts or shared type questions.
- Wait for ALL teammates to complete before proceeding.
- The lead handles integration files (entry points, barrel exports, wiring) after all teammates finish.

## Step 3: Verify and Ship

After all teammates complete:

1. **Verify file scope** — confirm no teammate modified files outside their assigned scope.
2. **Handle integration files** — the lead wires up entry points, exports, and shared files.
3. **Create interim commit** — `git add . && git commit -m "wip: [task]"`.
4. **Run `/pw:precheck HEAD`** via the Skill tool. Fix any issues and re-run until all checks pass.
5. **Finalize commit** — amend with a proper commit message: `[prefix]: [task description]` with `Co-Authored-By: Claude <noreply@anthropic.com>`.
6. **Push** — `git push -u origin [branch]`.
7. **Create PR** — use `gh pr create` with a summary of the task, agent team composition, and changes made. Include `Closes #[issue]` if an issue number was provided.
8. **Clean up the team** — ask all teammates to shut down, then clean up team resources.

### Error Handling

If any error occurs: do NOT modify files outside the worktree, do NOT switch branches, do NOT delete the worktree. Document the error and leave the worktree for inspection.
