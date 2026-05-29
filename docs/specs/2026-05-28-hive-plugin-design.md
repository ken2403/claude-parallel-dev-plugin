# Design: `hive` — Opus 4.8-native parallel autonomous feature-dev plugin

Date: 2026-05-28
Author: ken2403 (with Claude Opus 4.8)
Status: Approved direction — building

## Problem

The existing `pw` plugin orchestrates parallel feature development with **tmux + shell
scripts** (`spinup.sh`/`setup-worktree.sh`/`teardown.sh`) and drives workers by injecting
`claude -p "/pw:worker …"` via `tmux send-keys`, polling progress every 30s with a
`status-monitor` subagent. This predates the modern Claude Code primitives. As of
2026-05 (Claude Opus 4.8, Claude Code v2.1.x) the platform provides native facilities
that make the tmux/script layer obsolete and the workflow both more robust and more
isolated.

We want a **new plugin, co-located alongside `pw`** (pw left untouched), that lets a user:

1. Develop **many features in parallel**, each in a **fully independent, non-interfering**
   environment.
2. **Guarantee accuracy** of each parallel feature via multi-pass adversarial verification.
3. Run review **autonomously** all the way to **PR creation**.
4. Keep **PR / job size** right-sized so PRs stay fast to review and merge.
5. Never produce security-unsafe, inconsistent, or repo-contradicting code.
6. At **design time**, be free to propose a better architecture than the existing code
   (not bound by current conventions), while implementation stays consistent with the repo.

## Verified platform facts this design relies on (2026-05-28)

- **Opus 4.8** (`claude-opus-4-8`): 1M context, 128k output (300k via Batch). Adaptive
  thinking only (`thinking:{type:"adaptive"}`); manual extended-thinking returns 400.
  `output_config.effort` levels `low|medium|high|xhigh|max`, default `high`. Anthropic:
  **start at `xhigh` for coding/agentic**, use `low` for subagents. ~4x less likely than
  4.7 to overlook code flaws; better tool-triggering; better long-context/compaction.
- **Commands merged into Skills**: `skills/<name>/SKILL.md` is the recommended form; command
  frontmatter (`argument-hint`, `allowed-tools`, `disable-model-invocation`, `model`,
  `effort`, …) lives on skills.
- **Subagents**: `Agent` tool (formerly `Task`). Frontmatter `model|effort|tools|isolation|
  maxTurns|…`. `isolation: worktree` gives an isolated checkout (branched from default
  branch, auto-removed if unchanged). **Subagents cannot spawn subagents** — fan-out is one
  level deep. Plugin-shipped agents ignore `hooks|mcpServers|permissionMode`.
- **Agent view / background agents**: `claude --bg "<prompt>"` (flags `--name --model
  --permission-mode --agent`), `claude agents [--json]`, `claude attach|logs|stop|rm <id>`.
  Every background session **auto-moves into `.claude/worktrees/`** before its first edit
  (`worktree.bgIsolation`), survives terminal close, and the dashboard tracks **PR status**.
  `bypassPermissions`/`auto` are refused until accepted once interactively.
- **Inner-layer best practice (researched)**: for parallel *implementation* inside one
  session, **worktree-isolated subagents** are the lowest-risk default (GA, no env var, no
  tmux, same-file-safe). **Agent Teams** are experimental, off by default, env-var + tmux
  gated, and explicitly *not* recommended for parallel implementation (no worktree
  isolation). **Workflows/ultracode** are research-preview + plan-gated. → subagents are the
  shipped default; teams & workflows are opt-in escalations only.
- **Hooks**: `PreToolUse`, `PostToolUse`, `SessionStart`, `Stop`, `SubagentStop`, … exit 2
  blocks with stderr fed back to Claude.

## Approaches considered

- **A. Native background agents + worktree-isolated subagents (CHOSEN).** Orchestrator
  skills design/decompose, then dispatch one `claude --bg` agent per feature (auto worktree
  isolation). Each feature agent orchestrates worktree-isolated implementer/verifier
  subagents internally. All GA, no tmux, no flags. Matches every requirement.
- **B. Single-session Workflow-tool orchestration.** Deterministic but keeps everything in
  one session — weak on "each environment runs independently"; plan/version-gated.
- **C. Agent Teams.** Strong messaging but experimental, no worktree isolation (same-file
  overwrites), not recommended for implementation, needs env var + tmux.
- **D. Modernized tmux.** Keeps the obsolete substrate; not a rebirth.

Chosen: **A**, with B and C as documented opt-in escalations.

## Architecture — three layers

### Layer 0 — Orchestrator (runs in the user's main session)

| Skill | Role |
|---|---|
| `/hive:design` | Intake issue/spec/text → read-only exploration → design doc (free to propose superior architecture, deviations flagged) → risk×independence decomposition into file-disjoint, PR-ready features with per-feature size budget. |
| `/hive:launch` | For each feature, dispatch `claude --bg "/hive:worker <feature-json>"` with `--name`, `--model claude-opus-4-8`, `--permission-mode acceptEdits`. Native auto-worktree isolation ⇒ non-interfering. Records a run manifest. |
| `/hive:status` | `claude agents --json` + `gh pr list` → per-feature table (working / PR-open / merged / error), triage suggestions. |

### Layer 1 — Feature Worker (runs inside each background agent, its own worktree)

`/hive:worker <feature-json>` is the autonomous per-feature loop:

1. **Re-ground** — read CLAUDE.md + conventions in the worktree.
2. **Implement (TDD)** — apply standards skills automatically. For multi-file features,
   fan out **worktree-isolated `implementer` subagents** (one level) over file-disjoint
   pieces for speed; the worker itself is the orchestrator.
