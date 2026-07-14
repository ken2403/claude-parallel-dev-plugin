- `state` is not OPEN, or `isDraft` is true.
- `reviewDecision` is CHANGES_REQUESTED (a human requested changes on GitHub).
  Do NOT require APPROVED: a `/ha:review-pr` APPROVE is a process gate that lands
  as a PR *comment* — it never sets `reviewDecision` (and the PR's own author
  cannot approve it on GitHub), so requiring APPROVED would block solo use forever.
