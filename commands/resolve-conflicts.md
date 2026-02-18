---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: [branch name]
description: Resolve merge conflicts with default branch using parallel subagents for 3+ files
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

### Step 2: Identify and Group Conflicting Files
```bash
echo "=== Conflicting Files ==="
CONFLICTED_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null)
if [ -z "$CONFLICTED_FILES" ]; then
  echo "No conflicts detected. Merge completed cleanly."
  exit 0
fi

echo "$CONFLICTED_FILES"
CONFLICT_COUNT=$(echo "$CONFLICTED_FILES" | wc -l | tr -d ' ')
echo ""
echo "Total conflicting files: $CONFLICT_COUNT"

echo ""
echo "=== Files by Directory ==="
echo "$CONFLICTED_FILES" | while read f; do dirname "$f"; done | sort -u | while read dir; do
  count=$(echo "$CONFLICTED_FILES" | while read f; do dirname "$f"; done | grep -c "^${dir}$" || true)
  echo "  ${dir}/ : ${count} files"
done
```

### Step 3: Analyze Conflicts and Prepare Resolution Instructions

For each conflicted file:

1. **Read** the file to see all conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
2. **Understand both sides**:
   - `<<<<<<< HEAD` (ours): Changes on the current branch
   - `>>>>>>> origin/[base]` (theirs): Changes from the base branch
3. **Use explorer subagent** for additional context if needed:
   ```
   Use explorer subagent to understand the purpose and dependencies of conflicting code
   ```
4. **Determine resolution strategy** for each conflict block:
   - **Keep Ours**: Our changes are correct, theirs should be discarded
   - **Keep Theirs**: Base branch changes should take precedence
   - **Combine Both**: Both changes are needed and can coexist
   - **Rewrite**: Neither version is correct; new code is needed
5. **Write detailed per-file resolution instructions** with line-level specificity:
   - For Keep Ours/Theirs: Specify which lines to keep and which to remove
   - For Combine: Specify exact ordering and how to merge both sides
   - For Rewrite: Provide the exact replacement code

### Step 3.5: Pre-Dispatch Review

Before dispatching to subagents, verify the resolution instructions:

1. **Sufficiency**: Each instruction set is detailed enough for standalone execution
   - File paths are accurate
   - Line numbers and conflict block locations are specified
   - Resolution strategy is concrete (not vague)
2. **Cross-file consistency**: Instructions don't contradict each other
   - Function signatures match across files
   - Import/export changes are consistent
   - Shared types or interfaces align
3. **Scope check**: Estimated changes per group are within simple-implementer limits (~200 lines)

Fix any issues in the instructions before proceeding.

### Step 4: Resolve Conflicts

#### For 1-2 conflicting files (sequential):

Resolve directly without subagent overhead:
1. Edit each file to remove all conflict markers, applying the chosen strategy
2. Verify no conflict markers remain
3. Run `git add [file]` for each resolved file

#### For 3+ conflicting files (parallel via simple-implementer subagents):

Group files by parent directory. Each group becomes one subagent task.

**Grouping rules:**
- Files in the same directory form one group
- Max 5 files per group (split larger groups)
- Root-level files form their own group

Launch multiple simple-implementer subagents in parallel using the Task tool. For each group:

```
Use simple-implementer subagent to resolve merge conflicts in the following files:

Files:
- [file1 path]
- [file2 path]

Detailed resolution instructions per file:

### [file1]
Strategy: [Keep Ours / Keep Theirs / Combine Both / Rewrite]
- Conflict block at lines [N-M]:
  - [Specific line-level instructions: which lines to keep, remove, or how to combine]
  - [Expected final result description]

### [file2]
Strategy: [strategy]
- Conflict block at lines [N-M]:
  - [Specific instructions]

After resolving each file:
1. Verify NO conflict markers (<<<<<<< / ======= / >>>>>>>) remain in the file
2. Run `git add [file]` for each resolved file

IMPORTANT:
- Remove ALL conflict markers from every file
- Follow the resolution instructions exactly
- Do NOT modify any code outside of conflict blocks
```

Wait for all subagents to complete before proceeding.

### Step 4.5: Integration Review (CRITICAL)

After all subagents complete (or after direct resolution), perform thorough verification.

#### 4.5a. Marker Residue Check (mechanical)

```bash
echo "=== Checking for remaining conflict markers ==="
REMAINING=$(grep -rn -E "^<<<<<<<|^=======|^>>>>>>>" . --include='*' 2>/dev/null | grep -v '.git/' || true)
if [ -n "$REMAINING" ]; then
  echo "WARNING: Conflict markers still present:"
  echo "$REMAINING"
else
  echo "All conflict markers removed."
fi

echo ""
echo "=== Checking unresolved files ==="
UNMERGED=$(git diff --name-only --diff-filter=U 2>/dev/null)
if [ -n "$UNMERGED" ]; then
  echo "WARNING: Unmerged files remain:"
  echo "$UNMERGED"
else
  echo "All files merged and staged."
fi
```

If any markers remain or files are unmerged, resolve them directly before continuing.

#### 4.5b. Logic Integrity Review (Opus reads all resolved files)

**MANDATORY**: Read each resolved file in its entirety and verify:

1. **Strategy compliance**: The resolution matches the strategy decided in Step 3
   - Keep Ours was not accidentally replaced with Theirs content
   - Combine correctly includes both sides in the right order
   - No unintended code was kept or removed

2. **Syntactic correctness**: The resolved code is valid
   - Brackets, parentheses, and indentation are correct
   - No dangling or orphaned code blocks
   - Import statements reference symbols that exist

3. **Cross-file consistency**: Changes across files are compatible
   - Function signatures match their call sites
   - Type definitions are consistent across files
   - Shared constants or config values are not contradictory

4. **Business logic correctness**: The merged result makes functional sense
   - Incoming (base branch) changes' intent is preserved where chosen
   - Current branch changes' intent is preserved where chosen
   - Combined changes work together as a coherent whole

5. **If issues found**: Fix them directly — do not re-dispatch to subagents

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

## Execution Mode
- **Mode**: Sequential / Parallel (N subagents)
- **Files**: N conflicting files in M groups

## Files Resolved
| File | Strategy | Resolved By | Notes |
|------|----------|-------------|-------|
| [file1] | Combined | subagent-1 | Merged both changes |
| [file2] | Keep ours | lead | Our logic was correct |

## Integration Review
- [ ] All conflict markers removed
- [ ] Logic integrity verified (Opus read all files)
- [ ] Cross-file consistency confirmed
- [ ] Business logic correctness verified

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
