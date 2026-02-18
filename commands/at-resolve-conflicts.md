---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: [branch name]
description: Identify conflicting files and resolve in parallel via agent team
model: opus
---

# Agent Team Conflict Resolution

Identify conflicting files after merging the base branch and resolve them in parallel via an agent team.

## Target Branch
$ARGUMENTS

## Agent Teams Prerequisite Check

```bash
echo "=== Agent Teams Prerequisite Check ==="
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]; then
  echo "ERROR: Agent Teams feature is not enabled."
  echo ""
  echo "To enable, add to your settings.json:"
  echo '  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }'
  echo ""
  echo "Or set the environment variable:"
  echo "  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
  exit 1
fi
echo "Agent Teams: ENABLED"
```

## Context
- Current branch: !`git branch --show-current`
- Default branch: !`_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; "$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main"`
- Behind default branch by: !`_BB=$(_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; "$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main"); git rev-list --count HEAD..origin/$_BB 2>/dev/null || echo "unknown"`

---

## Phase 1: Detect Conflicts

### Fetch and Attempt Merge

```bash
echo "=== Conflict Detection ==="

# Base branch detection (using shared script)
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
DEFAULT_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
echo "Base branch: $DEFAULT_BRANCH"

git fetch origin "$DEFAULT_BRANCH"
echo ""
echo "Attempting merge..."
git merge "origin/$DEFAULT_BRANCH"
```

### Identify Conflicting Files

```bash
echo "=== Conflicting Files ==="
CONFLICTING_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null)
if [ -z "$CONFLICTING_FILES" ]; then
  echo "No conflicts detected. Merge succeeded cleanly."
  git status
else
  echo "Conflicting files:"
  echo "$CONFLICTING_FILES"
  echo ""
  echo "Total: $(echo "$CONFLICTING_FILES" | wc -l | tr -d ' ') files"
fi
```

### If No Conflicts
If the merge succeeds without conflicts, report success and exit:
```markdown
# Conflict Resolution Report
## Result: No Conflicts
Merge with the base branch completed cleanly. No resolution needed.
```

---

## Phase 2: Analyze and Group Conflicts

If conflicts exist, the Lead analyzes them for team assignment.

### Grouping Strategy
- **1-2 conflicting files** → Spawn 1 Resolver (no overhead from teaming)
- **3+ conflicting files** → Group by directory/module, spawn 1 Resolver per group

### File Grouping Logic
Group files by their parent directory or module:
```
Group 1 (src/auth/): src/auth/login.ts, src/auth/middleware.ts
Group 2 (src/api/): src/api/routes.ts, src/api/handlers.ts
Group 3 (tests/): tests/auth.test.ts, tests/api.test.ts
```

---

## Phase 3: Spawn Resolver Team

### Team Structure (Dynamic)

| Teammate | Model | Assigned Files |
|----------|-------|----------------|
| Resolver-1 | sonnet | [Conflict file group 1] |
| Resolver-2 | sonnet | [Conflict file group 2] |
| ... | sonnet | ... |

**Lead Mode**: Delegate

### Resolver Spawn Prompt Template

```
You are a **Conflict Resolver** on a team resolving merge conflicts in parallel.

## Your Assigned Files
[List of conflicting files assigned to this Resolver]

## Resolution Instructions

For EACH conflicting file:

1. **Read** the file to see conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
2. **Understand** both versions:
   - `<<<<<<< HEAD` (ours): Changes on the current branch
   - `>>>>>>> origin/[base]` (theirs): Changes from the base branch
3. **Use `explorer` subagent** to understand the purpose and context of the conflicting code
4. **Choose resolution strategy**:
   - **Keep Ours**: Our changes are correct, theirs should be discarded
   - **Keep Theirs**: Base branch changes should take precedence
   - **Combine Both**: Both changes are needed and can coexist
   - **Rewrite**: Neither version is correct; write new code
5. **Edit** the file to resolve conflicts (remove ALL conflict markers)
6. **Stage** the resolved file: `git add [file]`

## CRITICAL Rules
- You may ONLY modify files in your assigned list
- Do NOT modify any other files
- Remove ALL conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) from your files
- After resolving, run `git add` on each resolved file
- Do NOT run `git commit` — the Lead will commit

## Output
Report for each file:
- File path
- Resolution strategy used
- Brief explanation of the resolution
```

