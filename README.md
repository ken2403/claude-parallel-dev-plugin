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
| **`hv`** | Opus 4.8-native, massively-parallel **autonomous** feature development: plan → launch background agents → build/verify → PR → auto-clean, with multi-pass adversarial verification. | `/plugin install hv@claude-parallel-dev-plugin` | [hv/README.md](hv/README.md) |
| **`sa`** | **Simple Agents** — command-free skills + subagents for fast single-feature work: digest a plan, get your approval, isolate in a worktree, implement, and open a PR. The interactive, lightweight counterpart to `hv`. | `/plugin install sa@claude-parallel-dev-plugin` | [sa/README.md](sa/README.md) |

New to this? Pick **`sa`** for a single, simple feature you want done fast with a quick
approval gate; reach for **`hv`** when you want an autonomous fleet building many features
in parallel. Both are Opus 4.8-native and need no tmux.

## Try a plugin locally (without installing)

```
claude --plugin-dir /path/to/claude-paralell-dev-plugin/hv
claude --plugin-dir /path/to/claude-paralell-dev-plugin/sa
```

## Repository layout

```
.
├── .claude-plugin/marketplace.json   # marketplace manifest (lists the plugins below)
├── hv/                               # the hv plugin (its own .claude-plugin/plugin.json, skills, agents, …)
├── sa/                               # the sa plugin (its own .claude-plugin/plugin.json, skills, agents, hooks)
├── CLAUDE.md                         # maintainer guidance for this repo
└── README.md                         # this file
```

Each plugin is self-contained under its own directory with its own
`.claude-plugin/plugin.json`. The marketplace manifest at the repo root points to
each one via its `source` path. To add another plugin, create a new directory,
give it a `.claude-plugin/plugin.json`, and add an entry to `marketplace.json`.
