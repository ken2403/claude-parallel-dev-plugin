---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Skill
argument-hint: [task description or @design-document] [--feature|--fix]
description: Create worktree and spawn agent team for parallel implementation
model: opus
---

# Agent Team Worktree Job - Parallel Isolated Development

Create an isolated git worktree and spawn an agent team for parallel implementation.
**This command runs autonomously until PR creation without requiring user approval.**

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

## CRITICAL SAFETY RULES

### ABSOLUTE PROHIBITIONS (NEVER VIOLATE)

1. **NEVER modify files in the parent directory** — only work within the created worktree directory.
2. **NEVER modify the default branch (main/master/develop)** — all work must be on a feature branch.
3. **NEVER modify files outside the worktree** — any path not starting with your worktree path is forbidden.
4. **NEVER delete or force-push existing branches** — only create new branches, never use `git push --force`.
5. **NEVER delete the worktree before the PR is merged** — cleanup is handled by `/pw:wt-clean`.

Before ANY file write/edit operation, verify the target path starts with your worktree directory. If you are about to modify a file outside `worktrees/<job-name>/`, STOP IMMEDIATELY.

---

## Phase 1: Setup Isolated Worktree

### Environment Setup (Single Block)

```bash
#!/bin/bash
set -e

echo "=== Agent Team Worktree Job Setup ==="

# ============================================
# 1. Detect Git Repository
# ============================================
echo ""
echo "--- Repository Detection ---"

GIT_ROOT=""
if git rev-parse --show-toplevel &>/dev/null; then
  GIT_ROOT=$(git rev-parse --show-toplevel)
else
  for dir in . */; do
    if [ -d "$dir/.git" ] || git -C "$dir" rev-parse --show-toplevel &>/dev/null 2>&1; then
      GIT_ROOT=$(cd "$dir" && git rev-parse --show-toplevel)
      break
    fi
  done
fi

if [ -z "$GIT_ROOT" ]; then
  echo "ERROR: No git repository found"
  exit 1
fi

echo "Git repository: $GIT_ROOT"
cd "$GIT_ROOT"

# ============================================
# 2. Detect Base Branch
# ============================================
echo ""
echo "--- Base Branch Detection ---"

# Base branch detection (using shared script)
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")

echo "Base branch: $BASE_BRANCH"

# Ensure base branch is up to date
git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true

# ============================================
# 3. Generate Job Name and Branch
# ============================================
echo ""
echo "--- Job Configuration ---"

INPUT_ARGS="$ARGUMENTS"

# Detect branch prefix (--feature or --fix)
BRANCH_PREFIX="feature"
if echo "$INPUT_ARGS" | grep -q "\-\-fix"; then
  BRANCH_PREFIX="fix"
  INPUT_ARGS=$(echo "$INPUT_ARGS" | sed 's/--fix//g')
fi
if echo "$INPUT_ARGS" | grep -q "\-\-feature"; then
  BRANCH_PREFIX="feature"
  INPUT_ARGS=$(echo "$INPUT_ARGS" | sed 's/--feature//g')
fi

# Trim whitespace
INPUT_ARGS=$(echo "$INPUT_ARGS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

echo "Branch prefix: $BRANCH_PREFIX"

# Extract issue number if present
ISSUE_NUM=$(echo "$INPUT_ARGS" | grep -oE '#[0-9]+' | head -1 | tr -d '#')

if [ -n "$ISSUE_NUM" ]; then
  JOB_NAME="issue-${ISSUE_NUM}"
  BRANCH_NAME="${BRANCH_PREFIX}/issue-${ISSUE_NUM}"
else
  # Generate from description (kebab-case, max 40 chars)
  JOB_NAME=$(echo "$INPUT_ARGS" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | cut -c1-40 | sed 's/^-//;s/-$//')
  JOB_NAME="${JOB_NAME:-job}"
  BRANCH_NAME="${BRANCH_PREFIX}/${JOB_NAME}"
fi

# Store task description for commit/PR (clean version without flags)
TASK_DESCRIPTION="$INPUT_ARGS"
if [ -n "$ISSUE_NUM" ]; then
  TASK_DESCRIPTION="Issue #${ISSUE_NUM}"
fi

echo "Job name: $JOB_NAME"
echo "Branch: $BRANCH_NAME"
echo "Task: $TASK_DESCRIPTION"

# Check if branch already exists locally - ERROR if it does
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
  echo ""
  echo "ERROR: Local branch '$BRANCH_NAME' already exists!"
  echo ""
  echo "Options:"
  echo "  1. Use a different task description"
  echo "  2. Delete the existing branch: git branch -D $BRANCH_NAME"
  echo "  3. Clean up existing worktree: /pw:wt-clean $JOB_NAME"
  exit 1
fi

# Check if branch already exists on remote - ERROR if it does
if git ls-remote --heads origin "$BRANCH_NAME" 2>/dev/null | grep -q "$BRANCH_NAME"; then
  echo ""
  echo "ERROR: Remote branch 'origin/$BRANCH_NAME' already exists!"
  echo ""
  echo "Options:"
  echo "  1. Use a different task description"
  echo "  2. Delete the remote branch: git push origin --delete $BRANCH_NAME"
  exit 1
fi

# ============================================
# 4. Create Worktree
# ============================================
echo ""
echo "--- Worktree Creation ---"

WORKTREES_DIR="${GIT_ROOT}/worktrees"
mkdir -p "$WORKTREES_DIR"

WORKTREE_PATH="${WORKTREES_DIR}/${JOB_NAME}"

echo "Worktree path: $WORKTREE_PATH"

# Check if worktree already exists
if [ -d "$WORKTREE_PATH" ]; then
  echo ""
  echo "ERROR: Worktree already exists at $WORKTREE_PATH"
  echo ""
  echo "Options:"
  echo "  1. Use a different task description"
  echo "  2. Clean up existing worktree: /pw:wt-clean $JOB_NAME"
  exit 1
fi

# Create new branch and worktree
echo "Creating new branch and worktree..."
if git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "origin/${BASE_BRANCH}" 2>/dev/null; then
  echo "Created from origin/${BASE_BRANCH}"
else
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "${BASE_BRANCH}"
  echo "Created from ${BASE_BRANCH}"
fi

# ============================================
# 4.5 Copy Claude Local Settings
# ============================================
if [ -f "${GIT_ROOT}/.claude/settings.local.json" ]; then
  echo "Copying .claude/settings.local.json to worktree..."
  mkdir -p "${WORKTREE_PATH}/.claude"
  cp "${GIT_ROOT}/.claude/settings.local.json" "${WORKTREE_PATH}/.claude/settings.local.json"
  echo "Done."
fi

# ============================================
# 5. Verify Setup
# ============================================
echo ""
echo "--- Verification ---"

cd "$WORKTREE_PATH"
CURRENT_BRANCH=$(git branch --show-current)

echo "Working directory: $(pwd)"
echo "Current branch: $CURRENT_BRANCH"

# Safety check: ensure NOT on base branch
if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ] || [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo ""
  echo "FATAL ERROR: On protected branch '$CURRENT_BRANCH'!"
  echo "This should never happen. Aborting."
  exit 1
fi

# Verify we're in worktrees directory
if [[ ! "$(pwd)" == *"/worktrees/"* ]]; then
  echo ""
  echo "FATAL ERROR: Not in worktrees directory!"
  echo "Current path: $(pwd)"
  exit 1
fi

# ============================================
# 6. Save Metadata for Other Phases
# ============================================
cat > "$WORKTREE_PATH/.wtj-meta" << EOF
WORKTREE_PATH="$WORKTREE_PATH"
BRANCH_NAME="$BRANCH_NAME"
BRANCH_PREFIX="$BRANCH_PREFIX"
BASE_BRANCH="$BASE_BRANCH"
JOB_NAME="$JOB_NAME"
TASK_DESCRIPTION="$TASK_DESCRIPTION"
ISSUE_NUM="$ISSUE_NUM"
EOF

echo ""
echo "=== Setup Complete ==="
echo ""
echo "IMPORTANT REMINDERS:"
echo "  - All work must be done in: $WORKTREE_PATH"
echo "  - Never modify files outside this directory"
echo "  - Never switch to $BASE_BRANCH"
echo "  - Cleanup after merge: /pw:wt-clean $JOB_NAME"
echo ""
echo "Environment variables saved to .wtj-meta:"
echo "  WORKTREE_PATH=$WORKTREE_PATH"
echo "  BRANCH_NAME=$BRANCH_NAME"
echo "  BRANCH_PREFIX=$BRANCH_PREFIX"
echo "  BASE_BRANCH=$BASE_BRANCH"
echo "  JOB_NAME=$JOB_NAME"
echo "  TASK_DESCRIPTION=$TASK_DESCRIPTION"
```

