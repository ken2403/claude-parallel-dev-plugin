---
name: implement
description: Implement an approved ha plan for ONE feature and open a PR — thoroughly. Use after /ha:plan (or with a plan file or task) when you want ha's heavy build — an isolated worktree, the superpowers per-task implement-review-fix loop, then a whole-diff adversarial review loop, a verified build, and an opened PR. Invoke explicitly with /ha:implement. Stops at PR; hands off to /ha:review-pr. Requires the superpowers plugin.
argument-hint: '<plan-file-path | natural-language task>'
disable-model-invocation: true
effort: high
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch
---

# Implement

## Assignment
$ARGUMENTS

You drive ONE feature from an approved plan to an open PR, **built thoroughly**.
This skill **leverages superpowers rather than re-implementing it**: the per-task
implement→review→fix loop is delegated to `superpowers:subagent-driven-development`;
the build gate to `superpowers:verification-before-completion`; red-path debugging
to `superpowers:systematic-debugging`. ha's own delta is the worktree isolation,
the **whole-diff adversarial review loop** (the power-up), and the always-open-PR
finish. Requires the `superpowers` plugin. You stop at the PR — reviewing is the
separate `/ha:review-pr` step.

## Context (auto-injected)
- Repo root: !`git rev-parse --show-toplevel 2>/dev/null`
- Current branch: !`git branch --show-current 2>/dev/null`
- Base branch: !`bash "${CLAUDE_SKILL_DIR}/scripts/detect-base-branch.sh" 2>/dev/null`
- Conventions: !`test -f CLAUDE.md && echo "CLAUDE.md present — read it before editing" || echo "no CLAUDE.md"`

## Phase 1 — Digest the plan + restate

If `$ARGUMENTS` is a path, `Read` it; otherwise treat it as the task. Restate the
goal, scope, and success criteria in your own words. **Discrepancy gate:** if the
plan contradicts what the code actually is, stop and ask the human — do not
silently "fix" the plan. This phase is read-only (main checkout).

## Phase 2 — Isolate in a worktree

```bash
CLAUDE_SKILL_HA_DIR="${CLAUDE_SKILL_DIR}"   # ha-recognizable alias of the built-in skill dir
eval "$(bash "$CLAUDE_SKILL_HA_DIR/scripts/new-worktree.sh" "feat/<slug>")"
echo "Implementing in: $WORKTREE_PATH on $BRANCH (reused=$REUSED)"
```

`new-worktree.sh` runs a `superpowers:using-git-worktrees` Step 0 check (reuses an
existing linked worktree instead of nesting) and otherwise creates
`.claude/worktrees/ha/<slug>`. ha uses script-created **persistent** worktrees here,
not the native `EnterWorktree` — see `references/whole-diff-loop.md` for why.

**Absolute-path rule for the rest of the run (MUST — the one easy way to corrupt
the user's working copy):** the main session cwd stays in the main checkout, NOT
this worktree. So: every `Edit`/`Write` targets an absolute path under
`$WORKTREE_PATH`; every test/build runs as `cd "$WORKTREE_PATH" && <cmd>` in one
Bash call; every git op uses `git -C "$WORKTREE_PATH"`; every subagent is given
`$WORKTREE_PATH` and the same rule.

## Phase 3 — Per-task loop (delegated)

**REQUIRED SUB-SKILL:** Use `superpowers:subagent-driven-development` to execute
the plan task-by-task — its fresh-implementer-per-task dispatch, its two-verdict
task review, its fix loop, its `task-brief`/`review-package` scripts, its progress
ledger, and **its own risk-scaled model selection** (do not override the model
choices it makes). All work happens inside `$WORKTREE_PATH`.

ha overrides exactly two things:
- **Ledger location** → `$WORKTREE_PATH/.ha/sdd/progress.md` (not `.superpowers/`).
- **Scope** → stop after the per-task loop completes. **Do NOT** let SDD run its
  own final whole-branch review or invoke `superpowers:finishing-a-development-branch`;
  ha owns the finish (Phases 4–6 below).

If the plan is a bare task with no task breakdown, first produce a short task list
(or run `/ha:plan` to get one) — SDD needs tasks to iterate over.

## Phase 4 — Whole-diff adversarial review loop (ha power-up — run BOTH rounds)

This is ha's heavyweight delta on top of SDD's per-task reviews, and it is a
**discipline you must not shortcut**. Read `references/whole-diff-loop.md` and
follow it exactly. In brief, on the full `git -C "$WORKTREE_PATH" diff` against the
base:

1. **Round 1** — review the whole diff with ha's `review-pr` hybrid axis (generic
   checks → parallel `verifier` subagents; repo-specific/security/architectural
   judgment → main via `code-review`) **plus** `adversarial-verification`
   (refute-oriented `verifier`s + a completeness critic). Apply every fix.
2. **Round 2** — re-run the same review on the *post-fix* diff, because a fix can
   introduce a new break. Apply fixes again.

Run **up to `MAX_ROUNDS` (default 2)** rounds, stopping early only when a full
round finds nothing. **Running a single round and calling it done is the failure
this phase exists to prevent** — the per-task SDD review is NOT a substitute for
this whole-diff pass. See the prohibition + red-flags block in the reference.

## Phase 5 — Verify the build (objective gate, evidence required)

**REQUIRED SUB-SKILL:** Use `superpowers:verification-before-completion` — identify
the command that proves the build, run it FRESH, read the exit code and output
before any "passing" claim.

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

On red: **REQUIRED SUB-SKILL:** Use `superpowers:systematic-debugging` to find the
root cause before patching — do not improvise a fix on a failing test. If still red
after a real fix attempt, open the PR as a **draft** documenting the blocker.

## Phase 6 — Open the PR (end of this skill)

```bash
git -C "$WORKTREE_PATH" add -A
git -C "$WORKTREE_PATH" commit -m "$(cat <<'EOF'
<type>(<scope>): <concise summary>

<what changed and why>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git -C "$WORKTREE_PATH" push -u origin "$BRANCH"
# add --draft if checks are red or a high-risk claim is unresolved
gh pr create --head "$BRANCH" --title "<type>: <summary>" --body "$(cat <<'EOF'
## Summary
<what this PR does>

## Changes
- <change>

## Verification
- <command run> → <result>
- Whole-diff adversarial review: <rounds run> round(s), <PASS|PASS-WITH-NOTES>

## Notes
<assumptions; if draft: the blocker and what the human should decide>
EOF
)"
```

Always create the PR (a draft beats a silent half-run). **This is the end of
`implement` — do not review further here.**

## Final report

```
result: <feature> — PR <url> (<ready|draft>); SDD tasks complete, whole-diff review <N> round(s); build PASS|FAIL. Next: /ha:review-pr <pr>.
```
