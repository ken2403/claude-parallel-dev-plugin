# claude-parallel-dev-plugin

A Claude Code **plugin marketplace** (`.claude-plugin/marketplace.json`) shipping
plugins for parallel development. Each plugin is self-contained in its own
directory with its own `.claude-plugin/plugin.json`; the root holds only
marketplace-level files (`marketplace.json`, `README.md`, this file, `.gitignore`).

- **`sa`** — "Simple Agents": command-free skills + subagents for fast single-feature work (digest plan → approve → worktree → implement → PR; review cycle is on-demand), in `sa/`. See `sa/README.md`.
- **`ha`** — "Higher Agents": the thorough counterpart to `sa` for building ONE feature properly (deep red-teamed plan → SDD per-task loop + risk-scaled pre-PR adversarial gate → independent review → apply feedback → gated merge, plus standalone conflict resolution and worktree cleanup), in `ha/`. Single-feature, foreground, model-agnostic; leverages the `superpowers` disciplines (required dependency). See `ha/README.md`.
- **`ca`** — "Cooperate Agents": a Claude×Codex loop shipped as two co-located plugins (`ca/claude/`, `ca/codex/`). See `ca/README.md`.

Keep the plugins independent; don't let edits to one leak into another. To add
a plugin, create a new top-level dir with its own plugin manifest and add an
entry (with its `source` path) to the relevant marketplace.

## Common generated source

`common/` is maintained source for duplicated mechanical files shipped inside
`ha`, `sa`, and `ca/claude`: shared helper scripts, code-review reference docs,
the `code-review` standards skill (which carries the **canonical risky-surface
list** and the blocking rule "behavior change without a covering test", generated
into `ha` and `sa`), and the mechanical `clean-worktrees` / `merge-pr` skills.
Generated copies stay committed in each plugin so every plugin remains
self-contained and installable alone.

Edit `common/src/`, `common/plugins/<slug>/vars`, or
`common/plugins/<slug>/fragments/`, then run `bash common/sync.sh`. Do not edit
generated copies directly unless you are intentionally changing the rendered
artifact and then back-porting that change into `common/`. `common/manifest.tsv`
lists generated destinations; `common/exclusions.tsv` lists intentional
duplication that must remain plugin-specific, with a reason.

`common/` is not a plugin and must never contain `.claude-plugin/`,
`.codex-plugin/`, or cross-plugin runtime references. `${CLAUDE_PLUGIN_ROOT}` and
`${CLAUDE_SKILL_DIR}` resolve inside an installed plugin only.

> **Instruction-file convention:** `AGENTS.md` (this file) is the canonical,
> cross-tool instruction source (open standard; read by Codex and 30+ tools).
> `CLAUDE.md` is a symlink to it, so Claude Code reads the same content. Edit
> `AGENTS.md` only; never edit `CLAUDE.md` directly.

## ha layout

