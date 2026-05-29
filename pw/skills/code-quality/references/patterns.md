# Naming Conventions and Code Patterns

## Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Classes | PascalCase | `UserAuthentication` |
| Functions | snake_case / camelCase | `get_user` / `getUser` |
| Constants | UPPER_SNAKE | `MAX_RETRIES` |
| Private | Leading underscore | `_internal_method` |
| Boolean vars | is/has/can prefix | `is_active`, `has_permission` |
| Collections | Plural names | `users`, `items` |

## Code Smells Reference

### Long Methods
- **Signal**: Method longer than ~20-30 lines
- **Fix**: Extract smaller helper functions with descriptive names
- **Exception**: Simple sequential operations that lose clarity when split

### Deep Nesting
- **Signal**: More than 3 levels of indentation
- **Fix**: Use early returns, guard clauses, or extract methods
- **Pattern**:
```
# Before: nested
if a:
    if b:
        if c:
            do_thing()

# After: guard clauses
if not a: return
if not b: return
if not c: return
do_thing()
```

### Magic Numbers
- **Signal**: Literal numbers in logic (except 0, 1, -1 in obvious contexts)
- **Fix**: Extract to named constants
- **Example**: `RETRY_LIMIT = 3` instead of bare `3`

### God Classes
- **Signal**: Class with many unrelated responsibilities, too many methods
- **Fix**: Split into focused classes, use composition

### Feature Envy
- **Signal**: Method that uses more data from another class than its own
- **Fix**: Move the method to the class it envies

### Dead Code
- **Signal**: Unused functions, unreachable branches, commented-out code
- **Fix**: Delete it. Version control preserves history.

## Anti-Patterns

### Premature Abstraction
- Don't create abstractions until you have 3+ concrete use cases
- Three similar lines of code is better than a premature abstraction

### Over-Engineering
- Don't add configurability that isn't needed yet
- Don't design for hypothetical future requirements
- YAGNI (You Ain't Gonna Need It)

### Shotgun Surgery
- If one change requires edits in many unrelated files, consider consolidating
- Related logic should be co-located
