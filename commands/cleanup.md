---
allowed-tools: Bash
argument-hint: [branch1] [branch2] ... [--keep-branches] [--dry-run]
description: Clean up parallel worker environments after all PRs are merged
model: haiku
---

# Cleanup Parallel Environments

## Branches to Clean
$ARGUMENTS

## Plugin Location

Locate the parallel-workflow plugin scripts:
```bash
# Find plugin directory (check common locations)
if [ -d ".claude-paralell-dev-plugin/scripts" ]; then
  PLUGIN_DIR=".claude-paralell-dev-plugin"
elif [ -d "../.claude-paralell-dev-plugin/scripts" ]; then
  PLUGIN_DIR="../.claude-paralell-dev-plugin"
elif [ -n "$PW_PLUGIN_DIR" ]; then
  PLUGIN_DIR="$PW_PLUGIN_DIR"
else
  echo "Error: parallel-workflow plugin not found"
  echo "Set PW_PLUGIN_DIR environment variable or place plugin in .claude-paralell-dev-plugin/"
  exit 1
fi
```

## Git Repository Detection

The scripts automatically detect the git repository:
1. If running inside a git repository, use it
2. If running from a parent directory, detect git repo in subdirectories
3. If multiple repos found, specify with `GIT_REPO` environment variable

Worktrees are located inside the repository's `worktrees/` directory (consistent with `/pw:wt-j`):
```
/workspace/
└── my-project/              ← Git repo
    └── worktrees/           ← Worktrees directory
        ├── feature-auth/    ← worktree (to be cleaned)
        └── feature-api/     ← worktree (to be cleaned)
```

## Base Branch Detection

```bash
# Base branch detection (using shared script)
BASE_BRANCH=$("${PLUGIN_DIR}/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
echo "Base branch: $BASE_BRANCH"
```

## Pre-cleanup Merge Verification (BLOCKING)

**CRITICAL**: NEVER delete a branch or worktree whose branch has NOT been merged.

This uses the same multi-method verification as `/pw:wt-clean`:
- Method 1: GitHub API (most reliable, handles squash/rebase merges)
- Method 2: `git branch --merged` (local + remote)
- Principle: **When in doubt, REFUSE to delete**

```bash
#!/bin/bash
set -e

echo "=== Pre-cleanup Merge Verification ==="

# Ensure base branch is up to date
git fetch origin "${BASE_BRANCH:-main}" --quiet 2>/dev/null || true

# Parse arguments: extract branch names and flags
BRANCHES=()
CLEANUP_FLAGS=""
for arg in $ARGUMENTS; do
  case "$arg" in
    --keep-branches|--dry-run) CLEANUP_FLAGS="$CLEANUP_FLAGS $arg" ;;
    *) BRANCHES+=("$arg") ;;
  esac
done

if [ ${#BRANCHES[@]} -eq 0 ]; then
  echo "ERROR: No branches specified."
  echo "Usage: /pw:cleanup branch1 branch2 ... [--keep-branches] [--dry-run]"
  exit 1
fi

echo "Branches to verify: ${BRANCHES[*]}"
echo "Base branch: ${BASE_BRANCH:-main}"
echo ""

# Detect GitHub CLI availability
GH_AVAILABLE=false
if command -v gh &>/dev/null && git remote get-url origin &>/dev/null; then
  GH_AVAILABLE=true
fi

# ============================================================
# SAFETY-CRITICAL FUNCTION: check if branch is merged
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
    if git branch --merged "$base" 2>/dev/null | grep -q "^\s*$branch\$"; then
      verified_by="git branch --merged $base"
      echo "  Merge verified by: $verified_by"
      return 0  # CONFIRMED merged
    fi

    # Check if branch is merged into remote base
    if git branch --merged "origin/$base" 2>/dev/null | grep -q "^\s*$branch\$"; then
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
    echo "  Branch not found locally AND no merged PR found on GitHub"
    echo "  → REFUSING to confirm merge (no positive proof)"
    return 1  # SAFE: treat as not merged
  else
    echo "  Branch not found locally AND gh CLI unavailable for verification"
    echo "  → REFUSING to confirm merge (cannot verify)"
    return 1  # SAFE: treat as not merged
  fi
}

# Track results
MERGED_BRANCHES=()
BLOCKED_BRANCHES=()

echo "=== Verifying Merge Status ==="
echo ""

for branch in "${BRANCHES[@]}"; do
  echo "--- $branch ---"

  if is_branch_merged "$branch" "${BASE_BRANCH:-main}"; then
    echo "  Status: MERGED"
    MERGED_BRANCHES+=("$branch")
  else
    echo "  Status: NOT MERGED"
    echo ""
    echo "  *** BLOCKED: Branch '$branch' has NOT been merged! ***"
    echo "  *** Cannot clean up this branch. ***"
    echo ""
    echo "  To resolve:"
    echo "    1. Merge the PR: /pw:merge <pr-number>"
    echo "    2. Or abandon: git branch -D $branch"
    echo ""
    BLOCKED_BRANCHES+=("$branch")
  fi
done

echo ""
echo "=== Verification Summary ==="
echo "Merged (safe to clean):  ${#MERGED_BRANCHES[@]}"
echo "Blocked (NOT merged):    ${#BLOCKED_BRANCHES[@]}"

# Report blocked branches
if [ ${#BLOCKED_BRANCHES[@]} -gt 0 ]; then
  echo ""
  echo "*** BLOCKED BRANCHES ***"
  for b in "${BLOCKED_BRANCHES[@]}"; do
    echo "  - $b"
  done
  echo ""
  echo "These branches will NOT be cleaned up."
  echo "Merge them first, then re-run cleanup."
fi

# If nothing is safe to clean, exit
if [ ${#MERGED_BRANCHES[@]} -eq 0 ]; then
  echo ""
  echo "No merged branches to clean up."
  exit 0
fi
```

