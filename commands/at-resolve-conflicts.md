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

## Prerequisites

```bash
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]; then
  echo "ERROR: Agent Teams not enabled. Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json"
  exit 1
fi
echo "Agent Teams: ENABLED"
```

## Context
- Current branch: !`git branch --show-current`
- Default branch: !`_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; "$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main"`

## Detect Conflicts

```bash
echo "=== Conflict Detection ==="
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
DEFAULT_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
echo "Base branch: $DEFAULT_BRANCH"
git fetch origin "$DEFAULT_BRANCH"
echo "Attempting merge..."
git merge "origin/$DEFAULT_BRANCH"
```

```bash
echo "=== Conflicting Files ==="
CONFLICTING_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null)
if [ -z "$CONFLICTING_FILES" ]; then
  echo "No conflicts detected. Merge succeeded cleanly."
  git status
else
  echo "Conflicting files:"
  echo "$CONFLICTING_FILES"
  echo "Total: $(echo "$CONFLICTING_FILES" | wc -l | tr -d ' ') files"
fi
```

If no conflicts, report success and stop.

## Resolve Conflicts

### Goal

Create an agent team to resolve the merge conflicts. Adapt team size:

- **1-2 conflicting files**: Use a single teammate.
- **3+ conflicting files**: Create a team. Group files by directory or module.

Each conflicting file becomes a task in the shared task list. Teammates self-claim tasks and coordinate with each other when resolving conflicts in closely related files.

### Safety Context for ALL Teammates

Every teammate spawn prompt MUST include:
- The list of conflicting files assigned to them
- Explanation: `<<<<<<< HEAD` = current branch changes, `>>>>>>> origin/[base]` = base branch changes
- Resolution strategies: keep ours, keep theirs, combine both, or rewrite
- Remove ALL conflict markers from assigned files
- Run `git add` on each resolved file
- Do NOT run `git commit` — the lead handles the commit
- Only modify files in the assigned list

### After All Teammates Complete

1. Verify all conflict markers are removed:

```bash
echo "=== Checking for remaining conflict markers ==="
REMAINING=$(grep -rl "<<<<<<< " . --include='*' 2>/dev/null | grep -v '.git/' || true)
if [ -n "$REMAINING" ]; then
  echo "ERROR: Conflict markers still present in:"
  echo "$REMAINING"
else
  echo "All conflict markers resolved."
fi
```

2. Verify no unmerged files remain:

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

3. Run project checks:

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

4. If issues remain, have the responsible teammate re-resolve.

5. Commit and push:

```bash
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
DEFAULT_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")

git commit -m "$(cat <<EOF
merge: resolve conflicts with $DEFAULT_BRANCH

Resolved via Agent Team parallel conflict resolution.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push
```

6. Clean up the team.

## Next Steps

PR is now mergeable. Run `/pw:merge [pr-number]`
