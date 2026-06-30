# claude-parallel-dev-plugin

A **Claude Code plugin marketplace** — a single repository that hosts and manages
multiple parallel-development plugins. Add the marketplace once, then install
whichever plugins you want.

## Add the marketplace

In Claude Code:

```
/plugin marketplace add ken2403/claude-paralell-dev-plugin
```

(The GitHub repo is `claude-paralell-dev-plugin`; the marketplace name declared in
`.claude-plugin/marketplace.json` is `claude-parallel-dev-plugin` — note the
spelling differs.)

## Plugins

| Plugin | What it is | Install | Docs |
|--------|------------|---------|------|
| **`sa`** | **Simple Agents** — command-free skills + subagents for fast single-feature work: digest a plan, get your approval, isolate in a worktree, implement, and open a PR. | `/plugin install sa@claude-parallel-dev-plugin` | [sa/README.md](sa/README.md) |
| **`ha`** | **Higher Agents** — the **thorough** counterpart to `sa` for building ONE feature properly: a deep, red-teamed plan, an SDD per-task loop plus a risk-scaled pre-PR adversarial gate, an independent review, apply-feedback, and a gated merge. Leverages the `superpowers` disciplines (required). | `/plugin install ha@claude-parallel-dev-plugin` | [ha/README.md](ha/README.md) |
| **`ca`** | **Cooperate Agents** — a Claude×Codex loop: draft a plan sparring with Codex, then review the Codex-built diff against it. | `/plugin install ca@claude-parallel-dev-plugin` | [ca/README.md](ca/README.md) |

New to this? Pick **`sa`** for a single feature you want done fast with a quick approval
gate; reach for **`ha`** when you want that same single feature built thoroughly — a deeper
plan gate, layered review loops, and adversarial verification. Both are model-agnostic and
need no tmux (`ha` additionally requires the `superpowers` plugin).

## Try a plugin locally (without installing)

```
claude --plugin-dir /path/to/claude-paralell-dev-plugin/sa
claude --plugin-dir /path/to/claude-paralell-dev-plugin/ha
```

## Repository layout

```
.
├── .claude-plugin/marketplace.json   # marketplace manifest (lists the plugins below)
├── sa/                               # the sa plugin (its own .claude-plugin/plugin.json, skills, agents, hooks)
├── ha/                               # the ha plugin (its own .claude-plugin/plugin.json, skills, agents, hooks)
├── ca/                               # the ca plugin (Claude + Codex sides)
├── CLAUDE.md                         # maintainer guidance for this repo
└── README.md                         # this file
```

Each plugin is self-contained under its own directory with its own
`.claude-plugin/plugin.json`. The marketplace manifest at the repo root points to
each one via its `source` path. To add another plugin, create a new directory,
give it a `.claude-plugin/plugin.json`, and add an entry to `marketplace.json`.
