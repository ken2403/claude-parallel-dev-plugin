---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: '[task description]'
description: Execute assigned task as a parallel worker following workspace rules
model: opus
---

# Parallel Worker Task

## Assignment
$ARGUMENTS

## Context
- Branch: !`git branch --show-current`
- Working directory: !`pwd`
- Repository: !`basename $(git rev-parse --show-toplevel 2>/dev/null)`

## Workspace Rules

Check and follow project-specific CLAUDE.md:
```bash
if [ -f "CLAUDE.md" ]; then
  echo "=== Project CLAUDE.md ==="
  head -100 CLAUDE.md
fi
```

## Base Branch Detection

Detect the base branch from workspace configuration (NOT always main/master):
```bash
# Find plugin directory for shared scripts
PLUGIN_DIR=""
for d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin "$HOME"/.claude/plugins/cache/claude-parallel-dev-plugin/pw/*; do
  [ -d "$d/scripts" ] && PLUGIN_DIR="$d" && break
done 2>/dev/null
[ -n "${PW_PLUGIN_DIR:-}" ] && PLUGIN_DIR="$PW_PLUGIN_DIR"

# Base branch detection (using shared script)
BASE_BRANCH=$("${PLUGIN_DIR}/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
echo "Base branch: $BASE_BRANCH"
```

## Automatic Subagent Usage

**MANDATORY**: Before any implementation, you MUST use subagents:

1. **ALWAYS** use `explorer` subagent first to understand the codebase structure
2. For complex or risky changes, use `analyzer` subagent to assess impact
3. Never skip exploration - it prevents mistakes and ensures pattern compliance

## Execution Process

### Phase 1: Understanding (REQUIRED)

**MANDATORY**: Use explorer subagent to understand the codebase:
```
Use explorer subagent to find relevant files and patterns for this task
```

For complex changes, also use analyzer:
```
Use analyzer subagent to understand the architecture and dependencies
```

Key questions to answer:
- What existing patterns should I follow?
- What files need to be modified?
- Are there related tests I should update?

### Phase 2: Planning

Before writing any code:
1. List files to create/modify
2. Identify patterns to follow
3. Plan minimal, focused changes
4. Consider edge cases

### Phase 3: Implementation

Follow workspace conventions:
- Maintain existing code style
- Add type annotations where required
- Keep changes focused on the assigned task
- Do NOT modify files outside your scope

**Apply Quality Skills**:
- Follow `/pw:code-quality` standards (readability, maintainability, error handling)
- Follow `/pw:security-review` standards if handling auth, user input, or sensitive data

### Phase 4: Verification

Run project-specific checks:
```bash
# Try common verification commands
if [ -f "Makefile" ] && grep -q "check" Makefile; then
  make check
elif [ -f "package.json" ]; then
  npm test 2>/dev/null || npm run test 2>/dev/null || true
elif [ -f "pyproject.toml" ]; then
  uv run pytest 2>/dev/null || uv run mypy . 2>/dev/null || true
else
  echo "No standard check command found - verify manually"
fi
```

### Phase 5: Commit

Create atomic commit with conventional message:
```bash
git add .
git commit -m "$(cat <<'EOF'
feat: [brief description]

[Detailed description of changes]

- [Change 1]
- [Change 2]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Phase 6: Create PR

```bash
# Push branch
git push -u origin $(git branch --show-current)

# Create PR
gh pr create --title "[type]: [brief description]" --body "$(cat <<'EOF'
## Summary
[What this PR does]

## Changes
- [Change 1]
- [Change 2]

## Testing
- [ ] [Test performed]

## Related Issues
Closes #[issue-number] (if applicable)

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

## Output Report

When complete, provide:
```markdown
# Worker Report

## Task Completed
[Description of what was implemented]

## Files Changed
- `path/to/file1` - [What changed]
- `path/to/file2` - [What changed]

## PR Created
- **URL**: [PR URL]
- **Title**: [PR Title]
- **Status**: Ready for review

## Verification
- [ ] Tests pass
- [ ] Lint/type check pass
- [ ] Changes are focused and minimal

## Notes
[Any issues encountered or decisions made]
```

## Error Handling

If blocked:
1. Document the blocker clearly
2. Check if it's a dependency on another worker
3. If critical, notify orchestrator
4. Do NOT proceed with incomplete implementation
