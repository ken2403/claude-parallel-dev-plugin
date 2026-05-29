---
name: status
description: Show the live state of the hv — every background feature agent and its PR — in one table, with triage suggestions for anything stuck or failing. Use to check progress after /hv:launch, decide what to review/merge next, or find which feature errored.
argument-hint: '[optional name prefix, default "hv/"]'
model: opus
allowed-tools: Read, Bash, Grep, Glob
---

# Hv status

## Snapshot (auto-injected, default `hv/` prefix)
```
!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/agents-status.sh" hv/ 2>/dev/null`
```

If the user passed a different name prefix in `$ARGUMENTS`, re-run the script
yourself with a Bash tool call: `bash "$CLAUDE_PLUGIN_ROOT/scripts/agents-status.sh" <prefix>`
(the injected snapshot above only ever uses the default).

## What to do

Join the two sections above into a single per-feature view and triage it. The
top section lists live background agents (`claude agents --json`); the bottom
lists open PRs (`gh pr list`). Match them by branch / `hv/<id>` name.

Classify each feature:

- **working** — agent running, no PR yet.
- **pr-open** — PR exists; note review decision + CI (`statusCheckRollup`).
- **needs-review** — PR open, no review yet → suggest `/hv:review <pr>`.
- **changes-requested / red CI** — suggest `/hv:fix <pr>`.
- **approved + green** — suggest `/hv:merge <pr>`.
- **merged** — done; candidate for `/hv:cleanup`.
- **error / stalled** — agent stopped without a PR, or idle unexpectedly. Inspect
  with `claude logs <id>`; suggest relaunch via `/hv:launch <id>` or a manual look.

## Output

```
| feature | branch | agent | PR | CI | review | suggested next |
|---------|--------|-------|----|----|--------|----------------|
```

Then a one-line roll-up: `result: <x> working, <y> in review, <z> merged, <w> need attention.`

If the `claude` or `gh` CLI is missing from the snapshot, say so and tell the
user what to install — don't silently report an empty hv as "all done".
