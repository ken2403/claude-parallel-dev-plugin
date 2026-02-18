---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Skill
argument-hint: [#issue-number or "task description"] [--feature|--fix]
description: Create isolated worktree and autonomously implement task until PR creation
model: opus
---

# Worktree Job (wt-j) - Autonomous Isolated Development

Execute a development task in a completely isolated git worktree environment.
**This command runs autonomously until PR creation without requiring user approval.**

## Input
$ARGUMENTS

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

echo "=== Worktree Job Setup ==="

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

# Base branch detection (canonical: scripts/detect-base-branch.sh)
BASE_BRANCH=""
if [ -f "CLAUDE.md" ]; then
  BASE_BRANCH=$(grep -i "base.branch\|default.branch\|primary.branch" CLAUDE.md | head -1 | grep -oE "(main|master|develop|dev|release[^[:space:]]*)" || echo "")
fi
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
fi
if [ -z "$BASE_BRANCH" ]; then
  for branch in main master develop dev; do
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      BASE_BRANCH="$branch"
      break
    fi
  done
fi
BASE_BRANCH="${BASE_BRANCH:-main}"

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
# Each bash block runs in a separate process, so we save variables to a file
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

## Phase 2: Understand Requirements

### Fetch Issue Details (if applicable)

```bash
# Load metadata from Phase 1
if [ -z "$WORKTREE_PATH" ]; then
  # Try to find wtj-meta in any worktree
  for meta in worktrees/*/.wtj-meta; do
    if [ -f "$meta" ]; then
      source "$meta"
      break
    fi
  done
fi

if [ -z "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ]; then
  echo "ERROR: WORKTREE_PATH not set or directory does not exist"
  echo "This script must be run after Phase 1 setup"
  exit 1
fi

# Source metadata file for all variables
source "$WORKTREE_PATH/.wtj-meta"
cd "$WORKTREE_PATH"

if [ -n "$ISSUE_NUM" ]; then
  echo "=== Issue #${ISSUE_NUM} Details ==="
  gh issue view "$ISSUE_NUM" 2>/dev/null || echo "Could not fetch issue details"
fi
```

### Read Project Configuration

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

**MANDATORY**: Use explorer subagent to understand the codebase before implementation.

```
Use explorer subagent to:
1. Understand the project structure
2. Find files related to the task
3. Identify existing patterns and conventions
```

For complex tasks, also use analyzer:
```
Use analyzer subagent to understand architecture and dependencies if needed
```

---

## Phase 3: Autonomous Implementation

**NOTE**: This phase runs WITHOUT user approval. Make careful, incremental changes.

### Planning

Before writing code:
1. List all files to create or modify
2. Identify patterns to follow from existing code
3. Plan minimal, focused changes
4. Consider edge cases and error handling

### Implementation Guidelines

- **Follow existing code style** - match naming, formatting, idioms
- **Minimal changes** - only modify what's necessary
- **Type safety** - add type annotations where the project uses them
- **Error handling** - handle errors appropriately
- **No dead code** - don't leave commented-out code

**Apply Quality Skills**:
- Follow `/pw:code-quality` standards
- Follow `/pw:security-review` standards for sensitive code

### Safety Check Before Each File Operation

Before EVERY file write or edit, verify:
1. You are still in the worktree directory
2. The target file path is within the worktree
3. You are NOT modifying any file in the parent repository

---

## Phase 4: Verification (via /pw:precheck)

### 4.1 Create Interim Commit

`/pw:precheck` uses `git diff BASE...HEAD` to review committed changes. Create an interim commit so precheck can analyze the diff.

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

echo "=== Creating Interim Commit for Precheck ==="

git add .
if ! git diff --cached --quiet; then
  git commit -m "wip: ${TASK_DESCRIPTION}"
  echo "Interim commit created"
else
  echo "No changes to commit"
fi
```

### 4.2 Run /pw:precheck

Use the Skill tool to invoke `/pw:precheck HEAD`. This runs comprehensive checks including:
- Local checks (lint, format, type check, build)
- Test verification
- Code quality & codebase consistency review
- Specification alignment check

### 4.3 Fix Issues and Re-verify

If `/pw:precheck` reports any issues:
1. Fix the reported problems
2. Stage and amend the interim commit: `git add . && git commit --amend --no-edit`
3. Re-run `/pw:precheck HEAD` via the Skill tool
4. Repeat until all precheck phases pass

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

Automated implementation by wt-j

🤖 Generated with [Claude Code](https://claude.com/claude-code)

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

Automated implementation by wt-j.

## Changes

See commit history for details.

## Testing

- [ ] All existing tests pass
- [ ] New functionality tested

## Related Issues

${CLOSES_LINE:-N/A}

---

🤖 Generated autonomously with [Claude Code](https://claude.com/claude-code)

**Worktree Job**: This PR was created in an isolated worktree environment.

To clean up after merge: \`/pw:wt-clean $(basename $(pwd))\`
"

echo ""
echo "PR created successfully"
```

---

## Output Report

```markdown
# Worktree Job Report

## Job Information
- **Job Name**: [job-name]
- **Branch**: [branch-name]
- **Worktree Path**: worktrees/[job-name]/
- **Base Branch**: [base-branch]

## Task
[Original task description or issue reference]

## Implementation Summary
[What was implemented]

## Files Changed
- `path/to/file1` - [Description]
- `path/to/file2` - [Description]

## Verification Results
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
