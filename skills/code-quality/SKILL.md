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
