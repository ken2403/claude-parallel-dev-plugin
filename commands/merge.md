---
allowed-tools: Bash
argument-hint: [PR number] [--auto for auto-merge without confirmation]
description: Merge a reviewed PR after verification
model: opus
---

# Merge PR

## Target
$ARGUMENTS

## ⛔ MANDATORY MERGE REQUIREMENTS

**CRITICAL: The following conditions MUST be met before ANY merge. No exceptions!**

### Absolute Requirements (NEVER bypass)
1. **Human Approval Required**: PR MUST have at least one human approval (`APPROVED` status)
2. **CI Checks Must Pass**: ALL CI checks MUST be passing (green)
3. **No Merge Conflicts**: PR MUST be mergeable without conflicts

### Enforcement
- **NEVER** merge if `reviewDecision` is not `APPROVED`
- **NEVER** merge if any CI check is failing or pending
- **NEVER** use `--auto` flag to bypass these requirements
- If any requirement is not met, **STOP** and report to the user

```bash
# Verification script - run this FIRST
PR_NUM=$1
REVIEW=$(gh pr view $PR_NUM --json reviewDecision --jq '.reviewDecision' 2>/dev/null)
CI_STATUS=$(gh pr checks $PR_NUM --json state --jq 'all(.state == "SUCCESS")' 2>/dev/null)
MERGEABLE=$(gh pr view $PR_NUM --json mergeable --jq '.mergeable' 2>/dev/null)

if [ "$REVIEW" != "APPROVED" ]; then
  echo "⛔ BLOCKED: PR not approved by human reviewer"
  echo "Current status: $REVIEW"
  exit 1
fi

if [ "$CI_STATUS" != "true" ]; then
  echo "⛔ BLOCKED: CI checks not passing"
  exit 1
fi

if [ "$MERGEABLE" != "MERGEABLE" ]; then
  echo "⛔ BLOCKED: PR has merge conflicts"
  exit 1
fi

echo "✅ All requirements met - safe to proceed"
```

## Pre-merge Verification

### PR Status
```bash
echo "=== PR Details ==="
gh pr view $1 --json state,reviewDecision,mergeable,mergeStateStatus,title,headRefName 2>/dev/null || echo "Provide PR number"
```

### CI Checks
```bash
echo ""
echo "=== CI Status ==="
gh pr checks $1 2>/dev/null || echo "Cannot fetch CI status"
```

### Reviews
```bash
echo ""
echo "=== Reviews ==="
gh pr view $1 --json reviews --jq '.reviews[] | "\(.author.login): \(.state)"' 2>/dev/null || echo "No reviews"
```

### Merge Conflicts
```bash
echo ""
echo "=== Mergeable Status ==="
gh pr view $1 --json mergeable --jq '.mergeable' 2>/dev/null || echo "Cannot determine"
```

## Merge Decision Tree

```
1. Is PR approved?
   └─ No → Cannot merge. Request review first.
   └─ Yes → Continue

2. Are CI checks passing?
   └─ No → Cannot merge. Fix CI issues first.
   └─ Yes → Continue

3. Is it mergeable (no conflicts)?
   └─ No → Run /pw:resolve-conflicts first.
   └─ Yes → Continue

4. Is --auto flag provided?
   └─ No → Show confirmation message
   └─ Yes → Proceed with merge
```

## Merge Execution

### Without --auto (default)
```markdown
⚠️ **Merge Confirmation Required**

PR #[number]: [title]
Branch: [branch] → [base branch]

Please confirm by running one of:
- `gh pr merge [number] --squash` (squash and merge)
- `gh pr merge [number] --merge` (merge commit)
- `gh pr merge [number] --rebase` (rebase and merge)

Or use `/pw:merge [number] --auto` to auto-merge.
```

### With --auto flag
```bash
gh pr merge $1 --squash --delete-branch
```

## Post-merge

```bash
echo ""
echo "=== Merge Complete ==="
echo "Update your local main branch:"
echo "  git checkout [base-branch] && git pull"
echo ""
echo "If more PRs to merge:"
echo "  /pw:merge [next-pr-number]"
echo ""
echo "If all PRs merged:"
echo "  /pw:cleanup [branch1] [branch2] ..."
```

## Output Format

```markdown
# Merge Status

## PR #[number]
- **Title**: [title]
- **Branch**: [branch]
- **Status**: [Merged / Pending / Cannot merge]

## Pre-merge Checks
- [ ] PR approved
- [ ] CI checks passing
- [ ] No merge conflicts

## Action Taken
[Merged successfully / Waiting for confirmation / Blocked - reason]

## Next Steps
[What to do next]
```

## Error Handling

| Error | Solution |
|-------|----------|
| Not approved | Request review: `/pw:review [number]` |
| CI failing | Fix issues in worker session |
| Conflicts | Resolve: `/pw:resolve-conflicts [branch]` |
| Protected branch | Request admin merge or adjust settings |
