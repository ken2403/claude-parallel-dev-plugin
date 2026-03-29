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

## Detect Conflicts

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

## Conflict Analysis and Team Decision

After identifying conflicting files, decide how to assign resolution work:

- **1-2 conflicting files**: Assign to a single teammate — team overhead is not justified at this scale.
- **3+ conflicting files**: Create an agent team. Group files by directory or module (e.g., all files under `src/auth/` form one group), and assign each group to a separate teammate.

Add each conflicting file (or file group) as a task to the shared task list so teammates can self-claim their work.

---

## Teammate Spawn Guidelines

Include the following in each teammate's spawn prompt:

- The list of conflicting files assigned to this teammate
- Resolution strategies available:
  - **Keep Ours**: Current branch changes are correct; discard base branch changes
  - **Keep Theirs**: Base branch changes should take precedence; discard current branch changes
  - **Combine Both**: Both sets of changes are valid and can coexist
  - **Rewrite**: Neither version is correct; write new code that satisfies both intents
- For each file, clarify what "ours" and "theirs" means: `<<<<<<< HEAD` is the current branch; `>>>>>>> origin/[base]` is the base branch
- Available tools include the `explorer` subagent for understanding code context before resolving
- Rules:
  - Only modify files in the assigned list
  - Remove ALL conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) from every assigned file
  - Run `git add` on each resolved file
  - Do NOT run `git commit` — the lead will commit after verification

---

## Coordination

- Teammates self-claim conflict files (or file groups) from the shared task list before starting.
- If two teammates are resolving conflicts in closely related files (e.g., a module and its test file), they should message each other to coordinate so their resolutions stay consistent.
- The lead waits for all teammates to mark their tasks complete before proceeding to verification.

---

## Verification

After all teammates complete, verify the resolution:

### Check All Conflict Markers Removed

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

### Check Unmerged Files

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

### Run Project Checks

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

If any issues remain after verification, identify which teammate owns the affected file and have them re-resolve it, then re-run verification.

---

## Commit and Push

After all verifications pass, commit and push.

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
| Teammate | Files | Strategy |
|----------|-------|----------|
| Resolver-1 | [files] | [strategies used] |
| Resolver-2 | [files] | [strategies used] |

## Files Resolved
| File | Strategy | Notes |
|------|----------|-------|
| [file1] | Combine Both | Merged changes from both branches |
| [file2] | Keep Ours | Current branch logic was correct |

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
