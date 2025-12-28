---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: [review feedback or PR number]
description: Address review feedback and update the PR
model: opus
---

# Fix Review Feedback

## Feedback to Address
$ARGUMENTS

## Current Context
- Branch: !`git branch --show-current`
- Last commit: !`git log --oneline -1`

## PR Status
```bash
# Get current PR status if PR number provided
gh pr view --json reviewDecision,reviews,comments 2>/dev/null | head -30 || echo "Provide PR number for status"
```

## Fix Process

### Step 1: Parse Review Feedback

Categorize feedback:
- **Critical** (must fix): Bugs, security issues, logic errors
- **Required** (should fix): Style violations, missing tests
- **Suggestions** (consider): Improvements, alternatives

### Step 2: Address Each Issue

For each critical/required issue:
1. Locate the relevant code
2. Understand the concern
3. Implement the fix
4. Verify the fix

Use explorer subagent if needed:
```
Use explorer subagent to find related code or patterns
```

### Step 3: Verification

Run project checks:
```bash
if [ -f "Makefile" ] && grep -q "check" Makefile; then
  make check
elif [ -f "package.json" ]; then
  npm test 2>/dev/null || npm run test 2>/dev/null || true
elif [ -f "pyproject.toml" ]; then
  uv run pytest 2>/dev/null || uv run mypy . 2>/dev/null || true
fi
```

### Step 4: Commit Fixes

```bash
git add .
git commit -m "$(cat <<'EOF'
fix: address review feedback

- [Change 1]
- [Change 2]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 5: Push and Notify

```bash
git push

# Add comment to PR
gh pr comment [number] --body "$(cat <<'EOF'
Addressed review feedback:

- ✅ [Issue 1]: [How it was fixed]
- ✅ [Issue 2]: [How it was fixed]

Ready for re-review.
EOF
)"
```

## Output Format

```markdown
# Fix Report

## Issues Addressed
| Issue | Status | Changes Made |
|-------|--------|--------------|
| [Issue 1] | ✅ Fixed | [Description] |
| [Issue 2] | ✅ Fixed | [Description] |
| [Suggestion] | ⏭️ Deferred | [Reason] |

## Files Changed
- `path/to/file` - [What changed]

## Verification
- [ ] Tests pass
- [ ] Lint/type check pass
- [ ] Fixes address the feedback

## Outstanding Items
[Any items that couldn't be resolved or need clarification]

## Next Steps
Ready for re-review: `/pw:review [pr-number]`
```

## Handling Unclear Feedback

If feedback is ambiguous:
1. Document your interpretation
2. Implement based on best understanding
3. Add comment explaining your approach
4. Request clarification if critical
