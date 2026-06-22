# ca — Cooperate Agents (Claude × Codex loop)

`ca` ships **two co-located plugins** that make Claude and Codex cooperate on one feature, end to end:

```
Claude  /ca:plan-loop  ──spar with Codex (codex exec)──▶  saved plan
                                                              │
Claude  /ca:start <plan>  ──creates ca/<id> worktree, prints kickoff──┐
                                                              ▼
Codex   $ca-implement-plan PLAN=<abs>   (inside the worktree)
   ├─ implement the plan task-by-task (TDD), no network, no gh
   ├─ claude-review.sh ─▶ Claude /ca:review-diff ─▶ ca_claude_review.v1 JSON
   ├─ address blocking findings, re-review     (≤ 2 rounds)
   └─ open a PR + post the Claude/Codex exchange summary
Human merges ─▶ worktree + branch cleaned up
```

The implementing Codex session keeps continuous memory across rounds; state also lives in files
(`plan.md`, `round-N.diff`, `review-round-N.json`) so the loop is reproducible. Claude review runs
on the host (it has web search); Codex stays sandboxed (`-s workspace-write`, no network/no `gh`).

## Layout

```
ca/
  claude/                 # Claude Code plugin (/ca:plan-loop, /ca:review-diff, /ca:start)
    .claude-plugin/plugin.json
    skills/{plan-loop,review-diff,start}/   # each: SKILL.md + its own scripts/ (+ references/)
  codex/                  # Codex plugin ($ca-implement-plan)
    .codex-plugin/plugin.json
    skills/ca-implement-plan/               # SKILL.md + agents/openai.yaml + scripts/ + references/
  install.sh              # install the Codex skill into ~/.codex/skills; print the Claude install
```

Each skill is a self-contained folder (scripts bundled inside it) so it stays portable when copied
or distributed independently.

## Install

**Claude Code plugin** (plan + review side):

```bash
/plugin install ca@claude-parallel-dev-plugin     # from the marketplace
# or, for local development:
claude --plugin-dir /path/to/repo/ca/claude
```

**Codex plugin** (implement side):

```bash
bash ca/install.sh            # copies the skill into ~/.codex/skills, then: restart Codex
bash ca/install.sh --force    # overwrite an existing install
```

A Codex plugin manifest (`ca/codex/.codex-plugin/plugin.json`) and marketplace entry
(`.agents/plugins/marketplace.json`) are also provided for plugin-aware Codex installs; the
`install.sh` copy is the dependable route.

## Use

1. `bash ca/install.sh && bash ca/install.sh --claude` — install both, restart Codex.
2. In Claude: `/ca:plan-loop "<your epic>"` → spars with Codex, saves a plan.
3. In Claude: `/ca:start <plan>` → creates the worktree, prints the Codex command.
4. In a Codex session in that worktree (use a strong model + high reasoning):
   `$ca-implement-plan PLAN=<abs-plan-path>` → implements, gets Claude review (≤2 rounds), opens a PR.
5. Merge the PR; the worktree and branch are cleaned up.

## The handoff contract

Claude review returns a single `ca_claude_review.v1` JSON object (verdict + `blocking` findings);
a `blocking: true` finding gates the PR; missing/malformed output is treated as `blocked`
(fail-closed). The contract lives in each skill's
`references/review-contract.md`, validated by `validate-review.py`.

## Environment overrides

- `CODEX_BIN` — path to `codex` if it is not on `PATH` (e.g. a version-manager shim).
- `CLAUDE_BIN` — path to `claude` for the host-side review call.
- `CODEX_HOME` — where the Codex skill installs (default `~/.codex`).
- `CA_BASE` — base branch for the worktree (default `main`).
