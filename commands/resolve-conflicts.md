---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: [branch name]
description: Resolve merge conflicts with default branch
model: opus
---

# Resolve Merge Conflicts

## Target Branch
$ARGUMENTS

## Context
- Current branch: !`git branch --show-current`
- Default branch: !`_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; "$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main"`
- Behind default branch by: !`_BB=$(_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; "$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main"); git rev-list --count HEAD..origin/$_BB 2>/dev/null || echo "unknown"`

## Conflict Status
```bash
echo "=== Current Status ==="
git status 2>/dev/null || echo "Not in git repo"
```

## Resolution Process

### Step 1: Detect Base Branch, Fetch and Attempt Merge
```bash
# Base branch detection (using shared script)
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
echo "Base branch: $BASE_BRANCH"
git fetch origin "$BASE_BRANCH"
git merge "origin/$BASE_BRANCH"
```

### Step 2: Identify Conflicts
```bash
echo "=== Conflicting Files ==="
git status | grep "both modified" || echo "No conflicts or not in merge state"
```

### Step 3: Analyze Each Conflict

For each conflicted file:
1. Read the file to see conflict markers
2. Understand both versions (ours vs theirs)
3. Determine correct resolution
4. Edit to resolve

Use explorer subagent if context is needed:
```
Use explorer subagent to understand the purpose of conflicting code
```

### Step 4: Resolve Conflicts

For each conflicted file:
```bash
# After editing to resolve
git add [file]
```

### Step 5: Complete Merge
```bash
# Base branch detection (using shared script)
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
git commit -m "$(cat <<EOF
merge: resolve conflicts with $BASE_BRANCH

Resolved conflicts in:
- [file1]
- [file2]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 6: Verify
```bash
# Run project checks
if [ -f "Makefile" ] && grep -q "check" Makefile; then
  make check
elif [ -f "package.json" ]; then
  npm test 2>/dev/null || true
elif [ -f "pyproject.toml" ]; then
  uv run pytest 2>/dev/null || true
fi
```

### Step 7: Push
```bash
git push
```

## Conflict Resolution Strategies

### Strategy 1: Keep Ours
When our changes are correct and theirs should be discarded.

### Strategy 2: Keep Theirs
When default branch changes should take precedence.

### Strategy 3: Combine Both
When both changes are needed and can coexist.

### Strategy 4: Rewrite
When neither version is correct and new code is needed.

## Output Format

```markdown
# Conflict Resolution Report

## Files Resolved
| File | Strategy | Notes |
|------|----------|-------|
| [file1] | Combined | Merged both changes |
| [file2] | Keep ours | Our logic was correct |

## Verification
- [ ] Merge completed
- [ ] Tests pass
- [ ] Code compiles/runs
- [ ] Changes pushed

## Commit
- SHA: [commit-sha]
- Message: merge: resolve conflicts with [default-branch]

## Next Steps
PR is now mergeable. Run `/pw:merge [pr-number]`
```

## Troubleshooting

### Abort Merge
If resolution is too complex:
```bash
git merge --abort
```

### Reset to Clean State
```bash
git reset --hard HEAD
git clean -fd
```
