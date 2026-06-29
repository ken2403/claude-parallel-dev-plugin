# Whole-diff adversarial review loop (ha power-up)

This is the heavyweight delta `implement` adds **on top of** the per-task review
that `superpowers:subagent-driven-development` already runs. Two distinct review
layers, both required:

1. **Per-task** (owned by SDD): each task gets a two-verdict task review during
   the loop. Catches per-task defects close to where they were introduced.
2. **Whole-diff** (this file): after all tasks land, the *entire* change is
   reviewed as one unit, adversarially, for up to two rounds. Catches the
   cross-task and emergent defects no single-task review can see.

## The loop

Operate on the full diff: `git -C "$WORKTREE_PATH" diff <base>...HEAD`.

**Round 1**
- Run ha's `review-pr` hybrid axis on the whole diff: dispatch parallel
  `verifier` subagents for generic, diff-only checks (broad correctness, style,
  mechanical security patterns, missed call sites); keep repo-specific,
  security-critical, architectural, and cross-diff-consistency judgment in the
  main loop using the `code-review` standards.
- Run `adversarial-verification` on the change's central claims (refute-oriented
  `verifier`s + a completeness critic).
- Apply every Critical/Important fix. A fix touching 3+ file-disjoint,
  dependency-free spots may fan out to parallel general-purpose subagents
  (`superpowers:dispatching-parallel-agents`); never put two on the same file.

**Round 2**
- Re-run the same review on the **post-fix** diff. A fix can introduce a new
  break, so the second round is not optional padding — it is where second-order
  problems surface.
- Apply fixes again.

Run up to `MAX_ROUNDS` (default **2**). Stop early only when a full round produces
no REFUTED/UNCERTAIN verdicts and the completeness critic finds nothing new.

## This is a discipline — do not collapse it

The single most common way this phase fails is to **run one round and stop**, or
to treat SDD's per-task reviews as having "already covered it". They have not:
per-task review is blind to the assembled whole.

### Prohibition

- Do **not** skip Round 2 because Round 1 "looked clean" — Round 2 reviews a
  *different* diff (the post-fix one).
- Do **not** count the SDD per-task review as one of these rounds.
- Do **not** open the PR until either a full round came back clean or you have
  run `MAX_ROUNDS` rounds.

### Rationalization table

| Excuse | Reality |
|---|---|
| "SDD already reviewed every task." | Per-task review can't see cross-task interactions, the integrated whole, or emergent inconsistency. |
| "Round 1 found nothing, so Round 2 is a waste." | If Round 1 truly found nothing, Round 2 is one cheap confirming pass. If Round 1 applied fixes, Round 2 is mandatory — the diff changed. |
| "The build is green, so it's correct." | Green tests prove the tests pass, not that the change is correct, safe, and complete. That's what refutation is for. |
| "It's a small diff." | Small diffs hide ordering, security, and consistency bugs as readily as large ones; scale the verifier count down, not the rounds. |

### Red flags (stop and run the loop properly)

- You are writing the PR body and have run only one review round.
- You are about to claim "reviewed" without a verifier verdict on the whole diff.
- You skipped `adversarial-verification` because the change "seemed fine".

## SDD scope contract

When you invoke `superpowers:subagent-driven-development` in Phase 3, it normally
ends by running a final whole-branch review and then
`superpowers:finishing-a-development-branch`. **ha takes over instead:** stop SDD
after its per-task loop, then run *this* whole-diff loop and ha's own PR finish
(`implement` Phases 4–6). Also override SDD's ledger path to
`$WORKTREE_PATH/.ha/sdd/progress.md`. Everything else about SDD — its implementer
and task-reviewer dispatch, its file-handoff scripts, its model selection — is
used as-is, not reinvented.

## Why script-created persistent worktrees (not native EnterWorktree)

`superpowers:using-git-worktrees` prefers a native worktree tool (e.g.
`EnterWorktree`) when one exists. ha deliberately does **not** use it here, and
this is a considered trade-off, not an oversight:

- ha's worktree must **outlive the session** — it persists until the PR is
  reviewed and merged, possibly across several sessions. Native worktrees are
  harness-managed and auto-cleaned on session exit, which would destroy
  in-flight, unmerged work.
- `/ha:clean-worktrees` reclaims worktrees by their predictable path
  `.claude/worktrees/ha/<slug>` and verifies the PR merged first. Native
  worktrees live elsewhere and outside that contract.

`new-worktree.sh` still honors `using-git-worktrees` **Step 0** (if already inside
a linked worktree, reuse it rather than nest) — the part of the skill that applies
regardless of which creation mechanism is used.
