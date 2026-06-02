---
name: plan-features
description: Turn a GitHub issue, spec file, or free-text request into a design and the right-sized plan to build it. Judges the epic's total weight and decides whether to keep it as a single PR (small/cohesive work) or decompose it into independent, parallel-executable features for a fleet of agents (large work or separable risky cores) — it does not split by default. Use this first, before launching any work. Free to propose a better architecture than the current code; sizes by risk and independence. Outputs a feature manifest (one or more features) that /hv:launch-agents consumes.
argument-hint: '[#issue-number | "spec text" | @path/to/spec.md]'
model: opus
effort: xhigh
allowed-tools: Read, Grep, Glob, Bash, WebFetch, Agent
---

# Hv design & decomposition

## Input
$ARGUMENTS

You produce two things: a **design** (what to build and why) and a **build plan**
— a manifest of one or more features. You decide which: a small, cohesive epic
stays a **single feature (one PR)**; a large epic, or one with separable risky
cores, is **decomposed into independent features the hv builds in parallel**. Get
these right and the rest of the pipeline runs unattended; get them wrong — by
splitting trivial work into a fleet, or by cramming a sprawling change into one
PR — and you waste effort either way.

## Context (auto-injected)
- Repo: !`basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null`
- Branch: !`git branch --show-current 2>/dev/null`
- Base branch: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-base-branch.sh" 2>/dev/null`

## Step 1 — Resolve the input

- `#N` → `gh issue view N --json title,body,labels` for requirements.
- `@path` → read the file.
- free text → use as the spec.

Extract: objectives, functional + non-functional requirements, constraints,
and explicit success criteria. If the request bundles several unrelated
subsystems, say so and treat each as its own design rather than forcing one.

## Step 2 — Understand the ground truth

Dispatch Claude Code's built-in `Explore` subagents (several in parallel for
breadth) to map the relevant code, conventions, and module boundaries. For
anything risky or cross-cutting, add an `analyzer` to surface dependencies and
blast radius. You decompose far
better when you know where the real seams in the codebase are.

## Step 3 — Clarify until unambiguous (gate)

A plan that a fleet executes unattended must have **no open questions** — every
ambiguity left here becomes a wrong feature built in parallel. Before designing,
interrogate the human until the intent is fully pinned down. Ask **one topic at a
time** (use AskUserQuestion, or plain questions; in a background session this
surfaces as "Needs input" and waits for the human to answer).

Drive out, at minimum:
- requirements that are vague or could be read two ways,
- missing or fuzzy success criteria (what does "done" mean, measurably?),
- edge cases and error behavior,
- non-functional constraints (performance, security, compatibility),
- any intended deviation from existing patterns.

Do not proceed to the design while a material ambiguity remains. If the human
says "use your judgment", state the assumption explicitly and move on.

## Step 4 — Design (you may propose a better solution)

You are **not bound to mirror the existing code**. If a cleaner architecture
serves the goal better, propose it — that is the point of designing rather than
just patching. The one rule: a deviation from existing patterns must be
**explicit and justified** in the design, never silent, so implementation and
the consistency review can honor it deliberately.

Write the design:

```markdown
# Design: <feature/epic name>
## Overview            — what we're building, in a few sentences
## Requirements        — must-have / nice-to-have, with success criteria
## Architecture        — components, data flow, key decisions
## Deviations          — where this departs from current patterns + why (or "none")
## Risks & mitigations
## Shared contracts     — interfaces/types/configs features depend on (the seams between features)
```

### Vet the design for security and quality (bake it in, don't bolt it on)

Review the design through the `security-review` and `code-quality` lenses **now**,
while it's cheap to change, and turn the findings into concrete, testable
`success_criteria` on the affected features — so the standard is built in, not
discovered at review. Examples: "secret read from env, never hardcoded", "all
request input validated server-side", "authorization checks ownership (no IDOR)",
"new behavior covered by tests including edge cases X/Y", "reuses existing helper
Z rather than duplicating". A feature is not "done" until its security/quality
criteria are met, so they belong in the plan.

## Step 5 — Decide: one PR, or decompose?

**Parallel decomposition is a tool, not the default.** It pays off when the epic
is genuinely large or contains separable risky cores; it is pure overhead — extra
branches, specs, PRs, reviews, and merge coordination — when the work fits in a
single reviewable PR. Splitting a small epic into a fleet is as much a smell as
cramming a huge one into a single PR. Judge the **total weight first**, then choose.

### Step 5a — Weigh the whole epic, then choose a path

Estimate the size of the *entire* change (apply `reference/sizing.md` to the epic
as a whole) and pick:

- **Single PR (one feature).** Choose this when the whole epic comfortably fits one
  right-sized, reviewable PR: it is cohesive (one logical change), low-to-medium
  risk, and a reviewer could hold all of it in their head at once. Roughly: the
  total lands within a single feature's `size_budget` for its risk level (e.g.
  low-risk ≲ ~8 files / ~400 lines), with no independent high-risk core worth
  isolating and no natural seam that would make two PRs clearly easier to review
  than one. **This is the right answer for small epics** — emit a manifest with a
  **single feature** covering the whole scope. Do not invent extra features to
  "fill a fleet."
