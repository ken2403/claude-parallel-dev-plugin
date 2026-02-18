---
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: [PR number or review feedback text]
description: Parse review feedback and spawn agent team for parallel fixes
model: opus
---

# Agent Team Fix Review Feedback

Parse review feedback, group by file, and spawn an agent team to fix issues in parallel.

## Feedback to Address
$ARGUMENTS

## Agent Teams Prerequisite Check

```bash
echo "=== Agent Teams Prerequisite Check ==="
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]; then
  echo "ERROR: Agent Teams feature is not enabled."
  echo ""
  echo "To enable, add to your settings.json:"
  echo '  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }'
  echo ""
  echo "Or set the environment variable:"
  echo "  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
  exit 1
fi
echo "Agent Teams: ENABLED"
```

## Current Context
- Branch: !`git branch --show-current`
- Last commit: !`git log --oneline -1`

---

## Phase 1: Feedback Acquisition

### From PR Number
```bash
# Get current PR status and reviews
gh pr view --json reviewDecision,reviews,comments 2>/dev/null | head -50 || echo "Provide PR number for status"
```

```bash
# Get detailed review comments with file locations
PR_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+' | head -1)
if [ -n "$PR_NUM" ]; then
  OWNER_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
  echo "=== PR Reviews ==="
  gh api "repos/$OWNER_REPO/pulls/$PR_NUM/reviews" --jq '.[] | "Review by \(.user.login): \(.state)\n\(.body)\n---"' 2>/dev/null || true
  echo ""
  echo "=== Review Comments (inline) ==="
  gh api "repos/$OWNER_REPO/pulls/$PR_NUM/comments" --jq '.[] | "[\(.path):\(.line // .original_line)] \(.body)\n---"' 2>/dev/null || true
fi
```

### From Text Input
If the input is text (not a PR number), parse it directly. Expect the format from `at-rv` output:
- Required Changes section
- Recommended Changes section
- Inline findings with `file:line` references

---

## Phase 2: File Grouping

### Grouping Rules
1. **All findings targeting the same file** → MUST go to the same Fixer
2. **Closely related files** (same directory/module) → prefer same Fixer
3. **1-2 total files** → single Fixer (no team overhead)
4. **3+ files** → group by directory/module, max 5 Fixers

### Categorize Feedback

For each finding, categorize:
- **Critical** (must fix): Bugs, security issues, logic errors
- **Required** (should fix): Style violations, missing tests
- **Suggestions** (consider): Improvements, alternatives

### Build File Ownership Manifest

```
Fixer-1: src/auth/login.ts, src/auth/types.ts
  - [Critical] Fix SQL injection in login query (login.ts:42)
  - [Required] Add input validation for email (login.ts:28)
  - [Required] Export AuthResult type (types.ts:15)

Fixer-2: src/api/routes.ts, src/api/handlers.ts
  - [Critical] Fix missing authorization check (routes.ts:67)
  - [Required] Add error handling for timeout (handlers.ts:89)
```

---

## Phase 3: Spawn Fixer Team

### Team Structure (Dynamic)

| Teammate | Model | Assigned Files | Findings Count |
|----------|-------|----------------|----------------|
| Fixer-1 | sonnet | [File group 1] | N |
| Fixer-2 | sonnet | [File group 2] | N |
| ... | sonnet | ... | ... |

**Lead Mode**: Delegate

### Fixer Spawn Prompt Template

```
You are a **Fixer** on a team addressing PR review feedback in parallel.

## Your Assigned Files
[List of files this Fixer owns]

## Review Findings to Address

### Critical (Must Fix)
1. **[file:line]**: [Description of issue]
   - Reviewer's recommendation: [recommendation]

### Required (Should Fix)
1. **[file:line]**: [Description of issue]
   - Reviewer's recommendation: [recommendation]

### Suggestions (Consider)
1. **[file:line]**: [Description of suggestion]

## Instructions

For each finding:
1. **Read** the relevant file and understand the current code
2. **Understand** the reviewer's concern fully
3. **Implement** the fix following existing code patterns
4. **Verify** the fix addresses the reviewer's concern

## File Safety Rules
- You may ONLY modify files in your assigned list: [file list]
- You may NOT modify these files (other Fixers' territory): [other files list]
- Do NOT run `git commit` — the Lead will commit all changes
- Do NOT run `git push`

## Quality Standards
- Follow existing code style and patterns
- Ensure fixes don't introduce new issues
- Handle edge cases mentioned in the review

## Output
Report for each finding:
- Finding reference (file:line)
- Status: Fixed / Partially Fixed / Deferred
- What was changed and why
- Any concerns about the fix
```