## Cleanup Execution (Merged Branches Only)

### Using teardown.sh

Only pass **confirmed-merged** branches to teardown.sh. Use `--keep-branches` so teardown.sh
only handles worktrees and sessions; branch deletion is handled here after verification.

```bash
echo ""
echo "=== Cleaning Up Merged Branches ==="
echo "Passing to teardown.sh: ${MERGED_BRANCHES[*]}"
echo ""

# Call teardown with --keep-branches (we handle branch deletion ourselves)
# Also pass --skip-merge-check since we already verified
"${PLUGIN_DIR}/scripts/teardown.sh" --keep-branches --skip-merge-check ${CLEANUP_FLAGS} "${MERGED_BRANCHES[@]}"
```

### Delete Verified-Merged Branches

```bash
echo ""
echo "=== Deleting Verified-Merged Branches ==="

for branch in "${MERGED_BRANCHES[@]}"; do
  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    # Use -d (safe delete) — only deletes if fully merged
    if git branch -d "$branch" 2>/dev/null; then
      echo "  Deleted local branch: $branch"
    else
      echo "  WARNING: git branch -d failed for $branch (git does not consider it merged)"
      echo "  Keeping branch for safety. Force delete with: git branch -D $branch"
    fi
  else
    echo "  Local branch already gone: $branch"
  fi
done
```

### Options

| Option | Effect |
|--------|--------|
| `--keep-branches` | Keep local branches, only remove worktrees and sessions |
| `--dry-run` | Show what would be done without executing |

## Current State

```bash
echo ""
echo "=== Active Sessions ==="
tmux list-sessions 2>/dev/null || echo "No tmux sessions"

echo ""
echo "=== Git Worktrees ==="
git worktree list 2>/dev/null || echo "Not in git repo"
```

## Post-cleanup

After cleanup:
1. Update base branch: `git checkout ${BASE_BRANCH} && git pull`
2. Ready for next task: `/pw:design [new-task]`

## Output Format

```markdown
# Cleanup Report

## Merge Verification
| Branch | Verified By | Status |
|--------|-------------|--------|
| feature/branch1 | GitHub PR (state=MERGED) | MERGED |
| feature/branch2 | git branch --merged main | MERGED |
| feature/branch3 | — | NOT MERGED (BLOCKED) |

## Sessions Terminated
- [session1]
- [session2]

## Worktrees Removed
- /path/to/wt-branch1
- /path/to/wt-branch2

## Branches Deleted
- feature/branch1 (verified merged)
- feature/branch2 (verified merged)

## Blocked (NOT Merged)
- feature/branch3 — Must merge PR first

## Status
Cleanup completed for merged branches.

## Verify
```bash
tmux list-sessions      # Should not show cleaned sessions
git worktree list       # Should not show cleaned worktrees
git branch              # Should not show cleaned branches
```
```

## Troubleshooting

### CRITICAL: Human Confirmation Required

**NEVER execute force commands without explicit human approval!**

These commands are destructive and irreversible. Always ask the user to confirm before running:

### Cleanup Failed

If cleanup fails, present these options to the user and **wait for explicit confirmation**:

```markdown
**Manual intervention required**

The following commands may be needed. Please confirm which to execute:

1. Force remove stuck worktree:
   `git worktree remove --force /path/to/worktree`

2. Force kill tmux session:
   `tmux kill-session -t session-name`

3. Force delete branch:
   `git branch -D branch-name`

Reply with the number(s) to execute, or "skip" to abort.
```

### Orphaned Worktree Entry

```bash
# Prune stale worktree entries
git worktree prune
```
