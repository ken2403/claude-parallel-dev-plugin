# Design + plan delta (ha-specific)

This file holds **only what ha adds** on top of the invoked superpowers skills.
It deliberately does **not** restate `superpowers:writing-plans` (header format,
task structure, No-Placeholders, Self-Review) or `superpowers:brainstorming`
(question discipline, approach exploration) — read those skills for that. Adding
a copy here would just drift from the canonical versions.

## The fused document shape

ha produces ONE document at `docs/ha/plans/YYYY-MM-DD-<feature>.md`, not a
separate spec + plan. Structure:

```
# <Feature> Plan

## Design                 ← ha addition (short; the brainstorming outcome)
- Chosen approach: <2-4 sentences>
- Explicit deviations from the request: <each one + why>  (omit if none)
- Risks & mitigations: <the analyzer / adversarial-verification findings>

<then the full superpowers:writing-plans body verbatim from that skill:
 the header (Goal / Architecture / Tech Stack / Global Constraints),
 File Structure, and the bite-sized TDD Tasks>
```

The Design section is a few hundred words at most. Everything below it is owned
by `superpowers:writing-plans` — produce it by invoking that skill, not by hand.

## Design-vetting checklist (run before writing Phase 4)

Apply ha's standards to the *design*, not just the eventual code, and fold each
finding into a task or a success criterion:

- **`code-review` lens** — does the design respect existing conventions
  (`Grep`/`Glob` to confirm)? Are error paths and edge cases designed, not
  deferred? Is anything reinvented that the repo already provides?
- **Security (non-negotiable)** — if the feature touches auth, crypto, user
  input, secrets, file paths, or external calls, name the attack surface in the
  Design's Risks and add an explicit success criterion for it.
- **`adversarial-verification` lens (risky designs only)** — ask "what would make
  this design wrong?" before committing to it: a missed requirement, an
  unhandled modality, an ordering/migration hazard. Turn each into a task.

## Deviation-logging rule

ha's plan skill is free to propose a **better** architecture than the request
assumes. The rule: **every deviation is explicit**. If you change the data model,
the boundaries, or the approach the requester implied, list it under "Explicit
deviations" with the reason. A silent deviation — even a correct one — is a
defect, because the human approves the plan on the assumption it matches intent.
