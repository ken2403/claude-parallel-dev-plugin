---
name: ca-implement-plan
description: Build a saved task-by-task implementation plan in an isolated worktree, gated by Claude-reviewed rounds before the PR is marked ready — the Codex half of the ca (Cooperate Agents) loop. Use when the user points at a plan file under docs/superpowers/plans or any task-by-task plan and says things like "implement this plan", "build the plan at this path", "run the ca loop on this plan", or "have Claude review what you built". Human confirmation is required at key decision points and before cleanup.
license: MIT
metadata:
  short-description: Build a plan with Claude review rounds
---

# ca-implement-plan

Build a saved implementation plan task-by-task in an isolated worktree, get it reviewed by an
external Claude reviewer between rounds, address blocking feedback, and open a PR — with the human
present. Pause for the human at every point marked **ASK**.

## Inputs

- `PLAN` — absolute path to the plan markdown file. Ask the human if it was not provided.
- `MAX_ROUNDS` — optional cap on Claude review rounds before forcing a stop. Default 2.

Resolve the skill's own bundled scripts from its install dir:

```bash
SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/ca-implement-plan"
```

## Step 0 — Confirm isolation (never skip)

Run only inside a dedicated worktree on a `ca/` branch, never on the default branch or the shared checkout.

```bash
ROOT="$(git rev-parse --show-toplevel)"
BR="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
echo "root=$ROOT branch=$BR"
case "$BR" in ca/*) ;; *) echo "NOT ISOLATED: branch '$BR' is not a ca/ branch — STOP" >&2; exit 1;; esac
case "$ROOT" in */.claude/worktrees/ca/*) ;; *) echo "NOT ISOLATED: '$ROOT' is not a ca worktree — STOP" >&2; exit 1;; esac
```

If either check fails (branch not `ca/*`, or the tree is not under `.claude/worktrees/ca/`),
**STOP** and tell the human to launch from an isolated worktree first:

```bash
bash "$SKILL_DIR/scripts/new-worktree.sh" "$PLAN"
# then run codex inside the printed worktree path and invoke $ca-implement-plan again
```

Proceed only once on a `ca/<plan-id>` branch in its own worktree.

## Step 1 — Read and anchor the plan

1. Read `PLAN` in full. `PLAN` must be the **original** plan file (e.g. `docs/superpowers/plans/<id>.md`), not a staged copy named `plan.md` — the id is derived from its basename, and a copy named `plan.md` would collapse the id to `plan`. Ensure a copy and checksum exist at `$ROOT/.ca/runs/<id>/`:

   ```bash
   ID="$(basename "$PLAN" .md)"; RUN="$ROOT/.ca/runs/$ID"; mkdir -p "$RUN"
   [ "$ID" = plan ] && echo "WARN: id is 'plan' — pass the original plan path, not a staged copy" >&2
   cp "$PLAN" "$RUN/plan.md"; shasum -a 256 "$PLAN" | awk '{print $1}' > "$RUN/plan.sha256"
   ```
2. Restate the goal and the ordered task list in two or three sentences. Note each task's test command.
3. If the plan contradicts the actual code (a referenced file is gone, an interface drifted), **ASK** the human before building.

## Step 2 — Implement task-by-task (test-first, frequent commits)

For each task, in plan order:

1. Write the failing test the task specifies. Run it. Confirm it fails for the stated reason.
2. Write the minimal implementation. Run the test. Confirm it passes.
3. Run the task's lint/build/typecheck if specified. Capture real output — never claim success without evidence.
4. Commit with a conventional message and the repo's co-author footer.

Hard rules while implementing:

- Stay inside this worktree. Never edit `.env`, credentials, keys, or other secret files.
- Keep the diff scoped to the plan. Do not refactor unrelated code.
- Do not push or open a PR yet.

## Step 3 — Self-review, open a draft PR, then call Claude

1. Self-review the diff against the plan: every task covered, tests present and green, no placeholder left.
2. Push the branch and open a **draft** PR (the reviewer reviews the PR; the draft state is the
   fail-closed gate — it is promoted to ready only after Claude approves):

   ```bash
   RUND=1
   git -C "$ROOT" push -u origin "$BR"
   gh pr view "$BR" >/dev/null 2>&1 || \
     gh pr create --draft --base "${CA_BASE:-main}" --head "$BR" --title "feat: $ID" --body-file "$RUN/plan.md"
   PR="$(gh pr view "$BR" --json number --jq .number)"
   echo "draft PR: #$PR"
   ```
