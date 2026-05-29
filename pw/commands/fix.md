---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: '[review feedback or PR number]'
description: Address review feedback and update the PR using parallel subagents for 3+ files
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

### Step 1: Parse and Categorize Review Feedback

Categorize feedback:
- **Critical** (must fix): Bugs, security issues, logic errors
- **Required** (should fix): Style violations, missing tests
- **Suggestions** (consider): Improvements, alternatives

For each finding, extract:
- **File path** and **line number** (if provided)
- **Category** (Critical/Required/Suggestion)
- **Description** of what needs to change and how

If a PR number was provided, fetch detailed review comments:
```bash
PR_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+' | head -1)
if [ -n "$PR_NUM" ]; then
  OWNER_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
  echo "=== PR Reviews ==="
  gh api "repos/$OWNER_REPO/pulls/$PR_NUM/reviews" --jq '.[] | "Review by \(.user.login): \(.state)\n\(.body)\n---"' 2>/dev/null || true
  echo ""
  echo "=== Inline Review Comments ==="
  gh api "repos/$OWNER_REPO/pulls/$PR_NUM/comments" --jq '.[] | "[\(.path):\(.line // .original_line)] \(.body)\n---"' 2>/dev/null || true
fi
```

Group findings by file ownership:
- All findings for the same file go in the same group
- Files in the same directory may be combined (max 5 files per group)
- Findings without file references are handled directly by the lead

### Step 2: Prepare Fix Instructions

For each file group, write detailed instructions:
- Exact code location (file:line)
- What the current code does wrong
- What the fix should look like
- Reference to existing code patterns to follow

Use explorer subagent if context is needed:
```
Use explorer subagent to find related code patterns or understand dependencies
```

### Step 3: Pre-Dispatch Review

Before dispatching to subagents, verify the fix instructions:

1. **Sufficiency**: Each instruction set contains enough context for the subagent
   - File paths and line numbers are accurate
   - Fix descriptions are specific (not vague like "improve this")
   - Referenced code patterns are identified
2. **Cross-file consistency**: Fixes across groups don't contradict each other
   - API changes match their consumers
   - Type changes propagate to all usage sites
3. **Scope check**: Estimated changes per group fit within ~200 lines

Fix any issues in the instructions before proceeding.

### Step 4: Address Each Issue

#### For 1-2 affected files (sequential):

Address directly without subagent overhead:

For each critical/required issue:
1. Locate the relevant code
2. Understand the concern
3. Implement the fix
4. Verify the fix

#### For 3+ affected files (parallel via simple-implementer subagents):

Launch multiple simple-implementer subagents in parallel using the Task tool. For each group:

```
Use simple-implementer subagent to address review feedback for the following files:

Files and findings:
- `[file1 path]`:
  - Line [N]: [Critical] [Detailed description of the issue and exactly how to fix it]
  - Line [M]: [Required] [Detailed description and fix approach]
- `[file2 path]`:
  - Line [N]: [Required] [Detailed description and fix approach]

Context:
- Existing code pattern to follow: see [reference file:line]
- Related files (read-only reference): [list of related files]

Instructions:
1. Read each file and locate the code at the specified lines
2. Implement the fix as described above
3. Follow existing code style and conventions
4. Stage each fixed file: `git add [file]`

IMPORTANT:
- Only modify the files listed above
- Do not introduce new issues while fixing existing ones
- If a fix seems too large or risky, report it as REJECTED with explanation
```

Wait for all subagents to complete before proceeding.

#### Handle Subagent Rejections

If any simple-implementer subagent rejects a task (scope too large), address those files directly as the lead.

### Step 5: Integration Review

After all fixes are applied:

1. **Review changes**: Read `git diff` to verify all changes are correct
   ```bash
   echo "=== Changed Files ==="
   git diff --cached --name-only
   echo ""
   echo "=== Diff Summary ==="
   git diff --cached --stat
   ```
2. **Verify completeness**: Confirm all Critical and Required findings were addressed
3. **Cross-file consistency**: Check that fixes in one file don't break another
   - Function signatures match their call sites
   - Import/export changes are consistent
4. **No regressions**: Fixes don't introduce new issues
5. **Fix issues directly** if the integration review finds problems

### Step 6: Verification

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

### Step 7: Commit Fixes

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

### Step 8: Push and Notify

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

## Execution Mode
- **Mode**: Sequential / Parallel (N subagents)
- **Files affected**: N files in M groups

## Issues Addressed
| Issue | File:Line | Category | Status | Resolved By |
|-------|-----------|----------|--------|-------------|
| [Issue 1] | file.ts:42 | Critical | Fixed | subagent-1 |
| [Issue 2] | other.ts:15 | Required | Fixed | lead |
| [Suggestion] | - | Suggestion | Deferred | - |

## Files Changed
- `path/to/file` - [What changed]

## Integration Review
- [ ] All Critical findings fixed
- [ ] All Required findings fixed
- [ ] Cross-file consistency verified
- [ ] No regressions introduced

## Verification
- [ ] Tests pass
- [ ] Lint/type check pass
- [ ] Fixes address the feedback

## Outstanding Items
[Any items that couldn't be resolved or need clarification]

## Next Steps
Ready for re-review: `/pw:rv [pr-number]`
```

## Handling Unclear Feedback

If feedback is ambiguous:
1. Document your interpretation
2. Implement based on best understanding
3. Add comment explaining your approach
4. Request clarification if critical
