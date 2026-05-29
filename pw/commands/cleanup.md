---
allowed-tools: Bash
argument-hint: '[branch1] [branch2] ... [--keep-branches] [--dry-run]'
description: Clean up parallel worker environments after all PRs are merged
---

# Cleanup Parallel Environments

## Branches to Clean
$ARGUMENTS

## Plugin Location

Locate the parallel-workflow plugin scripts:
```bash
# Find plugin directory (check common locations)
PLUGIN_DIR=""
for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin "$HOME"/.claude/plugins/cache/claude-parallel-dev-plugin/pw/*; do
  [ -d "$_d/scripts" ] && PLUGIN_DIR="$_d" && break
done 2>/dev/null
[ -n "${PW_PLUGIN_DIR:-}" ] && PLUGIN_DIR="$PW_PLUGIN_DIR"
if [ -z "$PLUGIN_DIR" ]; then
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

## Pre-cleanup Merge Verification, Teardown, and Branch Deletion

**CRITICAL**: NEVER delete a branch or worktree whose branch has NOT been merged.

This uses the same multi-method verification as `/pw:wt-clean`:
- Method 1: GitHub API (most reliable, handles squash/rebase merges)
- Method 2: `git branch --merged` (local + remote)
- Principle: **When in doubt, REFUSE to delete**

All verification, teardown, and branch deletion are executed in a single block
to ensure variable state (MERGED_BRANCHES, BLOCKED_BRANCHES) is preserved.

Before any deletion decision, the block also fast-forwards the local default
branch to `origin/<base>` so the user can verify merges with `git log` after
the command finishes.

```bash
#!/bin/bash
set -e

echo "=== Pre-cleanup Sync: $BASE_BRANCH with origin ==="

# Fetch from origin (surface real errors — do not silently swallow)
if ! git fetch origin "${BASE_BRANCH:-main}" --prune --quiet; then
  echo "WARNING: git fetch origin ${BASE_BRANCH:-main} failed."
  echo "  Continuing, but local state may be stale."
  echo "  Merge verification will still use 'gh pr' as the authoritative source."
fi

# Fast-forward local <base> to origin/<base> BEFORE deletion decisions,
# so `git log <base>` after this command shows the merged PR.
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [ "$CURRENT_BRANCH" = "${BASE_BRANCH:-main}" ]; then
  # On base branch: advance working tree.
  if git pull --ff-only origin "${BASE_BRANCH:-main}" --quiet; then
    echo "Local ${BASE_BRANCH:-main} fast-forwarded to origin/${BASE_BRANCH:-main}"
  else
    echo "WARNING: Local ${BASE_BRANCH:-main} could not be fast-forwarded (diverged?)."
    echo "  Continuing; 'gh pr' will still drive merge verification."
  fi
else
  # On any other branch: update local ref without checkout (worktree-safe).
  if git fetch origin "${BASE_BRANCH:-main}:${BASE_BRANCH:-main}" --quiet; then
    echo "Local ${BASE_BRANCH:-main} ref fast-forwarded to origin/${BASE_BRANCH:-main}"
  else
    echo "WARNING: Local ${BASE_BRANCH:-main} ref could not be fast-forwarded (diverged?)."
    echo "  Continuing; 'gh pr' will still drive merge verification."
  fi
fi

echo ""
echo "=== Pre-cleanup Merge Verification ==="

# Parse arguments: extract branch names and flags
BRANCHES=()
CLEANUP_FLAGS=""
USER_KEEP_BRANCHES=false
for arg in $ARGUMENTS; do
  case "$arg" in
    --keep-branches) USER_KEEP_BRANCHES=true ;;
    --dry-run) CLEANUP_FLAGS="$CLEANUP_FLAGS --dry-run" ;;
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

# Source canonical merge verification (single source of truth: scripts/merge-check.sh)
source "${PLUGIN_DIR}/scripts/merge-check.sh"

# ============================================================
# Phase 1: Verify merge status for all branches
# ============================================================
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

if [ ${#MERGED_BRANCHES[@]} -eq 0 ]; then
  echo ""
  echo "No merged branches to clean up."
  exit 0
fi

# ============================================================
# Phase 2: Call teardown.sh for worktrees and sessions only
# ============================================================
echo ""
echo "=== Cleaning Up Merged Branches ==="
echo "Passing to teardown.sh: ${MERGED_BRANCHES[*]}"
echo ""

# Always pass --keep-branches (we handle branch deletion ourselves)
# Also pass --skip-merge-check since we already verified
# Pass user's --dry-run if specified
"${PLUGIN_DIR}/scripts/teardown.sh" --keep-branches --skip-merge-check ${CLEANUP_FLAGS} "${MERGED_BRANCHES[@]}"

# ============================================================
# Phase 3: Delete verified-merged branches (unless --keep-branches)
# ============================================================
if [ "$USER_KEEP_BRANCHES" = true ]; then
  echo ""
  echo "=== Skipping branch deletion (--keep-branches) ==="
else
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
fi

echo ""
echo "=== Cleanup Complete ==="
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
1. Base branch is already synced with origin (done automatically by the pre-cleanup block).
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
