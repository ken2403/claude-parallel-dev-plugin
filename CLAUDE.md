# claude-parallel-dev-plugin

A Claude Code **plugin marketplace** (`.claude-plugin/marketplace.json`) shipping two
plugins for parallel development. Each plugin is self-contained in its own
directory with its own `.claude-plugin/plugin.json`; the root holds only
marketplace-level files (`marketplace.json`, `README.md`, this file, `.gitignore`).

- **`pw`** — original tmux/shell parallel-workflow plugin, in `pw/` (`pw/agents/`, `pw/commands/`, `pw/skills/`, `pw/hooks/`, `pw/scripts/`). See `pw/README.md`.
- **`hv`** — Opus 4.8-native rewrite using background agents + worktree isolation, in `hv/`. See `hv/README.md`.

Keep `pw` and `hv` independent; don't let edits to one leak into the other. To add
a plugin, create a new top-level dir with its own `.claude-plugin/plugin.json` and
add an entry (with its `source` path) to `marketplace.json`.

## hv layout

- `hv/.claude-plugin/plugin.json` — the only file in `hv/.claude-plugin/`.
- `hv/skills/<name>/SKILL.md` — skills (also the slash commands `/hv:<name>`). `reference/` holds progressively-disclosed detail.
- `hv/agents/<name>.md` — subagents (`analyzer`, `implementer`, `verifier`, `janitor`).
- `hv/scripts/*.sh`, `hv/scripts/validate_manifest.py` — self-contained helpers.
- `hv/hooks.json` — PreToolUse secret-file guard. `hv/routines/` — Cloud Routine templates.

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

- `claude plugin validate ./hv` (and `./pw` if you touched it) — must pass.
- Skill `name:` ↔ directory and agent `name:` ↔ filename all match.
- `bash -n hv/scripts/*.sh`; `python3 hv/scripts/validate_manifest.py <manifest>` for manifest changes.
- Each `SKILL.md` body stays **under 500 lines** (push detail to `reference/`).

## Git

- Branch off the default branch (e.g. `feat/<topic>`); commit/push only when asked.
- End commit messages with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
