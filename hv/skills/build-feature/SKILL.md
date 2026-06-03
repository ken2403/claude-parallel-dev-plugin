---
name: build-feature
description: Autonomously drives ONE feature end-to-end — understand, implement, review-and-fix, and open a right-sized PR — inside its own worktree. Runs as the main loop of a background feature agent (launched by /hv:launch-agents, or directly via `claude --bg "/hv:build-feature ..."` for a single feature). Accepts a spec-file path, inline JSON, a plain-text task, or `<spec> <featurename>`.
argument-hint: '<spec-path | inline JSON | plain task | <spec> <featurename>>'
model: opus
disable-model-invocation: true
effort: xhigh
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch
---

# Hv feature worker

## Assignment
$ARGUMENTS

You own this one feature from understanding to PR. Drive it to a clean PR without
hand-holding — but never claim a step passed without evidence.

The assignment may be:
- a **path to a JSON spec file** (how `/hv:launch-agents` invokes you — `Read` it first; it carries the feature object plus `epic_summary` and `shared_contracts`),
- **inline JSON**,
- **plain text** (a free-form task — infer the fields and state your assumptions), or
- **`<spec> <featurename>`** (a spec/source to draw from plus a name for the feature).

For JSON, honor: `scope`, `target_files`, `do_not_touch`, `success_criteria`,
`risk`, `size_budget`, `branch`, and the whole-picture `epic_summary` /
`shared_contracts`.

## Context (auto-injected)
- Worktree: !`pwd`
- Branch: !`git branch --show-current 2>/dev/null`
- Repo: !`basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null`
- Base branch: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-base-branch.sh" 2>/dev/null`
- Project conventions: !`test -f CLAUDE.md && echo "CLAUDE.md present — read it before editing" || echo "no CLAUDE.md"`

## Phase 0 — Isolation guard, then land on the feature branch

You rely on **native background-agent isolation**: a `claude --bg` / agent-view
session auto-moves into its own `.claude/worktrees/` checkout before its first
write. You do **not** create a worktree yourself.