- `ha/.claude-plugin/plugin.json` — the only file in `ha/.claude-plugin/`.
- `ha/skills/<name>/SKILL.md` — skills (also the slash commands `/ha:<name>`): `plan`, `implement`, `review-pr`, `apply-feedback`, `merge-pr`, `resolve-conflicts`, `clean-worktrees`, plus the auto-activating standards `code-review` and `adversarial-verification`. **Scripts are skill-local** under `ha/skills/<name>/scripts/`, referenced via `${CLAUDE_SKILL_DIR}` (aliased to `CLAUDE_SKILL_HA_DIR` in skill bodies); detail lives in `references/`. Shared helpers (`detect-base-branch.sh` ×4, `attach-or-create-worktree.sh` ×2, `new-worktree.sh`) are duplicated byte-identically into each skill that needs them.
- `ha/agents/<name>.md` — only `verifier` and `analyzer` (the invoked `superpowers:subagent-driven-development` supplies the implementer + task-reviewer). No `janitor` — cleanup is a script.
- `ha/hooks/{hooks.json,guard-protected.sh}` — PreToolUse secret-file guard (only plugin-level script, referenced via `${CLAUDE_PLUGIN_ROOT}`).
- **Single-feature, foreground; model-agnostic.** Every skill **omits** `model` (inherits the session model) and every agent uses `model: inherit` — no pinned IDs, no `opus` alias. **Two documented exceptions pin haiku** because their guardrails are mechanical, not judgment: `clean-worktrees` (only orchestrates `clean.sh`, which owns every rule — merged-only with positive proof, never the main checkout — the current worktree is removed too, but only if merged, run from the main checkout — no `--force`/`-D`) and `merge-pr` (preflight is field-equality checks on `gh pr view` JSON, and `gh pr merge` + branch protection refuse ineligible merges server-side). Effort: substantive skills `high` (`plan`/`implement`/`review-pr`/`apply-feedback`/`resolve-conflicts`); `merge-pr`/`clean-worktrees` `low`; standards skills omit it; `verifier`/`analyzer` `high`.
- **Leverage, not fork — `ha` hard-depends on `superpowers`** and **invokes** its disciplines via `**REQUIRED SUB-SKILL:** Use superpowers:<name>` markers (never `@skills/...` links): `brainstorming` + `writing-plans` (in `plan`; the plan doc is saved to the repo's plan dir — `docs/ha/plans/` by default, a `plan.dir:` CLAUDE.md hint or existing `docs/plans/` if present — **never** under `docs/superpowers/`, and Phase 4 verifies that), `subagent-driven-development` (the per-task loop in `implement`, scoped to stop before SDD's own finish; SDD's own workspace paths are left untouched and its `.superpowers/sdd/` scratch is excluded from the PR — never partially redirected), `verification-before-completion` (build gates), `receiving-code-review` (in `apply-feedback`), `systematic-debugging` (red paths), and `finishing-a-development-branch`'s guardrails (in `merge-pr`/`clean-worktrees`). ha's own power-ups are front-loaded: a **design red-team + test-rigor** pass in `plan` (catch defects as missing requirements/tests, not late review findings), `adversarial-verification`, the auto-activating `code-review`, the constructive-reviewer (SDD) / adversarial-verifier split, and a **risk-scaled pre-PR adversarial gate** in `implement` (deliberately lighter than the independent `/ha:review-pr`, scaled to the analyzer's risk grade — not a second full review).
- **Worktrees**: created by `implement/scripts/new-worktree.sh` under `.claude/worktrees/ha/<slug>` — persistent script-created (NOT native `EnterWorktree`, because they must outlive the session until the PR merges and `/ha:clean-worktrees` finds them by path), with a `using-git-worktrees` Step 0 reuse check. `apply-feedback`/`resolve-conflicts` isolate via `attach-or-create-worktree.sh` (reuse or create, **refuse** the main checkout). `code-review` is preloaded into `verifier` via its `skills:` frontmatter (subagents don't auto-activate skills by description).

## sa layout

- `sa/.claude-plugin/plugin.json` — the only file in `sa/.claude-plugin/`.
- `sa/skills/<name>/SKILL.md` — skills (also the slash commands `/sa:<name>`): `simple-implement`, `review-pr`, `apply-feedback`, `merge-pr`, `resolve-conflicts`, `clean-worktrees`, and `code-review`. **Scripts are skill-local** under `sa/skills/<name>/scripts/`, referenced via `${CLAUDE_SKILL_DIR}` (aliased to `CLAUDE_SKILL_SA_DIR` in skill bodies); detail lives in `references/`. Shared helpers (`detect-base-branch.sh`, `merge-check.sh`, `attach-or-create-worktree.sh`) are duplicated byte-identically into each skill that needs them.
- `sa/agents/<name>.md` — subagents (`implementer` **sonnet**·effort medium, `verifier` **sonnet**·effort high — the cheap fan-out cross-checker, `deep-verifier` **opus**·effort high — escalation only). No `janitor`/`analyzer` — sa stays light; risk grading is an inline heuristic in `simple-implement`, not an agent.
- `sa/hooks/{hooks.json,guard-protected.sh}` — PreToolUse secret-file guard (only plugin-level script, referenced via `${CLAUDE_PLUGIN_ROOT}`).
- **Model/effort**: all-Sonnet cross-checks with targeted Opus escalation — the thesis is **error-rate multiplication**: several cheap, independent checks (mandatory red-green, a risk-scaled pre-PR `verifier` pass in `simple-implement`, three mutually blind `verifier` lenses in `review-pr`) miss less together than one expensive correlated pass. Graded:
  - build & feedback: latest **Sonnet** (`simple-implement`/`apply-feedback`/`implementer` medium);
  - review/verify: **Sonnet** (`review-pr`/`verifier` high) with **deterministic escalation** to `deep-verifier` (**opus**·high) — triggers: risky surface / UNCERTAIN on a would-be-blocking claim / conflicting verifier verdicts; it gets only the unresolved claim, never a re-review;
  - `resolve-conflicts`: **opus**·high (rare, judgment-dense, silent-corruption risk; its integration check dispatches `deep-verifier`);
  - `merge-pr` + `clean-worktrees`: **haiku**·effort low (mechanical guardrails — merge-pr's preflight is field checks on `gh pr view` JSON with `gh`/branch-protection refusing ineligible merges server-side);
  - `code-review`: omits both (standards skill; carries the **canonical risky-surface list** and the blocking rule "behavior change without a covering test" — defined once in `common/src/skills/code-review` and generated into sa and ha; other sa skills reference that list, never re-enumerate it).

  Models are pinned via the `sonnet`/`opus`/`haiku` aliases (not IDs) so they track the latest — `sa` is allowed to pin (unlike model-agnostic `ha`). Note a pin also **downgrades** a stronger session model by design (cost): the Opus look comes from escalation, not the session.
- **Worktrees**: created explicitly by `simple-implement/scripts/new-worktree.sh` under `.claude/worktrees/sa/<slug>`. `apply-feedback` and `resolve-conflicts` run in the same isolation via `attach-or-create-worktree.sh`, which **reuses** the branch's existing sa worktree or **creates** one (and **refuses** if the branch is checked out in the main checkout) — they never `gh pr checkout`/merge into the user's working copy. Every write skill enforces the absolute-path rule (edit only under `$WORKTREE_PATH`, `git -C`). `simple-implement` builds **red-green** (failing test captured before the implementation), runs a **risk-scaled pre-PR cross-check** (inline TRIVIAL/NORMAL/RISKY heuristic → 0/1/2 `verifier`s, one fix round max, fail-safe to a draft PR), then **stops at PR**; the review cycle (`review-pr`/`apply-feedback`) and `resolve-conflicts` are on-demand. `code-review` is the single standards skill (quality/security/consistency): auto-activates in the main loop and is **preloaded** into the `implementer`/`verifier`/`deep-verifier` subagents via their `skills:` frontmatter (subagents don't auto-activate skills by description).

## Authoring rules (learned the hard way)

- **Identity by name field**: a skill's `name:` MUST equal its directory; an agent's `name:` MUST equal its filename. Validation and references break otherwise.
- **YAML frontmatter**: single-quote values starting with `[` (e.g. `argument-hint`); avoid a bare `: ` (colon-space) in plain scalars — both break the parser.
- **Side-effecting / irreversible skills** set `disable-model-invocation: true` so they run only on explicit invocation. In `ha`: `implement`, `apply-feedback`, `merge-pr`, `resolve-conflicts`, `clean-worktrees`. Entry/read-mostly skills (`plan`, `review-pr`) and standards skills do **not** (and standards skills must stay enabled so they can be preloaded into subagents — `disable-model-invocation` also blocks preload).
- **Subagent fan-out stays at the skill top level.** The platform now supports nested subagents (depth limited), but `ha` keeps all fan-out and all human questions (`AskUserQuestion`) in the skill's main loop for predictability — don't rely on a subagent spawning its own.
- **Plugin subagents ignore** `hooks`, `mcpServers`, `permissionMode`. A subagent's `cd` does not persist between Bash calls — use `git -C <root>` / absolute paths.
- **Cross-reference other skills by name**, via `**REQUIRED SUB-SKILL:** Use superpowers:<name>` markers — never `@skills/...` links (they force-load 200k+ tokens). `ha` leverages superpowers this way instead of vendoring it.
- **Scripts must be self-contained** (no `../` to the repo root) and referenced via `${CLAUDE_PLUGIN_ROOT}` (hooks) / `${CLAUDE_SKILL_DIR}` (skill scripts) — keeps them cache-safe.
- **Single source of truth**: in `ha`, cleanup/guardrail logic lives in `clean-worktrees/scripts/clean.sh`; the review judgment axis lives in `code-review` + `skills/review-pr/SKILL.md`. Reference them; don't duplicate.
- **No time-sensitive info**: `ha` is model-agnostic — skills omit `model`, agents use `model: inherit`; never pin an ID like `claude-opus-4-8`.
- **Security**: never weaken the secret-file guard (`<plugin>/hooks/guard-protected.sh`); never let cleanup delete unmerged work.

## Validate before committing

- `claude plugin validate ./ha` (and `./sa`, `./ca/claude` if you touched them) — must pass.
- `bash common/sync.sh --check` and `bash common/tests/run.sh` — generated files
  must match `common/`.
- Skill `name:` ↔ directory and agent `name:` ↔ filename all match.
- `bash -n ha/skills/*/scripts/*.sh ha/hooks/*.sh sa/skills/*/scripts/*.sh sa/hooks/*.sh`.
- Generated helpers stay in lockstep by editing `common/` and rerunning
  `common/sync.sh`; CI enforces this instead of manual `md5` checks.
- Each `SKILL.md` body stays **under 500 lines** (push detail to `references/`).

## Git

- Branch off the default branch (e.g. `feat/<topic>`); commit/push only when asked.
- End commit messages with: `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Working on the ca plugin

`ca` ("Cooperate Agents") is a Claude×Codex loop: **Claude drafts a milestone-grouped plan
(saved to `docs/ca/plans/` — never `docs/superpowers/`) and spars with Codex → Codex implements
it milestone by milestone in an isolated git worktree, opening a draft PR at the first milestone
and getting a Claude checkpoint review (`mode=checkpoint`) between milestones → Claude runs the
final review vs. the plan (≤2 rounds) → on approve Codex marks the PR ready with an exchange
summary → human merges → `/ca:clean-worktrees` reclaims it.**
Plus standalone `/ca:resolve-conflicts` and `/ca:clean-worktrees`, mirroring sa/ha.
It ships as two co-located plugins so each
tool scans only its own skills.

**Layout**

- `ca/claude/` — Claude Code plugin (`.claude-plugin/plugin.json`, skills `/ca:plan-loop`, `/ca:implement`, `/ca:review-pr`, `/ca:merge-pr`, `/ca:resolve-conflicts`, `/ca:clean-worktrees`). `merge-pr`/`resolve-conflicts`/`clean-worktrees` are ported from `ha` but **agent-less** (ca ships no subagents / no `code-review` skill — they verify inline); their `detect-base-branch.sh` copies stay byte-identical.
- `ca/codex/` — Codex plugin (`.codex-plugin/plugin.json`, skill `$ca-implement-plan`).
- `ca/install.sh` — installs the Codex skill into `~/.codex/skills`; prints the Claude install.
- `ca/README.md` — human-facing overview + install for both tools.

**Skill best practices (both tools share the SKILL.md open standard)**

- A skill is a self-contained folder: `SKILL.md` + its own `scripts/` + `references/` (+ `assets/`). Helper scripts live INSIDE the owning skill's `scripts/`, never in a plugin-level `scripts/`.
- No `README.md` inside a skill folder; human READMEs live at the plugin/repo root.
- `SKILL.md` body under 5,000 words; push detail to `references/` (progressive disclosure); critical instructions first.
- Frontmatter `name` = folder name (kebab-case, ≤64). `description` = WHAT + WHEN (real trigger phrases); **no `<` or `>`; < 1024 chars**.
- Codex frontmatter allows only `name, description, license, allowed-tools, metadata` (no `model`/`effort`). Claude additionally allows `model`, `effort`, `disable-model-invocation`, `compatibility`.
- Side-effecting skills: Codex sets `agents/openai.yaml` → `policy.allow_implicit_invocation: false`; Claude sets `disable-model-invocation: true`.

**Model & effort**

- `ca-implement-plan` (Codex): set at session launch (`codex -m <model>`, `~/.codex/config.toml`, profile) — frontmatter can't carry it.
- Claude-side skills are **model-agnostic** (omit `model`; in loop mode the review runs under the `claude -p` session's default model) with **ha-style graded effort**: `plan-loop`/`review-pr`/`resolve-conflicts` `effort: high`, `implement` `effort: medium`, `merge-pr` + `clean-worktrees` pinned **haiku** / `effort: low` (their guardrails are mechanical, not judgment: `clean.sh` owns every cleanup rule — merged-only with positive proof, never the main checkout (the current worktree is removed too, but only if merged, run from the main checkout), no `--force`/`-D` — and merge-pr's preflight is field checks on `gh pr view` JSON with `gh`/branch-protection refusing ineligible merges server-side; in ca a **draft** blocks the merge, since draft = the review loop has not approved).

**Loop rules**

- **Final** review capped at 2 rounds (`MAX_ROUNDS` default 2). **Milestone checkpoint reviews
  don't count against it**: plans group tasks into 2–4 milestones (plan-loop writes a
  `## Milestones` section; ≤4-task plans are a single milestone = no checkpoints); after each
  milestone except the last, Codex pushes and calls `/ca:review-pr` with `mode=checkpoint`
  (`--mode checkpoint` on `claude-review.sh`, output `review-checkpoint-<m>.json`), fixes
  blocking findings before the next milestone, with no checkpoint re-review — the final review
  verifies the fixes. Checkpoint verdicts never promote the PR; only a final-mode approve does.
- Implementation runs in a `ca/<plan-id>` worktree created by `new-worktree.sh` (a script, never the model, never `main`), located under `.claude/worktrees/ca/<plan-id>` to match `sa`/`ha`'s worktree convention (all three share the single `.claude/worktrees/` gitignore).
- **Draft-PR-first loop (the review reviews a *PR*, not a pre-PR diff).** Codex pushes and opens the **draft** PR at the end of the *first milestone* (single-milestone plans: before the final review), then calls `/ca:review-pr`; blocking findings keep it a draft; on a final-mode approve Codex runs `gh pr ready`. The draft state is the fail-closed gate. `/ca:review-pr` fetches the PR via `gh pr diff`, takes `mode=checkpoint|final` (default final; checkpoint judges only the milestones built so far and never flags unbuilt later tasks), and still emits the `ca_claude_review.v1` JSON the loop consumes (and, if a human runs it with no `CA_OUT`, prints an APPROVE/REQUEST-CHANGES summary). If the `pr=` input is absent it auto-detects the current branch's PR.
- **Both plugins are required.** The Codex skill implements; it calls the Claude plugin's `/ca:review-pr` via `claude -p`. So `claude-review.sh` needs `/ca:review-pr` resolvable — the ca Claude plugin installed in the user's config, or `CA_CLAUDE_PLUGIN_DIR` set so it passes `--plugin-dir`. Installing only one side makes every review round fail.
- Codex runs `-s workspace-write -c approval_policy=never` for implementation. The push, draft-PR, and review steps need **network + an authenticated `gh`** (`claude -p` reaches the API; `/ca:review-pr` fetches the PR via `gh pr diff`) — Codex's `workspace-write` sandbox blocks network, so run them where network+gh are allowed (network-permitted Codex launch/approval, or run `claude-review.sh` on the host). `claude-review.sh` fails loudly, naming both possible causes (skill-not-installed / network-or-gh), if no review is produced. Capture `thread_id` from `codex exec --json`; resume by id, **never `--last`**.
- Handoff contract: `ca_claude_review.v1` JSON with an optional `mode` echo (see `ca/claude/skills/review-pr/references/review-contract.md`); validated by `validate-review.py`; missing/malformed → treat as `blocked` (fail-closed).
- Self-containment: `review-contract.md` and `new-worktree.sh` are intentionally duplicated into each skill that needs them (skills must be portable when copied); keep the copies byte-identical.

**Validate the ca plugins before committing**

- `claude plugin validate ./ca/claude` — must pass.
- Codex skill frontmatter: allowed keys only, `name` == folder, `description` ≤1024 with no `<>`. If PyYAML is available, run `~/.codex/skills/.system/skill-creator/scripts/quick_validate.py ca/codex/skills/ca-implement-plan`.
- `bash -n ca/**/*.sh ca/install.sh`; `python3 -m py_compile` every bundled `*.py`; `ca/install.sh --dry-run`.
- No README inside any skill folder; no leftover identifiers from the previous working name.
