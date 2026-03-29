---
allowed-tools: Read, Bash, Grep, Glob
argument-hint: [PR number]
description: Spawn specialist reviewers for parallel critical PR review
model: opus
---

# Agent Team PR Review

Spawn a team of reviewers to conduct parallel, adversarial PR review. Reviewers actively try to disprove each other's findings, like a scientific debate — only findings that survive challenge make it into the final report.

## Target
$ARGUMENTS

## Prerequisites

```bash
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]; then
  echo "ERROR: Agent Teams not enabled. Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json"
  exit 1
fi
PR_NUM=$(echo "$ARGUMENTS" | tr -d ' ')
echo "Agent Teams: ENABLED | PR: $PR_NUM"
```

## Gather PR Context

```bash
echo "=== PR Details ==="
gh pr view $1 2>/dev/null || echo "Provide PR number as argument"
```

```bash
echo "=== Files Changed ==="
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
gh pr diff $1 --stat 2>/dev/null || git diff "origin/${BASE_BRANCH}"...HEAD --stat
```

```bash
echo "=== Full Diff ==="
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
gh pr diff $1 2>/dev/null || git diff "origin/${BASE_BRANCH}"...HEAD
```

```bash
echo "=== CI Checks ==="
gh pr checks $1 2>/dev/null || echo "Cannot fetch CI status"
```

## Create Review Team

Create an agent team to review this PR. Adapt the number and focus of reviewers to the actual content of the changes.

Common useful review perspectives:
- Security (apply `/pw:security-review` skill) — authentication, injection, secrets, data protection
- Code quality and codebase consistency (apply `/pw:code-quality` skill) — readability, patterns, tests, hidden bugs, consistency with existing implementation
- Architecture and design — abstraction levels, coupling, SOLID, scalability, API contracts

Adapt based on the PR content — a CSS-only change does not need a security reviewer. A database migration needs data integrity focus. A new API endpoint benefits from both security and architecture review.

### How Reviewers Should Work

Each reviewer should:
1. Focus exclusively on their assigned perspective
2. For each finding, provide: Severity (Critical/High/Medium/Low), Location (file:line), Issue, Recommendation
3. After completing their own review, **actively challenge other reviewers' findings**. The goal is adversarial: try to disprove each other's findings. "Is that really a security issue or an acceptable tradeoff?" / "This finding is a false positive because..." Only findings that survive challenge are trustworthy.
4. Conclude with their individual verdict: APPROVE / REQUEST_CHANGES / COMMENT

### Lead Synthesis

Wait for all reviewers to complete (including cross-challenge). Then:
1. Collect all surviving findings
2. Deduplicate overlapping findings (keep the most severe categorization)
3. Prioritize by severity: Critical > High > Medium > Low
4. Determine verdict:
   - Any Critical finding → **REQUEST_CHANGES** (mandatory)
   - Multiple High findings → **REQUEST_CHANGES**
   - Only Medium/Low findings → **APPROVE** with comments or **COMMENT**
   - No findings → **APPROVE**
5. Generate unified review report
6. Clean up the team

## Output Format

```markdown
# Review: PR #[number]

## Reviewer Panel
| Reviewer | Focus | Findings | Verdict |
|----------|-------|----------|---------|
| [Reviewer] | [focus area] | N findings | APPROVE/REQUEST_CHANGES |

## Status: APPROVE | REQUEST_CHANGES | COMMENT

## Findings
| Issue | Severity | Domain | Location | Recommendation |
|-------|----------|--------|----------|----------------|
| [Issue] | Critical/High | [domain] | file:line | [Fix] |

## Verdict
[Detailed explanation]

## Required Changes (Must Fix)
1. [ ] [Change - file:line]

## Recommended Changes (Should Fix)
1. [ ] [Change]

## Positive Notes
- [What was done well]

## Next Steps
- If approved: `/pw:merge [pr-number]`
- If changes requested: `/pw:at-fix [pr-number]` or `/pw:fix [feedback]`
```

## Post Review to GitHub

Track each finding with a specific file:line as a structured inline comment (path, line, body).

**MANDATORY**: Ask the user whether to post the review to GitHub using the AskUserQuestion tool.

Prompt: **"Post this review to GitHub PR?"**

### If confirmed:

Determine event type (APPROVE / REQUEST_CHANGES / COMMENT), construct JSON payload with inline comments, and post via:

```bash
OWNER_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
OWNER=$(echo "$OWNER_REPO" | cut -d'/' -f1)
REPO=$(echo "$OWNER_REPO" | cut -d'/' -f2)

gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  "/repos/$OWNER/$REPO/pulls/$PR_NUM/reviews" \
  --input - <<< "$REVIEW_JSON_PAYLOAD"
```

### If declined:
Do not post.

## Actions

- **Approved**: `/pw:merge [pr-number]`
- **Changes needed**: `/pw:at-fix [pr-number]` or `/pw:fix [feedback]`
- **Discussion needed**: `gh pr comment`