---

## Phase 4: Parallel Fixes

Each Fixer works independently on their assigned files:
1. Reads each file to understand current code
2. Implements fixes for all findings in their scope
3. Reports what was changed

**File Safety**: Each Fixer is strictly scoped to their assigned files.

---

## Phase 5: Lead Verification

After all Fixers complete, the Lead verifies:

### 1. Check File Scope Compliance

```bash
echo "=== Checking file changes ==="
git diff --name-only
echo ""
echo "=== Checking for scope violations ==="
# Lead compares changed files against the manifest
# Any file changed that wasn't in any Fixer's scope is a violation
```

### 2. Verify Each Fix Addresses Its Finding

The Lead reviews each Fixer's report and spot-checks:
- Critical findings are properly addressed
- Required findings are addressed
- No regressions introduced

### 3. Run Project Checks

```bash
echo "=== Project Checks ==="
if [ -f "Makefile" ] && grep -q "check" Makefile; then
  make check
elif [ -f "package.json" ]; then
  npm test 2>/dev/null || npm run test 2>/dev/null || true
elif [ -f "pyproject.toml" ]; then
  uv run pytest 2>/dev/null || uv run mypy . 2>/dev/null || true
fi
```

### 4. Handle Failures

If project checks fail:
- Identify which Fixer's changes caused the failure
- Instruct that Fixer to correct the issue
- Re-run checks after correction

---

## Phase 6: Commit and Push

After all verifications pass, the Lead commits and pushes.

```bash
git add .
git commit -m "$(cat <<'EOF'
fix: address review feedback

- [Change 1]
- [Change 2]

Automated fixes by at-fix (Agent Teams).

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

```bash
git push
```

---

## Phase 7: PR Comment

Post a summary of fixes to the PR.

```bash
PR_NUM=$(echo "$ARGUMENTS" | grep -oE '[0-9]+' | head -1)
if [ -n "$PR_NUM" ]; then
  gh pr comment "$PR_NUM" --body "$(cat <<'EOF'
## Review Feedback Addressed (Agent Teams)

Fixes were applied in parallel by an agent team.

### Issues Fixed
- [Issue 1]: [How it was fixed]
- [Issue 2]: [How it was fixed]

### Deferred Items
- [Item]: [Reason for deferral]

Ready for re-review.
EOF
)"
fi
```

---

## Output Format

```markdown
# Fix Report (Agent Teams)

## Team
| Fixer | Files | Findings Addressed |
|-------|-------|--------------------|
| Fixer-1 | [files] | N/N fixed |
| Fixer-2 | [files] | N/N fixed |

## Issues Addressed
| Issue | Severity | Status | Changes Made |
|-------|----------|--------|--------------|
| [Issue 1] | Critical | Fixed | [Description] |
| [Issue 2] | Required | Fixed | [Description] |
| [Suggestion] | Low | Deferred | [Reason] |

## Files Changed
- `path/to/file` - [What changed]

## Verification
- [ ] All critical findings fixed
- [ ] All required findings fixed
- [ ] Project checks pass
- [ ] Changes committed and pushed
- [ ] PR comment posted

## Outstanding Items
[Any items that couldn't be resolved or need clarification]

## Next Steps
Ready for re-review: `/pw:at-rv [pr-number]` or `/pw:rv [pr-number]`
```

---

## Handling Unclear Feedback

If feedback is ambiguous:
1. Document your interpretation
2. Implement based on best understanding
3. Flag in the PR comment explaining the approach
4. Request clarification if critical
