---
allowed-tools: Read, Bash, Grep, Glob
argument-hint: [PR number]
description: Spawn specialist reviewers for parallel critical PR review
model: opus
---

# Agent Team PR Review (Critical)

Spawn a team of three specialist reviewers to conduct parallel, adversarial PR review with cross-challenge.

## Target
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

## Review Mode

```bash
echo "*** AGENT TEAM CRITICAL REVIEW MODE ***"
echo ""
echo "3 specialist reviewers running in parallel:"
echo "  - Security Reviewer: OWASP, auth, injection, secrets"
echo "  - Quality & Consistency Reviewer: readability, patterns, tests, hidden bugs"
echo "  - Architecture Reviewer: design, coupling, SOLID, scalability"
echo ""
PR_NUM=$(echo "$ARGUMENTS" | tr -d ' ')
echo "PR Number: $PR_NUM"
```

---

## PR Context Collection

### PR Details
```bash
echo "=== PR Details ==="
gh pr view $1 2>/dev/null || echo "Provide PR number as argument"
```

### Changes Overview
```bash
echo "=== Files Changed ==="
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
gh pr diff $1 --stat 2>/dev/null || git diff "origin/${BASE_BRANCH}"...HEAD --stat
```

### Full Diff
```bash
echo "=== Full Diff ==="
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
gh pr diff $1 2>/dev/null || git diff "origin/${BASE_BRANCH}"...HEAD
```

### CI Status
```bash
echo "=== CI Checks ==="
gh pr checks $1 2>/dev/null || echo "Cannot fetch CI status"
```

---

## Team Configuration

| Teammate | Focus Area | Model | Skill Applied |
|----------|-----------|-------|---------------|
| **Security Reviewer** | OWASP Top 10, authentication, authorization, injection, secrets, data protection | sonnet | `/pw:security-review` |
| **Quality & Consistency Reviewer** | Readability, maintainability, error handling, testing, hidden bugs, codebase consistency | sonnet | `/pw:code-quality` |
| **Architecture Reviewer** | Design, abstraction levels, coupling, SOLID principles, scalability, performance, API contracts | sonnet | - |

### Spawn: Security Reviewer

```
You are the Security Reviewer on a PR review team. Apply the /pw:security-review skill.

Focus on: OWASP Top 10, authentication mechanisms, authorization checks, injection prevention
(SQL, XSS, command), secrets management (no hardcoded credentials), data protection (encryption,
PII handling, logging safety), and API security.

For each finding provide: Severity (Critical/High/Medium/Low), Location (file:line), Issue,
Attack vector, Recommendation.

After completing your findings, review the other reviewers' findings and cross-challenge where
appropriate ("Is that really a security issue or an acceptable tradeoff?", "This finding is a
false positive because...").

Conclude with your verdict: APPROVE / REQUEST_CHANGES / COMMENT
```

### Spawn: Quality & Consistency Reviewer

```
You are the Quality & Consistency Reviewer on a PR review team. Apply the /pw:code-quality skill.

Focus on: code readability and maintainability, codebase pattern consistency (contradictions with
existing implementation, coding style match, library/utility consistency), error handling, test
coverage and quality, edge case handling, and hidden bugs (race conditions, N+1 queries, memory
leaks, off-by-one errors, unhandled exceptions).

For each finding provide: Severity (Critical/High/Medium/Low), Location (file:line), Issue,
Evidence, Recommendation.

After completing your findings, review the other reviewers' findings and cross-challenge where
appropriate ("The quality concern overlaps with this architecture issue", "This finding is a
false positive because...").

Conclude with your verdict: APPROVE / REQUEST_CHANGES / COMMENT
```

### Spawn: Architecture Reviewer

```
You are the Architecture Reviewer on a PR review team.

Focus on: abstraction levels (is this the right layer?), coupling and dependencies, SOLID
principles, scalability considerations (10x/100x load), performance (query efficiency, caching,
async operations), and API contract cleanliness (well-defined boundaries, error propagation).

For each finding provide: Severity (Critical/High/Medium/Low), Location (file:line or
architectural scope), Issue, Impact (long-term consequence), Recommendation.

After completing your findings, review the other reviewers' findings and cross-challenge where
appropriate ("The architecture concern is actually a security boundary issue", "This finding is
a false positive because...").

Conclude with your verdict: APPROVE / REQUEST_CHANGES / COMMENT
```

