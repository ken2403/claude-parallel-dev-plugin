---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Skill
argument-hint: [message describing the task]
description: Execute a task in current worktree with precheck and commit
model: opus
---

# Worktree Do (wt-do) - Execute Task in Existing Worktree

Execute a task within an existing worktree environment, verify with precheck, and commit.
**This command does NOT push automatically. Push requires explicit human confirmation.**

## Input
$ARGUMENTS

## CRITICAL SAFETY RULES

### ABSOLUTE PROHIBITIONS (NEVER VIOLATE)

1. **NEVER modify files outside the worktree**
   - Your working directory must be within `worktrees/<job-name>/`
   - Any path not starting with your worktree path is FORBIDDEN

2. **NEVER modify the default branch (main/master/develop)**
   - All work MUST be on a feature branch
   - NEVER checkout or commit to the default branch

3. **NEVER push to remote**
   - This command NEVER pushes automatically
   - Push must be done manually by the user after review

4. **NEVER delete or force-push existing branches**
   - NEVER use `git push --force`

### Verification Before Any File Operation

Before ANY file write/edit operation, verify the target path starts with your worktree directory.
If you are about to modify a file outside `worktrees/<job-name>/`, STOP IMMEDIATELY.

---

## Phase 1: Environment Verification

### Verify Worktree Context

```bash
#!/bin/bash
set -e

echo "=== Worktree Environment Check ==="

CURRENT_DIR=$(pwd)
echo "Current directory: $CURRENT_DIR"

# Verify we are inside a worktree
if [[ ! "$CURRENT_DIR" == *"/worktrees/"* ]]; then
  echo ""
  echo "ERROR: Not inside a worktree directory!"
  echo "This command must be run from within an existing worktree."
  echo "Current path: $CURRENT_DIR"
  echo ""
  echo "To create a new worktree, use: /pw:wtj [task]"
  exit 1
fi

# Try to load .wtj-meta
WTJ_META=""
if [ -f ".wtj-meta" ]; then
  WTJ_META=".wtj-meta"
elif [ -f "$CURRENT_DIR/.wtj-meta" ]; then
  WTJ_META="$CURRENT_DIR/.wtj-meta"
else
  # Search up for .wtj-meta
  SEARCH_DIR="$CURRENT_DIR"
  while [[ "$SEARCH_DIR" == *"/worktrees/"* ]]; do
    if [ -f "$SEARCH_DIR/.wtj-meta" ]; then
      WTJ_META="$SEARCH_DIR/.wtj-meta"
      break
    fi
    SEARCH_DIR=$(dirname "$SEARCH_DIR")
  done
fi

if [ -n "$WTJ_META" ]; then
  echo ""
  echo "--- Loaded .wtj-meta ---"
  source "$WTJ_META"
  echo "WORKTREE_PATH=$WORKTREE_PATH"
  echo "BRANCH_NAME=$BRANCH_NAME"
  echo "BASE_BRANCH=$BASE_BRANCH"
  echo "JOB_NAME=$JOB_NAME"
  echo "TASK_DESCRIPTION=$TASK_DESCRIPTION"
else
  echo ""
  echo "WARNING: No .wtj-meta found. Using git context."
fi

# Verify branch
CURRENT_BRANCH=$(git branch --show-current)
echo ""
echo "Current branch: $CURRENT_BRANCH"

# Safety: ensure NOT on protected branch
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ] || [ "$CURRENT_BRANCH" = "develop" ]; then
  echo ""
  echo "FATAL ERROR: On protected branch '$CURRENT_BRANCH'!"
  echo "This command cannot run on protected branches."
  exit 1
fi

# Detect base branch if not loaded from meta
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
  if [ -z "$BASE_BRANCH" ]; then
    for branch in main master develop dev; do
      if git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
        BASE_BRANCH="$branch"
        break
      fi
    done
  fi
  BASE_BRANCH="${BASE_BRANCH:-main}"
  echo "Detected base branch: $BASE_BRANCH"
fi

echo ""
echo "=== Git Status ==="
git status --short

echo ""
echo "=== Environment OK ==="
echo "Ready to proceed with task: $ARGUMENTS"
```

---

## Phase 2: Understand & Implement

### Explore Codebase

**MANDATORY**: Use explorer subagent to understand the codebase before making changes.

```
Use explorer subagent to:
1. Find files related to the task
2. Understand existing patterns and conventions
3. Identify dependencies and potential impact areas
```

### Implementation Guidelines

