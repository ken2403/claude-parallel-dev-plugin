# ca — Cooperate Agents (Claude × Codex loop)

`ca` ships **two co-located plugins** that make Claude and Codex cooperate on one feature, end to end:

```
Claude  /ca:plan-loop  ──spar with Codex (codex exec)──▶  saved plan
                                                              │
Claude  /ca:implement <plan>  ──creates ca/<id> worktree, prints kickoff──┐
                                                              ▼
Codex   $ca-implement-plan PLAN=<abs>   (inside the worktree)
   ├─ implement milestone 1 (TDD) ─ push + open a DRAFT PR
   ├─ per milestone: Claude /ca:review-pr mode=checkpoint ─▶ fix blocking before building on
   ├─ final: Claude-only by default, or CA_DUAL_REVIEW=1:
   │     ├─ Claude /ca:review-pr blind final review
   │     ├─ Codex offline second-opinion review (advisory)
   │     └─ Claude /ca:synthesize-review adjudicates one ca_claude_review.v1 verdict
   ├─ address blocking findings, push, re-review the PR   (≤ 2 final rounds)
   └─ on approve: gh pr ready + post the Claude/Codex exchange summary
/ca:merge-pr (gated) or human merges ─▶ /ca:clean-worktrees reclaims it

Standalone (Claude): /ca:merge-pr [pr], /ca:resolve-conflicts [pr|branch], /ca:clean-worktrees
```

The implementing Codex session keeps continuous memory across rounds; state also lives in files
(`plan.md`, `review-checkpoint-M.json`, `review-round-N.json`) and in the PR itself, so the loop
is reproducible. Plans live in `docs/ca/plans/` (grouped into 2–4 milestones by `/ca:plan-loop`;
small plans are a single milestone and skip checkpoints). Codex implements sandboxed
(`-s workspace-write`); the push, draft-PR, `/ca:review-pr`, and `/ca:synthesize-review` steps
need network + an authenticated `gh`.

> **Network + `gh` note for the review step.** Claude review and synthesis call `claude -p`
> (needs the Anthropic API) and fetch the PR via `gh pr diff` (needs an authenticated `gh`).
> Codex's default
> `-s workspace-write` sandbox **blocks network**, so the review must run where network is allowed
> and `gh` is authenticated: launch Codex for ca with network permitted for that command
> (approval/profile), or run `claude-review.sh` in a host terminal between rounds. `claude-review.sh`
> fails loudly with guidance if no verdict is produced, so an unreachable reviewer is never mistaken
> for a real verdict.

## Layout

```
ca/
  claude/                 # Claude Code plugin (/ca:plan-loop, /ca:implement, /ca:review-pr,
    .claude-plugin/plugin.json          #        /ca:synthesize-review, /ca:merge-pr, ...)
    skills/{plan-loop,implement,review-pr,synthesize-review,code-review,merge-pr,resolve-conflicts,clean-worktrees}/
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
3. In Claude: `/ca:implement <plan>` → creates the worktree, prints the Codex command.
4. In a Codex session in that worktree (use a strong model + high reasoning):
   `$ca-implement-plan PLAN=<abs-plan-path>` → implements milestone by milestone, opens a
   **draft** PR at the first milestone, gets a Claude checkpoint review between milestones,
   then the final `/ca:review-pr` review (≤2 rounds), and on approve marks the PR **ready**.
5. Merge the PR — `/ca:merge-pr [pr]` (gated: refuses drafts/red CI/conflicts) or on GitHub —
   then `/ca:clean-worktrees` reclaims the worktree and branch.

Standalone Claude skills: `/ca:merge-pr [pr]` (gated merge — refuses drafts, red CI, conflicts;
in ca a draft means the review loop has not approved), `/ca:resolve-conflicts [pr|branch]`
(resolve base-branch conflicts in an isolated worktree) and `/ca:clean-worktrees` (reclaim merged
ca worktrees) — the same operations ha ships, adapted to ca.

## The handoff contract

Claude review returns a single `ca_claude_review.v1` JSON object (verdict + `blocking` findings);
a `blocking: true` finding keeps the PR a draft (it is promoted to ready only on a final-mode
approve); missing/malformed output is treated as `blocked` (fail-closed). Checkpoint reviews
(`mode=checkpoint`) use the same contract but only gate continuing to the next milestone — they
never promote the PR. The contract lives in each skill's `references/review-contract.md`,
validated by `validate-review.py`.

## Optional dual-model final review

Set `CA_DUAL_REVIEW=1` to opt into dual-model **final** review rounds. Checkpoints remain
Claude-only progress gates. In a dual final round:

1. `codex-review.sh` fetches PR metadata/diff on the host, builds a bounded prompt, and runs
   `codex exec --sandbox read-only --output-schema` with no network or `gh` access inside Codex.
2. `claude-review.sh` runs the normal blind Claude final review. It does not see Codex's findings.
3. If Codex reports findings, warnings, or partial coverage, `synthesize-review.sh` invokes
   `/ca:synthesize-review`; Claude treats Codex output as untrusted claims and emits the one
   gating `ca_claude_review.v1` verdict.
4. If Codex exits clean with zero findings and full coverage, synthesis is skipped and the blind
   Claude JSON is final. If Codex is unavailable or invalid, the round degrades visibly to
   Claude-only and records the reason in `.ca/runs/<id>/review-round-N.meta.json`.

This adds model diversity, not author independence: Codex wrote the code, and a fresh Codex
review may share model-family blind spots with the implementer. Claude remains the sole verdict
holder. Flip-to-default criterion: after at least 5 real dual PRs, the confirmed-finding rate is
nonzero and the invalid/unavailable rate is below 20%.

## Both plugins are required

The loop only works with **both** sides installed: the Codex skill implements, and it calls the
Claude plugin's `/ca:review-pr` (via `claude -p`) to review. Installing only one side makes every
review round fail. `bash ca/install.sh` with no flags handles the Codex install and prints/checks
the Claude side. If you cannot install the Claude plugin globally, set `CA_CLAUDE_PLUGIN_DIR` so the
review call can load it with `--plugin-dir`.

## Environment overrides

- `CODEX_BIN` — path to `codex` if it is not on `PATH` (e.g. a version-manager shim).
- `CLAUDE_BIN` — path to `claude` for the review call.
- `CA_CLAUDE_PLUGIN_DIR` — path to the `ca/claude` plugin dir; lets `claude-review.sh` load
  `/ca:review-pr` via `--plugin-dir` when the Claude plugin isn't installed globally.
- `CA_DUAL_REVIEW=1` — opt into Codex second-opinion + Claude synthesis for final rounds.
- `CA_CODEX_REVIEW_TIMEOUT` — timeout for the Codex second-opinion leg, default 900 seconds.
- `CA_CODEX_REVIEW_FULL_DIFF_BYTES` — full-diff prompt threshold, default 180000 bytes.
- `CA_CODEX_REVIEW_FALLBACK_PROMPT_BYTES` — structured fallback budget, default 360000 bytes.
- `CODEX_HOME` — where the Codex skill installs (default `~/.codex`).
- `CA_BASE` — base branch for the worktree (default `main`).
