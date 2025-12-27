---
allowed-tools: Bash
argument-hint: [branch1] [branch2] ... [--keep-branches] [--dry-run]
description: Clean up parallel worker environments after all PRs are merged
model: haiku
---

# Cleanup Parallel Environments

## Branches to Clean
$ARGUMENTS

## Pre-cleanup Safety Check

**CRITICAL**: Never cleanup until ALL PRs are merged!

### Verify No Open PRs
```bash
echo "=== Open PRs (MUST be empty before cleanup) ==="
OPEN_PRS=$(gh pr list --state open --json number,headRefName --jq 'length' 2>/dev/null || echo "0")
gh pr list --state open 2>/dev/null || echo "Cannot fetch PRs"

if [ "$OPEN_PRS" -gt 0 ]; then
  echo ""
  echo "⚠️  WARNING: $OPEN_PRS open PR(s) found!"
  echo "⚠️  Do NOT run cleanup until all PRs are merged."
  echo ""
  echo "To merge open PRs:"
  echo "  /pw:merge [pr-number]"
fi
```

### Current State
```bash
echo ""
echo "=== Active Sessions ==="
tmux list-sessions 2>/dev/null || echo "No tmux sessions"

echo ""
echo "=== Git Worktrees ==="
git worktree list 2>/dev/null || echo "Not in git repo"
```

## Cleanup Process

### Using existing teardown.sh

The cleanup uses the existing `teardown.sh` script:

```bash
# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run teardown with provided arguments
# $ARGUMENTS contains: branch1 branch2 ... [--keep-branches] [--dry-run]
"${SCRIPT_DIR}/teardown.sh" $ARGUMENTS
```

### Options

| Option | Effect |
|--------|--------|
| `--keep-branches` | Keep local branches, only remove worktrees and sessions |
| `--dry-run` | Show what would be done without executing |

## Cleanup Steps (performed by teardown.sh)

1. **Kill tmux sessions**
   - Find session by project name and branch
   - Terminate session

2. **Remove worktrees**
   - Find worktree directory
   - Force remove worktree

3. **Delete branches** (unless --keep-branches)
   - Delete local branch
   - Optionally delete remote branch

## Output Format

```markdown
# Cleanup Report

## Sessions Terminated
- [session1] ✅
- [session2] ✅

## Worktrees Removed
- /path/to/wt-branch1 ✅
- /path/to/wt-branch2 ✅

## Branches Deleted
- feature/branch1 ✅ (local + remote)
- feature/branch2 ✅ (local + remote)

## Status
All cleanup completed successfully.

## Verify
```bash
tmux list-sessions      # Should not show cleaned sessions
git worktree list       # Should not show cleaned worktrees
git branch              # Should not show cleaned branches
```
```

## Post-cleanup

After cleanup:
1. Update main branch: `git checkout main && git pull`
2. Ready for next task: `/pw:design [new-task]`

## Troubleshooting

### Cleanup Failed

```bash
# Force remove stuck worktree
git worktree remove --force /path/to/worktree

# Force kill tmux session
tmux kill-session -t session-name

# Force delete branch
git branch -D branch-name
```

### Orphaned Worktree Entry

```bash
# Prune stale worktree entries
git worktree prune
```
