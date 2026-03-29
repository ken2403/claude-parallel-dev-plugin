---
name: code-quality
description: Code quality standards for reviewing code changes. Automatically provides quality checklist when reviewing PRs, implementing features, or discussing code quality. Use when user asks to "review code", "check quality", "improve code", "refactor", or runs /rv or /precheck commands.
allowed-tools: Read, Grep, Glob
metadata:
    author: ken2403
    version: 1.1.0
---

# Code Quality Standards

Apply these quality criteria when reviewing or writing code.

## Instructions

### Step 1: Understand Existing Patterns

Before reviewing or writing code, explore the codebase to understand existing conventions.

```
Use explorer subagent to find similar implementations in the codebase
Use analyzer subagent to understand the coding patterns used in this project
```

### Step 2: Apply Quality Criteria

Evaluate code against these core principles:

- **Readability**: Self-documenting through clear naming, complex logic has comments
- **Maintainability**: Small focused functions (SRP), no duplication (DRY), clear module boundaries
- **Simplicity**: No over-engineering, no premature optimization, minimal dependencies
- **Error Handling**: Errors caught at appropriate level, meaningful messages, no silent failures, resources cleaned up
- **Type Safety**: Public functions have type annotations, no unnecessary `Any` types

For detailed checklists, consult `references/checklist.md`.

### Step 3: Check for Code Smells

Flag these common issues:

- Long methods -> break into smaller functions
- Deep nesting -> flatten with early returns
- Magic numbers -> use named constants
- God classes -> split responsibilities
- Dead code -> remove unused code

For naming conventions and style patterns, consult `references/patterns.md`.

### Step 4: Verify Consistency

| Aspect | Check |
|--------|-------|
| Naming | Match existing variable/function naming conventions |
| Structure | Follow established file/directory organization |
| Patterns | Use same design patterns as existing code |
| Formatting | Match indentation, spacing, line breaks |
| Imports | Match import ordering and grouping |
| Error handling | Use same error handling patterns |

### Step 5: Final Review Checklist

- [ ] Logic is correct
- [ ] Edge cases handled
- [ ] Error handling appropriate
- [ ] Types are correct
- [ ] No security vulnerabilities
- [ ] Tests adequate
- [ ] Code is readable
- [ ] No unnecessary complexity
- [ ] Consistent with existing codebase style
- [ ] Follows established patterns (verified with subagent exploration)

## Examples

### Example 1: N+1 Query Detection

When reviewing database access code, watch for queries inside loops:

```python
# Bad - N+1 query
for user in users:
    posts = db.query(Post).filter(Post.user_id == user.id).all()

# Good - Eager loading
users = db.query(User).options(joinedload(User.posts)).all()
```

### Example 2: Early Return for Deep Nesting

```python
# Bad - Deep nesting
def process(data):
    if data:
        if data.is_valid():
            if data.has_permission():
                return do_work(data)

# Good - Early returns
def process(data):
    if not data:
        return None
    if not data.is_valid():
        raise ValueError("Invalid data")
    if not data.has_permission():
        raise PermissionError("Access denied")
    return do_work(data)
```

## Common Issues

### Skill Not Catching Issues

If code quality problems are missed:
1. Verify the codebase was explored first with subagents
2. Consult the detailed checklist in `references/checklist.md`
3. Check if the issue is language-specific

### Inconsistent Style Feedback

If style suggestions conflict with the existing codebase:
1. Existing codebase patterns always take precedence
2. Use `analyzer` subagent to confirm the established convention
3. Only suggest style changes if the existing pattern is clearly problematic
