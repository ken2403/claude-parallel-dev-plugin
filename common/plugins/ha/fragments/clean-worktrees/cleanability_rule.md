A worktree/branch is cleanable only if its PR is **MERGED** (confirm via
`gh pr list --state merged`, or, after `CLAUDE_SKILL_@@PLUGIN_UPPER@@_DIR="${CLAUDE_SKILL_DIR}"`,
`bash "$CLAUDE_SKILL_@@PLUGIN_UPPER@@_DIR/scripts/merge-check.sh"`), or there is no PR and the
user explicitly asked to abandon it. If a PR is still OPEN, skip it and say why.
