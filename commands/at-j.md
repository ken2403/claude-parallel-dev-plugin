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

1. **NEVER modify files in the parent directory**
   - The parent of the worktree directory is OFF-LIMITS
   - Only work within the created worktree directory

2. **NEVER modify the default branch (main/master/develop)**
   - All work MUST be on a feature branch
   - NEVER checkout or commit to the default branch

3. **NEVER modify files outside the worktree**
   - Your working directory is `worktrees/<job-name>/`
   - Any path not starting with your worktree path is FORBIDDEN

4. **NEVER delete or force-push existing branches**
   - Only create new branches
   - NEVER use `git push --force` on existing branches

5. **NEVER delete the worktree before the PR is merged**
   - Worktree cleanup is handled by `/pw:wt-clean`
   - Only wt-clean can delete worktrees, and only after merge verification

### Verification Before Any File Operation

Before ANY file write/edit operation, verify the target path starts with your worktree directory.
If you are about to modify a file outside `worktrees/<job-name>/`, STOP IMMEDIATELY.

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

## Phase 2: Task Analysis and Decomposition

### Load Metadata

```bash
# Load metadata from Phase 1
if [ -z "$WORKTREE_PATH" ]; then
  for meta in worktrees/*/.wtj-meta; do
    [ -f "$meta" ] && source "$meta" && break
  done
fi
[ -z "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ] && echo "ERROR: Run Phase 1 first" && exit 1
source "$WORKTREE_PATH/.wtj-meta"
cd "$WORKTREE_PATH"
echo "Working in: $(pwd)"
echo "Branch: $(git branch --show-current)"
```

### Read Project Configuration

```bash
source "$WORKTREE_PATH/.wtj-meta"
cd "$WORKTREE_PATH"

echo "=== Project Configuration ==="
if [ -f "CLAUDE.md" ]; then
  echo "--- CLAUDE.md ---"
  head -100 CLAUDE.md
fi

if [ -f "README.md" ]; then
  echo ""
  echo "--- README.md (excerpt) ---"
  head -50 README.md
fi
```

### Explore Codebase

**MANDATORY**: Use explorer subagent to understand the codebase before decomposition.

```
Use explorer subagent to:
1. Understand the project structure
2. Find files related to the task
3. Identify existing patterns and conventions
```

### Determine Input Type

