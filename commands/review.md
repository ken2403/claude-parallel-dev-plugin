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

## Apply Review Skills

**MANDATORY**: Apply the following skills for comprehensive review:

1. **Code Quality Skill** (`/pw:code-quality`):
   - Readability, maintainability, simplicity
   - Type safety, error handling
   - Naming conventions, code smells
   - Consistency with existing codebase patterns

2. **Security Review Skill** (`/pw:security-review`):
   - Authentication & authorization
   - Input validation & injection prevention
   - Data protection & secrets management
   - OWASP Top 10 vulnerabilities

Refer to the skill definitions for detailed checklists.

## Review Checklist Summary

### Code Quality
- [ ] Logic is correct and handles edge cases
- [ ] Code is readable and maintainable
- [ ] Follows existing patterns in the codebase
- [ ] No unnecessary complexity
- [ ] Proper error handling

### Security
- [ ] No hardcoded secrets or credentials
- [ ] Input validation on external data
- [ ] No injection vulnerabilities (SQL, XSS, command)
- [ ] Sensitive data handled appropriately

### Testing & Documentation
- [ ] Tests added for new functionality
- [ ] Edge cases covered
- [ ] Code comments where needed

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
