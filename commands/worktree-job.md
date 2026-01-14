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

### Verification Before Any File Operation

Before ANY file write/edit operation, verify:
```bash
WORKTREE_ROOT=$(pwd)
TARGET_FILE="[file you want to modify]"

# Ensure target is within worktree
if [[ ! "$(realpath "$TARGET_FILE")" == "$WORKTREE_ROOT"* ]]; then
  echo "ERROR: Attempting to modify file outside worktree!"
  echo "Target: $TARGET_FILE"
  echo "Worktree: $WORKTREE_ROOT"
  exit 1
fi
```

---

## Current Context

```bash
echo "=== Environment Detection ==="
echo "Current directory: $(pwd)"
echo "Git root: $(git rev-parse --show-toplevel 2>/dev/null || echo 'Not in git repo')"
```

## Phase 1: Setup Isolated Worktree

### 1.1 Detect Repository and Base Branch

```bash
echo "=== Repository Detection ==="

# Find git repository
GIT_ROOT=""
if git rev-parse --show-toplevel &>/dev/null; then
  GIT_ROOT=$(git rev-parse --show-toplevel)
else
  # Look for git repo in current or subdirectories
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

# Detect base branch
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
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
```

### 1.2 Generate Job Name and Branch

```bash
# Generate unique job identifier
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# If input contains issue number (#123), extract it
ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '#[0-9]+' | head -1 | tr -d '#')

if [ -n "$ISSUE_NUM" ]; then
  JOB_NAME="issue-${ISSUE_NUM}"
  BRANCH_NAME="feature/issue-${ISSUE_NUM}"
else
  # Generate from description (first 3-4 words, kebab-case)
  JOB_NAME=$(echo "$ARGUMENTS" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | cut -c1-40 | sed 's/-$//')
  JOB_NAME="${JOB_NAME:-job}-${TIMESTAMP}"
  BRANCH_NAME="feature/${JOB_NAME}"
fi

echo "Job name: $JOB_NAME"
echo "Branch: $BRANCH_NAME"
```

### 1.3 Create Worktree

```bash
# Create worktrees directory if not exists
WORKTREES_DIR="${GIT_ROOT}/worktrees"
mkdir -p "$WORKTREES_DIR"

WORKTREE_PATH="${WORKTREES_DIR}/${JOB_NAME}"

echo "Creating worktree at: $WORKTREE_PATH"

# Check if worktree already exists
if [ -d "$WORKTREE_PATH" ]; then
  echo "Worktree already exists, using existing one"
else
  # Create new branch and worktree
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "origin/${BASE_BRANCH}" 2>/dev/null || \
  git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "${BASE_BRANCH}"
fi

echo "Worktree created successfully"
echo ""
echo "=== IMPORTANT ==="
echo "Working directory: $WORKTREE_PATH"
echo "All operations must be within this directory"
```

### 1.4 Change to Worktree Directory

**CRITICAL**: From this point forward, ALL operations must be within the worktree.

```bash
cd "$WORKTREE_PATH"
echo "Changed to worktree: $(pwd)"
echo "Current branch: $(git branch --show-current)"

# Verify we are NOT on the base branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ]; then
  echo "ERROR: On base branch! This should never happen."
  exit 1
fi
```

---

## Phase 2: Understand Requirements

### 2.1 Fetch Issue Details (if applicable)

```bash
ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '#[0-9]+' | head -1 | tr -d '#')

if [ -n "$ISSUE_NUM" ]; then
  echo "=== Issue #${ISSUE_NUM} Details ==="
  gh issue view "$ISSUE_NUM" 2>/dev/null || echo "Could not fetch issue details"
fi
```

### 2.2 Read Project Configuration

```bash
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

### 2.3 Explore Codebase

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

### 3.1 Planning

Before writing code:
1. List all files to create or modify
2. Identify patterns to follow from existing code
3. Plan minimal, focused changes
4. Consider edge cases and error handling

### 3.2 Implementation Guidelines

- **Follow existing code style** - match naming, formatting, idioms
- **Minimal changes** - only modify what's necessary
- **Type safety** - add type annotations where the project uses them
- **Error handling** - handle errors appropriately
- **No dead code** - don't leave commented-out code

**Apply Quality Skills**:
- Follow `/pw:code-quality` standards
- Follow `/pw:security-review` standards for sensitive code

### 3.3 Safety Check Before Each File Operation

Before EVERY file write or edit:

```bash
# Verify still in worktree
if [[ ! "$(pwd)" == *"/worktrees/"* ]]; then
  echo "ERROR: Not in worktree directory!"
  exit 1