3. Call the Claude reviewer on the PR. This bundled script runs `claude -p /ca:review-pr` and writes
   a validated JSON verdict.

   **TWO PRECONDITIONS — important.** Both must hold or no review is produced:
   - **Skill resolvable:** `claude -p /ca:review-pr` only works if the ca *Claude* plugin is
     installed in the user's Claude config, or `CA_CLAUDE_PLUGIN_DIR` points at the `ca/claude` dir
     (the script then passes `--plugin-dir`). If neither, the skill won't load.
   - **Network + `gh`:** `claude -p` reaches the Anthropic API, and the review fetches the PR via
     `gh pr diff`, so both network and an authenticated `gh` are required. Codex's default
     `-s workspace-write` sandbox blocks network, so the call fails inside a normal sandboxed
     session. Provide network by launching Codex with it permitted for this command, or run the
     command in a host terminal where `gh` is authenticated.

   Tell the human which arrangement you are relying on before running it.

   ```bash
   bash "$SKILL_DIR/scripts/claude-review.sh" \
     --plan "$RUN/plan.md" --pr "$PR" --worktree "$ROOT" \
     --round "$RUND" --out "$RUN/review-round-$RUND.json"
   ```

   The script fails loudly (non-zero) with an actionable reason if no valid review is produced — if
   it reports the API was unreachable, **STOP and ASK** the human to run the review step where
   network is allowed; do not treat an unreachable reviewer as a real "blocked" verdict.
4. Read `review-round-$RUND.json`. Its shape is documented in `references/review-contract.md`
   (`verdict`, plus `findings` where each has `blocking: true` or `false`). On a malformed file,
   treat it as blocked and **ASK** the human.

## Step 4 — Address feedback and loop

- If `verdict` is `approve`, or no finding has `blocking: true`, go to Step 5.
- Otherwise address every blocking finding. For a finding you judge incorrect, do not silently skip
  it — record your disagreement to surface in the PR summary, and **ASK** the human if it is material.
- Re-run the affected tests, commit, and **push** (this updates the draft PR's diff), increment the
  round, and call Claude again on the same PR (Step 3.3 — reuse `$PR`, never open a second PR).
- Stop when approved, when the round count reaches `MAX_ROUNDS` (default 2 — the initial review plus
  at most one fix-and-re-review round), or when two consecutive rounds produce an identical diff. On a forced stop,
  **leave the PR as a draft** and **ASK** the human whether to keep going or take it from here.

This is one continuous session, so prior rounds are already in context — still re-read the latest
review JSON and the current PR diff so decisions rest on the current files, not memory alone.

## Step 5 — Promote the PR to ready, with an exchange summary

The PR already exists (opened as a draft in Step 3). Once the review approved — or produced no
blocking findings — promote it to ready:

```bash
gh pr ready "$PR"          # promote the draft PR to ready-for-review
```

If the loop hit a forced stop with unresolved blocking findings, leave it as a draft instead and say so.

Then post the round-by-round Claude/Codex exchange (verdicts, what each round fixed, any disputed
findings) as a PR comment, and report the PR link to the human:

```bash
bash "$SKILL_DIR/scripts/post-summary.sh" "$RUN" "$PR"
```

**ASK** the human to review and merge.

## Step 6 — Cleanup after merge (only on confirmation)

Delete nothing until the human confirms the PR merged. The preferred path is the Claude-side
`/ca:clean-worktrees` (it owns the cleanup guardrails and verifies the merge itself). If the human
asks you to clean up from here instead, derive the main checkout first — `git worktree remove`
must run from OUTSIDE the worktree being removed:

```bash
MAIN="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"   # first entry = main checkout
[ -n "$MAIN" ] && [ "$MAIN" != "$ROOT" ] || { echo "cannot resolve main checkout — use /ca:clean-worktrees" >&2; exit 1; }
cd "$MAIN"
git worktree remove "$ROOT"   # no --force; refuses uncommitted changes
git branch -d "$BR"           # -d refuses unmerged; never -D
git worktree prune
```

If the PR was closed unmerged, clean nothing and tell the human.

## References

- `references/review-contract.md` — the JSON Claude returns and how `blocking` gates the loop.
