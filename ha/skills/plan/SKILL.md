---
name: plan
description: Plan ONE feature thoroughly before any code. Use when starting a feature in ha and you want a rigorous, vetted plan you approve before implementation — for a non-trivial change where getting the design and the tests right up front matters more than speed. Accepts a GitHub issue, spec, @file, or free-text task. Invoke explicitly with /ha:plan; hands off to /ha:implement. Requires the superpowers plugin.
argument-hint: '<#issue | "spec text" | @file | natural-language task>'
effort: high
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, WebFetch, Agent, AskUserQuestion
---

# Plan

## Assignment
$ARGUMENTS

You produce a thorough, executable plan for ONE feature — design first, then a
bite-sized implementation plan — and you do not write any feature code here. ha's
thoroughness is **front-loaded**: the design is adversarially red-teamed and every
edge case becomes a required test *before* implementation, so defects are caught as
missing requirements rather than as review findings later. This skill **leverages
superpowers rather than re-implementing it**: it invokes `superpowers:brainstorming`
for the design dialogue and `superpowers:writing-plans` for the plan document.
Requires the `superpowers` plugin.

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
scope is uncertain) to map the files involved, the existing patterns/conventions to
follow, the tests that cover the area, and what could break. For a risky or
cross-cutting change, also dispatch the **`analyzer`** subagent and record its
**risk grade** (LOW / MEDIUM / HIGH) — it scales the red-team in Phase 3.5 and the
pre-PR check in `/ha:implement`. Record each assumption in one line.

## Phase 3 — Design dialogue (leverage brainstorming)

**REQUIRED SUB-SKILL:** Use `superpowers:brainstorming` for the design dialogue
ONLY — its clarifying questions one topic at a time (via `AskUserQuestion`), 2-3
approaches with trade-offs and a recommendation, and per-section design approval.
Keep questioning until no **material** ambiguity remains; when you must use
judgment, state the assumption explicitly.

**Scope contract (do not skip).** Stop brainstorming once the design is agreed. Do
**NOT** let it run its document-writing step — it would write and `git commit` a
separate spec to `docs/superpowers/specs/`, which ha does not use — and do **NOT**
let it invoke `writing-plans` itself; ha owns the single fused document in Phase 4.
You want brainstorming's *dialogue*, not its file output.

**Deviation rule (ha's real delta).** You may propose a **superior architecture** to
what the request assumes, but every deviation from the request must be **explicit**
and justified in the design — never silent. A silent-but-correct deviation is a
defect, because the human approves on the assumption the plan matches intent.

## Phase 3.5 — Red-team the design (front-loaded rigor)

Adversarially review the **design itself**, not just the eventual diff — this is
where ha invests its thoroughness. Apply the `code-review` lens (quality, security,
consistency) to the design, then dispatch `verifier` subagent(s) to **REFUTE** it,
scaled to the `analyzer` risk grade:

- **LOW** — one verifier: "what requirement, edge case, or failure mode is missing?"
- **MEDIUM/HIGH** — use the `adversarial-verification` lens (≥3 verifiers, distinct
  lenses: correctness, security/abuse, ordering/migration). For anything touching
  auth, crypto, user input, secrets, money, or data migration, name the attack
  surface explicitly.

Turn every surviving concern into either an explicit **success criterion** or a
**required test task** in Phase 4. See `references/design-plan-delta.md`.

## Phase 4 — Write the design-plus-plan document (leverage writing-plans)

**REQUIRED SUB-SKILL:** Use `superpowers:writing-plans` to write the bite-sized,
TDD-structured plan (its header, File Structure, per-task Files/Interfaces/RED→GREEN
steps, No-Placeholders rule, inline Self-Review). **Pass the location override**
`docs/ha/plans/YYYY-MM-DD-<feature>.md` (writing-plans honors a caller's location).

**Fused doc, one gate.** ha diverges from superpowers' two-doc spec→plan model:
capture the agreed design as a short **Design** section at the top of the single
plan doc (chosen approach, explicit deviations, risk grade, the red-team's residual
risks), then the writing-plans body. Do not write a separate spec file.

**Front-load test rigor.** Every edge case and failure mode surfaced in Phase 2/3.5
**MUST** appear as an explicit test task (RED→GREEN) in the plan — not left to the
implementer's discretion. Where the toolchain supports coverage, state the coverage
expectation as a success criterion. This is the point of ha's thoroughness: the plan
already encodes how the feature will be proven correct.

## Phase 5 — Approval gate (HARD GATE)

Present: the plan path, the proposed branch name (`feat/<slug>`), the file map, the
approach, the risk grade, and the red-team's residual risks. Then call
**`AskUserQuestion`** with options **"Approve & implement"** / **"Adjust"**. On
"Adjust", revise and re-ask. Nothing is implemented from this skill.

On approval, print a one-line hand-off:

```
result: plan ready at docs/ha/plans/<file>.md (risk <LOW|MED|HIGH>) — approved. Next: /ha:implement docs/ha/plans/<file>.md
```
