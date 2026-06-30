---
name: adversarial-verification
description: Multi-pass adversarial verification harness that guarantees the accuracy of a change before it ships. Use whenever you need high confidence that an implementation is correct, safe, and complete — before opening a PR, before approving a review, or whenever a change touches risky surface area such as auth, crypto, data migration, money, or external input.
allowed-tools: Read, Grep, Glob, Bash, Agent
---

<!-- ported from hv/skills/adversarial-verification/SKILL.md @ hv 0.1.0 (implementer -> general-purpose; nesting note reworded for ha) -->

# Adversarial verification

A single self-review tends to rationalize its own work. This harness instead
tries to **prove the change wrong** from several independent angles. A change is
trusted only after it survives refutation — that is what "accuracy guaranteed"
means here.

Use this on a completed-but-unshipped change (your own, or a PR under review).
Because it dispatches `verifier` subagents, run it from a top-level skill context
(the `implement` / `review-pr` main loop), not from inside a subagent, so it can
fan out cleanly and keep the fan-out predictable.

## The loop

Run rounds until the change is clean or you hit the round cap (default **3** —
enough for a fix to surface a second-order problem and be re-checked; beyond
that, diminishing returns usually mean the change needs rethinking, not more
rounds).

### 1. Enumerate claims

List the specific claims the change makes. Typical claims:

- **Correctness** — it does what the spec asked, for all relevant inputs.
- **Safety** — it introduces no security regression (input→sink, authz, secrets).
- **Completeness** — every requirement and call site is handled; nothing stubbed.
- **Consistency** — it follows existing repo conventions; no contradiction.
- **No regression** — existing tests/behavior still hold.

Scale the claim set to the change. A one-line fix needs correctness + no-regression;
an auth change needs all five.

### 2. Dispatch verifiers in parallel (refute-oriented)

For each claim, dispatch a `verifier` subagent with a distinct lens, **in
parallel** (one `Agent` message, multiple calls). Tell each one to *try to break
the claim* and default to REFUTED when uncertain. For higher-stakes claims, put
**3 or more verifiers** on the same claim with different lenses (e.g. correctness,
edge-cases, security) and take a majority — an odd number breaks ties, and three
distinct lenses is the smallest panel that catches failure modes a single
reviewer is blind to. Scale the count up with the stakes.

Why parallel + independent: redundancy catches what one reviewer rationalizes;
diverse lenses catch failure modes a single lens is blind to.

### 3. Judge

- A claim **fails** if a verifier returns REFUTED with a concrete counter-example,
  or if a majority of its verifiers refute it.
- `UNCERTAIN` with a real gap is treated as a fail for risky claims (auth, data
  loss, money, external input) — do not ship on "probably fine" there.

### 4. Completeness critic

After the per-claim verifiers, run one more pass asking the inverse question:
**"What did everyone miss?"** — a requirement not turned into a claim, a modality
not tested, a call site not checked, an error path ignored. Its findings become
new claims for the next round.

### 5. Fix and repeat

For every failed claim, apply the minimal fix the verifier specified (yourself,
or via a general-purpose subagent for a file-disjoint slice), then start a new
round. Re-verify — a fix can introduce a new break.

Stop when a full round produces no REFUTED/UNCERTAIN verdicts and the
completeness critic finds nothing new, or when you reach the round cap.

## Output

Report the final verdict with evidence, not assertions:

```
## Verification result: PASS | PASS-WITH-NOTES | FAIL

## Claims checked
- [PASS|FAIL] <claim> (<n> verifiers, <lens(es)>) — <one-line evidence>

## Fixes applied this run
- path:line — <what changed and which claim it closed>

## Residual risk (if PASS-WITH-NOTES)
- <what remains unverified and why it's acceptable to ship>
```

If you hit the round cap with unresolved high-risk failures, the honest result
is **FAIL** — say so and surface the blocker. Shipping an unverified risky change
is the failure mode this skill exists to prevent.

## Cost control

Verification fan-out multiplies tokens. Match rigor to risk: low-risk, isolated
changes get a single correctness + no-regression pass; reserve the ≥3-verifier,
multi-lens treatment for changes the `analyzer` flagged HIGH risk.
