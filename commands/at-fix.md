---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: [PR number or review feedback text]
description: Parse review feedback and spawn agent team for parallel fixes
model: opus
---

# Agent Team Fix Review Feedback

Parse review feedback, group by file, and spawn an agent team to fix issues in parallel.

## Feedback to Address
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

## Current Context
- Branch: !`git branch --show-current`
- Last commit: !`git log --oneline -1`

---

## Feedback Acquisition

### From PR Number
```bash
# Get current PR status and reviews
gh pr view --json reviewDecision,reviews,comments 2>/dev/null | head -50 || echo "Provide PR number for status"
```

```bash
# Get detailed review comments with file locations
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
If the input is text (not a PR number), parse it directly. Expect the format from `at-rv` output:
- Required Changes section
- Recommended Changes section
- Inline findings with `file:line` references

---

## Feedback Analysis

After acquiring all feedback, analyze and structure it:

1. Categorize each finding:
   - **Critical** (must fix): Bugs, security issues, logic errors
   - **Required** (should fix): Style violations, missing tests, API contract issues
   - **Suggestion** (consider): Improvements, alternative approaches
2. Group by file — all findings for the same file belong to the same teammate.
3. Related files in the same directory or module: prefer assigning to the same teammate.

---

## Team Decision

Based on the number of affected files:

- **1-2 affected files**: Assign to a single teammate — skip team overhead.
- **3+ affected files**: Create an agent team. Group files by directory or module. Cap at 5 teammates. Each finding becomes a separate task in the shared task list, targeting 5-6 tasks per teammate.

---

## Teammate Spawn Guidelines

Include the following in each teammate's spawn prompt:

- The list of files they are assigned and all findings for those files with `file:line` references.
- The reviewer's recommendation for each finding.
- The list of files they must NOT modify (other teammates' territory).
- Explicit instruction: do NOT run `git commit` or `git push` — the lead handles all commits.
- Instruction to follow existing code patterns and style.

---

## Coordination

- Teammates self-claim tasks from the shared task list to avoid duplicate work.
- If a fix has cross-file implications, teammates message each other before making changes.
- Lead waits for all teammates to complete before starting verification.
- Lead verifies each fix directly addresses the original reviewer concern.

---

## Verification

After all teammates complete:

1. **Check file scope compliance** — confirm no files were changed outside assigned scope.

```bash
echo "=== Checking file changes ==="
git diff --name-only
echo ""
echo "=== Checking for scope violations ==="
# Lead compares changed files against the manifest
# Any file changed that wasn't in any teammate's scope is a violation
```

2. **Run project checks.**

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

3. **If failures**: identify the responsible teammate, have them fix the issue, then re-verify.

---

## Commit and Push

After all verifications pass, commit and push.

```bash
git add .
git commit -m "$(cat <<'EOF'
fix: address review feedback

- [Change 1]
- [Change 2]

Automated fixes by at-fix (Agent Teams).

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

```bash
git push
```

---

## PR Comment

Post a fix summary to the PR.

```bash
PR_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+' | head -1)
if [ -n "$PR_NUM" ]; then
  gh pr comment "$PR_NUM" --body "$(cat <<'EOF'
## Review Feedback Addressed (Agent Teams)

Fixes were applied in parallel by an agent team.

### Issues Fixed
- [Issue 1]: [How it was fixed]
- [Issue 2]: [How it was fixed]

### Deferred Items
- [Item]: [Reason for deferral]

Ready for re-review.
EOF
)"
fi
```

---

## Output Format

```markdown
# Fix Report (Agent Teams)

## Team Summary
| Teammate | Files | Findings Addressed |
|----------|-------|--------------------|
| Fixer-1  | [files] | N/N fixed |
| Fixer-2  | [files] | N/N fixed |

## Issues Addressed
| Finding (file:line) | Severity | Status | Notes |
|---------------------|----------|--------|-------|
| [file:line]         | Critical | Fixed  | [What changed] |
| [file:line]         | Required | Fixed  | [What changed] |
| [file:line]         | Suggestion | Deferred | [Reason] |

## Files Changed
- `path/to/file` — [What changed]

## Verification Results
- [ ] All critical findings fixed
- [ ] All required findings fixed
- [ ] No scope violations
- [ ] Project checks pass
- [ ] Changes committed and pushed
- [ ] PR comment posted

## Next Steps
Ready for re-review: `/pw:at-rv [pr-number]` or `/pw:rv [pr-number]`
```
