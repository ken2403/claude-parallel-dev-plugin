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

## Guardrails

These rules apply to the **lead and all teammates** throughout the entire job. Violations are never acceptable, regardless of circumstances.

### Worktree Boundaries (Lead + Teammates)
- **NEVER modify files outside the worktree directory.** Before any file write/edit, verify the target path starts with the worktree path. If it doesn't, STOP.
- **NEVER modify the parent directory** of the worktree.
- **NEVER modify the default branch** (main/master/develop). All work must be on the feature branch created by setup.

### Git Safety (Lead only — teammates must not touch git)
- **NEVER delete or force-push branches.** Only create new branches.
- **NEVER delete the worktree** before the PR is merged. Cleanup is handled by `/pw:wt-clean`.
- Teammates must **NEVER run `git commit`, `git push`, or switch branches**. Only the lead handles git operations.

### File Ownership (Lead + Teammates)
- Each file belongs to exactly **one** teammate. No file appears in multiple scopes.
- Shared files (entry points, index files, barrel exports) are reserved for the **lead** to handle after all teammates complete.
- Teammates must **only modify files in their assigned list**.

### Error Recovery
If any error occurs: do NOT modify files outside the worktree, do NOT switch branches, do NOT delete the worktree. Document the error clearly and leave the worktree in its current state for manual inspection.

---

## Setup Worktree

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

---

## Implement with Agent Team

After the worktree is ready, load `.wtj-meta` and implement the task using an agent team.

### What to Achieve

Explore the codebase, decompose the task into file-isolated work, and create an agent team to implement everything in parallel. Decide the team size (2-5 teammates) and specialization based on the actual work required — there is no fixed team structure.

**Input handling**:
- **@design-document**: Parse for file lists, task scopes, and success criteria.
- **#issue-number**: Fetch issue details via `gh issue view`.
- **Text description**: Explore the codebase first, then decompose.

### Task List

Use the shared task list with task dependencies. Aim for several focused tasks per teammate rather than one monolithic assignment — this keeps teammates productive and lets them self-claim work as they finish. Example dependency chain:

- "Define interfaces/types for [feature]" (no dependencies)
- "Implement [handler]" (depends on types task)
- "Write tests for [handler]" (depends on implementation task)

### Safety Context for ALL Teammates

**CRITICAL**: Teammates do not inherit the lead's conversation history. Every spawn prompt MUST include these rules verbatim:

> **Safety Rules** (include in every spawn prompt):
> - Work ONLY within the worktree directory: `[WORKTREE_PATH]`
> - NEVER modify files outside the worktree
> - NEVER run `git commit` or `git push` — the lead handles all commits
> - NEVER switch branches
> - Only modify files in your assigned file list
> - Do NOT modify files assigned to other teammates

Also include in each spawn prompt: the worktree path from `.wtj-meta`, the specific files this teammate owns and must NOT touch, task context scoped to their work, and available tools (`explorer`/`analyzer` subagents, `/pw:code-quality` and `/pw:security-review` skills).

### Plan Approval

For complex or risky tasks, consider requiring plan approval before implementation begins — each teammate proposes their approach first, and the lead reviews and resolves conflicts before anyone writes code. For straightforward tasks, the lead may skip this step.

### Coordination

- Teammates **self-claim** tasks from the shared task list as they finish earlier work.
- Teammates **message each other directly** to resolve API contracts or shared type questions.
- The lead **monitors progress** and redirects approaches that aren't working — don't let the team run unattended too long.
- **Wait for ALL teammates** to complete before proceeding to verification.
- The lead handles integration files (entry points, barrel exports, wiring) after all teammates finish.

---

## Verify and Ship

After all teammates complete, verify the implementation is correct, then ship it as a PR. The lead handles all git operations.

**Verification**: Confirm no teammate modified files outside their assigned scope. Handle integration files. Run `/pw:precheck HEAD` via the Skill tool — fix issues and re-run until all checks pass.

**Commit**: Create a commit with message `[prefix]: [task description]` and `Co-Authored-By: Claude <noreply@anthropic.com>`.

**Push and PR**: Push to origin and create a PR via `gh pr create` with a summary of the task, team composition, and changes. Include `Closes #[issue]` if applicable.

**Cleanup**: Shut down all teammates and clean up team resources.
