---
allowed-tools: Bash
argument-hint: [job-name or --all]
description: Clean up wt-j environments after PRs are merged
model: haiku
---

# Cleanup Worktree Job

Clean up worktree environments created by `/pw:wt-j`.

## Input
$ARGUMENTS

## CRITICAL SAFETY RULES

### ABSOLUTE PROHIBITION

**NEVER delete a worktree whose branch has NOT been merged to the base branch.**

- Always verify merge status before deletion using MULTIPLE methods
- If merge status CANNOT be confirmed with certainty, treat as NOT MERGED
- If not merged, show alert and ABORT
- User must explicitly merge or abandon the PR first
- **NEVER assume "branch not found" means "merged"** — always verify via GitHub API
- **NEVER guess branch names** — if branch name cannot be determined, treat as NOT MERGED
- **Principle: When in doubt, REFUSE to delete**

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
UNKNOWN_JOBS=()
CLEANED_JOBS=()
FAILED_JOBS=()

# Detect GitHub remote for gh CLI
GITHUB_REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
GH_AVAILABLE=false
if command -v gh &>/dev/null && [ -n "$GITHUB_REMOTE_URL" ]; then
  GH_AVAILABLE=true
fi

# ============================================================
# SAFETY-CRITICAL FUNCTION: check if branch is merged
# (canonical: scripts/merge-check.sh)
#
# Principle: NEVER return "merged" unless we have POSITIVE PROOF.
# When in doubt, return "not merged" (safe side).
#
# Verification methods (in order):
#   1. gh pr — check GitHub PR state (most reliable, handles squash merge)
#   2. git branch --merged — check local git merge status
#   3. If all methods are inconclusive → return NOT MERGED
# ============================================================
is_branch_merged() {
  local branch="$1"
  local base="$2"
  local verified_by=""

  # --- Method 1: Check via GitHub PR (most reliable) ---
  # This correctly handles squash merges, rebase merges, etc.
  if [ "$GH_AVAILABLE" = true ]; then
    local pr_state=""
    pr_state=$(gh pr list --head "$branch" --state merged --json number,state --jq '.[0].state' 2>/dev/null || echo "")
    if [ "$pr_state" = "MERGED" ]; then
      verified_by="GitHub PR (state=MERGED)"
      echo "  Merge verified by: $verified_by"
      return 0  # CONFIRMED merged
    fi

    # Also check if PR is still open (definitively NOT merged)
    local pr_open=""
    pr_open=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null || echo "")
    if [ -n "$pr_open" ]; then
      echo "  PR #$pr_open is still OPEN — NOT merged"
      return 1  # Definitively not merged
    fi
  fi

  # --- Method 2: Check local git merge status ---
  # Only works for non-squash merges; requires branch to exist locally
  local branch_exists=false
  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    branch_exists=true
  fi

  if [ "$branch_exists" = true ]; then
    # Check if branch is merged into local base
    if git branch --merged "$base" 2>/dev/null | grep -qx "[ *]*$branch"; then
      verified_by="git branch --merged $base"
      echo "  Merge verified by: $verified_by"
      return 0  # CONFIRMED merged
    fi

    # Check if branch is merged into remote base
    if git branch --merged "origin/$base" 2>/dev/null | grep -qx "[ *]*$branch"; then
      verified_by="git branch --merged origin/$base"
      echo "  Merge verified by: $verified_by"
      return 0  # CONFIRMED merged
    fi

    # Branch exists but not merged into base
    echo "  Branch exists locally but is NOT merged into $base"
    return 1  # NOT merged
  fi

  # --- Branch does not exist locally ---
  # CRITICAL: Do NOT assume "branch gone = merged".
  # The branch could have been deleted without merging, or the name could be wrong.
  # Without positive proof from GitHub PR, we REFUSE to confirm merge.
  if [ "$GH_AVAILABLE" = true ]; then
    # gh was available but found no merged PR → not confirmed
    echo "  Branch not found locally AND no merged PR found on GitHub"
    echo "  → REFUSING to confirm merge (no positive proof)"
    return 1  # SAFE: treat as not merged
  else
    # gh is not available, cannot verify remotely
    echo "  Branch not found locally AND gh CLI unavailable for verification"
    echo "  → REFUSING to confirm merge (cannot verify)"
    return 1  # SAFE: treat as not merged
  fi
}

