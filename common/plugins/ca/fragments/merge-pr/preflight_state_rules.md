- `state` is not OPEN.
- `isDraft` is true — **in ca the draft state IS the review gate**: the Codex loop
  promotes the PR to ready only after `/ca:review-pr` approves. A draft means the
  loop has not approved (or was force-stopped); send it back to the loop, don't merge.
- `reviewDecision` is CHANGES_REQUESTED (a human requested changes on GitHub).