First, confirm you are actually isolated — otherwise you would edit the user's
working copy directly:

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
case "$ROOT" in
  */.claude/worktrees/*) ;;                    # isolated — good
  *) echo "NOT ISOLATED"; ;;
esac
```

If it prints `NOT ISOLATED` (you were run in a foreground session, or
`worktree.bgIsolation:"none"` is set), **stop before editing** and tell the human
to relaunch you as a background session — e.g. `claude --bg "/hv:build-feature <your task>"`
or type it in the `claude agents` view — so isolation kicks in. Do not edit the
working copy.

Once isolated, switch to the feature's intended branch so the PR is named correctly:

```bash
BR="<branch from spec, e.g. feat/auth-jwt>"
if [ "$(git branch --show-current)" != "$BR" ]; then
  git rev-parse --verify "$BR" >/dev/null 2>&1 && git checkout "$BR" || git checkout -b "$BR"
fi
git branch --show-current
```

`git checkout` (not `git switch`) is used for portability across git versions.

## Phase 1 — Understand the whole + your slice (required)

First **restate the whole picture**: read `epic_summary` and `shared_contracts`
from the spec and state, in a sentence or two, what the epic is and how your
feature fits — so you build something that integrates, not just something that
compiles.

Dispatch Claude Code's built-in `Explore` subagent to map the files and
**existing conventions** relevant to the feature (keeps search out of your main
context). For changes the spec marked risky, also dispatch an `analyzer` for blast
radius and integration points. Answer: which files change, which patterns to
follow, which tests cover this area, what could break.

**Ambiguity sweep**: before building, scan your slice for vagueness the spec left
open — requirements readable two ways, success criteria that aren't measurable,
unstated edge cases / error behavior, and non-functional constraints (performance,
security, compatibility). This is the lighter, self-resolving counterpart to
`/hv:plan-features`' clarify gate: resolve each gap from the existing code and
conventions and **record the assumption in one line** (it carries into the PR
body's Notes), rather than interrogating the human. Escalate — via the same
pause-and-ask as the discrepancy gate below — only for a *material* ambiguity you
genuinely can't settle from the code.

**Discrepancy gate**: check the spec against the *actual* existing code. If the
plan conflicts with reality (a named file/function/contract doesn't exist or works
differently, a `shared_contract` has drifted, the approach can't work as written)
or is genuinely ambiguous, **pause and ask the human** — in a background session
this surfaces as "Needs input". Don't guess past a real conflict. Once the human
confirms (or you've stated a reasonable assumption for a minor gap), finalize and
run to the end.

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

When the change alters behavior, interfaces, or config the repo keeps documented
in step with the code (READMEs, reference docs, doc comments), update those docs
too — in the repo's own doc style, and within `target_files` — since a feature
whose docs lie about it isn't done.

## Phase 3 — Self review-and-fix loop (≤2 rounds, then PR no matter what)

Review your own change the same way `/hv:review-pr` reviews a PR — reuse **its
hybrid judgment axis** (defined there; don't re-invent it), but applied to your
**local diff** (`git diff`) since there's no PR yet:

- **Generic / mechanical → verifier subagents (parallel, keeps main clean)**: broad
  correctness, style/quality, mechanical security patterns (injection/secrets),
  missed call sites, and **code↔docs drift** (behavior/interface/config changes in
  the diff reflected in READMEs, reference docs, and doc comments — see the Phase 2
  doc rule). Run **`adversarial-verification`** here as the accuracy core
  (refute-oriented; scale verifier count to risk). Heavy diff-reading stays in the
  subagents; they return verdicts, not dumps.
- **Context-critical → you, in main**: compliance with `CLAUDE.md` and the repo's
  security guide / conventions, security-critical judgment, and integration with
  the `epic_summary` / `shared_contracts`. The axis: *does judging this need this
  repo's specific guidance or the live context? → keep it in main; is it a generic
  diff-only check? → delegate.*

Fix what's found (1–2 files yourself; 3+ disjoint files via parallel `implementer`
subagents), then re-review. **Cap at 2 rounds** — fan-out multiplies tokens and
two rounds is enough to catch a fix's second-order break. Keep fan-out at this top
level (subagents can't spawn subagents).

After 2 rounds, **open the PR regardless** (Phase 5). If issues remain, open it as
a **draft**, list the residual risk in the body, and ask the human to decide — a
stalled-but-clean feature helps no one, and an honest draft beats silence.

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

If checks fail, fix them. If they're still red after your fix attempts, don't open
a *ready* PR — open a **draft** documenting the failure (Phase 5), so the work is
visible and a human can step in. (A PR is always created; only its draft/ready
state reflects whether checks are green.)

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
# Add --draft if checks are red or the review loop left unresolved issues.
gh pr create --title "<type>: <summary>" --body "$(cat <<'EOF'
## Summary
<what this PR does, in one or two sentences>

## Changes
- <change>

## Verification
- <command run> → <result>
- Self review (adversarial): <PASS | PASS-WITH-NOTES + residual risk>

## Notes
<deviations + rationale; size note if relevant; if draft: the unresolved issue and what the human should decide>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Always create the PR — even on failure, open a **draft** with the blocker in the
body. A half-finished silent run is worse than an honest draft.

## Phase 6 — Wire auto-clean, then hand off

So this feature reclaims itself when it lands, call **`/hv:watch-merges <pr>`** as
your final step. It watches the PR in the background (exponential backoff) and runs
`/hv:clean-agents` once it merges; if the PR is later closed unmerged or stays open
past `--max`, it cleans nothing and just reports.

## Final report

```
result: <feature name> — PR <url> opened (<ready|draft>, verification: PASS|PASS-WITH-NOTES|UNRESOLVED)
```

Include files changed, the verdict, and any residual risk. A PR is always opened;
if it's a draft, state the blocker and what the human should decide.
