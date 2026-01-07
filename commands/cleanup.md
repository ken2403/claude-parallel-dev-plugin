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

This allows running from a parent directory where worktrees are located alongside the repo:
```
/workspace/              ← Claude session here
├── my-project/          ← Git repo (auto-detected)
├── wt-feature-auth/     ← worktree (to be cleaned)
└── wt-feature-api/      ← worktree (to be cleaned)
```

## Cleanup Process

### Using teardown.sh

The cleanup uses the plugin's `teardown.sh` script:

```bash
# Run teardown with provided arguments
# $ARGUMENTS contains: branch1 branch2 ... [--keep-branches] [--dry-run]
"${PLUGIN_DIR}/scripts/teardown.sh" $ARGUMENTS
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

## Base Branch Detection

Detect the base branch from workspace configuration:
```bash
# Check CLAUDE.md for base branch specification
BASE_BRANCH=""
if [ -f "CLAUDE.md" ]; then
  BASE_BRANCH=$(grep -i "base.branch\|default.branch\|primary.branch" CLAUDE.md | head -1 | grep -oE "(main|master|develop|dev|release[^[:space:]]*)" || echo "")
fi

# Fallback: check git remote HEAD or common branches
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
fi

# Final fallback: check which exists
if [ -z "$BASE_BRANCH" ]; then
  for branch in main master develop dev; do
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      BASE_BRANCH="$branch"
      break
    fi
  done
fi

echo "Base branch: ${BASE_BRANCH:-main}"
```

## Post-cleanup

After cleanup:
1. Update base branch: `git checkout ${BASE_BRANCH} && git pull`
2. Ready for next task: `/pw:design [new-task]`

## Troubleshooting

### ⚠️ CRITICAL: Human Confirmation Required

**NEVER execute force commands without explicit human approval!**

These commands are destructive and irreversible. Always ask the user to confirm before running:

### Cleanup Failed

If cleanup fails, present these options to the user and **wait for explicit confirmation**:

```markdown
⚠️ **Manual intervention required**

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
