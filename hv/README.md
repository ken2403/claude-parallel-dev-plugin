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
| Many features in parallel | one `claude --bg` agent per feature, dispatched by `/hv:launch-agents` |
| Fully independent / non-interfering | every background agent auto-isolates in its own `.claude/worktrees/` checkout |
| Accuracy guaranteed | `adversarial-verification`: independent skeptics try to *refute* each change + a completeness critic, looping until it survives |
| Autonomous → PR | `/hv:build-feature` runs understand → implement → verify → PR by itself |
| Right-sized PRs | `/hv:plan-features` sizes each feature by **risk × independence** |
| Safe & consistent | auto-applied `security-review` + `codebase-consistency` skills; a hook blocks edits to secrets |
| Better designs, not just patches | `/hv:plan-features` may propose a superior architecture; deviations are explicit, never silent |

---

## The flow

```
/hv:plan-features  →  /hv:launch-agents  →  (agents run /hv:build-feature in parallel)  →  /hv:agent-status
                                                                              │
                                            /hv:review-pr → /hv:apply-feedback → /hv:merge-pr → /hv:clean-agents
```

1. **`/hv:plan-features <#issue | "spec" | @file>`** — explores the codebase, writes a
   design (free to propose a better architecture), and decomposes it into
   file-disjoint, risk-sized features. Outputs a JSON **feature manifest**.
2. **`/hv:launch-agents <manifest>`** — validates the manifest (no shared files, no
   dependency cycles), then dispatches one background agent per feature in
   dependency waves. Each runs `/hv:build-feature`.
3. **`/hv:build-feature <feature>`** *(runs inside each agent)* — lands on the feature
   branch, understands the code, implements (test-driven; fans out `implementer`
   subagents over disjoint slices for speed), **adversarially verifies**, runs the
   build, and opens a right-sized PR.
4. **`/hv:agent-status`** — one table of every agent + its PR, with triage suggestions.
5. **`/hv:review-pr <pr> [--comment]`** — independent adversarial review.
6. **`/hv:apply-feedback <pr>`** — applies review feedback (parallel for 3+ files), updates PR.
7. **`/hv:merge-pr <pr>`** — merges only when approved + green + mergeable.
8. **`/hv:clean-agents`** — stops finished agents, prunes merged worktrees/branches
   (never touches unmerged work).

---

## Components

**Skills** (`/hv:*`): `plan-features`, `launch-agents`, `build-feature`,
`agent-status`, `review-pr`, `apply-feedback`, `merge-pr`, `clean-agents`, plus
auto-activating standards: `adversarial-verification`, `code-quality`,
`security-review`, `codebase-consistency`. The side-effecting skills
(`launch-agents`, `build-feature`, `apply-feedback`, `merge-pr`, `clean-agents`)
set `disable-model-invocation` so they run only when you call them explicitly,
never by accidental auto-trigger.

**Subagents**: `analyzer` (architecture & risk, high effort), `implementer`
(one file-disjoint slice), `verifier` (adversarial, refute-oriented).
Read-only codebase scouting uses Claude Code's built-in `Explore` agent rather
than a bundled one.

**Hook**: `PreToolUse(Edit|Write)` blocks edits to `.env`/secrets/keys.

**Effort policy (Opus 4.8)**: orchestrator skills and the worker run at `xhigh`
with adaptive thinking; the verifier runs cheap (`medium`);
implementers at `high`.

---

## Requirements

- Claude Code with background agents / agent view (`claude --bg`, `claude agents`).
- `git` (worktrees), `gh` (PRs), `python3` (manifest validation in
  `/hv:launch-agents`), and ideally `jq` (richer `/hv:agent-status`).
- **Permissions for hands-off runs:** background agents auto-accept edits with
  `--permission-mode acceptEdits` but auto-deny other prompts. For fully
  unattended `git push` / `gh pr create`, allow those in your settings, or accept
  `bypassPermissions` once interactively and relaunch with
  `--dangerously-skip-permissions`. `/hv:launch-agents` surfaces this.

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