---

## Coordination

All three reviewers work in parallel on the same PR diff. After completing their own domain
review, each reviewer reads the others' findings and may challenge them directly. Challenged
findings must be reconsidered by the original reviewer.

Wait for all reviewers to complete before synthesizing. The lead (this agent) then:
1. Collects all findings from the three reviewers
2. Deduplicates overlapping findings (keep the most severe categorization)
3. Prioritizes by severity: Critical > High > Medium > Low
4. Determines verdict:
   - Any Critical finding → **REQUEST_CHANGES** (mandatory)
   - Multiple High findings → **REQUEST_CHANGES**
   - Only Medium/Low findings → **APPROVE** with comments or **COMMENT**
   - No findings → **APPROVE**
5. Generates unified review report

---

## Output Format

```markdown
# Review: PR #[number]

## Reviewer Panel
| Reviewer | Focus | Findings | Verdict |
|----------|-------|----------|---------|
| Security Reviewer | OWASP, auth, injection | N findings | APPROVE/REQUEST_CHANGES |
| Quality & Consistency Reviewer | Code quality, consistency, tests | N findings | APPROVE/REQUEST_CHANGES |
| Architecture Reviewer | Design, SOLID | N findings | APPROVE/REQUEST_CHANGES |

## Status: APPROVE | REQUEST_CHANGES | COMMENT

## Critical Findings

### Security Findings
| Issue | Severity | Location | Attack Vector | Recommendation |
|-------|----------|----------|---------------|----------------|
| [Issue] | Critical/High | file:line | [How to exploit] | [Fix] |

### Quality & Consistency Findings
| Issue | Severity | Location | Evidence | Recommendation |
|-------|----------|----------|----------|----------------|
| [Issue] | Critical/High | file:line | [Why it's a problem] | [Fix] |

### Architecture Findings
| Issue | Severity | Location | Impact | Recommendation |
|-------|----------|----------|--------|----------------|
| [Issue] | Critical/High | scope | [Long-term impact] | [Fix] |

## Verdict
[Detailed explanation of the unified decision]

## Required Changes (Must Fix)
1. [ ] [Change 1 - file:line]
2. [ ] [Change 2 - file:line]

## Recommended Changes (Should Fix)
1. [ ] [Change 1]
2. [ ] [Change 2]

## Positive Notes
- [What was done well - be specific]

## Next Steps
- If approved: `/pw:merge [pr-number]`
- If changes requested: `/pw:at-fix [pr-number]` (Agent Teams) or `/pw:fix [feedback]`
```

---

## Post Review to GitHub

While generating the review report, internally track each finding that references a specific file
and line as a structured inline comment, recording: path (relative to repo root), line (in the
new version of the file, must appear in the PR diff), and body (severity + description +
recommendation).

**MANDATORY**: Ask the user whether to post the review to GitHub using the AskUserQuestion tool.

Prompt: **"Post this review to GitHub PR?"**

Explain what will be posted: full review summary as body, inline comments on specific file
locations, and the review event (APPROVE / REQUEST_CHANGES / COMMENT).

### If the user confirms:

#### 1. Determine review event type
- `APPROVE` → `APPROVE`
- `REQUEST_CHANGES` → `REQUEST_CHANGES`
- Otherwise → `COMMENT`

#### 2. Construct and post review

```bash
# Get repository info
OWNER_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
OWNER=$(echo "$OWNER_REPO" | cut -d'/' -f1)
REPO=$(echo "$OWNER_REPO" | cut -d'/' -f2)

# Dynamically construct JSON payload from actual review findings and post
# Use proper JSON escaping for body content; include inline comments for findings with file:line
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  "/repos/$OWNER/$REPO/pulls/$PR_NUM/reviews" \
  --input - <<< "$REVIEW_JSON_PAYLOAD"
```

#### 3. Report result

```markdown
### Review Posted to GitHub
- **Review type**: APPROVE / REQUEST_CHANGES / COMMENT
- **Inline comments**: N posted
- **PR URL**: [link]
```

### If the user declines:
Do not post. Proceed to Actions.

---

## Actions

After review:
- **Approved**: `/pw:merge [pr-number]`
- **Changes needed**: `/pw:at-fix [pr-number]` (Agent Teams parallel fix) or `/pw:fix [feedback]`
- **Discussion needed**: Comment on PR via `gh pr comment`
