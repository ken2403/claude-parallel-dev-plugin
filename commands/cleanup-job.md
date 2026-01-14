---
allowed-tools: Bash
argument-hint: [job-name or --all]
description: Clean up worktree-job environments after PRs are merged
model: haiku
---

# Cleanup Worktree Job

Clean up worktree environments created by `/pw:worktree-job`.

## Input
$ARGUMENTS

## CRITICAL SAFETY RULES

### ABSOLUTE PROHIBITION

**NEVER delete a worktree whose branch has NOT been merged to the base branch.**

- Always verify merge status before deletion
- If not merged, show alert and ABORT
- User must explicitly merge or abandon the PR first

---

## Cleanup Process

```bash
#!/bin/bash
set -e

echo "=== Worktree Job Cleanup ==="

# Detect git repository
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

cd "$GIT_ROOT"
echo "Repository: $GIT_ROOT"

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

# Fetch latest from remote
git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true

WORKTREES_DIR="${GIT_ROOT}/worktrees"

if [ ! -d "$WORKTREES_DIR" ]; then
  echo "No worktrees directory found at: $WORKTREES_DIR"
  echo "Nothing to clean up."
  exit 0
fi

# Parse arguments from $ARGUMENTS
INPUT_ARG=$(echo "$ARGUMENTS" | awk '{print $1}')
CLEANUP_ALL=false

if [ "$INPUT_ARG" = "--all" ]; then
  CLEANUP_ALL=true
fi

echo ""
echo "=== Scanning Worktrees ==="

# Track results
MERGED_JOBS=()
UNMERGED_JOBS=()
CLEANED_JOBS=()
FAILED_JOBS=()

# Function to check if branch is merged
is_branch_merged() {
  local branch="$1"
  local base="$2"

  # Check if branch exists
  if ! git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    # Branch doesn't exist locally, check if it was merged via PR
    # by checking if any commits from that branch are in base
    return 0  # Assume merged if branch is gone
  fi

  # Check if branch is merged into base
  if git branch --merged "$base" 2>/dev/null | grep -q "^\s*$branch\$"; then
    return 0  # Merged
  fi

  # Also check against remote base
  if git branch --merged "origin/$base" 2>/dev/null | grep -q "^\s*$branch\$"; then
    return 0  # Merged
  fi

  return 1  # Not merged
}

# Scan worktrees directory
for job_dir in "$WORKTREES_DIR"/*/; do
  if [ ! -d "$job_dir" ]; then
    continue
  fi

  job_name=$(basename "$job_dir")

  # Skip if specific job requested and this isn't it
  if [ "$CLEANUP_ALL" = false ] && [ -n "$INPUT_ARG" ] && [ "$job_name" != "$INPUT_ARG" ]; then
    continue
  fi

  echo ""
  echo "--- Job: $job_name ---"

  # Get branch name from worktree
  branch_name=""
  if [ -d "$job_dir/.git" ] || [ -f "$job_dir/.git" ]; then
    branch_name=$(git -C "$job_dir" branch --show-current 2>/dev/null || echo "")
  fi

  if [ -z "$branch_name" ]; then
    # Try to infer from job name
    if [[ "$job_name" == issue-* ]]; then
      branch_name="feature/$job_name"
    else
      branch_name="feature/$job_name"
    fi
  fi

  echo "Branch: $branch_name"

  # Check merge status
  if is_branch_merged "$branch_name" "$BASE_BRANCH"; then
    echo "Status: MERGED into $BASE_BRANCH"
    MERGED_JOBS+=("$job_name:$branch_name")
  else
    echo "Status: NOT MERGED"
    echo ""
    echo "  *** ALERT: Branch '$branch_name' has NOT been merged! ***"
    echo "  *** Cannot delete this worktree. ***"
    echo ""
    echo "  To resolve:"
    echo "    1. Merge the PR: /pw:merge <pr-number>"
    echo "    2. Or abandon: git branch -D $branch_name"
    echo ""
    UNMERGED_JOBS+=("$job_name:$branch_name")
  fi
done

echo ""
echo "=== Summary ==="
echo "Merged (safe to delete): ${#MERGED_JOBS[@]}"
echo "Not merged (BLOCKED): ${#UNMERGED_JOBS[@]}"

# If there are unmerged jobs and not forcing, abort
if [ ${#UNMERGED_JOBS[@]} -gt 0 ]; then
  echo ""
  echo "*** CLEANUP BLOCKED ***"
  echo ""
  echo "The following worktrees have unmerged branches:"
  for item in "${UNMERGED_JOBS[@]}"; do
    job="${item%%:*}"
    branch="${item##*:}"
    echo "  - $job ($branch)"
  done
  echo ""
  echo "Please merge or abandon these branches before cleanup."
  echo ""

  # If specific job was requested and it's unmerged, exit with error
  if [ "$CLEANUP_ALL" = false ] && [ -n "$INPUT_ARG" ] && [ "$INPUT_ARG" != "--all" ]; then
    exit 1
  fi
fi

# Clean up merged jobs
if [ ${#MERGED_JOBS[@]} -eq 0 ]; then
  echo ""
  echo "No merged worktrees to clean up."
  exit 0
fi

echo ""
echo "=== Cleaning Merged Worktrees ==="

for item in "${MERGED_JOBS[@]}"; do
  job="${item%%:*}"
  branch="${item##*:}"
  job_path="${WORKTREES_DIR}/${job}"

  echo ""
  echo "Cleaning: $job"

  # Remove worktree
  if git worktree remove "$job_path" 2>/dev/null; then
    echo "  Worktree removed"
  elif git worktree remove --force "$job_path" 2>/dev/null; then
    echo "  Worktree force removed"
  else
    echo "  Failed to remove worktree"
    FAILED_JOBS+=("$job")
    continue
  fi

  # Delete local branch if it exists
  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    if git branch -d "$branch" 2>/dev/null; then
      echo "  Local branch deleted"
    else
      echo "  Could not delete local branch (may need -D)"
    fi
  else
    echo "  Local branch already gone"
  fi

  CLEANED_JOBS+=("$job")
done

# Prune worktree references
git worktree prune 2>/dev/null || true

# Remove empty worktrees directory
if [ -d "$WORKTREES_DIR" ] && [ -z "$(ls -A "$WORKTREES_DIR")" ]; then
  rmdir "$WORKTREES_DIR"
  echo ""
  echo "Removed empty worktrees directory"
fi

# Update default branch to latest
if [ ${#CLEANED_JOBS[@]} -gt 0 ]; then
  echo ""
  echo "=== Updating Default Branch ==="

  # Switch to default branch
  CURRENT_BRANCH=$(git branch --show-current)
  if [ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]; then
    git checkout "$BASE_BRANCH" 2>/dev/null || true
  fi

  # Pull latest changes
  echo "Pulling latest $BASE_BRANCH..."
  if git pull origin "$BASE_BRANCH" --ff-only 2>/dev/null; then
    echo "Default branch updated successfully"
  else
    echo "Could not fast-forward, trying rebase..."
    git pull origin "$BASE_BRANCH" --rebase 2>/dev/null || echo "Manual update may be needed"
  fi
fi

echo ""
echo "=== Cleanup Complete ==="
echo "Cleaned: ${#CLEANED_JOBS[@]}"
echo "Failed: ${#FAILED_JOBS[@]}"
echo "Blocked (unmerged): ${#UNMERGED_JOBS[@]}"
if [ ${#CLEANED_JOBS[@]} -gt 0 ]; then
  echo "Default branch: $BASE_BRANCH (updated)"
fi
```

