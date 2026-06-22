---
name: start
description: Kick off the ca implement loop for a saved plan — create an isolated git worktree for it and print the exact Codex command to run there. Use when the user has a saved plan and wants to start building it, or says things like "start the ca loop on this plan", "kick off implementation of", "set up the worktree for", or invokes /ca:start. Hands off to a Codex session; it does not implement the plan itself.
license: MIT
effort: low
disable-model-invocation: true
allowed-tools: Read, Bash
---

# start

Prepare an isolated worktree for a saved plan and hand off to Codex. This is the bridge between `/ca:plan-loop` (which produced the plan) and `$ca-implement-plan` (which builds it). It is human-in-the-loop: you set up isolation and print the launch commands; the human runs Codex.

## Step 1 — Create the worktree

Given the plan path, run the bundled script (it creates a `ca/<plan-id>` worktree off the base branch, copies the plan in, and records a checksum):

```bash
bash scripts/new-worktree.sh /abs/path/to/plan.md
```

`CX_BASE` (default `main`) overrides the base branch. The script prints the worktree path and branch.

## Step 2 — Print the Codex kickoff

Report to the human, verbatim, the commands the script printed:

```bash
codex -C "<worktree-path>"
# then in the Codex session:
$ca-implement-plan PLAN=<abs-plan-path>
```

## Step 3 — Recommend the Codex launch settings

The Codex skill cannot set model/effort in its frontmatter, so tell the human to launch Codex with a strong model and high reasoning, e.g.:

```bash
codex -C "<worktree-path>" -m <strong-model> -c model_reasoning_effort=high
```

State clearly: this hands control to a Codex session that implements the plan, calls Claude (`/ca:review-diff`) for review over at most 2 rounds, and opens a PR. Do not attempt to implement the plan from here.
