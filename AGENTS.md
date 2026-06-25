# claude-parallel-dev-plugin

A Claude Code **plugin marketplace** (`.claude-plugin/marketplace.json`) shipping
plugins for parallel development. Each plugin is self-contained in its own
directory with its own `.claude-plugin/plugin.json`; the root holds only
marketplace-level files (`marketplace.json`, `README.md`, this file, `.gitignore`).

- **`sa`** — "Simple Agents": command-free skills + subagents for fast single-feature work (digest plan → approve → worktree → implement → PR; review cycle is on-demand), in `sa/`. See `sa/README.md`.
- **`hv`** — Opus 4.8-native rewrite using background agents + worktree isolation, in `hv/`. See `hv/README.md`.
- **`ca`** — "Cooperate Agents": a Claude×Codex loop shipped as two co-located plugins (`ca/claude/`, `ca/codex/`). See `ca/README.md`.

Keep the plugins independent; don't let edits to one leak into another. To add
a plugin, create a new top-level dir with its own plugin manifest and add an
entry (with its `source` path) to the relevant marketplace.

> **Instruction-file convention:** `AGENTS.md` (this file) is the canonical,
> cross-tool instruction source (open standard; read by Codex and 30+ tools).
> `CLAUDE.md` is a symlink to it, so Claude Code reads the same content. Edit
> `AGENTS.md` only; never edit `CLAUDE.md` directly.

## hv layout

- `hv/.claude-plugin/plugin.json` — the only file in `hv/.claude-plugin/`.
- `hv/skills/<name>/SKILL.md` — skills (also the slash commands `/hv:<name>`). `reference/` holds progressively-disclosed detail.
- `hv/agents/<name>.md` — subagents (`analyzer`, `implementer`, `verifier`, `janitor`).
- `hv/scripts/*.sh`, `hv/scripts/validate_manifest.py` — self-contained helpers.
- `hv/hooks.json` — PreToolUse secret-file guard.

## sa layout

- `sa/.claude-plugin/plugin.json` — the only file in `sa/.claude-plugin/`.
- `sa/skills/<name>/SKILL.md` — skills (also the slash commands `/sa:<name>`): `simple-feature`, `review-pr`, `apply-feedback`, `resolve-conflicts`, `clean-worktrees`, and `code-review`. **Scripts are skill-local** under `sa/skills/<name>/scripts/`, referenced via `${CLAUDE_SKILL_DIR}` (aliased to `CLAUDE_SKILL_SA_DIR` in skill bodies); detail lives in `references/`. Shared helpers (`detect-base-branch.sh`, `merge-check.sh`, `attach-or-create-worktree.sh`) are duplicated byte-identically into each skill that needs them.
- `sa/agents/<name>.md` — subagents (`implementer` opus·effort medium, `verifier` opus·effort high). No `janitor`/`analyzer` — sa stays light.
- `sa/hooks/{hooks.json,guard-protected.sh}` — PreToolUse secret-file guard (only plugin-level script, referenced via `${CLAUDE_PLUGIN_ROOT}`).
- **Model/effort**: all Opus, graded — `simple-feature` medium, `review-pr` high, `apply-feedback` medium, `resolve-conflicts` high, `implementer` medium, `verifier` high, `clean-worktrees` **haiku**, `code-review` omits both (standards skill).
- **Worktrees**: created explicitly by `simple-feature/scripts/new-worktree.sh` under `.claude/worktrees/sa/<slug>` (vs hv's background auto-isolation). `apply-feedback` and `resolve-conflicts` run in the same isolation via `attach-or-create-worktree.sh`, which **reuses** the branch's existing sa worktree or **creates** one (and **refuses** if the branch is checked out in the main checkout) — they never `gh pr checkout`/merge into the user's working copy. Every write skill enforces the absolute-path rule (edit only under `$WORKTREE_PATH`, `git -C`). `simple-feature` **stops at PR**; the review cycle (`review-pr`/`apply-feedback`) and `resolve-conflicts` are on-demand. `code-review` is the single standards skill (quality/security/consistency): auto-activates in the main loop and is **preloaded** into the `implementer`/`verifier` subagents via their `skills:` frontmatter (subagents don't auto-activate skills by description).

## Authoring rules (learned the hard way)

