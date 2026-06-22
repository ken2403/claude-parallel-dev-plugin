---
name: ca-implement-plan
description: Implement a saved implementation-plan markdown file task-by-task inside an isolated git worktree, then loop with an external Claude reviewer that checks the plan against the diff, address blocking feedback over a few rounds, and open a PR that includes a summary of the Claude/Codex exchange. Use when the user points at a plan file under docs/superpowers/plans or any task-by-task plan and says things like "implement this plan", "build the plan at this path", "run the ca loop on this plan", or "have Claude review what you built". The human stays in control and is asked to confirm at key decision points and before any cleanup.
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
```

If `BR` is `main` or `master`, or the tree is not a `ca/` worktree, **STOP** and tell the human to
launch from an isolated worktree first:

```bash
bash "$SKILL_DIR/scripts/new-worktree.sh" "$PLAN"
# then run codex inside the printed worktree path and invoke $ca-implement-plan again
```

Proceed only once on a `ca/<plan-id>` branch in its own worktree.

## Step 1 — Read and anchor the plan

1. Read `PLAN` in full. Ensure a copy and checksum exist at `$ROOT/.ca/runs/<plan-id>/`:

   ```bash
   ID="$(basename "$PLAN" .md)"; RUN="$ROOT/.ca/runs/$ID"; mkdir -p "$RUN"
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

## Step 3 — Self-review, then call Claude

1. Self-review the diff against the plan: every task covered, tests present and green, no placeholder left.
2. Produce the diff for review (use the round number, starting at 1):

   ```bash
   RUND=1
   git -C "$ROOT" add -A
   git -C "$ROOT" diff --cached > "$RUN/round-$RUND.diff"
   ```
3. Call the external Claude reviewer. This bundled script shells out to `claude` on the host (Claude
   has its own web search) and writes a validated JSON verdict. It exits non-zero if the output is
   missing or malformed — treat that as a blocking result:

   ```bash
   bash "$SKILL_DIR/scripts/claude-review.sh" \
     --plan "$RUN/plan.md" --diff "$RUN/round-$RUND.diff" --worktree "$ROOT" \
     --round "$RUND" --out "$RUN/review-round-$RUND.json"
   ```
4. Read `review-round-$RUND.json`. Its shape is documented in `references/review-contract.md`
   (`verdict`, plus `findings` where each has `blocking: true` or `false`). On a missing or invalid
   file, treat it as blocked and **ASK** the human.

## Step 4 — Address feedback and loop

- If `verdict` is `approve`, or no finding has `blocking: true`, go to Step 5.
- Otherwise address every blocking finding. For a finding you judge incorrect, do not silently skip
  it — record your disagreement to surface in the PR summary, and **ASK** the human if it is material.
- Re-run the affected tests, increment the round, regenerate the diff, and call Claude again (Step 3).
- Stop when approved, when the round count reaches `MAX_ROUNDS` (default 2 — the initial review plus
  at most two fix rounds), or when two consecutive rounds produce an identical diff. On a forced stop,
  **ASK** the human whether to open a draft PR or keep going.

This is one continuous session, so prior rounds are already in context — still re-read the latest
review JSON and diff so decisions rest on the current files, not memory alone.

## Step 5 — Open the PR with an exchange summary

```bash
git -C "$ROOT" push -u origin "$BR"
gh pr create --base main --head "$BR" --title "feat: $ID" --body-file "$RUN/plan.md"   # add --draft if not approved
```

Then post the round-by-round Claude/Codex exchange (verdicts, what each round fixed, any disputed
findings) as a PR comment, and report the PR link to the human:

```bash
bash "$SKILL_DIR/scripts/post-summary.sh" "$RUN" "PR_URL_OR_NUMBER"
```

**ASK** the human to review and merge.

## Step 6 — Cleanup after merge (only on confirmation)

Delete nothing until the human confirms the PR merged. Then, from the main checkout (`MAIN` is the
original repo root, not this worktree):

```bash
git -C "$MAIN" worktree remove "$ROOT"   # no --force; refuses uncommitted changes
git -C "$MAIN" branch -d "$BR"           # -d refuses unmerged; never -D
git -C "$MAIN" worktree prune
```

If the PR was closed unmerged, clean nothing and tell the human.

## References

- `references/review-contract.md` — the JSON Claude returns and how `blocking` gates the loop.