---

## Phase 4: Parallel Resolution

Each Resolver works independently on their assigned conflict files.

The Resolvers:
1. Read each conflicting file
2. Use `explorer` subagent to understand the code context
3. Apply the appropriate resolution strategy
4. Edit files to remove all conflict markers
5. Stage resolved files with `git add`

---

## Phase 5: Lead Verification

After all Resolvers complete, the Lead verifies:

### 1. Check All Conflict Markers Removed

```bash
echo "=== Checking for remaining conflict markers ==="
REMAINING=$(grep -rl "<<<<<<< " . --include='*' 2>/dev/null | grep -v '.git/' || true)
if [ -n "$REMAINING" ]; then
  echo "ERROR: Conflict markers still present in:"
  echo "$REMAINING"
  echo ""
  echo "These files need further resolution."
else
  echo "All conflict markers resolved."
fi
```

### 2. Verify All Files Staged

```bash
echo "=== Checking unresolved files ==="
UNMERGED=$(git diff --name-only --diff-filter=U 2>/dev/null)
if [ -n "$UNMERGED" ]; then
  echo "ERROR: Unmerged files remain:"
  echo "$UNMERGED"
else
  echo "All files merged and staged."
fi
```

### 3. Handle Remaining Issues
If any files still have conflict markers or are unmerged:
- Identify which Resolver's scope the file belongs to
- Instruct that Resolver to re-resolve
- Re-verify after correction

### 4. Run Project Checks

```bash
echo "=== Project Checks ==="
if [ -f "Makefile" ] && grep -q "check" Makefile; then
  make check
elif [ -f "package.json" ]; then
  npm test 2>/dev/null || npm run test 2>/dev/null || true
elif [ -f "pyproject.toml" ]; then
  uv run pytest 2>/dev/null || uv run mypy . 2>/dev/null || true
fi
```

---

## Phase 6: Commit and Push

After all verifications pass, the Lead commits and pushes.

```bash
# Base branch detection (using shared script)
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
DEFAULT_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")

git commit -m "$(cat <<EOF
merge: resolve conflicts with $DEFAULT_BRANCH

Resolved via Agent Team parallel conflict resolution.

Resolved files:
- [file1]
- [file2]

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

```bash
git push
```

---

## Output Format

```markdown
# Conflict Resolution Report

## Team
| Resolver | Files | Strategy |
|----------|-------|----------|
| Resolver-1 | [files] | [strategies used] |
| Resolver-2 | [files] | [strategies used] |

## Files Resolved
| File | Strategy | Notes |
|------|----------|-------|
| [file1] | Combined | Merged both changes |
| [file2] | Keep ours | Our logic was correct |

## Verification
- [ ] All conflict markers removed
- [ ] All files staged and merged
- [ ] Project checks pass
- [ ] Changes committed
- [ ] Changes pushed

## Commit
- SHA: [commit-sha]
- Message: merge: resolve conflicts with [default-branch]

## Next Steps
PR is now mergeable. Run `/pw:merge [pr-number]`
```

---

## Resolution Strategies Reference

### Strategy 1: Keep Ours
When our changes are correct and theirs should be discarded.

### Strategy 2: Keep Theirs
When default branch changes should take precedence.

### Strategy 3: Combine Both
When both changes are needed and can coexist.

### Strategy 4: Rewrite
When neither version is correct and new code is needed.

---

## Troubleshooting

### Abort Merge
If resolution becomes too complex:
```bash
git merge --abort
```

### Check Conflict Details
```bash
git diff --name-only --diff-filter=U
git status
```
