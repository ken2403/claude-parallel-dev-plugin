---
name: design
description: Turn a GitHub issue, spec file, or free-text request into a design and a decomposition into independent, right-sized, parallel-executable features for the hive. Use this first, before launching any parallel work. Free to propose a better architecture than the current code; sizes each feature by risk and independence. Outputs a feature manifest that /hive:launch consumes.
argument-hint: '[#issue-number | "spec text" | @path/to/spec.md]'
model: opus
effort: xhigh
allowed-tools: Read, Grep, Glob, Bash, WebFetch, Agent
---

# Hive design & decomposition

## Input
$ARGUMENTS

You produce two things: a **design** (what to build and why) and a
**decomposition** (a set of independent features the hive can build in
parallel). Get these right and the rest of the pipeline runs unattended; get
them wrong and you waste a fleet of agents.

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

Dispatch `explorer` subagents (in parallel for breadth) to map the relevant
code, conventions, and module boundaries. For anything risky or cross-cutting,
add an `analyzer` to surface dependencies and blast radius. You decompose far
better when you know where the real seams in the codebase are.

## Step 3 — Design (you may propose a better solution)

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
```

## Step 4 — Decompose into independent features

Split the work into features that can each become **one PR, built in parallel**.
Each feature MUST be:

1. **File-disjoint** — no two features modify the same file. This is what lets
   them run in separate worktrees without interfering.
2. **Logically complete** — produces working, testable, independently mergeable code.
3. **Clearly scoped** — unambiguous boundaries; a worker knows exactly what it owns.

Avoid: arbitrary line-count splits, circular dependencies between features,
over-granular decomposition (more than ~6 features is usually a smell). If two
candidate features must touch the same file, either merge them or sequence them
(`depends_on`).

### Size each feature by risk × independence

Right-sizing keeps PRs fast to review and safe to merge. Read
`reference/sizing.md` for the rubric and apply it per feature — low-risk and
independent work may be a larger PR; high-risk or coupled work must be split
smaller. Record the resulting `size_budget` and `risk` on each feature.

## Step 5 — Emit the feature manifest

Output the manifest as a fenced ```json block (this is what `/hive:launch`
consumes) followed by the human-readable design. Use this schema:

```json
{
  "epic": "<short name>",
  "base_branch": "<detected base>",
  "features": [
    {
      "id": "auth-jwt",
      "branch": "feat/auth-jwt",
      "scope": "Add JWT issuance + verification middleware",
      "target_files": ["src/auth/jwt.ts", "src/auth/middleware.ts"],
      "do_not_touch": ["src/db/**", "src/api/routes/**"],
      "success_criteria": ["tokens signed/verified", "401 on invalid", "unit tests pass"],
      "risk": "high",
      "size_budget": { "max_files": 4, "max_lines": 250 },
      "depends_on": []
    }
  ]
}
```

Then present a short summary table (feature, risk, size, dependencies) and the
recommended launch order. End by pointing the user to run **`/hive:launch`** with
the manifest (or to review/edit the manifest first).
