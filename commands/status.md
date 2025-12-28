---
allowed-tools: Bash
argument-hint: [optional: session-name or job-id]
description: Check status of all parallel workers, PRs, and worktrees
model: haiku
---

# Parallel Workflow Status

## Target
$ARGUMENTS

## Status Report

### Active Sessions
```bash
echo "=== tmux Sessions ==="
tmux list-sessions 2>/dev/null || echo "No tmux sessions running"
```

### Open PRs
```bash
echo ""
echo "=== Open Pull Requests ==="
gh pr list --state open 2>/dev/null || echo "Cannot fetch PRs (not in git repo or gh not configured)"
```

### Git Worktrees
```bash
echo ""
echo "=== Git Worktrees ==="
git worktree list 2>/dev/null || echo "Not in a git repository"
```

### Per-Session Details

If specific session requested, show detailed output:
```bash
if [ -n "$1" ]; then
  echo ""
  echo "=== Session: $1 (last 50 lines) ==="
  tmux capture-pane -t "$1" -p 2>/dev/null | tail -50 || echo "Session not found: $1"
fi
```

Otherwise, show summary of all sessions:
```bash
echo ""
echo "=== Session Summaries ==="
for session in $(tmux list-sessions -F '#{session_name}' 2>/dev/null); do
  echo "--- $session ---"
  tmux capture-pane -t "$session" -p 2>/dev/null | tail -10
  echo ""
done
```

## Status Interpretation

| Indicator | Meaning |
|-----------|---------|
| `Waiting for input` | Worker needs human intervention |
| `Running command` | Worker is actively processing |
| `Error` / `failed` | Worker encountered issue |
| `PR created` | Worker completed successfully |
| `Committed` | Changes committed, PR pending |

## Quick Actions

Based on status, suggested next steps:

- **All PRs created**: Run `/pw:review [pr-number]` for each
- **Worker stuck**: Check output, consider restarting
- **All merged**: Run `/pw:cleanup [branches]`
