# 🐝 hv

**Opus 4.8-native, massively-parallel autonomous feature development for Claude Code.**

`hv` designs and decomposes work, dispatches **one isolated background agent per
feature**, drives each feature autonomously through implementation and **multi-pass
adversarial verification** to a **right-sized PR**, and gives you review / merge /
cleanup skills to land them — all without tmux and without features stepping on
each other.

It is a ground-up rewrite of the `pw` plugin for the modern Claude Code
primitives (background agents, worktree isolation, the `Agent` tool, effort
control). `pw` is untouched; `hv` is installed alongside it.

---

## Why hv

You want to build many features at once, **guarantee each one is correct**, and
have reviews and PRs happen on their own — with every feature running in a
**fully independent environment** that can't interfere with the others.

hv maps each of those to a native platform capability:

| Goal | How hv does it |
|---|---|
| Many features in parallel | one `claude --bg` agent per feature, dispatched by `/hv:launch` |
| Fully independent / non-interfering | every background agent auto-isolates in its own `.claude/worktrees/` checkout |
| Accuracy guaranteed | `adversarial-verification`: independent skeptics try to *refute* each change + a completeness critic, looping until it survives |
| Autonomous → PR | `/hv:worker` runs understand → implement → verify → PR by itself |
| Right-sized PRs | `/hv:design` sizes each feature by **risk × independence** |
| Safe & consistent | auto-applied `security-review` + `codebase-consistency` skills; a hook blocks edits to secrets |
| Better designs, not just patches | `/hv:design` may propose a superior architecture; deviations are explicit, never silent |

---

## The flow

```
/hv:design  →  /hv:launch  →  (agents run /hv:worker in parallel)  →  /hv:status
                                                                              │
                                            /hv:review → /hv:fix → /hv:merge → /hv:cleanup
```

1. **`/hv:design <#issue | "spec" | @file>`** — explores the codebase, writes a
   design (free to propose a better architecture), and decomposes it into
   file-disjoint, risk-sized features. Outputs a JSON **feature manifest**.
2. **`/hv:launch <manifest>`** — validates the manifest (no shared files, no
   dependency cycles), then dispatches one background agent per feature in
   dependency waves. Each runs `/hv:worker`.
3. **`/hv:worker <feature>`** *(runs inside each agent)* — lands on the feature
   branch, understands the code, implements (test-driven; fans out `implementer`
   subagents over disjoint slices for speed), **adversarially verifies**, runs the
   build, and opens a right-sized PR.
4. **`/hv:status`** — one table of every agent + its PR, with triage suggestions.
5. **`/hv:review <pr> [--comment]`** — independent adversarial review.
6. **`/hv:fix <pr>`** — applies review feedback (parallel for 3+ files), updates PR.
7. **`/hv:merge <pr>`** — merges only when approved + green + mergeable.
8. **`/hv:cleanup`** — stops finished agents, prunes merged worktrees/branches
   (never touches unmerged work).

---

## Components

**Skills** (`/hv:*`): `design`, `launch`, `worker`, `status`, `review`, `fix`,
`merge`, `cleanup`, plus auto-activating standards: `adversarial-verification`,
`code-quality`, `security-review`, `codebase-consistency`.

**Subagents**: `explorer` (read-only scout, Haiku/low effort), `analyzer`
(architecture & risk, high effort), `implementer` (one file-disjoint slice),
`verifier` (adversarial, refute-oriented).

**Hook**: `PreToolUse(Edit|Write)` blocks edits to `.env`/secrets/keys.

**Effort policy (Opus 4.8)**: orchestrator skills and the worker run at `xhigh`
with adaptive thinking; explorers/verifiers run cheap (`low`/`medium`);
implementers at `high`.

---

## Requirements

- Claude Code with background agents / agent view (`claude --bg`, `claude agents`).
- `git` (worktrees), `gh` (PRs), and ideally `jq` (richer `/hv:status`).
- **Permissions for hands-off runs:** background agents auto-accept edits with
  `--permission-mode acceptEdits` but auto-deny other prompts. For fully
  unattended `git push` / `gh pr create`, allow those in your settings, or accept
  `bypassPermissions` once interactively and relaunch with
  `--dangerously-skip-permissions`. `/hv:launch` surfaces this.

---

## Opt-in escalations (not the default)

The default inner parallelism is **worktree-isolated subagents** because they are
generally available, need no flags, and are same-file-safe. Two heavier
mechanisms are available when a job warrants them — neither is shipped on by
default:

- **Agent Teams** (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) — when a feature
  genuinely needs cross-agent negotiation across layers. Note: teams don't
  isolate worktrees, so partition files manually.
- **Dynamic workflows / ultracode** — when the job outgrows a handful of files
  (large audits, broad migrations) and your plan/version supports it.

---

## Relationship to `pw`

`hv` is the modern successor to `pw`. `pw` orchestrates via tmux + shell
scripts; `hv` uses native background agents and the `Agent` tool. Both ship from
this marketplace; pick `hv` for new work.
