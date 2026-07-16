#!/usr/bin/env bash
# Behavior tests for the generated clean-worktrees clean.sh (run against the ha
# copy — all three plugin copies are generated from the same common source).
#
# Covers, in one scratch repo with a local bare "origin":
#   1. merged worktree                → removed, branch deleted
#   2. unmerged worktree              → blocked, untouched
#   3. merged + STALE lock (dead pid) → unlocked, removed
#   4. merged + lock held by a RUNNING pid → skipped, untouched
#   5. empty orphan dirs (child + group)  → removed
#   6. non-empty orphan dir           → kept and reported (unverifiable)
#
# gh is stubbed to fail fast so merge verification deterministically uses git
# ancestry (merge-check.sh Method 2) — no network, no GitHub.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLEAN="$ROOT/ha/skills/clean-worktrees/scripts/clean.sh"
TMP="${TMPDIR:-/tmp}/clean-worktrees-test.$$"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# gh stub: always fails fast -> merge-check falls through to git ancestry.
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Scratch repo: bare origin + clone --------------------------------------
git init -q --bare -b main "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/repo"
REPO="$TMP/repo"
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name t
git -C "$REPO" commit -q --allow-empty -m init
git -C "$REPO" push -q origin main

make_wt() { # name branch  -> worktree with one unique commit on the branch
  local name="$1" branch="$2"
  mkdir -p "$REPO/.claude/worktrees/ha"
  git -C "$REPO" worktree add -q -b "$branch" "$REPO/.claude/worktrees/ha/$name" main
  ( cd "$REPO/.claude/worktrees/ha/$name" \
    && echo "$name" > "$name.txt" && git add "$name.txt" \
    && git -c user.email=t@example.invalid -c user.name=t commit -qm "$name" )
}
merge_branch() { git -C "$REPO" merge -q --no-ff "$1" -m "merge $1" && git -C "$REPO" push -q origin main; }

# Case 1: merged, unlocked.
make_wt merged-plain wt/merged-plain
merge_branch wt/merged-plain
# Case 2: unmerged.
make_wt open-branch wt/open-branch
# Case 3: merged + stale lock (a pid that has already exited).
make_wt merged-stale-lock wt/merged-stale-lock
merge_branch wt/merged-stale-lock
bash -c ':' & DEAD_PID=$!; wait "$DEAD_PID" 2>/dev/null || true
git -C "$REPO" worktree lock --reason "claude session test (pid $DEAD_PID start now)" \
  "$REPO/.claude/worktrees/ha/merged-stale-lock"
# Case 4: merged + lock held by a RUNNING process (this test shell).
make_wt merged-live-lock wt/merged-live-lock
merge_branch wt/merged-live-lock
git -C "$REPO" worktree lock --reason "claude session live (pid $$ start now)" \
  "$REPO/.claude/worktrees/ha/merged-live-lock"
# Case 5: empty orphans — a bare group dir and an empty child.
mkdir -p "$REPO/.claude/worktrees/ca" "$REPO/.claude/worktrees/sa/empty-child"
# Case 6: non-empty orphan (no git metadata -> unverifiable).
mkdir -p "$REPO/.claude/worktrees/leftover-with-content"
echo data > "$REPO/.claude/worktrees/leftover-with-content/file.txt"

OUT="$(cd "$REPO" && bash "$CLEAN" all-merged 2>&1)" || fail "clean.sh exited non-zero: $OUT"

# 1. merged removed + branch gone
[ ! -d "$REPO/.claude/worktrees/ha/merged-plain" ] || fail "merged worktree not removed"
git -C "$REPO" show-ref --verify --quiet refs/heads/wt/merged-plain && fail "merged branch not deleted"
# 2. unmerged untouched
[ -d "$REPO/.claude/worktrees/ha/open-branch" ] || fail "unmerged worktree was removed"
git -C "$REPO" show-ref --verify --quiet refs/heads/wt/open-branch || fail "unmerged branch was deleted"
# 3. stale lock unlocked and removed
[ ! -d "$REPO/.claude/worktrees/ha/merged-stale-lock" ] || fail "stale-locked merged worktree not removed"
echo "$OUT" | grep -q "Stale lock" || fail "stale lock path not reported"
# 4. live lock respected
[ -d "$REPO/.claude/worktrees/ha/merged-live-lock" ] || fail "live-locked worktree was removed"
echo "$OUT" | grep -q "locked by a RUNNING process" || fail "live lock skip not reported"
# 5. empty orphans removed (child, then its emptied group; bare group too)
[ ! -d "$REPO/.claude/worktrees/ca" ] || fail "empty orphan group dir not removed"
[ ! -d "$REPO/.claude/worktrees/sa" ] || fail "emptied orphan group dir not folded up"
# 6. non-empty orphan kept and reported
[ -d "$REPO/.claude/worktrees/leftover-with-content" ] || fail "non-empty orphan was deleted"
echo "$OUT" | grep -q "ORPHANED" || fail "non-empty orphan not reported"

echo "clean-worktrees-test.sh: ok"
