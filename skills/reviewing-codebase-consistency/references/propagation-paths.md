# Change Propagation Paths

When an entity is modified in a PR, verify that the change has propagated to all dependent paths below.

## Entity Rename/Remove

- [ ] All source files importing or referencing the entity
- [ ] All test files referencing the entity
- [ ] All mock, fixture, and seed data using the entity
- [ ] All string literals containing the entity name (form fields, error messages, log messages, API paths, query parameters)
- [ ] All ORM/DB relation and association names
- [ ] All generated type field names that derive from the entity
- [ ] All configuration and environment variable references
- [ ] All end-to-end test data and selectors

## Schema/Migration Change

- [ ] Migration execution order: no migration that runs AFTER a rename/drop references old entity names
- [ ] Migrations added on the base branch since the PR branched do not conflict
- [ ] Schema definition files consistent with migration changes
- [ ] Generated code regenerated after schema changes
- [ ] Database policies, constraints, and indexes recreated for renamed entities

## API Contract Change

- [ ] All API callers updated to use new contract (request shape, response shape, route paths)
- [ ] API documentation or specification files updated
- [ ] Frontend types and data-fetching code updated
- [ ] Integration and E2E tests updated

## Type/Interface Change

- [ ] All implementations of the interface updated
- [ ] All callers passing or receiving the type updated
- [ ] All type assertions and casts updated

## Configuration Change

- [ ] All files reading the configuration updated
- [ ] All environment-specific config files updated
- [ ] Deployment and CI/CD configurations updated
