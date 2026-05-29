---
allowed-tools: Bash
argument-hint: '[PR number] [--skip]'
description: Merge a reviewed PR after verification
model: opus
---

# Merge PR

## Target
$ARGUMENTS

## Options

| Option | Description |
|--------|-------------|
| `--skip` | Skip human approval check (use for self-reviewed PRs) |

## Parse Options

```bash
ARGS="$ARGUMENTS"
SKIP_APPROVE=false

if echo "$ARGS" | grep -q "\-\-skip"; then
  SKIP_APPROVE=true
  ARGS=$(echo "$ARGS" | sed 's/--skip//g')
fi

PR_NUM=$(echo "$ARGS" | tr -d ' ')

echo "PR Number: $PR_NUM"
echo "Skip Approve: $SKIP_APPROVE"
```

## Merge Requirements

### Default Requirements
1. **CI Checks Must Pass**: ALL CI checks MUST be passing (green)
2. **No Merge Conflicts**: PR MUST be mergeable without conflicts
3. **Human Approval Required**: PR MUST have approval (unless `--skip`)

### With --skip
- Skips the human approval check
- Useful for solo development or self-reviewed PRs
- CI checks and merge conflict checks still apply

```bash
# Verification script
REVIEW=$(gh pr view $PR_NUM --json reviewDecision --jq '.reviewDecision' 2>/dev/null)
CI_STATUS=$(gh pr checks $PR_NUM 2>/dev/null | grep -v "no checks" | grep -c "fail\|pending" || echo "0")
MERGEABLE=$(gh pr view $PR_NUM --json mergeable --jq '.mergeable' 2>/dev/null)

echo ""
echo "=== Merge Requirements Check ==="

# Check CI (always required)
if [ "$CI_STATUS" != "0" ] && [ -n "$CI_STATUS" ]; then
  echo "⛔ BLOCKED: CI checks not passing"
  gh pr checks $PR_NUM 2>/dev/null
  exit 1
else
  echo "✅ CI checks: OK (or no checks configured)"
fi

# Check mergeable (always required)
if [ "$MERGEABLE" = "CONFLICTING" ]; then
  echo "⛔ BLOCKED: PR has merge conflicts"
  echo "Run: /pw:resolve-conflicts"
  exit 1
else
  echo "✅ Merge conflicts: None"
fi

# Check approval (skip if --skip)
if [ "$SKIP_APPROVE" = "true" ]; then
  echo "⚠️  Approval check: SKIPPED (--skip)"
else
  if [ "$REVIEW" != "APPROVED" ]; then
    echo "⛔ BLOCKED: PR not approved by human reviewer"
    echo "Current status: $REVIEW"
    echo ""
    echo "Options:"
    echo "  1. Get human approval on the PR"
    echo "  2. Use --skip to bypass (for self-reviewed PRs)"
    exit 1
  else
    echo "✅ Approval: APPROVED"
  fi
fi

echo ""
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
1. Are CI checks passing?
   └─ No → Cannot merge. Fix CI issues first.
   └─ Yes → Continue

2. Is it mergeable (no conflicts)?
   └─ No → Run /pw:resolve-conflicts first.
   └─ Yes → Continue

3. Is PR approved OR --skip provided?
   └─ No → Cannot merge. Get approval or use --skip.
   └─ Yes → Proceed with merge
```

## Merge Execution

```bash
echo "=== Executing Merge ==="
gh pr merge $PR_NUM --merge --delete-branch

if [ $? -eq 0 ]; then
  echo "✅ PR merged successfully"
else
  echo "❌ Merge failed"
  exit 1
fi
```

## Post-merge

```bash
echo ""
echo "=== Merge Complete ==="
DEFAULT_BRANCH=$(gh pr view $PR_NUM --json baseRefName --jq '.baseRefName' 2>/dev/null || git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main")
echo "Update your local $DEFAULT_BRANCH branch:"
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
| Not approved | Request review: `/pw:rv [number]` |
| CI failing | Fix issues in worker session |
| Conflicts | Resolve: `/pw:resolve-conflicts [branch]` |
| Protected branch | Request admin merge or adjust settings |
