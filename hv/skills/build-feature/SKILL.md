---
name: build-feature
description: Autonomously implements ONE feature end-to-end — understand, implement, adversarially verify, and open a right-sized PR — inside an isolated worktree. This runs as the main loop of a background feature agent; /hv:launch-agents dispatches it. Invoke directly only when you want to drive a single feature to a PR autonomously in the current session.
argument-hint: <feature spec — JSON from /hv:plan-features, or a plain-text task>
model: opus
disable-model-invocation: true
effort: xhigh
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch
---

# Hv feature worker

## Assignment
$ARGUMENTS

You own this one feature from understanding to PR. You are running in an
isolated worktree (a hv background agent moved here before its first edit, or
you were launched here deliberately), so your work cannot interfere with any
other feature. Drive it to a clean PR without hand-holding — but never claim a
step passed without evidence.

The assignment may be (a) a **path to a JSON spec file** (how `/hv:launch-agents`
invokes you — read the file first), (b) inline JSON, or (c) plain text. For JSON,
honor its fields: `scope`, `target_files`, `do_not_touch`, `success_criteria`,
`risk`, `size_budget`, `branch`. For plain text, infer them and state your
assumptions. If the assignment is a single path ending in `.json`, `Read` it to
get the feature object.

## Context (auto-injected)
- Worktree: !`pwd`
- Branch: !`git branch --show-current 2>/dev/null`
- Repo: !`basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null`
- Base branch: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-base-branch.sh" 2>/dev/null`
- Project conventions: !`test -f CLAUDE.md && echo "CLAUDE.md present — read it before editing" || echo "no CLAUDE.md"`

## Phase 0 — Land on the feature branch

You are in an isolated worktree, but its branch is whatever the host created
(often `worktree-…`). Switch to the feature's intended branch so the PR is named
correctly, creating it from the base branch if needed:

```bash
BR="<branch from spec, e.g. feat/auth-jwt>"
if [ "$(git branch --show-current)" != "$BR" ]; then
  if git rev-parse --verify "$BR" >/dev/null 2>&1; then
    git checkout "$BR"          # branch exists — switch to it
  else
    git checkout -b "$BR"       # create from current (fresh) base
  fi
fi
git branch --show-current
```

`git checkout` (not `git switch`) is used for portability across git versions.

## Phase 1 — Understand (required)

Dispatch an `explorer` subagent to map the files and **existing conventions**
relevant to the feature. For changes the spec marked risky, also dispatch an
`analyzer` to assess blast radius and integration points. Do this before
writing any code — it is the cheapest way to avoid building the wrong thing or
breaking a neighbor.

Answer: which files must change, which patterns to follow, which tests cover
this area, what could break.

## Phase 2 — Implement (test-driven)

Plan the smallest change that fully satisfies `success_criteria`. Then build it.

- **Single-file or tightly-coupled work**: implement it yourself, test-first.
- **Multi-file features with independent slices**: partition into **file-disjoint
  slices** and dispatch one `implementer` subagent per slice, in parallel (one
  `Agent` message, multiple calls). Disjoint files mean their edits land in this
  shared worktree without colliding. Then integrate and reconcile the seams
  yourself.

Stay inside `target_files`; never touch anything in `do_not_touch`. The
`code-quality`, `security-review`, and `codebase-consistency` skills activate
automatically — follow them so the change is clean, safe, and consistent with
the repo.

## Phase 3 — Adversarially verify (the accuracy gate)

Invoke the **adversarial-verification** skill on the completed change. Do not
skip this and do not soften it — it is the reason a hv feature can be trusted
without a human babysitting it. Match rigor to the feature's risk level: an
isolated low-risk change gets a light pass; anything risky gets the multi-lens,
≥3-verifier treatment plus the completeness critic.

If verification returns FAIL, fix and re-verify. Only proceed once it returns
PASS or PASS-WITH-NOTES with acceptable residual risk.

## Phase 4 — Verify the build (evidence required)

Run the project's real checks and capture the actual output:

```bash
if [ -f Makefile ] && grep -qE '^(check|test|ci):' Makefile; then make check 2>&1 || make test 2>&1
elif [ -f package.json ]; then npm test 2>&1 || npm run test 2>&1
elif [ -f pyproject.toml ]; then { command -v uv >/dev/null && uv run pytest 2>&1; } || pytest 2>&1
elif [ -f go.mod ]; then go test ./... 2>&1
elif [ -f Cargo.toml ]; then cargo test 2>&1
else echo "No standard check found — verify the touched paths manually"; fi
```

If checks fail, fix them. Do not open a PR on red.

## Phase 5 — Open the PR

Confirm the diff respects `size_budget` (see the sizing rubric in
`/hv:plan-features`). If it grew well past budget, that is a signal the feature
should have been split — note it in the PR body and keep the PR focused.

```bash
git add -A
git commit -m "$(cat <<'EOF'
<type>(<scope>): <concise summary>

<what changed and why>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push -u origin "$(git branch --show-current)"
gh pr create --title "<type>: <summary>" --body "$(cat <<'EOF'
## Summary
<what this PR does, in one or two sentences>

## Changes
- <change>

## Verification
- <command run> → <result>
- Adversarial verification: <PASS | PASS-WITH-NOTES + residual risk>

## Notes
<deviations from existing patterns + rationale, if any; size note if relevant>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

## Final report

```
result: <feature name> — PR <url> opened (verification: PASS|PASS-WITH-NOTES)
```

Include files changed, the verification verdict, and any residual risk. If you
were blocked and could not open a PR, say so plainly with the blocker — a
half-finished silent PR is worse than an honest stop.
