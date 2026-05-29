# Feature sizing rubric (risk × independence)

The goal is PRs that are **fast to review and safe to merge**. A PR's right size
is not a fixed line count — it depends on how risky the change is and how
independent it is from the rest of the system. Use this rubric to set each
feature's `risk` and `size_budget`.

## Step 1 — Score risk

A feature is **high risk** if it touches any of:

- authentication / authorization / sessions
- cryptography, secrets, key handling
- money, billing, payments
- PII or other regulated data
- data migrations or schema changes (esp. destructive/irreversible)
- untrusted external input reaching a sink (injection surface)
- concurrency, locking, or ordering-sensitive code
- broad cross-cutting refactors (touches many modules)

**Medium risk**: meaningful business logic with limited blast radius.
**Low risk**: additive, well-isolated, easily tested code (a new pure module,
docs, a self-contained component) with no risk markers.

When unsure, round **up** — the cost of over-cautious splitting is small; the
cost of a sprawling risky PR is large.

## Step 2 — Score independence

- **Independent**: file-disjoint from all other features; touches no shared
  entity (shared types, config, public interfaces, generated code).
- **Coupled**: would share files or shared entities with another feature, or
  changes a contract other features depend on.

Coupled features either get merged into one feature or sequenced with
`depends_on` — they must not run as parallel siblings touching the same file.

## Step 3 — Set the size budget

| Risk \ Independence | Independent | Coupled |
|---|---|---|
| **Low**    | larger OK — `max_files ~8, max_lines ~400` | medium — `~5 / ~250`, or sequence |
| **Medium** | medium — `max_files ~5, max_lines ~250` | small — `~3 / ~150`, sequence |
| **High**   | small — `max_files ~3, max_lines ~150`, isolate the risky core | smallest — `~2 / ~80`, sequence + extra verification |

These numbers are defaults, not hard gates. The real test: **can a reviewer hold
the whole change in their head and be confident it is correct?** If not, split.

## Step 4 — Split when over budget

When a candidate feature exceeds its budget, split along natural seams in this
preference order:

1. **Isolate the risky core** — pull the high-risk part into its own small PR
   that gets extra adversarial verification; keep the low-risk remainder larger.
2. **By module / layer boundary** — disjoint directories or layers.
3. **Interface first, then consumers** — land the new interface/contract as one
   PR, then build callers on top (sequenced with `depends_on`).
4. **Behavior-preserving refactor first** — separate "move/rename" from "change
   behavior" so each PR is easy to reason about.

Never split by arbitrary line count alone — a split that severs a single logical
change into two non-working halves is worse than one slightly-large PR.