fi
```

---

## Phase 4: Verification

### 4.1 Run Project Checks

```bash
echo "=== Running Verification ==="

# Lint/Format
if [ -f "Makefile" ]; then
  grep -q "^lint:" Makefile && make lint
  grep -q "^format:" Makefile && make format
  grep -q "^typecheck:" Makefile && make typecheck
fi

if [ -f "package.json" ]; then
  grep -q '"lint"' package.json && npm run lint 2>/dev/null
  grep -q '"typecheck"' package.json && npm run typecheck 2>/dev/null
  grep -q '"build"' package.json && npm run build 2>/dev/null
fi

if [ -f "pyproject.toml" ]; then
  command -v ruff &>/dev/null && ruff check . 2>/dev/null
  uv run mypy . 2>/dev/null || mypy . 2>/dev/null || true
fi
```

### 4.2 Run Tests

```bash
echo "=== Running Tests ==="

if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  make test
elif [ -f "package.json" ] && grep -q '"test"' package.json; then
  npm test 2>/dev/null
elif [ -f "pyproject.toml" ] || [ -d "tests" ]; then
  uv run pytest 2>/dev/null || pytest 2>/dev/null || true
elif [ -f "Cargo.toml" ]; then
  cargo test
elif [ -f "go.mod" ]; then
  go test ./...
fi
```

### 4.3 Fix Any Issues

If checks or tests fail:
1. Analyze the error output
2. Fix the issues
3. Re-run verification
4. Repeat until all checks pass

---

## Phase 5: Commit and Push

### 5.1 Final Safety Verification

```bash
echo "=== Final Safety Check ==="
echo "Current directory: $(pwd)"
echo "Current branch: $(git branch --show-current)"

# Verify NOT on base branch
CURRENT_BRANCH=$(git branch --show-current)
BASE_BRANCH="${BASE_BRANCH:-main}"

if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ] || [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "FATAL ERROR: On protected branch! Aborting."
  exit 1
fi

# Show what will be committed
echo ""
echo "=== Files to be committed ==="
git status --short
```

### 5.2 Create Commit

```bash
git add .

# Generate commit message
ISSUE_REF=""
ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
if [ -n "$ISSUE_NUM" ]; then
  ISSUE_REF="Refs #${ISSUE_NUM}"
fi

git commit -m "$(cat <<'EOF'
feat: [Brief description of changes]

[Detailed description]

- [Change 1]
- [Change 2]

$ISSUE_REF

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### 5.3 Push Branch

```bash
BRANCH=$(git branch --show-current)
git push -u origin "$BRANCH"
```

---

## Phase 6: Create Pull Request

```bash
ISSUE_NUM=$(echo "$ARGUMENTS" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
ISSUE_REF=""
CLOSES_LINE=""

if [ -n "$ISSUE_NUM" ]; then
  ISSUE_REF="Refs #${ISSUE_NUM}"
  CLOSES_LINE="Closes #${ISSUE_NUM}"
fi

gh pr create --title "feat: [Brief description]" --body "$(cat <<EOF
## Summary

[Description of what this PR accomplishes]

## Changes

- [Change 1]
- [Change 2]
- [Change 3]

## Testing

- [ ] All existing tests pass
- [ ] New functionality tested
- [ ] Edge cases considered

## Related Issues

${CLOSES_LINE:-N/A}

---

🤖 Generated autonomously with [Claude Code](https://claude.com/claude-code)

**Worktree Job**: This PR was created in an isolated worktree environment.
EOF
)"
```

---

## Output Report

```markdown
# Worktree Job Report

## Job Information
- **Job Name**: [job-name]
- **Branch**: [branch-name]
- **Worktree Path**: [path]
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

## Worktree Location
The worktree remains at: `worktrees/[job-name]/`

To clean up after PR is merged:
```bash
git worktree remove worktrees/[job-name]
git branch -d [branch-name]
```

## Notes
[Any additional notes, decisions made, or issues encountered]
```

---

## Error Handling

If ANY error occurs:

1. **DO NOT** attempt to fix by modifying files outside worktree
2. **DO NOT** switch to base branch
3. Document the error clearly in the output
4. Leave the worktree in its current state for manual inspection
5. Report what was attempted and what failed

```bash
# On error, show diagnostic info
echo "=== Error Diagnostic ==="
echo "Working directory: $(pwd)"
echo "Branch: $(git branch --show-current)"
echo "Git status:"
git status --short
echo ""
echo "Recent commits:"
git log --oneline -5
```