- **Decompose (multiple parallel features).** Choose this only when the epic is too
  large for one reviewable PR, OR it contains a high-risk core worth isolating into
  its own small PR, OR it has genuinely independent parts (file-disjoint, separable
  seams) that benefit from running in parallel. Then continue to Step 5b.

State the decision and the one-line reason ("single PR — cohesive, low-risk, ~3
files" / "decompose — auth core is high-risk and the UI is independent") before
emitting the manifest. When borderline, prefer the **single PR**: one slightly-large
cohesive PR beats two coordinated half-PRs.

**The borderline tie-breaker never overrides risk.** It applies only to
low-to-medium-risk work. A high-risk core, a schema/data-migration or other
contract change, or a broad cross-cutting refactor is **decomposed (isolate the
risky core) no matter how cohesive it feels** — score risk via `reference/sizing.md`
first, and remember `cohesive` ≠ `independent`: a change can be one logical idea
*and* have a large blast radius (a column rename is both), which is exactly the case
that must not be crammed into one PR.

A single-feature manifest is a **first-class outcome** — it flows through the rest
of the pipeline unchanged (`/hv:launch-agents` emits one launch command; or, for a
small cohesive change, the human can skip the fleet and run `/hv:build-feature`
directly on the one spec).

### Step 5b — Decompose into independent features (only when Step 5a chose to split)

Split the work into features that can each become **one PR, built in parallel**.
Each feature MUST be:

1. **File-disjoint** — no two features modify the same file. This is what lets
   them run in separate worktrees without interfering.
2. **Logically complete** — produces working, testable, independently mergeable code.
3. **Clearly scoped** — unambiguous boundaries; a worker knows exactly what it owns.

Give each feature a short kebab-case `id` and set its `branch` to `feat/<id>`.
Keeping that one-to-one means the feature `id`, its `hv/<id>` background-agent
name, its `.hv/specs/<id>.json` spec file, and its `feat/<id>` branch (and PR
head) all share the same key — which is exactly how `/hv:agent-status` and
`/hv:clean-agents` correlate a running agent with its PR and worktree.

Avoid: arbitrary line-count splits, circular dependencies between features,
over-granular decomposition (more than ~6 features is usually a smell — and so is
splitting a small epic that Step 5a should have kept as one PR). If two
candidate features must touch the same file, either merge them or sequence them
(`depends_on`).

### Size each feature by risk × independence

Right-sizing keeps PRs fast to review and safe to merge. Read
`reference/sizing.md` for the rubric and apply it per feature — low-risk and
independent work may be a larger PR; high-risk or coupled work must be split
smaller. Record the resulting `size_budget` and `risk` on each feature.

## Step 6 — Emit the feature manifest

The manifest carries both the **whole picture** (so every feature agent
understands the epic and its own place in it) and the per-feature detail. Use this
schema — top level holds the design summary + shared contracts; each feature holds
its own slice:

```json
{
  "epic": "<short name>",
  "base_branch": "<detected base>",
  "epic_summary": "2-4 sentence summary of the whole epic: goal, the set of features and how they fit, and the shared contracts — embedded into every feature's spec so each agent sees the whole.",
  "shared_contracts": ["src/auth/types.ts: AuthToken interface", "config key AUTH_SECRET"],
  "features": [
    {
      "id": "auth-jwt",
      "branch": "feat/auth-jwt",
      "scope": "Add JWT issuance + verification middleware",
      "target_files": ["src/auth/jwt.ts", "src/auth/middleware.ts"],
      "do_not_touch": ["src/db/**", "src/api/routes/**"],
      "success_criteria": ["tokens signed/verified", "401 on invalid", "secret from env (not hardcoded)", "unit tests incl. expiry/tamper"],
      "risk": "high",
      "size_budget": { "max_files": 4, "max_lines": 250 },
      "depends_on": []
    }
  ]
}
```

`epic_summary` and `shared_contracts` are top-level (written once). `/hv:launch-agents`
copies them into each per-feature spec file so a worker reads "the whole + my slice"
without the rest of the manifest.

**Persist it**: write the manifest to `<repo>/.hv/manifest.json` so `/hv:launch-agents`
can consume it directly:

```bash
mkdir -p "$(git rev-parse --show-toplevel)/.hv"
# write the JSON above to "$(git rev-parse --show-toplevel)/.hv/manifest.json"
```

Then present a short summary table (feature, risk, size, dependencies) and the
recommended launch order, and point the user to run **`/hv:launch-agents`** (review
/edit `.hv/manifest.json` first if desired).

**Single-feature plans:** when Step 5a chose one PR, the manifest still has exactly
one feature and the same path holds — but skip the launch-order talk and tell the
user the lighter-weight options: either run **`/hv:launch-agents`** (one background
agent → one PR, tracked by `/hv:agent-status`), or, since there is nothing to run in
parallel, just build it directly with **`/hv:build-feature .hv/specs/<id>.json`**
(after `/hv:launch-agents` has written the spec) or in this session.
