# sa — Simple Agents

A command-free Claude Code plugin for getting **one simple feature** done fast: hand it a
plan, approve it, and it isolates a worktree, implements with subagents, and opens a PR —
all on Opus 4.8 with effort tuned for speed. The interactive, lightweight counterpart to
[`hv`](../hv/README.md).

## Install

```
/plugin install sa@claude-parallel-dev-plugin
```

Or try it locally without installing:

```
claude --plugin-dir /path/to/claude-paralell-dev-plugin/sa
```

Requirements: `git`, the GitHub CLI (`gh`, authenticated), and Opus 4.8.

## Why sa

Not every task needs `hv`'s autonomous fleet of background agents and multi-pass
adversarial verification. `sa` is the fast path for a **single, well-scoped change** where
you want to stay in the loop: it asks before it builds, gets your approval, then runs to a
PR without hand-holding. Speed comes from graded effort and parallel subagents; quality
comes from one shared standards skill and an on-demand review guardrail.

## The flow

```
(1) /sa:simple-feature <plan | task>
      digest plan -> explore (read-only) -> ask if unsure -> APPROVE GATE
        -> create worktree (.claude/worktrees/sa/<slug>)
          -> implement (you + parallel `implementer` subagents)
            -> run tests -> open PR -> STOP

(2) on demand:
      /sa:review-pr <pr>          independent review (opus/high + `verifier` subagents)
        -> /sa:apply-feedback <pr>   fix + push
          -> merge -> /sa:clean-worktrees   reclaim merged worktrees + branches
```

`simple-feature` deliberately **stops at PR creation** for speed; reviewing is a separate,
explicit step.

## Components

**Skills** (`/sa:<name>`)
- `simple-feature` — plan -> approve -> worktree -> implement -> PR (opus, effort medium).
- `review-pr` — independent correctness/security/consistency review (opus, effort high).
- `apply-feedback` — turn review feedback into committed fixes (opus, effort medium).
- `clean-worktrees` — reclaim merged sa worktrees + branches, safely (haiku).
- `code-review` — the single source of engineering standards (quality, security,
  consistency); **auto-activates** during both implementation and review.

**Subagents** (`sa/agents/`)
- `implementer` — builds one file-disjoint slice in the worktree (inherit model, effort medium).
- `verifier` — adversarial read-only reviewer that tries to refute a claim (inherit, effort high).

**Hook** — `sa/hooks/` ships a PreToolUse guard that refuses edits/writes to secret files
(`.env`, keys, credentials), allowing `*.example`/`*.sample` variants.

**Guardrails for "fast but accurate"** — the bulk implementation runs at medium effort,
but the `code-review` standards (security non-negotiable), an objective build/test gate,
and the on-demand opus/high `review-pr` keep accuracy from regressing.

## Relationship to hv

| | `sa` (Simple Agents) | `hv` |
|---|---|---|
| Scope | one simple feature | a fleet of features in parallel |
| Mode | foreground, human approval gate | autonomous background agents |
| Worktree | explicit, `.claude/worktrees/sa/` | native background auto-isolation |
| Verification | code-review standards + on-demand review-pr | multi-pass adversarial verification |
| Speed dial | graded effort (medium build, high review) | thoroughness-first |

Both are Opus 4.8-native and need no tmux.
