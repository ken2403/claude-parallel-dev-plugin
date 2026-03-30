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
echo "=== Full Diff ==="
gh pr diff $1 2>/dev/null || git diff "origin/${BASE_BRANCH}"...HEAD
```

```bash
echo "=== CI Checks ==="
gh pr checks $1 2>/dev/null || echo "Cannot fetch CI status"
```

## Create Review Team

Create an agent team to review this PR. Adapt the number and focus of reviewers to the actual content of the changes.

Common useful review perspectives:
- Security (`/pw:security-review`) — injection, secrets, auth, data protection
- Code quality (`/pw:code-quality`) — readability, patterns, tests, consistency
- Architecture — coupling, SOLID, scalability, API contracts

Adapt team size and focus to the PR content.

### Task List

Use the shared task list with 3 phases:
1. **Review** — each reviewer analyzes their assigned perspective (no dependencies)
2. **Cross-challenge** — reviewers message each other to dispute findings (depends on phase 1)
3. **Synthesis** — lead collects surviving findings and determines verdict (depends on phase 2)

### Safety Context for ALL Reviewers

**CRITICAL**: Teammates do not inherit the lead's conversation history. Every spawn prompt MUST include:

> **Reviewer Rules** (include in every spawn prompt):
> - You are a READ-ONLY reviewer. NEVER use Edit, Write, or file-modifying Bash commands
> - NEVER run `git commit`, `git push`, or any git write commands
> - Use ONLY: Read, Grep, Glob, Bash (read-only)
> - Focus exclusively on your assigned perspective
> - Apply `/pw:security-review` or `/pw:code-quality` skills as appropriate

Also include in each spawn prompt: the full diff, CI status, files changed list, and the reviewer's focus area.

### Coordination

- Each reviewer provides findings as: Severity (Critical/High/Medium/Low), Location (file:line), Issue, Recommendation.
- In cross-challenge, reviewers **message each other directly** to **defend or concede** each finding. Only surviving findings enter synthesis.
- The lead determines verdict: any Critical → REQUEST_CHANGES; multiple High → REQUEST_CHANGES; only Medium/Low → APPROVE with comments; no findings → APPROVE.
- **Wait for ALL reviewers** to complete before synthesis.
- Clean up the team after posting the review report.

## Output Format

```markdown
# Review: PR #[number]

## Reviewer Panel
| Reviewer | Focus | Findings | Verdict |
|----------|-------|----------|---------|

## Status: APPROVE | REQUEST_CHANGES | COMMENT
[Verdict explanation]

## Findings
| Severity | Domain | Location | Issue | Recommendation |
|----------|--------|----------|-------|----------------|

## Action Items
- [ ] [Must fix] Critical/High — file:line — description
- [ ] [Should fix] Medium/Low — description

## Next Steps
- Approved: `/pw:merge [pr-number]`
- Changes needed: `/pw:at-fix [pr-number]` or `/pw:fix [feedback]`
```

## Post Review to GitHub

Track each finding with file:line as a structured inline comment (path, line, body).

**MANDATORY**: Ask the user via AskUserQuestion: **"Post this review to GitHub PR?"**

If confirmed, determine event type (APPROVE / REQUEST_CHANGES / COMMENT), construct JSON payload with inline comments, and post:

```bash
OWNER_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
OWNER=$(echo "$OWNER_REPO" | cut -d'/' -f1)
REPO=$(echo "$OWNER_REPO" | cut -d'/' -f2)
gh api --method POST -H "Accept: application/vnd.github+json" \
  "/repos/$OWNER/$REPO/pulls/$PR_NUM/reviews" --input - <<< "$REVIEW_JSON_PAYLOAD"
```

## Actions

- **Approved**: `/pw:merge [pr-number]`
- **Changes needed**: `/pw:at-fix [pr-number]` or `/pw:fix [feedback]`