---

## Output Format

```markdown
# Cleanup Job Report

## Scanned Worktrees
| Job Name | Branch | Status |
|----------|--------|--------|
| issue-123 | feature/issue-123 | MERGED |
| add-feature | feature/add-feature | NOT MERGED |

## Cleanup Results

### Cleaned
- `issue-123` - Worktree and branch removed

### Blocked (Not Merged)
- `add-feature` - Branch not merged, cleanup blocked

### Failed
- (none)

## Next Steps
- For blocked items: Merge PR first with `/pw:merge <pr-number>`
- Verify cleanup: `git worktree list`
```

---

## Usage Examples

```bash
# Clean up a specific job
/pw:cleanup-job issue-123

# Clean up all merged worktree-jobs
/pw:cleanup-job --all

# Check status without cleaning (just run the scan part)
ls -la worktrees/
```

---

## Troubleshooting

### Worktree removal failed

If automatic removal fails:

```bash
# Force remove worktree
git worktree remove --force worktrees/<job-name>

# Prune stale entries
git worktree prune

# Force delete branch
git branch -D <branch-name>
```

### Branch shows as unmerged but PR is merged

Verify the PR state and force delete if needed:

```bash
# Verify PR is merged on GitHub
gh pr view <pr-number> --json state

# If merged, force delete the branch
git branch -D <branch-name>

# Then re-run cleanup
/pw:cleanup-job <job-name>
```