3. **Self-review = multi adversarial verification + completeness critic** (accuracy core):
   spawn ≥3 independent `verifier` subagents prompted to *refute* the change; majority-
   refute ⇒ fix loop. Then a completeness critic enumerates "what's missing / unverified";
   findings re-enter the loop. Repeat until clean or budget/round-cap reached.
4. **Verify** — run tests/lint/build; evidence required before any "done" claim.
5. **PR** — commit (conventional) + `gh pr create`. Size already bounded at design time.

### Layer 2 — Standards skills (auto-activating during implement + verify)

- `code-quality`, `security-review`, `codebase-consistency` — modernized ports of the pw
  skills, applied automatically in worker + review.
- `adversarial-verification` — the reusable accuracy harness (refute-oriented multi-verify
  + completeness critic), invoked by the worker and the reviewer.

### Layer 3 — Review / Merge / Cleanup (orchestrator side)

| Skill | Role |
|---|---|
| `/hive:review` | Adversarial PR review (correctness/security/consistency) on a PR number; `--comment` posts inline. |
| `/hive:fix` | Parse review feedback, dispatch parallel fixes (worktree-isolated subagents for 3+ files), update PR. |
| `/hive:merge` | Verify green + reviewed, then merge. |
| `/hive:cleanup` | After merges: `claude rm` finished agents, prune merged worktrees/branches. |

### Subagents (`hive/agents/`)

| Agent | model / effort | tools | isolation | purpose |
|---|---|---|---|---|
| `explorer` | haiku / low | read-only (Read,Grep,Glob,Bash) | — | map codebase/patterns |
| `analyzer` | inherit / high | read-only + WebFetch | — | architecture/impact/dependency analysis |
| `implementer` | inherit / high | Read,Edit,Write,Bash,Grep,Glob | — (shares the worker's already-isolated worktree) | implement one file-disjoint slice |
| `verifier` | inherit / medium | read-only | — | adversarial refutation of a specific claim |

Note: implementers do **not** use `isolation: worktree`. The worker is already in
its own isolated worktree; inner implementers share that tree and are kept
conflict-free by **file-disjoint slicing**. A nested `isolation: worktree` would
branch from the default branch (not the feature branch) and make collecting the
slice's changes back into the feature ambiguous — so disjoint slices in the
shared tree are both simpler and safer.

(Plugin agents omit `hooks/mcpServers/permissionMode` — ignored for plugin agents.)

### Hooks (`hive/hooks.json`)

- `PreToolUse(Edit|Write)` — block edits to protected paths (`.env`, secrets, keys) → exit 2.
- `SessionStart` — (optional) note hive context.
- Cross-platform, language-agnostic (mirrors pw but self-contained).

## Cross-cutting guarantees

- **Non-interference**: top-level background agents each in their own auto-worktree
  (native, between features). Inside a feature, parallel implementer subagents share that
  one worktree but are partitioned into file-disjoint slices, so they never write the same
  file. No shared mutable state between features; no same-file races within a feature.
- **Accuracy**: multi adversarial verify + completeness critic + tests-as-evidence +
  codebase-consistency review. Worker may not claim done without command output.
- **Security & consistency**: protected-file hook; `security-review` + `codebase-
  consistency` auto-applied; implementation stays consistent with repo even when design
  proposed a deviation (deviation is explicit + justified, never silent).
- **Right-sizing (risk × independence)**: design computes, per candidate feature,
  *independence* (file-disjoint? shared entities touched?) and *risk* (auth/crypto/external
  input/data migration/broad cross-cutting change). Low-risk **and** independent ⇒ larger PR
  allowed; high-risk **or** coupled ⇒ split smaller. Rubric lives in
  `skills/design/reference/sizing.md`.
- **Design-time freedom**: `/hive:design` is explicitly allowed to propose a better
  architecture than the current code; deviations are recorded with rationale in the design
  doc so implementation + consistency review can honor them deliberately.

## Effort / model policy (Opus 4.8)

- Orchestrator skills & worker main loop: `model: opus` (`claude-opus-4-8`), `effort: xhigh`,
  adaptive thinking.
- `explorer`/`verifier`: `effort: low|medium` (cheap fan-out).
- `implementer`: `effort: high`.

## Plugin packaging

- New plugin **co-located** in `hive/` subdirectory (pw stays at repo root, untouched).
- `hive/.claude-plugin/plugin.json` (name `hive`, version `0.1.0`).
- Root `.claude-plugin/marketplace.json` gains a second entry `{name:"hive", source:"./hive"}`.
- Self-contained scripts under `hive/scripts/` (no `../` references — cache-safe).

## Out of scope (YAGNI)

- Rewriting or removing `pw`.
- Shipping Agent Teams / Workflow orchestration as defaults (documented as opt-in only).
- A custom GUI/dashboard (the native `claude agents` view is used).

## File manifest

```
hive/
  .claude-plugin/plugin.json
  skills/
    design/SKILL.md            design/reference/sizing.md
    launch/SKILL.md
    worker/SKILL.md
    status/SKILL.md
    review/SKILL.md
    fix/SKILL.md
    merge/SKILL.md
    cleanup/SKILL.md
    adversarial-verification/SKILL.md
    code-quality/SKILL.md
    security-review/SKILL.md
    codebase-consistency/SKILL.md
  agents/{explorer,analyzer,implementer,verifier}.md
  hooks.json
  scripts/{detect-base-branch.sh,agents-status.sh}
  README.md
docs/specs/2026-05-28-hive-plugin-design.md   (this file)
```
