# ha — Higher Agents

A command-free Claude Code plugin for getting **one feature built thoroughly**: plan it
deeply (design red-teamed, edge cases turned into required tests), implement it behind a
per-task review loop *and* a risk-scaled pre-PR adversarial gate, get an independent
review, apply feedback rigorously, and merge behind a gate. The **thorough** counterpart to
[`sa`](../sa/README.md) — same single-feature, foreground, in-the-loop shape, heavier at
every phase.

## Install

```
/plugin install ha@claude-parallel-dev-plugin
```

Or try it locally without installing:

```
claude --plugin-dir /path/to/claude-paralell-dev-plugin/ha
```

**Requirements:** `git`, the GitHub CLI (`gh`, authenticated), and — importantly — the
**`superpowers`** plugin (from the official Claude Code plugins marketplace). `ha` does not
vendor the superpowers disciplines; it **invokes** them, so they must be installed — if
`superpowers` is absent, the `REQUIRED SUB-SKILL: Use superpowers:…` steps will not resolve
and the skill stops. `ha` is model-agnostic (it inherits whatever model your session runs —
use your strongest, e.g. Opus).

## Why ha

Not every feature should be rushed. Where `sa` optimizes for speed (digest a given plan →
approve → implement → PR, review on demand), `ha` optimizes for **getting it right**: it
questions you until the design is unambiguous, red-teams the plan and turns edge cases into
required tests *before* coding, reviews each task as it lands, and runs a risk-scaled
adversarial gate before the PR. It leverages the proven `superpowers` disciplines rather
than reinventing them, and adds its rigor where defects are actually born — the plan — not
only at the end.

## The flow

```
/ha:plan <#issue | "spec" | @file | task>
   explore → design dialogue (superpowers:brainstorming) → bite-sized plan
   (superpowers:writing-plans) → vet for quality+security → APPROVE GATE
     → /ha:implement <plan>
         worktree → per-task loop (superpowers:subagent-driven-development)
           → risk-scaled pre-PR adversarial gate → build gate → PR → STOP

on demand:
   /ha:review-pr <pr> [--comment]   independent heavyweight review (verifiers +
                                     adversarial-verification + the 5 code-reviewer dims)
     → /ha:apply-feedback <pr>       fix (superpowers:receiving-code-review) + push
   /ha:merge-pr <pr>                 gated merge (approved + green + mergeable)
     → /ha:clean-worktrees           reclaim merged worktrees + branches, safely
   /ha:resolve-conflicts <pr|branch> merge base + resolve in isolation + verify + push
```

`implement` runs its own review loops but still **stops at PR**; `/ha:review-pr` is the
separate, independent second opinion.

## Components

**Skills** (`/ha:<name>`)
- `plan` — design dialogue + bite-sized plan, vetted for quality/security (effort high).
  Invokes `superpowers:brainstorming` + `superpowers:writing-plans`.
- `implement` — worktree → the per-task loop (`superpowers:subagent-driven-development`) →
  a **risk-scaled pre-PR adversarial gate** (lighter than `review-pr`, scaled to the risk
  grade) → verified build → PR (effort high).
- `review-pr` — independent review: verifier subagents + `adversarial-verification` + the
  five code-reviewer dimensions (effort high).
- `apply-feedback` — turn review feedback into committed fixes, with the
  `superpowers:receiving-code-review` discipline (effort high).
- `merge-pr` — gated merge; inherits `superpowers:finishing-a-development-branch`'s
  guardrails (effort low).
- `resolve-conflicts` — merge the base and resolve conflicts in isolation, verified
  (effort high).
- `clean-worktrees` — reclaim merged `ha` worktrees + branches, safely (effort low).
- `code-review` + `adversarial-verification` — the auto-activating standards skills.

**Subagents** (`ha/agents/`)
- `verifier` — adversarial read-only reviewer that tries to refute a claim.
- `analyzer` — read-only architecture/impact analyst.

(The per-task implementer and task-reviewer come from the invoked `superpowers`
subagent-driven-development — `ha` doesn't duplicate them.)

**Hook** — `ha/hooks/` ships a PreToolUse guard that refuses edits/writes to secret files.

## Relationship to sa

| | `sa` (Simple Agents) | `ha` (Higher Agents) |
|---|---|---|
| Goal | one feature, fast | one feature, thorough |
| Plan | digests a given plan | design dialogue + **design red-team** + edge-cases→required tests |
| Implement | subagents → PR (no self-review) | SDD per-task loop **+** risk-scaled pre-PR adversarial gate → PR |
| Review | code-review + on-demand review-pr | + adversarial-verification + the 5 code-reviewer dimensions |
| Disciplines | inlined, light | **invokes** the `superpowers` disciplines (required dependency) |
| Effort | graded (medium build, high review) | high across substantive skills |

Both are foreground, single-feature, model-agnostic, and need no tmux.
