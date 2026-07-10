# Design + plan delta (ha-specific)

This file holds **only what ha adds** on top of the invoked superpowers skills. It
deliberately does **not** restate `superpowers:writing-plans` (header format, task
structure, No-Placeholders, Self-Review) or `superpowers:brainstorming` (question
discipline, approach exploration) — read those skills for that.

ha's whole bet is **front-loading rigor**: catch the defect as a missing
requirement or a missing test at plan time, not as a REFUTED verdict in review.
Everything below serves that.

## The fused document shape

ha produces ONE document at `docs/ha/plans/YYYY-MM-DD-<feature>.md`, not a separate
spec + plan. Structure:

```
# <Feature> Plan

## Design                 ← ha addition (short; the brainstorming outcome)
- Chosen approach: <2-4 sentences>
- Explicit deviations from the request: <each one + why>  (omit if none)
- Risk grade: <LOW | MEDIUM | HIGH>  (from the analyzer)
- Residual risks (post red-team): <what survived Phase 3.5 + how it's mitigated>

<then the full superpowers:writing-plans body: Goal / Architecture / Tech Stack /
 Global Constraints, File Structure, and the bite-sized TDD Tasks — produced by
 INVOKING that skill, not by hand>
```

## Red-team the design (Phase 3.5)

Adversarial review of the *design*, before any code. Scale to the analyzer's grade:

- **`code-review` lens** on the design — conventions respected (`Grep`/`Glob` to
  confirm)? error paths and edge cases designed, not deferred? anything reinvented
  the repo already provides?
- **`verifier` refutation** — dispatch verifier(s) to break the design: a missing
  requirement, an unhandled modality, an ordering/migration hazard, an abuse case.
  LOW → one verifier; MEDIUM/HIGH → the `adversarial-verification` lens (≥3
  verifiers, distinct lenses).
- **Security surface** — if the feature touches auth, crypto, user input, secrets,
  file paths, money, or external calls, name the attack surface in the Design's
  residual risks and add a success criterion for it.

Every surviving concern becomes a success criterion OR a required test task. Nothing
is left as "the reviewer will catch it later" — that is the axis ha is correcting.

## Front-loaded test rigor (Phase 4)

The plan must encode *how the feature is proven correct*, not delegate it:

- Each edge case / failure mode from Phase 2 and the Phase 3.5 red-team is an
  explicit **test task** with the intended assertion, not a vague "add tests" step.
- **Test strategy is declared per task, deviations named.** RED→GREEN TDD is the
  default for new behavior; a task may instead declare `characterization`
  (refactor — pin current behavior first), `test-after` (interface only stabilizes
  with the code), or `e2e` (no unit seam), each with a one-line reason. What makes
  LLM-built code correct is tests-as-context plus executable checks — procedural
  RED→GREEN everywhere is ceremony on tasks that don't fit it.
- Tests assert **real behavior**, not mocks of the thing under test.
- Where the toolchain supports coverage (e.g. `pytest --cov`, `go test -cover`,
  `jest --coverage`), state the coverage expectation for the touched code as a
  success criterion so `/ha:implement`'s build gate can check it.

## Deviation-logging rule

ha's plan skill is free to propose a **better** architecture than the request
assumes. The rule: **every deviation is explicit**. If you change the data model,
the boundaries, or the approach the requester implied, list it under "Explicit
deviations" with the reason. A silent deviation — even a correct one — is a defect,
because the human approves the plan on the assumption it matches intent.
