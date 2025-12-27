---
allowed-tools: Bash
argument-hint: [PR number] [--auto for auto-merge without confirmation]
description: Merge a reviewed PR after verification
model: opus
---

# Merge PR

## Target
$ARGUMENTS

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
Branch: [branch] → main

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
echo "  git checkout main && git pull"
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
