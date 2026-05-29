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
| **`pw`** | The original **Parallel Workflow** plugin: generic large-scale parallel development via git worktrees + tmux + Agent Teams. | `/plugin install pw@claude-parallel-dev-plugin` | [pw/README.md](pw/README.md) |

New to this? Start with **`hv`** — it's the modern, Opus 4.8-native successor and
needs no tmux. `pw` remains available for the tmux/Agent-Teams workflow.

## Try a plugin locally (without installing)

```
claude --plugin-dir /path/to/claude-paralell-dev-plugin/hv
claude --plugin-dir /path/to/claude-paralell-dev-plugin/pw
```

## Repository layout

```
.
├── .claude-plugin/marketplace.json   # marketplace manifest (lists the plugins below)
├── hv/                               # the hv plugin (its own .claude-plugin/plugin.json, skills, agents, …)
├── pw/                               # the pw plugin (its own .claude-plugin/plugin.json, commands, skills, …)
├── CLAUDE.md                         # maintainer guidance for this repo
└── README.md                         # this file
```

Each plugin is self-contained under its own directory with its own
`.claude-plugin/plugin.json`. The marketplace manifest at the repo root points to
each one via its `source` path. To add another plugin, create a new directory,
give it a `.claude-plugin/plugin.json`, and add an entry to `marketplace.json`.
