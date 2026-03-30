# Code Quality Detailed Checklist

## Contents
- Readability
- Maintainability
- Type Safety
- Error Handling
- Performance
- Testing Requirements
- Documentation

## Readability

- Code is self-documenting through clear naming
- Complex logic has explanatory comments
- Consistent formatting and style
- Appropriate abstraction level
- No abbreviations that aren't universally understood

## Maintainability

- Functions are small and focused (single responsibility)
- No code duplication (DRY principle)
- Clear module boundaries
- Easy to modify without breaking other parts
- Dependencies are explicit and minimal

## Type Safety

- All public functions have type annotations
- No `Any` type unless absolutely necessary
- Generic types properly constrained
- Return types explicitly declared
- Union types used instead of overloading where appropriate

## Error Handling

- Errors caught at appropriate level
- Error messages are meaningful and actionable
- No silent failures (swallowed exceptions)
- Graceful degradation where appropriate
- Resources properly cleaned up (finally/context managers)
- Custom exception types for domain errors

## Performance

### N+1 Query Prevention
- No database queries inside loops
- Use eager loading / preloading for related data
- Batch queries when fetching multiple records

### General Performance
- No unnecessary allocations in hot paths
- Appropriate data structures chosen
- Caching used for expensive repeated operations
- Async/concurrent processing where beneficial

## Testing Requirements

- Unit tests for business logic
- Integration tests for APIs
- Edge cases covered
- Mocks used appropriately (not overused)
- Test names describe behavior (not implementation)
- Test data is realistic and comprehensive
- Both positive and negative test cases present

## Documentation

- Public APIs documented
- Complex algorithms explained
- Configuration options described
- Examples provided for non-obvious usage
- CHANGELOG updated for user-facing changes
