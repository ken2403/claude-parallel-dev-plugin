---
allowed-tools: Read, Bash, Grep, Glob
argument-hint: [PR number or branch name]
description: Review a pull request for quality, security, and correctness
model: opus
---

# PR Review

## Target
$ARGUMENTS

## PR Information
```bash
# Get PR details
gh pr view $1 2>/dev/null || echo "Provide PR number as argument"
```

## Review Context

### Changes Overview
```bash
echo "=== Files Changed ==="
gh pr diff $1 --stat 2>/dev/null || git diff origin/main...HEAD --stat
```

### Detailed Diff
```bash
echo ""
echo "=== Diff Preview (first 200 lines) ==="
gh pr diff $1 2>/dev/null | head -200 || git diff origin/main...HEAD | head -200
```

### CI Status
```bash
echo ""
echo "=== CI Checks ==="
gh pr checks $1 2>/dev/null || echo "Cannot fetch CI status"
```

## Review Checklist

### 1. Code Quality
- [ ] Logic is correct and handles edge cases
- [ ] No obvious bugs or errors
- [ ] Code is readable and maintainable
- [ ] Follows existing patterns in the codebase
- [ ] No unnecessary complexity

### 2. Type Safety & Style
- [ ] Type annotations present (where required by project)
- [ ] Consistent naming conventions
- [ ] No linting errors
- [ ] Proper error handling

### 3. Security
- [ ] No hardcoded secrets or credentials
- [ ] Input validation on external data
- [ ] No SQL injection vulnerabilities
- [ ] No XSS vulnerabilities
- [ ] Sensitive data handled appropriately

### 4. Testing
- [ ] Tests added for new functionality
- [ ] Existing tests still pass
- [ ] Edge cases covered
- [ ] Test coverage adequate

### 5. Documentation
- [ ] Code comments where needed
- [ ] API changes documented
- [ ] README updated (if applicable)

## Review Process

1. **Read the PR description** - Understand intent
2. **Review the diff** - Check each file changed
3. **Run tests locally** (if needed)
4. **Check CI status** - All checks passing?
5. **Provide feedback** - Be specific and constructive

## Output Format

```markdown
# Review: PR #[number]

## Summary
[Brief description of what this PR does]

## Status: ✅ Approved | ⚠️ Changes Requested | ❌ Rejected

## Findings

### Critical Issues (Must Fix)
- [ ] [Issue description with file:line reference]

### Suggestions (Nice to Have)
- [ ] [Suggestion with reasoning]

### Questions
- [Question about implementation choice]

### Positive Notes
- [What was done well]

## Recommendation
[Approve / Request changes / Need discussion]

## Next Steps
- [What should happen after this review]
```

## Actions

After review:
- **Approved**: `/pw:merge [pr-number]`
- **Changes needed**: `/pw:fix [review feedback]` (in worker session)
- **Discussion needed**: Comment on PR via `gh pr comment`
