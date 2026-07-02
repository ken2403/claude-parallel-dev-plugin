---
name: resolve-conflicts
description: Resolve merge conflicts between a ca feature branch and its base branch, in an isolated worktree, preserving the intent of both sides. Use when a ca PR or feature branch is behind or conflicting with the base branch and you want the conflicts resolved, verified, and pushed. Invoke explicitly with /ca:resolve-conflicts.
license: MIT
disable-model-invocation: true
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# resolve-conflicts

## Input
$ARGUMENTS

You merge the base branch into a ca feature branch and resolve the conflicts
**correctly** — preserving the intent of *both* sides, never blindly picking one.
All work happens in an **isolated worktree**, never the user's main checkout. A
wrong conflict resolution silently corrupts code, so verify before you push.

## Step 1 — Resolve the target branch and its isolated worktree

`$ARGUMENTS` is a PR number or a branch name (default: the current branch). If no
PR number is given, auto-detect it from the current branch. Get the branch, then
reuse its existing ca worktree or create one — **never** edit the main checkout.

```bash
ARG="<pr-number | branch | empty>"
if [ -z "$ARG" ]; then ARG="$(gh pr view --json number --jq .number 2>/dev/null)"; fi
if printf '%s' "$ARG" | grep -qE '^[0-9]+$'; then
  PR="$ARG"; BRANCH="$(gh pr view "$PR" --json headRefName --jq .headRefName)"
else
  PR=""; BRANCH="${ARG:-$(git branch --show-current)}"
fi
eval "$(bash "${CLAUDE_SKILL_DIR}/scripts/attach-or-create-worktree.sh" "$BRANCH")"
[ -n "${WORKTREE_PATH:-}" ] || { echo "error: worktree was not resolved — aborting"; exit 1; }
echo "Resolving in: $WORKTREE_PATH on $BRANCH (reused=$REUSED)"
```

If `attach-or-create-worktree.sh` exits non-zero (e.g. the branch is checked out in
the main checkout), **stop and report**; do not fall back to resolving in place.

**Absolute-path rule (MUST):** the main session cwd is NOT this worktree, and a
`cd` does not persist between Bash calls. So: every `Edit`/`Write` targets an
absolute path under `$WORKTREE_PATH`; every git/test/build runs as
`git -C "$WORKTREE_PATH" ...` or `cd "$WORKTREE_PATH" && <cmd>` in one Bash call.

## Step 2 — Merge the base branch and surface the conflicts

```bash
BASE="$(bash "${CLAUDE_SKILL_DIR}/scripts/detect-base-branch.sh" "$WORKTREE_PATH")"
echo "Base branch: $BASE"
git -C "$WORKTREE_PATH" fetch origin "$BASE" --quiet
git -C "$WORKTREE_PATH" merge --no-edit "origin/$BASE" || true   # conflicts are expected
echo "=== Conflicting files ==="
git -C "$WORKTREE_PATH" diff --name-only --diff-filter=U
```

If there are **no** conflicting files, the merge already succeeded — skip to Step 4
(verify) and finish. If the working tree was dirty and the merge refused to start,
stop and report; do not force it.

## Step 3 — Plan each resolution, then resolve (intent first)

For every conflicted file, read the conflict hunks (`<<<<<<<` / `=======` /
`>>>>>>>`) and the surrounding code, and decide the resolution **strategy** per
hunk — keep ours, keep theirs, or **combine** both (the common correct answer:
both sides changed for a reason). Record one line per file: the strategy and why.
Resolving a conflict by deleting one side's real change is a silent regression.

Then resolve each file, editing absolute paths under `$WORKTREE_PATH`, and
`git -C "$WORKTREE_PATH" add <file>` as you finish each.

## Step 4 — Integration review (CRITICAL) + verify the build

Conflict resolution is exactly where independently-resolved seams silently break.
Before committing, re-read the full merged result and confirm no hunk lost either
side's intent and the seams are coherent. Also confirm no markers survive and run
the build:

```bash
git -C "$WORKTREE_PATH" diff --check
grep -rnE '^(<<<<<<<|=======|>>>>>>>)' "$WORKTREE_PATH" --exclude-dir=.git && echo "MARKERS REMAIN — fix before commit" || echo "no markers"

cd "$WORKTREE_PATH" && {
  if [ -f Makefile ] && grep -qE '^(check|test|ci):' Makefile; then make check 2>&1 || make test 2>&1
  elif [ -f package.json ]; then npm test 2>&1 || npm run test 2>&1
  elif [ -f pyproject.toml ]; then { command -v uv >/dev/null && uv run pytest 2>&1; } || pytest 2>&1
  elif [ -f go.mod ]; then go test ./... 2>&1
  elif [ -f Cargo.toml ]; then cargo test 2>&1
  else echo "No standard check found — verify the touched paths manually"; fi
}
```

If markers remain or checks fail, find the **root cause** and fix it before
committing — do not improvise a patch on a broken merge.

## Step 5 — Commit the merge and push

Only once markers are gone and checks pass:

```bash
git -C "$WORKTREE_PATH" add -A
git -C "$WORKTREE_PATH" commit --no-edit   # completes the merge commit
git -C "$WORKTREE_PATH" push
```

If a PR number was resolved, leave a short note:

```bash
[ -n "$PR" ] && gh pr comment "$PR" --body "Merged origin/$BASE and resolved conflicts:
- <file> — <strategy>
Verification: <result>"
```

## If it goes wrong

Abort cleanly without touching anything else — the worktree isolates the damage:

```bash
git -C "$WORKTREE_PATH" merge --abort
```

Then report what conflicted and why you stopped.

## Final report

```
result: PR/branch <id> — merged origin/<base>, resolved <k> conflicted files in <worktree>; checks <green/red>, <pushed|stopped>.
```