- **Identity by name field**: a skill's `name:` MUST equal its directory; an agent's `name:` MUST equal its filename. Validation and references break otherwise.
- **YAML frontmatter**: single-quote values starting with `[` (e.g. `argument-hint`); avoid a bare `: ` (colon-space) in plain scalars — both break the parser.
- **Side-effecting / irreversible skills** (`launch-agents`, `build-feature`, `apply-feedback`, `merge-pr`, `clean-agents`, `watch-merges`) set `disable-model-invocation: true` so they run only on explicit invocation.
- **Subagents are one level deep** — a subagent cannot spawn subagents, and cannot use `Agent` / `AskUserQuestion`. Do all fan-out at the skill's top level; ask the human from the skill's main loop, not a subagent.
- **Plugin subagents ignore** `hooks`, `mcpServers`, `permissionMode`. A subagent's `cd` does not persist between Bash calls — use `git -C <root>` / absolute paths.
- **No nested `claude --bg`**: a session spawning sessions is unsupported. `launch-agents` emits commands for the human; background sessions auto-isolate into `.claude/worktrees/` on first write.
- **Scripts must be self-contained** (no `../` to the repo root) and referenced via `${CLAUDE_PLUGIN_ROOT}` — keeps them cache-safe.
- **Single source of truth**: cleanup/guardrail logic lives in `agents/janitor.md`; the review judgment axis lives in `skills/review-pr/SKILL.md`. Reference them; don't duplicate.
- **No time-sensitive info**: use the `opus` model alias, not a pinned ID like `claude-opus-4-8`.
- **Security**: never weaken the secret-file guard (`hv/scripts/guard-protected.sh`); never let cleanup delete a running agent or unmerged work.

## Validate before committing

- `claude plugin validate ./hv` (and `./sa`, `./ca/claude` if you touched them) — must pass.
- Skill `name:` ↔ directory and agent `name:` ↔ filename all match.
- `bash -n hv/scripts/*.sh sa/skills/*/scripts/*.sh sa/hooks/*.sh`; `python3 hv/scripts/validate_manifest.py <manifest>` for manifest changes.
- Each `SKILL.md` body stays **under 500 lines** (push detail to `reference/`).

## Git

- Branch off the default branch (e.g. `feat/<topic>`); commit/push only when asked.
- End commit messages with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Working on the ca plugin

`ca` ("Cooperate Agents") is a Claude×Codex loop: **Claude drafts a plan and spars
with Codex → Codex implements an epic in an isolated git worktree → Claude reviews
the diff vs. the plan (≤2 rounds) → Codex opens a PR with an exchange summary →
human merges → worktree cleaned up.** It ships as two co-located plugins so each
tool scans only its own skills.

**Layout**

- `ca/claude/` — Claude Code plugin (`.claude-plugin/plugin.json`, skills `/ca:plan-loop`, `/ca:review-diff`, `/ca:start`).
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
- `plan-loop` (Claude): `opus` / `xhigh`. `review-diff` (Claude): `opus` / `high`. `start` (Claude): `effort: low`.

**Loop rules**

- Review capped at 2 rounds (`MAX_ROUNDS` default 2).
- Implementation runs in a `ca/<plan-id>` worktree created by `new-worktree.sh` (a script, never the model, never `main`).
- **Both plugins are required.** The Codex skill implements; it calls the Claude plugin's `/ca:review-diff` via `claude -p`. So `claude-review.sh` needs `/ca:review-diff` resolvable — the ca Claude plugin installed in the user's config, or `CA_CLAUDE_PLUGIN_DIR` set so it passes `--plugin-dir`. Installing only one side makes every review round fail.
- Codex runs `-s workspace-write -c approval_policy=never` for implementation (no `gh`). The review step calls `claude -p`, which **needs network** — Codex's `workspace-write` sandbox blocks it, so the review must run where network is allowed (network-permitted Codex launch/approval for that command, or run `claude-review.sh` on the host). `claude-review.sh` fails loudly, naming both possible causes (skill-not-installed / network), if no review is produced. Capture `thread_id` from `codex exec --json`; resume by id, **never `--last`**.
- Handoff contract: `ca_claude_review.v1` JSON (see `ca/claude/skills/review-diff/references/review-contract.md`); validated by `validate-review.py`; missing/malformed → treat as `blocked` (fail-closed).
- Self-containment: `review-contract.md` and `new-worktree.sh` are intentionally duplicated into each skill that needs them (skills must be portable when copied); keep the copies byte-identical.

**Validate the ca plugins before committing**

- `claude plugin validate ./ca/claude` — must pass.
- Codex skill frontmatter: allowed keys only, `name` == folder, `description` ≤1024 with no `<>`. If PyYAML is available, run `~/.codex/skills/.system/skill-creator/scripts/quick_validate.py ca/codex/skills/ca-implement-plan`.
- `bash -n ca/**/*.sh ca/install.sh`; `python3 -m py_compile` every bundled `*.py`; `ca/install.sh --dry-run`.
- No README inside any skill folder; no leftover identifiers from the previous working name.