- **@design-document input**: Parse the at-design output directly for task decomposition. Extract file lists, subtask scopes, and success criteria from the document.
- **Issue input (#number)**: Fetch issue details, then decompose using Lead analysis.
- **Text input**: Analyze the text, explore the codebase, then decompose.

### Build File Ownership Manifest

Decompose the task into file-isolated subtasks. Create a manifest:

```
Implementer-1: src/auth/login.ts, src/auth/types.ts, tests/auth/login.test.ts
  Scope: Implement authentication flow

Implementer-2: src/api/routes.ts, tests/api/routes.test.ts
  Scope: Add API endpoints

Integration (Lead): src/index.ts (after all Implementers complete)
  Scope: Wire up new modules in entry point
```

**Rules**:
- Each file belongs to exactly ONE Implementer
- No file appears in multiple Implementer scopes
- Shared files (entry points, index files) are reserved for Lead integration
- 2-5 Implementers maximum

---

## Phase 3: Agent Team Parallel Implementation

### Team Structure (Dynamic)

| Teammate | Model | File Scope |
|----------|-------|------------|
| Implementer-1 | sonnet | [File group 1] |
| Implementer-2 | sonnet | [File group 2] |
| ... | sonnet | ... |

**Lead Mode**: Delegate

### Implementer Spawn Prompt Template

```
You are an **Implementer** on a parallel development team working in a git worktree.

## Worktree
Working directory: [WORKTREE_PATH]

## Your Task
[Specific implementation scope for this Implementer]

## Files You Own (may create/modify)
- [file1]
- [file2]
- [test file]

## Files You Must NOT Modify
- [other Implementer's files]
- [shared files reserved for Lead]

## Implementation Guidelines

1. **Explore first**: Use `explorer` subagent to understand existing patterns
2. **Follow existing code style**: Match naming, formatting, and idioms
3. **Minimal changes**: Only modify what's necessary for your scope
4. **Type safety**: Add type annotations where the project uses them
5. **Error handling**: Handle errors appropriately
6. **No dead code**: Don't leave commented-out code

### Quality Standards
- Follow `/pw:code-quality` standards
- Follow `/pw:security-review` standards for sensitive code

## CRITICAL Safety Rules
- ONLY modify files in your "Files You Own" list
- NEVER modify files outside the worktree: [WORKTREE_PATH]
- NEVER run `git commit` or `git push` — the Lead handles all commits
- NEVER switch branches

## On Completion
Report:
1. List of files changed with descriptions
2. Any concerns or decisions made
3. Any integration points the Lead needs to handle
```

### Lead Coordination During Implementation

The Lead:
1. Spawns all Implementers with their scoped prompts
2. Monitors for completion
3. Does NOT implement anything during this phase (Delegate mode)

---

## Phase 4: Verification (via /pw:precheck)

### 4.1 File Scope Validation

```bash
source "$WORKTREE_PATH/.wtj-meta"
cd "$WORKTREE_PATH"

echo "=== File Scope Validation ==="
echo "Changed files:"
git diff --name-only
echo ""
echo "New files:"
git ls-files --others --exclude-standard
```

The Lead checks:
- Every changed file belongs to exactly one Implementer's scope
- No files outside the manifest were modified
- If violations found → instruct the offending Implementer to revert

### 4.2 Lead Handles Shared Files

After all Implementers complete, the Lead:
1. Processes shared/integration files (e.g., index.ts, exports)
2. Wires up new modules created by Implementers
3. Resolves any remaining integration points

### 4.3 Create Interim Commit

```bash
source "$WORKTREE_PATH/.wtj-meta"
cd "$WORKTREE_PATH"

echo "=== Creating Interim Commit for Precheck ==="

git add .
if ! git diff --cached --quiet; then
  git commit -m "wip: ${TASK_DESCRIPTION}"
  echo "Interim commit created"
else
  echo "No changes to commit"
fi
```

### 4.4 Run /pw:precheck

Use the Skill tool to invoke `/pw:precheck HEAD`. This runs comprehensive checks including:
- Local checks (lint, format, type check, build)
- Test verification
- Code quality & codebase consistency review
- Specification alignment check

### 4.5 Fix Issues and Re-verify

If `/pw:precheck` reports issues:
1. Identify which Implementer's files are affected
2. Instruct the relevant Implementer to fix their files
3. For shared file issues, the Lead fixes directly
4. Stage and amend: `git add . && git commit --amend --no-edit`
5. Re-run `/pw:precheck HEAD` via the Skill tool
6. Repeat until all precheck phases pass

---

## Phase 5: Commit and Push

### Final Safety Verification and Commit

```bash
# Load metadata from Phase 1
if [ -z "$WORKTREE_PATH" ]; then
  for meta in worktrees/*/.wtj-meta; do
    [ -f "$meta" ] && source "$meta" && break
  done
fi
[ -z "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ] && echo "ERROR: Run Phase 1 first" && exit 1
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

---

## Phase 6: Create Pull Request

```bash
# Load metadata from Phase 1
if [ -z "$WORKTREE_PATH" ]; then
  for meta in worktrees/*/.wtj-meta; do
    [ -f "$meta" ] && source "$meta" && break
  done
fi
[ -z "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ] && echo "ERROR: Run Phase 1 first" && exit 1
source "$WORKTREE_PATH/.wtj-meta"
cd "$WORKTREE_PATH"

# Variables are now loaded from metadata file:
# - BRANCH_PREFIX, TASK_DESCRIPTION, ISSUE_NUM, etc.

CLOSES_LINE=""
if [ -n "$ISSUE_NUM" ]; then
  CLOSES_LINE="Closes #${ISSUE_NUM}"
fi

# Generate PR title from task description (variables from metadata)
PR_TITLE="${BRANCH_PREFIX}: ${TASK_DESCRIPTION}"

echo "=== Creating Pull Request ==="
echo "Title: ${PR_TITLE}"

gh pr create --title "${PR_TITLE}" --body "## Summary

${TASK_DESCRIPTION}

Automated implementation by at-j (Agent Teams).

## Agent Team Summary

| Implementer | Scope | Files |
|------------|-------|-------|
| [Implementer details filled by Lead] |

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

---

## Output Report

```markdown
# Agent Team Worktree Job Report

## Job Information
- **Job Name**: [job-name]
- **Branch**: [branch-name]
- **Worktree Path**: worktrees/[job-name]/
- **Base Branch**: [base-branch]

## Task
[Original task description or issue reference]

## Agent Team Summary
| Implementer | Scope | Files Changed |
|------------|-------|---------------|
| Implementer-1 | [scope] | [files] |
| Implementer-2 | [scope] | [files] |
| Lead (Integration) | [shared files] | [files] |

## Implementation Summary
[What was implemented]

## Files Changed
- `path/to/file1` - [Description]
- `path/to/file2` - [Description]

## Verification Results
- [ ] File scope validation: PASS/FAIL
- [ ] Lint: PASS/FAIL
- [ ] Type Check: PASS/FAIL
- [ ] Tests: PASS/FAIL
- [ ] Build: PASS/FAIL

## Pull Request
- **PR URL**: [URL]
- **PR Number**: #[number]
- **Status**: Ready for Review

## Cleanup Instructions

After PR is merged, run:
```bash
/pw:wt-clean [job-name]
```

**WARNING**: Do NOT manually delete the worktree before merging!

## Notes
[Any additional notes, decisions made, or issues encountered]
```

---

## Error Handling

If ANY error occurs:

1. **DO NOT** attempt to fix by modifying files outside worktree
2. **DO NOT** switch to base branch
3. **DO NOT** delete the worktree
4. Document the error clearly in the output
5. Leave the worktree in its current state for manual inspection
6. Report what was attempted and what failed

```bash
# On error, show diagnostic info
echo "=== Error Diagnostic ==="
echo "Working directory: $(pwd)"
echo "Branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
echo "Git status:"
git status --short 2>/dev/null || echo "Not in git repo"
echo ""
echo "Recent commits:"
git log --oneline -5 2>/dev/null || echo "No commits"
```
