---
name: code-quality
description: Code quality standards for reviewing code changes. Automatically provides quality checklist when reviewing PRs, implementing features, or discussing code quality.
allowed-tools: Read, Grep, Glob
---

# Code Quality Standards

Apply these quality criteria when reviewing or writing code.

## General Quality

### Readability
- Code is self-documenting through clear naming
- Complex logic has explanatory comments
- Consistent formatting and style
- Appropriate abstraction level

### Maintainability
- Functions are small and focused (single responsibility)
- No code duplication (DRY principle)
- Clear module boundaries
- Easy to modify without breaking other parts

### Simplicity
- No over-engineering
- No premature optimization
- Straightforward solutions preferred
- Minimal dependencies

## Type Safety

- All public functions have type annotations
- No `Any` type unless absolutely necessary
- Generic types properly constrained
- Return types explicitly declared

## Error Handling

- Errors caught at appropriate level
- Error messages are meaningful and actionable
- No silent failures (swallowed exceptions)
- Graceful degradation where appropriate
- Resources properly cleaned up (finally/context managers)

## Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Classes | PascalCase | `UserAuthentication` |
| Functions | snake_case / camelCase | `get_user` / `getUser` |
| Constants | UPPER_SNAKE | `MAX_RETRIES` |
| Private | Leading underscore | `_internal_method` |

## Code Smells to Avoid

- **Long methods**: Break into smaller functions
- **Deep nesting**: Flatten with early returns
- **Magic numbers**: Use named constants
- **God classes**: Split responsibilities
- **Feature envy**: Move method to appropriate class
- **Dead code**: Remove unused code

## Performance

### N+1 Query Prevention
- No database queries inside loops
- Use eager loading / preloading for related data
- Batch queries when fetching multiple records

Common patterns to avoid:
```python
# Bad - N+1 query
for user in users:
    posts = db.query(Post).filter(Post.user_id == user.id).all()

# Good - Eager loading
users = db.query(User).options(joinedload(User.posts)).all()
```

## Testing Requirements

- Unit tests for business logic
- Integration tests for APIs
- Edge cases covered
- Mocks used appropriately
- Test names describe behavior

## Documentation

- Public APIs documented
- Complex algorithms explained
- Configuration options described
- Examples provided for non-obvious usage

## Coding Style Consistency

**IMPORTANT**: New code must be consistent with existing codebase patterns.

### Before Making Changes

Use subagents to understand existing patterns:

```
Use explorer subagent to find similar implementations in the codebase
Use analyzer subagent to understand the coding patterns used in this project
```

### Consistency Checks

| Aspect | Check |
|--------|-------|
| Naming | Match existing variable/function naming conventions |
| Structure | Follow established file/directory organization |
| Patterns | Use same design patterns as existing code |
| Formatting | Match indentation, spacing, line breaks |
| Comments | Follow existing comment style and density |
| Imports | Match import ordering and grouping |
| Error handling | Use same error handling patterns |

### Workflow

1. **Explore first**: Always use `explorer` subagent to find similar code
2. **Analyze patterns**: Use `analyzer` subagent for complex architectural decisions
3. **Match style**: Implement using the same patterns found in existing code
4. **Verify consistency**: Compare your changes with surrounding code

## Review Checklist

When reviewing code, verify:

- [ ] Logic is correct
- [ ] Edge cases handled
- [ ] Error handling appropriate
- [ ] Types are correct
- [ ] No security vulnerabilities
- [ ] Tests adequate
- [ ] Code is readable
- [ ] No unnecessary complexity
- [ ] **Consistent with existing codebase style**
- [ ] **Follows established patterns (verified with subagent exploration)**
