---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: [#issue-number or "task description"]
description: Create isolated worktree and autonomously implement task until PR creation
model: opus
---

# Worktree Job - Autonomous Isolated Development

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
   - Worktree cleanup is handled by `/pw:cleanup-job`
   - Only cleanup-job can delete worktrees, and only after merge verification

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

BASE_BRANCH=""
if [ -f "CLAUDE.md" ]; then
  BASE_BRANCH=$(grep -i "base.branch\|default.branch\|primary.branch" CLAUDE.md | head -1 | grep -oE "(main|master|develop|dev)" || echo "")
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

TIMESTAMP=$(date +%Y%m%d-%H%M%S-%N | cut -c1-20)
INPUT_ARGS="$ARGUMENTS"

# Extract issue number if present
ISSUE_NUM=$(echo "$INPUT_ARGS" | grep -oE '#[0-9]+' | head -1 | tr -d '#')

if [ -n "$ISSUE_NUM" ]; then
  JOB_NAME="issue-${ISSUE_NUM}"
  BRANCH_NAME="feature/issue-${ISSUE_NUM}"
else
  # Generate from description (kebab-case, max 30 chars)
  JOB_NAME=$(echo "$INPUT_ARGS" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | cut -c1-30 | sed 's/^-//;s/-$//')
  JOB_NAME="${JOB_NAME:-job}-${TIMESTAMP}"
  BRANCH_NAME="feature/${JOB_NAME}"
fi

echo "Job name: $JOB_NAME"
echo "Branch: $BRANCH_NAME"

# ============================================
# 4. Create Worktree
# ============================================
echo ""
echo "--- Worktree Creation ---"

WORKTREES_DIR="${GIT_ROOT}/worktrees"
mkdir -p "$WORKTREES_DIR"

WORKTREE_PATH="${WORKTREES_DIR}/${JOB_NAME}"

echo "Worktree path: $WORKTREE_PATH"

# Handle existing worktree or branch
if [ -d "$WORKTREE_PATH" ]; then
  echo "Worktree already exists at $WORKTREE_PATH"
  echo "Using existing worktree"
elif git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
  # Branch exists but worktree doesn't - reuse branch
  echo "Branch $BRANCH_NAME exists, creating worktree for it"
  git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
else
  # Fresh start - create new branch and worktree
  echo "Creating new branch and worktree"
  if git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "origin/${BASE_BRANCH}" 2>/dev/null; then
    echo "Created from origin/${BASE_BRANCH}"
  else
    git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "${BASE_BRANCH}"
    echo "Created from ${BASE_BRANCH}"
  fi
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

echo ""
echo "=== Setup Complete ==="
echo ""
echo "IMPORTANT REMINDERS:"
echo "  - All work must be done in: $WORKTREE_PATH"
echo "  - Never modify files outside this directory"
echo "  - Never switch to $BASE_BRANCH"
echo "  - Cleanup after merge: /pw:cleanup-job $JOB_NAME"
echo ""
echo "Environment variables for this session:"
echo "  WORKTREE_PATH=$WORKTREE_PATH"
echo "  BRANCH_NAME=$BRANCH_NAME"
echo "  BASE_BRANCH=$BASE_BRANCH"
echo "  JOB_NAME=$JOB_NAME"
```

---

## Phase 2: Understand Requirements

### Fetch Issue Details (if applicable)

```bash
cd "$WORKTREE_PATH" 2>/dev/null || cd worktrees/*/

ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '#[0-9]+' | head -1 | tr -d '#')

if [ -n "$ISSUE_NUM" ]; then
  echo "=== Issue #${ISSUE_NUM} Details ==="
  gh issue view "$ISSUE_NUM" 2>/dev/null || echo "Could not fetch issue details"
fi
```

### Read Project Configuration

```bash
cd "$WORKTREE_PATH" 2>/dev/null || cd worktrees/*/

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

## Phase 4: Verification

### Run Project Checks

```bash
cd "$WORKTREE_PATH" 2>/dev/null || cd worktrees/*/

echo "=== Running Verification ==="

# Track status
CHECKS_PASSED=true

# Lint/Format/TypeCheck
if [ -f "Makefile" ]; then
  echo "--- Makefile checks ---"
  grep -q "^lint:" Makefile && { make lint || CHECKS_PASSED=false; }
  grep -q "^format:" Makefile && { make format || true; }
  grep -q "^typecheck:" Makefile && { make typecheck || CHECKS_PASSED=false; }
fi

if [ -f "package.json" ]; then
  echo "--- Node.js checks ---"
  grep -q '"lint"' package.json && { npm run lint 2>/dev/null || CHECKS_PASSED=false; }
  grep -q '"typecheck"' package.json && { npm run typecheck 2>/dev/null || CHECKS_PASSED=false; }
  grep -q '"build"' package.json && { npm run build 2>/dev/null || CHECKS_PASSED=false; }
fi

if [ -f "pyproject.toml" ]; then
  echo "--- Python checks ---"
  command -v ruff &>/dev/null && { ruff check . 2>/dev/null || CHECKS_PASSED=false; }
  { uv run mypy . 2>/dev/null || mypy . 2>/dev/null || true; }
fi

if [ -f "Cargo.toml" ]; then
  echo "--- Rust checks ---"
  cargo check || CHECKS_PASSED=false
  cargo clippy -- -D warnings 2>/dev/null || CHECKS_PASSED=false
fi

if [ -f "go.mod" ]; then
  echo "--- Go checks ---"
  go vet ./... || CHECKS_PASSED=false
fi

echo ""
if [ "$CHECKS_PASSED" = true ]; then
  echo "All checks passed"
else
  echo "Some checks failed - please fix before continuing"
fi
```

### Run Tests

```bash
cd "$WORKTREE_PATH" 2>/dev/null || cd worktrees/*/

echo "=== Running Tests ==="

if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  make test
elif [ -f "package.json" ] && grep -q '"test"' package.json; then
  npm test 2>/dev/null || true
elif [ -f "pyproject.toml" ] || [ -d "tests" ]; then
  uv run pytest 2>/dev/null || pytest 2>/dev/null || true
elif [ -f "Cargo.toml" ]; then
  cargo test
elif [ -f "go.mod" ]; then
  go test ./...
else
  echo "No test framework detected"
fi
```

### Fix Any Issues

If checks or tests fail:
1. Analyze the error output
2. Fix the issues
3. Re-run verification
4. Repeat until all checks pass

---

## Phase 5: Commit and Push

### Final Safety Verification and Commit

```bash
cd "$WORKTREE_PATH" 2>/dev/null || cd worktrees/*/

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
echo "=== Files to be committed ==="
git status --short

echo ""
echo "=== Creating commit ==="
git add .

# Check if there are changes to commit
if git diff --cached --quiet; then
  echo "No changes to commit"
else
  git commit -m "feat: implement task

Automated implementation by worktree-job

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

  echo "Commit created"
fi

echo ""
echo "=== Pushing branch ==="
git push -u origin "$CURRENT_BRANCH"

echo ""
echo "Branch pushed successfully"
```

---

## Phase 6: Create Pull Request

```bash
cd "$WORKTREE_PATH" 2>/dev/null || cd worktrees/*/

ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '#[0-9]+' | head -1 | tr -d '#')

CLOSES_LINE=""
if [ -n "$ISSUE_NUM" ]; then
  CLOSES_LINE="Closes #${ISSUE_NUM}"
fi

echo "=== Creating Pull Request ==="

gh pr create --title "feat: implement task" --body "## Summary

Automated implementation by worktree-job.

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

To clean up after merge: \`/pw:cleanup-job $(basename $(pwd))\`
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
/pw:cleanup-job [job-name]
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
