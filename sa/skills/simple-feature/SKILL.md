---
name: simple-feature
description: Take a plan — a file path or plain-text task — and drive ONE simple feature to an open PR fast. Digests the plan, inspects the codebase, asks you only when genuinely unsure, gets your approval, then creates an isolated worktree, implements with subagents, verifies the build, and opens a PR. Stops at PR for speed; run /sa:review-pr separately to review. Use for small-to-medium implementation tasks. Invoke explicitly with /sa:simple-feature.
argument-hint: '<plan-file-path | natural-language task>'
model: opus
disable-model-invocation: true
effort: medium
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Agent, AskUserQuestion, WebFetch
---

# Simple feature

## Assignment
$ARGUMENTS

You own one simple feature from plan to an open PR. Move fast, but **write nothing
until the human approves the plan**, and never claim a step passed without evidence.
You stop once the PR is open — reviewing is a separate `/sa:review-pr` step.

## Context (auto-injected)
- Repo root: !`git rev-parse --show-toplevel 2>/dev/null`
- Current branch: !`git branch --show-current 2>/dev/null`
- Base branch: !`bash "${CLAUDE_SKILL_DIR}/scripts/detect-base-branch.sh" 2>/dev/null`
- Conventions: !`test -f CLAUDE.md && echo "CLAUDE.md present — read it before editing" || echo "no CLAUDE.md"`

## Phase 1 — Digest the plan

If `$ARGUMENTS` is a path to an existing file, `Read` it; otherwise treat the text as
the plan. Restate, in 2-3 sentences, the **goal**, the **scope**, and the **success
criteria** in your own words. This is read-only — you are still in the main checkout.

## Phase 2 — Inspect the codebase (read-only)

Dispatch the built-in **`Explore`** subagent (one, or several in parallel if scope is
uncertain) to map: which files change, the existing patterns/conventions to follow, which
tests cover the area, and what could break. Resolve small ambiguities from the code and
**record each assumption in one line** (it carries into the PR body's Notes).

## Phase 3 — Clarify gate (ask only when it matters)

If a **material** ambiguity remains that you genuinely cannot settle from the code — a
requirement readable two ways, an unmeasurable success criterion, an unstated error/edge
behavior with real consequences — ask the human with **`AskUserQuestion`** (concrete
options, not open-ended). Skip this phase entirely when there is nothing material to ask.

## Phase 4 — Present the plan and get approval (HARD GATE)

Present the concrete plan:
- branch name (`feat/<slug>` or `fix/<slug>`),
- the files to create/modify,
- the approach and the test strategy,
- any assumptions.

Then call **`AskUserQuestion`** with options **"Approve & implement"** / **"Adjust"**.
**Nothing is written and no worktree is created until "Approve".** On "Adjust", revise
and re-ask. Do not proceed to Phase 5 without approval.

## Phase 5 — Create the isolated worktree (only after approval)

```bash
CLAUDE_SKILL_SA_DIR="${CLAUDE_SKILL_DIR}"   # sa-recognizable alias of the built-in skill dir
eval "$(bash "$CLAUDE_SKILL_SA_DIR/scripts/new-worktree.sh" "feat/<slug>")"
echo "Implementing in: $WORKTREE_PATH on $BRANCH"
```

`new-worktree.sh` prints `WORKTREE_PATH=...` and `BRANCH=...`; `eval` makes both shell
variables available. The worktree is created under `.claude/worktrees/sa/<slug>`.

**Absolute-path rule for the rest of the run:** the main session's cwd stays in the main
checkout, so **every edit targets an absolute path under `$WORKTREE_PATH`**, every test
runs as `cd "$WORKTREE_PATH" && <cmd>` in one Bash call, and every git op uses
`git -C "$WORKTREE_PATH"`.

## Phase 6 — Implement (test-driven, fast)

Plan the smallest change that fully satisfies the success criteria, then build:
- **Single file / tightly coupled**: implement it yourself, test-first, editing absolute
  paths under `$WORKTREE_PATH`.
- **3+ independent files**: partition into **file-disjoint slices** and dispatch one
  **`implementer`** subagent per slice in parallel (one `Agent` message, multiple calls).
  **Pass each implementer the absolute `$WORKTREE_PATH`** and its exact file set; then
  integrate the seams yourself.

The `code-review` standards skill auto-activates — follow it (quality, security,
consistency). Update any docs the repo keeps in step with the code (within scope).

## Phase 7 — Verify the build (objective gate, evidence required)

```bash
cd "$WORKTREE_PATH" && {
  if [ -f Makefile ] && grep -qE '^(check|test|ci):' Makefile; then make check 2>&1 || make test 2>&1
  elif [ -f package.json ]; then npm test 2>&1 || npm run test 2>&1
  elif [ -f pyproject.toml ]; then { command -v uv >/dev/null && uv run pytest 2>&1; } || pytest 2>&1
  elif [ -f go.mod ]; then go test ./... 2>&1
  elif [ -f Cargo.toml ]; then cargo test 2>&1
  else echo "No standard check found — verify the touched paths manually"; fi
}
```

Fix failures. If still red after a fix attempt, open the PR as a **draft** documenting it.

## Phase 8 — Open the PR (end of this skill)

```bash
git -C "$WORKTREE_PATH" add -A
git -C "$WORKTREE_PATH" commit -m "$(cat <<'EOF'
<type>(<scope>): <concise summary>

<what changed and why>

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git -C "$WORKTREE_PATH" push -u origin "$BRANCH"
# add --draft if checks are red
gh pr create --head "$BRANCH" --title "<type>: <summary>" --body "$(cat <<'EOF'
## Summary
<what this PR does, in one or two sentences>

## Changes
- <change>

## Verification
- <command run> → <result>

## Notes
<assumptions; if draft: the blocker and what the human should decide>
EOF
)"
```

Always create the PR (a draft on failure beats a silent half-run). **This is the end of
`simple-feature` — do not review here.** Print a one-line hand-off telling the user to run
`/sa:review-pr <pr>` when they want the (separate, on-demand) review guardrail.

## Final report

```
result: <feature> — PR <url> (<ready|draft>) implemented in <worktree>; build: PASS|FAIL. Next: /sa:review-pr <pr> to review.
```
