---
name: codebase-consistency
description: Checks a change against the BROADER codebase beyond the diff — missed propagation (a renamed or changed entity not updated everywhere), stale references, inconsistent patterns, logic duplicated instead of reusing existing helpers, and docs/types/configs that drift from the change. Replicates the senior reviewer who holds the whole repo in their head. Use this whenever you implement or review a change, especially one touching a shared entity used across files. Auto-activates during /hive:worker and /hive:review.
allowed-tools: Read, Grep, Glob, Bash
---

# Codebase Consistency

A senior reviewer carries the whole codebase in their head: reading a diff, they instantly know which *other* files should have changed too. A model only sees the diff. This skill rebuilds that mental map from the diff outward, so the change stays consistent with the repo — which is a core hive guarantee. Where the design deliberately deviates from an existing pattern, that is fine, but the deviation must be explicit and documented, never a silent inconsistency that looks like an oversight.

Apply this both while implementing (so you propagate your own change) and while reviewing (so you catch what the author missed). The value scales with PR size and how cross-cutting the change is.

## Workflow

Track progress with this checklist:

```
- [ ] 1. Build codebase context (intent + changed entities + usage graph)
- [ ] 2. Run build / lint / typecheck
- [ ] 3. Trace change propagation
- [ ] 4. Inspect files outside the diff
- [ ] 5. Verify cross-layer consistency
- [ ] 6. Compile findings
```

### Step 1 — Build codebase context

1. Read the PR/task description to understand **intent** — what is this change for?
2. From the diff, extract the **changed entities**: renamed identifiers, modified types/interfaces, altered DB schemas, changed API contracts or function signatures, modified config keys.
3. For each entity, `Grep`/`Glob` its **usage graph** — every file that imports, calls, extends, or references it.
4. Subtract the diff's file list from that usage graph. Files in the graph but NOT in the diff are **suspects for missed updates**.

This is the most important step — the usage graph is exactly what the senior reviewer holds in their head.

### Step 2 — Run build / lint / typecheck

Detect and run the project's commands (Makefile, `package.json` scripts, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.). The compiler is a mechanical safety net: it catches every compile-time inconsistency that reading alone can miss. Categorize errors by file and cause. (In dynamic languages without a compiler, lean harder on Steps 3–4.)

### Step 3 — Trace change propagation

For each changed entity, confirm the change reached *everything* downstream:

- **Data model** → query code, serializers, API responses, form fields, validators, test fixtures, mock/seed data.
- **API contract / signature** → all callers, frontend clients, integration tests, generated clients, docs.
- **Schema / migration** → list migrations in execution order; ensure none running *after* a rename/drop still references the old name. Check migrations added on the base branch since this branch forked.
- **Type / interface** → implementers, callers, casts, type assertions.
- **Config key / flag / env var** → every reader, plus environment-specific configs and example/`.env.sample` files.

### Step 4 — Inspect files outside the diff

For each suspect file from Step 1: `Read` it, check whether it still uses the old form of any changed entity, and if so report it as a missed change with `file:line` and what to update.

Also catch **partial updates inside the diff** — e.g. a symbol renamed in code but the old name lingers in string literals, log messages, error text, comments, doc comments, or serialized keys. These compile fine and slip through tests, which is exactly why they need a human-like sweep.

### Step 5 — Verify cross-layer consistency

Confirm the change is coherent across layers:

- **DB ↔ model/ORM**: schema reflected in model definitions, relations, queries.
- **Backend ↔ API contract**: changed types/routes reflected in specs and response shapes.
- **API contract ↔ frontend**: changed responses reflected in frontend types, forms, display logic.
- **Code ↔ tests**: changed behavior reflected in unit/integration/E2E tests and fixtures.
- **Code ↔ docs/config**: changed behavior reflected in README, docstrings, config, feature flags.

Also watch for **reinvented logic** — if the change adds a helper that duplicates an existing one (`Grep` for similar names/signatures), flag it to reuse the existing one. Duplicated logic drifts apart and is how two code paths silently disagree.

### Step 6 — Compile findings

```
INTENT:            one-line summary of the change's goal
CHANGED_ENTITIES:  entities modified by the diff
BUILD_ERRORS:      categorized list, or "none"
MISSED_FILES:      file:line + what to update, or "none"
PARTIAL_UPDATES:   file:line + what was missed, or "none"
CROSS_LAYER_ISSUES: list, or "none"
DUPLICATED_LOGIC:  existing helper that should be reused, or "none"
MIGRATION_ORDERING: conflicts, or "none"
```

## Report format

For each finding:
- **Severity**: Critical / High / Medium / Low
- **Location**: `file:line`
- **Issue**: what is inconsistent and why it matters
- **Suggestion**: the specific update to make
