---
name: plan
description: Plan ONE feature thoroughly before any code — turn a GitHub issue, spec, @file, or free-text task into a vetted design and an executable, bite-sized implementation plan. Use when you want ha's rigorous up-front planning (a design dialogue that asks clarifying questions until requirements are unambiguous, security and quality vetting, and a single approved design-plus-plan doc) rather than a quick hand-off. Invoke explicitly with /ha:plan; hands off to /ha:implement.
argument-hint: '<#issue | "spec text" | @file | natural-language task>'
effort: high
allowed-tools: Read, Grep, Glob, Bash, WebFetch, Agent, AskUserQuestion
---

# Plan

## Assignment
$ARGUMENTS

You produce a thorough, executable plan for ONE feature — design first, then a
bite-sized implementation plan — and you do not write any feature code here.
This skill **leverages the superpowers disciplines rather than re-implementing
them**: it invokes `superpowers:brainstorming` for the design dialogue and
`superpowers:writing-plans` for the plan document, and adds ha's design-vetting
and the single approval gate on top. Requires the `superpowers` plugin.

## Context (auto-injected)
- Repo root: !`git rev-parse --show-toplevel 2>/dev/null`
- Current branch: !`git branch --show-current 2>/dev/null`
- Base branch: !`bash "${CLAUDE_SKILL_DIR}/scripts/detect-base-branch.sh" 2>/dev/null`
- Conventions: !`test -f CLAUDE.md && echo "CLAUDE.md present — read it before designing" || echo "no CLAUDE.md"`

## Phase 1 — Resolve the input

- `#<n>` → `gh issue view <n>` for the body and discussion.
- `@<path>` or a file path → `Read` it.
- Otherwise treat `$ARGUMENTS` as the request text.

Restate the goal in 2-3 sentences. This is read-only — you are in the main checkout.

## Phase 2 — Explore ground truth (read-only)

Dispatch the built-in **`Explore`** subagent (one, or several in parallel when
scope is uncertain) to map the files involved, the existing patterns/conventions
to follow, the tests that cover the area, and what could break. For a risky or
cross-cutting change, also dispatch the **`analyzer`** subagent for blast radius,
dependencies, and migration/compatibility concerns. Record each assumption in one
line — it carries into the plan.

## Phase 3 — Design dialogue

**REQUIRED SUB-SKILL:** Use `superpowers:brainstorming` to run the design
dialogue — clarifying questions one topic at a time (via `AskUserQuestion`),
2-3 approaches with trade-offs and a recommendation, and incremental approval of
each design section. Keep questioning until no **material** ambiguity remains; when
you must use judgment, state the assumption explicitly and proceed.

**ha additions on top of brainstorming:**
- Vet the chosen design through ha's standards before locking it in — apply the
  **`code-review`** lens (quality, security, consistency) and, for a risky design,
  the **`adversarial-verification`** lens (what would make this design wrong?).
  Fold the findings into the plan's success criteria.
- You may propose a **superior architecture** to what the request assumes — but
  every deviation from the request must be **explicit** and justified in the
  design, never silent.

See `references/design-plan-delta.md` for the design-vetting checklist and the
deviation-logging rule.

## Phase 4 — Write the design-plus-plan document

**REQUIRED SUB-SKILL:** Use `superpowers:writing-plans` to write the bite-sized,
TDD-structured implementation plan (its header, File Structure, per-task
Files/Interfaces/RED→GREEN steps, No-Placeholders rule, and the inline
Self-Review). **Pass the location override** `docs/ha/plans/YYYY-MM-DD-<feature>.md`
(writing-plans honors a caller's plan-location preference).

**ha delta — one fused doc, one gate:** ha deliberately diverges from superpowers'
two-document spec→plan model (a separate `docs/superpowers/specs/` spec). Instead,
capture the agreed design as a short **Design** section at the top of the single
plan doc (chosen approach, explicit deviations, risks), followed by the
writing-plans body. Rationale: a single feature deserves one document and one
approval gate, not two. Do not write a separate spec file. Detail in
`references/design-plan-delta.md`.

## Phase 5 — Approval gate (HARD GATE)

Present: the plan path, the proposed branch name (`feat/<slug>`), the file map,
and the approach. Then call **`AskUserQuestion`** with options
**"Approve & implement"** / **"Adjust"**. On "Adjust", revise and re-ask. Nothing
is implemented from this skill.

On approval, print a one-line hand-off:

```
result: plan ready at docs/ha/plans/<file>.md — approved. Next: /ha:implement docs/ha/plans/<file>.md
```
