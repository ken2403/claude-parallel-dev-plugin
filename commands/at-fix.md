---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: [PR number or review feedback text]
description: Parse review feedback and spawn agent team for parallel fixes
model: opus
---

# Agent Team Fix Review Feedback

Parse review feedback, group by file, and create an agent team to fix issues in parallel.

## Input
$ARGUMENTS

## Prerequisites

```bash
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]; then
  echo "ERROR: Agent Teams not enabled. Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json"
  exit 1
fi
echo "Agent Teams: ENABLED"
```

## Current Context
- Branch: !`git branch --show-current`
- Last commit: !`git log --oneline -1`

## Gather Feedback

### From PR Number

```bash
gh pr view --json reviewDecision,reviews,comments 2>/dev/null | head -50 || echo "Provide PR number for status"
```

```bash
PR_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+' | head -1)
if [ -n "$PR_NUM" ]; then
  OWNER_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
  echo "=== PR Reviews ==="
  gh api "repos/$OWNER_REPO/pulls/$PR_NUM/reviews" --jq '.[] | "Review by \(.user.login): \(.state)\n\(.body)\n---"' 2>/dev/null || true
  echo ""
  echo "=== Review Comments (inline) ==="
  gh api "repos/$OWNER_REPO/pulls/$PR_NUM/comments" --jq '.[] | "[\(.path):\(.line // .original_line)] \(.body)\n---"' 2>/dev/null || true
fi
```

### From Text Input

If the input is text (not a PR number), parse it directly for Required Changes, Recommended Changes, and inline findings with `file:line` references.

## Analyze and Fix

### Goal

Categorize each finding (Critical / Required / Suggestion), group by file, and create an agent team to fix them in parallel. Adapt team size to scope:

- **1-2 affected files**: Use a single teammate — team overhead is not justified.
- **3+ affected files**: Create a team. Group files by directory or module, max 5 teammates.

Each finding becomes a task in the shared task list. Teammates self-claim tasks and message each other if fixes have cross-file implications.

### Safety Context for ALL Teammates

Every teammate spawn prompt MUST include:
- Assigned files and findings with file:line references and reviewer recommendations
- Files they must NOT modify (other teammates' territory)
- Do NOT run `git commit` or `git push` — the lead handles all commits
- Follow existing code patterns and style

### After All Teammates Complete

1. Verify no files were changed outside assigned scope.
2. Run project checks:

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

3. If failures: have the responsible teammate fix, then re-verify.
4. Commit and push:

```bash
git add .
git commit -m "$(cat <<'EOF'
fix: address review feedback

Automated fixes by at-fix (Agent Teams).

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push
```

5. Post fix summary to the PR:

```bash
PR_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+' | head -1)
if [ -n "$PR_NUM" ]; then
  gh pr comment "$PR_NUM" --body "$(cat <<'EOF'
## Review Feedback Addressed (Agent Teams)

Fixes applied in parallel by an agent team.

### Issues Fixed
- [Issue 1]: [How it was fixed]

### Deferred Items
- [Item]: [Reason]

Ready for re-review.
EOF
)"
fi
```

6. Clean up the team.

## Next Steps

Ready for re-review: `/pw:at-rv [pr-number]` or `/pw:rv [pr-number]`
