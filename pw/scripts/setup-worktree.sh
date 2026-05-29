#!/usr/bin/env bash
# ==============================================================================
# Shared worktree setup for the pw plugin.
#
# Creates an isolated git worktree with a new branch, performs safety checks,
# and saves metadata to .wtj-meta for subsequent phases.
#
# Used by: at-j.md, wt-j.md
#
# Usage:
#   setup-worktree.sh <arguments> [label]
#
# Arguments:
#   $1  Raw arguments string (task description, #issue, @file, --feature/--fix)
#   $2  Optional label for log messages (default: "Worktree Job")
#
# Output:
#   Creates worktree at worktrees/<job-name>/ and writes .wtj-meta metadata file.
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect-base-branch.sh"

RAW_ARGS="${1:-}"
LABEL="${2:-Worktree Job}"

echo "=== ${LABEL} Setup ==="

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

BASE_BRANCH=$(get_base_branch "$GIT_ROOT")

echo "Base branch: $BASE_BRANCH"

# Ensure base branch is up to date
git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true

# ============================================
# 3. Generate Job Name and Branch
# ============================================
echo ""
echo "--- Job Configuration ---"

INPUT_ARGS="$RAW_ARGS"

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
  JOB_NAME=$(echo "$INPUT_ARGS" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cs '[:alnum:]' '-' | cut -c1-40 | sed 's/^-//;s/-$//')
  JOB_NAME="${JOB_NAME:-job-$(date +%Y%m%d-%H%M%S)}"
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