---

## Task Analysis and Team Spawning

### Task Decomposition

Explore the codebase to understand its structure and patterns before decomposing the work. Use an explorer subagent to find relevant files and identify existing conventions.

Decompose the task into file-isolated work items. Create **5-6 tasks per teammate** in the shared task list — not one monolithic task per teammate. Examples for a typical feature:

- "explore patterns in auth/"
- "implement login handler"
- "add types for auth module"
- "write tests for login"
- "handle edge cases and errors"
- "update exports"

Set task dependencies where needed (e.g., types task must complete before implementation task).

**Input type handling**:
- **@design-document**: Parse the at-design output directly. Extract file lists, task scopes, and success criteria from the document.
- **Issue (#number)**: Fetch issue details via `gh issue view`, then decompose using the Lead's analysis.
- **Text description**: Explore the codebase, then decompose based on the description.

### File Ownership

Each file belongs to exactly ONE teammate. No file appears in multiple teammates' scopes. Shared files (entry points, index files, barrel exports) are reserved for the Lead to handle after all teammates complete. Use 2-5 teammates maximum.

### Teammate Spawn Guidelines

Include the following in every teammate spawn prompt:

- **Worktree path and safety rules**: work only within the worktree, never run `git commit` or `git push`, never switch branches.
- **File ownership**: the specific files this teammate may create or modify, and the files they must NOT touch.
- **Task context**: the spec, issue description, or task description scoped to their work.
- **Available tools**: explorer and analyzer subagents for codebase exploration; `/pw:code-quality` and `/pw:security-review` skills for quality checks.

### Plan Approval

Require plan approval before teammates begin implementation. Each teammate first proposes their approach (key decisions, API shapes, notable tradeoffs). The Lead reviews all proposals, resolves conflicts (e.g., shared type definitions), and approves before anyone writes code.

### Coordination

- Let teammates **self-claim** remaining tasks from the shared task list as they finish earlier tasks.
- Teammates can **message each other directly** to resolve API contracts or shared type questions — they do not need to route everything through the Lead.
- **Wait for ALL teammates** to report completion before proceeding to verification.
- The Lead handles integration files (entry points, barrel exports, wiring) only after all teammates finish.

---

## Verification, Commit, and PR

### Verification

Check all changed files against file ownership. Confirm no teammate modified files outside their assigned scope. The Lead then handles shared and integration files.

Create an interim commit:

```bash
source "$WORKTREE_PATH/.wtj-meta"
cd "$WORKTREE_PATH"

git add .
if ! git diff --cached --quiet; then
  git commit -m "wip: ${TASK_DESCRIPTION}"
  echo "Interim commit created"
else
  echo "No changes to commit"
fi
```

Run `/pw:precheck HEAD` via the Skill tool. If issues are reported, fix them and re-run precheck until all phases pass.

### Commit and Push

```bash
source "$WORKTREE_PATH/.wtj-meta"
cd "$WORKTREE_PATH"

echo "=== Final Safety Check ==="

CURRENT_DIR=$(pwd)
CURRENT_BRANCH=$(git branch --show-current)

echo "Current directory: $CURRENT_DIR"
echo "Current branch: $CURRENT_BRANCH"

# Verify in worktree
if [[ ! "$CURRENT_DIR" == *"/worktrees/"* ]]; then
  echo "FATAL ERROR: Not in worktree directory!"
  exit 1
fi

# Verify NOT on protected branch
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ] || [ "$CURRENT_BRANCH" = "develop" ]; then
  echo "FATAL ERROR: On protected branch '$CURRENT_BRANCH'! Aborting."
  exit 1
fi

echo ""
echo "=== Finalizing commit ==="

# Stage any remaining changes (from precheck fix iterations)
git add .
if ! git diff --cached --quiet; then
  git commit --amend --no-edit
fi

# Amend interim commit with proper message
COMMIT_TITLE="${BRANCH_PREFIX}: ${TASK_DESCRIPTION}"

git commit --amend -m "${COMMIT_TITLE}

Automated implementation by at-j (Agent Teams)

Co-Authored-By: Claude <noreply@anthropic.com>"

echo "Commit finalized: ${COMMIT_TITLE}"

echo ""
echo "=== Pushing branch ==="
git push -u origin "$CURRENT_BRANCH"

echo ""
echo "Branch pushed successfully"
```

### Create Pull Request

```bash
source "$WORKTREE_PATH/.wtj-meta"
cd "$WORKTREE_PATH"

CLOSES_LINE=""
if [ -n "$ISSUE_NUM" ]; then
  CLOSES_LINE="Closes #${ISSUE_NUM}"
fi

PR_TITLE="${BRANCH_PREFIX}: ${TASK_DESCRIPTION}"

echo "=== Creating Pull Request ==="
echo "Title: ${PR_TITLE}"

gh pr create --title "${PR_TITLE}" --body "## Summary

${TASK_DESCRIPTION}

Automated implementation by at-j (Agent Teams).

## Agent Team Summary

| Teammate | Scope | Files |
|----------|-------|-------|
| [Teammate details filled by Lead] |

## Changes

See commit history for details.

## Testing

- [ ] All existing tests pass
- [ ] New functionality tested

## Related Issues

${CLOSES_LINE:-N/A}

---

**Agent Team Worktree Job**: This PR was created in an isolated worktree environment using parallel Agent Teams implementation.

To clean up after merge: \`/pw:wt-clean $(basename $(pwd))\`
"

echo ""
echo "PR created successfully"
```

### Error Handling

- Do NOT modify files outside the worktree.
- Do NOT switch to the base branch.
- Do NOT delete the worktree.
- Document errors clearly and leave the worktree in its current state for inspection.
- Report what was attempted and what failed.