# ============================================================
# SAFETY-CRITICAL FUNCTION: resolve branch name
#
# Returns branch name via echo. Returns empty string if unknown.
# NEVER guesses or fabricates branch names.
# ============================================================
resolve_branch_name() {
  local job_dir="$1"
  local job_name="$2"
  local result=""

  # Method 1: Read from .wtj-meta metadata file (most reliable)
  if [ -f "$job_dir/.wtj-meta" ]; then
    result=$(grep "^BRANCH_NAME=" "$job_dir/.wtj-meta" | cut -d'"' -f2)
    if [ -n "$result" ]; then
      echo "$result"
      return 0
    fi
  fi

  # Method 2: Get from git worktree directly
  if [ -d "$job_dir/.git" ] || [ -f "$job_dir/.git" ]; then
    result=$(git -C "$job_dir" branch --show-current 2>/dev/null || echo "")
    if [ -n "$result" ]; then
      echo "$result"
      return 0
    fi
  fi

  # Method 3: Check git worktree list for this path
  local abs_job_dir=""
  abs_job_dir=$(cd "$job_dir" 2>/dev/null && pwd || echo "$job_dir")
  result=$(git worktree list --porcelain 2>/dev/null | grep -A2 "^worktree $abs_job_dir\$" | grep "^branch " | sed 's|^branch refs/heads/||')
  if [ -n "$result" ]; then
    echo "$result"
    return 0
  fi

  # Method 4: Infer from job name — but ONLY if the branch actually exists
  for prefix in feature fix; do
    local test_branch="${prefix}/${job_name}"
    if git show-ref --verify --quiet "refs/heads/$test_branch" 2>/dev/null; then
      echo "$test_branch"
      return 0
    fi
  done

  # SAFETY: Do NOT guess. Return empty to signal "unknown".
  echo ""
  return 1
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

  # Resolve branch name — NEVER guess
  branch_name=$(resolve_branch_name "$job_dir" "$job_name")

  if [ -z "$branch_name" ]; then
    echo "Branch: UNKNOWN (could not determine)"
    echo ""
    echo "  *** SAFETY BLOCK: Cannot determine branch name for '$job_name' ***"
    echo "  *** Treating as NOT MERGED (safe default) ***"
    echo ""
    echo "  To resolve:"
    echo "    1. Check the worktree manually: git -C $job_dir branch"
    echo "    2. Or remove manually if no longer needed:"
    echo "       git worktree remove $job_dir"
    echo ""
    UNKNOWN_JOBS+=("$job_name:UNKNOWN")
    continue
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
    echo "    2. Or abandon: git branch -D $branch_name && /pw:wt-clean $job_name"
    echo ""
    UNMERGED_JOBS+=("$job_name:$branch_name")
  fi
done

echo ""
echo "=== Summary ==="
echo "Merged (safe to delete): ${#MERGED_JOBS[@]}"
echo "Not merged (BLOCKED):    ${#UNMERGED_JOBS[@]}"
echo "Unknown (BLOCKED):       ${#UNKNOWN_JOBS[@]}"

BLOCKED_COUNT=$(( ${#UNMERGED_JOBS[@]} + ${#UNKNOWN_JOBS[@]} ))

# If there are unmerged or unknown jobs, report them
if [ $BLOCKED_COUNT -gt 0 ]; then
  echo ""
  echo "*** BLOCKED WORKTREES ***"
  echo ""

  if [ ${#UNMERGED_JOBS[@]} -gt 0 ]; then
    echo "Not merged:"
    for item in "${UNMERGED_JOBS[@]}"; do
      job="${item%%:*}"
      branch="${item##*:}"
      echo "  - $job ($branch)"
    done
  fi

  if [ ${#UNKNOWN_JOBS[@]} -gt 0 ]; then
    echo "Unknown branch (cannot verify):"
    for item in "${UNKNOWN_JOBS[@]}"; do
      job="${item%%:*}"
      echo "  - $job (branch name could not be determined)"
    done
  fi

  echo ""
  echo "These worktrees will NOT be deleted."
  echo "To resolve: merge the PR first, or manually remove with 'git worktree remove <path>'."
  echo ""

  # If specific job was requested and it's blocked, exit with error
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
echo "Blocked (unknown):  ${#UNKNOWN_JOBS[@]}"
if [ ${#CLEANED_JOBS[@]} -gt 0 ]; then
  echo "Default branch: $BASE_BRANCH (updated)"
fi
```

---

## Output Format

```markdown
# Cleanup Job Report

## Scanned Worktrees
| Job Name | Branch | Merge Verified By | Status |
|----------|--------|-------------------|--------|
| issue-123 | feature/issue-123 | GitHub PR (state=MERGED) | MERGED |
| add-feature | feature/add-feature | — | NOT MERGED |
| old-task | UNKNOWN | — | BLOCKED (unknown branch) |

## Cleanup Results

### Cleaned
- `issue-123` - Worktree and branch removed

### Blocked (Not Merged)
- `add-feature` - Branch not merged, cleanup blocked

### Blocked (Unknown Branch)
- `old-task` - Branch name could not be determined, cleanup refused

### Failed
- (none)

## Next Steps
- For not-merged items: Merge PR first with `/pw:merge <pr-number>`
- For unknown items: Check manually with `git -C worktrees/<job> branch`
- Verify cleanup: `git worktree list`
```

---

## Usage Examples

```bash
# Clean up a specific job
/pw:wt-clean issue-123

# Clean up all merged wt-j
/pw:wt-clean --all

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
/pw:wt-clean <job-name>
```