- **Follow existing code style** — match naming, formatting, idioms
- **Minimal changes** — only modify what is necessary for the task
- **Type safety** — add type annotations where the project uses them
- **Error handling** — handle errors appropriately
- **No dead code** — do not leave commented-out code

**Apply Quality Skills**:
- Follow `/pw:code-quality` standards
- Follow `/pw:security-review` standards for security-sensitive code

### Safety Check Before Each File Operation

Before EVERY file write or edit, verify:
1. You are still in the worktree directory
2. The target file path is within the worktree
3. You are NOT modifying any file in the parent repository

---

## Phase 3: Verification

### 3.1 Conflict Check with Base Branch

```bash
# Load metadata if available
if [ -f ".wtj-meta" ]; then
  source ".wtj-meta"
fi
BASE_BRANCH="${BASE_BRANCH:-main}"

echo "=== Checking for Conflicts with $BASE_BRANCH ==="

git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true

# Attempt merge to detect conflicts
if git merge "origin/$BASE_BRANCH" --no-commit --no-ff 2>/dev/null; then
  echo "No conflicts detected."
  git merge --abort 2>/dev/null || true
else
  CONFLICT_COUNT=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')
  echo "Conflicts detected in $CONFLICT_COUNT file(s):"
  git diff --name-only --diff-filter=U 2>/dev/null
  git merge --abort 2>/dev/null || true
  echo ""
  echo "CONFLICTS_FOUND=true"
fi
```

If `CONFLICTS_FOUND=true`, use the Skill tool to invoke `/pw:resolve-conflicts` to resolve them.
If no conflicts, skip and proceed.

### 3.2 Interim Commit

Create an interim commit so `/pw:precheck` can analyze changes via `git diff BASE...HEAD`.

```bash
# Load metadata if available
if [ -f ".wtj-meta" ]; then
  source ".wtj-meta"
fi

echo "=== Creating Interim Commit ==="

git add .
if ! git diff --cached --quiet; then
  git commit -m "wip: $ARGUMENTS"
  echo "Interim commit created"
else
  echo "No new changes to commit"
fi
```

### 3.3 Run /pw:precheck

Use the Skill tool to invoke `/pw:precheck HEAD`. This runs comprehensive checks including:
- Local checks (lint, format, type check, build)
- Test verification
- Code quality & codebase consistency review
- Specification alignment check

### 3.4 Fix Issues and Re-verify

If `/pw:precheck` reports any issues:
1. Fix the reported problems
2. Stage and amend the interim commit: `git add . && git commit --amend --no-edit`
3. Re-run `/pw:precheck HEAD` via the Skill tool
4. Repeat until all precheck phases pass

---

## Phase 4: Commit & Report

### Finalize Commit

```bash
# Load metadata if available
if [ -f ".wtj-meta" ]; then
  source ".wtj-meta"
fi

CURRENT_BRANCH=$(git branch --show-current)

echo "=== Finalizing Commit ==="

# Stage any remaining changes
git add .
if ! git diff --cached --quiet; then
  git commit --amend --no-edit
fi

# Determine commit prefix from branch name
COMMIT_PREFIX="feat"
if echo "$CURRENT_BRANCH" | grep -q "^fix/"; then
  COMMIT_PREFIX="fix"
elif echo "$CURRENT_BRANCH" | grep -q "^refactor/"; then
  COMMIT_PREFIX="refactor"
elif echo "$CURRENT_BRANCH" | grep -q "^docs/"; then
  COMMIT_PREFIX="docs"
fi

# Amend with proper commit message
COMMIT_MSG="${COMMIT_PREFIX}: $ARGUMENTS"

git commit --amend -m "${COMMIT_MSG}

Automated implementation by wt-do

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

echo ""
echo "Commit finalized: ${COMMIT_MSG}"
```

### Output Report

```markdown
# wt-do Report

## Task
[Original task message]

## Changes Made
- `path/to/file1` — [description]
- `path/to/file2` — [description]

## Verification Results
- Conflict Check: ✅ No conflicts / ✅ Resolved
- Precheck: ✅ All checks passed

## Commit
- **Branch**: [branch-name]
- **Commit**: [commit hash and message]

## Next Steps

**Push is NOT automatic.** When ready, run:

```bash
git push -u origin [branch-name]
```

**WARNING**: Review your changes before pushing!
```

---

## Error Handling

If ANY error occurs:

1. **DO NOT** attempt to fix by modifying files outside the worktree
2. **DO NOT** switch to the base branch
3. **DO NOT** push any changes
4. Document the error clearly in the output
5. Leave the worktree in its current state for manual inspection

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
