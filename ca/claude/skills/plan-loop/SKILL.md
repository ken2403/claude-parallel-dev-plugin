---
name: plan-loop
description: Draft an implementation plan for an epic or feature, then spar with Codex to harden it before saving. Use when the user wants to plan a sizable change and have a second model stress-test the plan, or says things like "plan this feature", "draft a plan and spar with Codex", "write an implementation plan for", or invokes /ca:plan-loop. Produces a saved task-by-task plan ready for the ca implement loop.
license: MIT
effort: high
allowed-tools: Read, Grep, Glob, Bash, WebFetch, Agent
---

# plan-loop

Draft a strong implementation plan, sharpen it by sparring with Codex, then save it. This is the planning half of the ca (Cooperate Agents) loop; the saved plan is later built by `$ca-implement-plan` and reviewed by `/ca:review-pr`.

## Step 1 — Draft

Ground the plan in the codebase (read relevant files, dispatch `Explore` agents for unfamiliar areas) and write a task-by-task implementation plan following the superpowers writing-plans conventions: a clear goal, architecture, exact file paths, bite-sized TDD steps with real code/commands, and a self-review. Resolve ambiguities with the human before designing.

Include a `## Milestones` section that groups the tasks into 2–4 natural checkpoints (layer or dependency seams — e.g. "data model", "API", "UI"); the implement loop pushes and gets a Claude checkpoint review at the end of each one, so defects surface before more code is built on top of them. A small plan (roughly 4 tasks or fewer) is a single milestone.

## Step 2 — Spar with Codex (1–2 rounds)

Get an independent, adversarial critique from Codex. **Codex `exec` calls are stateless** — each call forgets the last — so write the FULL current draft plus your specific questions into a prompt file each round, then:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/spar-codex.sh" /path/to/round-N-prompt.md
```

Ask Codex to attack the plan: missing tasks, wrong sequencing, risky assumptions, simpler approaches, failure modes, and whether the milestone grouping/ordering is right (each milestone should leave the tree green and reviewable on its own). Incorporate what holds up; record (don't silently drop) what you reject and why. Repeat once more if the first round surfaced substantial changes.

## Step 3 — Finalize and save

Apply the sparring outcomes, re-run the writing-plans self-review (spec coverage, no placeholders, type/identifier consistency), and save to the ca-owned plan dir (never `docs/superpowers/` — that is superpowers' scratch namespace):

```
docs/ca/plans/YYYY-MM-DD-<feature-name>.md
```

Tell the human the saved path and that the next step is `/ca:implement <plan>` to launch the Codex implement loop. Open a plan PR only if the human asks.

## Notes

- `CODEX_BIN` overrides the `codex` binary if it is not on PATH.
- Sparring runs Codex read-only (no edits) at high reasoning; it is advice, not authority — you own the final plan.
