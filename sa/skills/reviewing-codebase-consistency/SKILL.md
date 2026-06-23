---
name: reviewing-codebase-consistency
description: Reviews PR changes against the broader codebase to find inconsistencies, missed propagation, and stale references beyond the diff. Replicates senior reviewer codebase knowledge. Activates when reviewing PRs, checking consistency, or when changes touch shared entities across multiple files.
allowed-tools: Read, Grep, Glob, Bash
metadata:
    author: ken2403
    version: 1.0.0
---

# Reviewing Codebase Consistency

A senior reviewer has the full codebase in their head. When they read a diff, they instantly know what other files should also change. This skill replicates that by building codebase context around the diff and checking for inconsistencies.

## When to apply

Apply on every PR review. The value scales with PR size and cross-cutting concerns.

## Workflow

Copy this checklist and track progress:

```
Codebase Consistency Review:
- [ ] Step 1: Build codebase context
- [ ] Step 2: Run local build
- [ ] Step 3: Trace change propagation
- [ ] Step 4: Check related files outside the diff
- [ ] Step 5: Verify cross-layer consistency
- [ ] Step 6: Compile findings
```

### Step 1: Build codebase context

1. Read the PR description to understand **intent** — what is this PR trying to accomplish?
2. From the diff, extract **changed entities**: renamed identifiers, modified types/interfaces, altered DB schemas, changed API contracts, modified configurations
3. For each changed entity, use Grep and Glob to map its **usage graph** — every file that imports, references, extends, or depends on it
4. Compare the usage graph against the diff file list. Files in the usage graph but NOT in the diff are **candidates for missed changes**.

This is the most critical step. The usage graph is what a senior reviewer holds in their head.

### Step 2: Run local build

Run the project's build, lint, and typecheck commands to collect concrete errors. Detect the appropriate commands from the project structure (Makefile, package.json, pyproject.toml, Cargo.toml, go.mod, etc.).

Build errors provide a mechanical safety net that catches every compile-time inconsistency that code reading alone might miss. Categorize errors by file and type.

### Step 3: Trace change propagation

For each changed entity from Step 1, verify the change has propagated to ALL dependent code:

- **Data model changes** → query code, serializers, API responses, form fields, test fixtures, mock data, seed data
- **API contract changes** → frontend components, integration tests, API clients, documentation
- **Schema/migration changes** → List all migrations in execution order. Verify no migration that runs AFTER a rename/drop references old entity names. Check migrations added on the base branch since the PR branched.
- **Type/interface changes** → implementations, callers, type assertions, casts
- **Configuration changes** → all readers of the configuration, environment-specific configs

For detailed propagation paths by change type, see [references/propagation-paths.md](references/propagation-paths.md).

### Step 4: Check related files outside the diff

For each candidate file identified in Step 1 (in usage graph but not in diff):

1. Read the file
2. Check if it uses the old version of any changed entity
3. If it does, report it as a missed change with file:line and what needs updating

Also check for files that are in the diff but only **partially updated** — for example, a variable was renamed but string literals or form field references using the old name were not.

### Step 5: Verify cross-layer consistency

Check that changes are consistent across all layers of the application:

- **DB layer ↔ ORM/model layer**: Schema changes reflected in model definitions, relation names, query code
- **Backend ↔ API contract**: Changed types/routes reflected in API specifications, response shapes
- **API contract ↔ Frontend**: Changed API responses reflected in frontend types, form fields, display logic
- **Code ↔ Tests**: Changed behavior reflected in unit tests, integration tests, E2E tests, mock/fixture data
- **Code ↔ Configuration**: Changed features reflected in config files, permissions, feature flags

### Step 6: Compile findings

Output structured findings:

```
PR_INTENT: [one-line summary of what the PR is trying to accomplish]
CHANGED_ENTITIES: [list of entities modified by the diff]
BUILD_ERRORS: [categorized list or "none"]
MISSED_FILES: [file:line list with what needs updating, or "none"]
PARTIAL_UPDATES: [file:line list with what was missed, or "none"]
CROSS_LAYER_ISSUES: [list or "none"]
MIGRATION_ORDERING: [conflicts or "none"]
```

## Report format

For each finding:
- **Severity**: Critical / High / Medium / Low
- **Location**: file:line
- **Issue**: Brief description
- **Suggestion**: Specific fix
