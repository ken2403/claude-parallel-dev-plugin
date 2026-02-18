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
echo "This review uses 3 specialist reviewers in parallel:"
echo "  - Security Reviewer: OWASP, auth, injection, secrets"
echo "  - Quality Reviewer: readability, patterns, tests, errors"
echo "  - Architecture Reviewer: design, coupling, SOLID, scalability"
echo ""

PR_NUM=$(echo "$ARGUMENTS" | tr -d ' ')
echo "PR Number: $PR_NUM"
```

---

## Phase 1: PR Context Collection

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

## Phase 2: Spawn Review Team

### Team Structure

| Teammate | Focus Area | Model | Skill Applied |
|----------|-----------|-------|---------------|
| **Security Reviewer** | OWASP, authentication, injection, secrets | sonnet | security-review |
| **Quality Reviewer** | Readability, pattern consistency, tests, error handling | sonnet | code-quality |
| **Architecture Reviewer** | Design, coupling, SOLID principles, scalability | sonnet | - |

**Lead Mode**: Delegate (coordinates review, synthesizes at end)

### Teammate: Security Reviewer

```
You are the **Security Reviewer** on a PR review team. Your sole focus is security.

## PR Context
- PR Number: [PR_NUM]
- PR Diff: [Full diff content]
- PR Description: [PR description]

## Your Review Scope

Apply the `/pw:security-review` skill checklist rigorously:

### Authentication & Authorization
- [ ] Authentication mechanisms are properly implemented
- [ ] Authorization checks on all protected endpoints
- [ ] Session management is secure
- [ ] Token handling follows best practices

### Input Validation & Injection Prevention
- [ ] All user inputs validated and sanitized
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (output encoding)
- [ ] Command injection prevention
- [ ] Path traversal prevention

### Data Protection & Secrets
- [ ] No hardcoded secrets, API keys, or credentials
- [ ] Sensitive data encrypted at rest and in transit
- [ ] PII handled according to requirements
- [ ] Logging does not expose sensitive data

### OWASP Top 10
- [ ] Broken access control
- [ ] Cryptographic failures
- [ ] Injection
- [ ] Insecure design
- [ ] Security misconfiguration
- [ ] Vulnerable components
- [ ] Authentication failures
- [ ] Data integrity failures
- [ ] Logging/monitoring failures
- [ ] SSRF

## Output Format
For each finding, provide:
- **Severity**: Critical / High / Medium / Low
- **Location**: file:line
- **Issue**: Description
- **Attack vector**: How it could be exploited
- **Recommendation**: How to fix it

Provide your verdict: APPROVE / REQUEST_CHANGES / COMMENT
```

### Teammate: Quality Reviewer

```
You are the **Quality Reviewer** on a PR review team. Your sole focus is code quality.

## PR Context
- PR Number: [PR_NUM]
- PR Diff: [Full diff content]
- PR Description: [PR description]

## Your Review Scope

Apply the `/pw:code-quality` skill checklist rigorously:

### Code Quality
- [ ] Logic is correct and handles edge cases
- [ ] Code is readable and maintainable
- [ ] Follows existing patterns in the codebase
- [ ] No unnecessary complexity or dead code
- [ ] Proper error handling

### Codebase Consistency
- [ ] No contradictions with existing implementation
- [ ] Coding style matches existing codebase
- [ ] Consistent use of libraries and utilities
- [ ] File/folder structure follows conventions

### Testing
- [ ] Tests added for new functionality
- [ ] Edge cases covered in tests
- [ ] Test naming and structure follow conventions

### Hidden Bugs
- [ ] Race conditions in concurrent code
- [ ] Memory/resource leaks
- [ ] Off-by-one errors
- [ ] Null pointer dereferences
- [ ] Unhandled exceptions
- [ ] N+1 query problems

## Output Format
For each finding, provide:
- **Severity**: Critical / High / Medium / Low
- **Location**: file:line
- **Issue**: Description
- **Evidence**: Why this is a problem
- **Recommendation**: How to fix it

Provide your verdict: APPROVE / REQUEST_CHANGES / COMMENT
```

### Teammate: Architecture Reviewer

```
You are the **Architecture Reviewer** on a PR review team. Your sole focus is design and architecture.

## PR Context
- PR Number: [PR_NUM]
- PR Diff: [Full diff content]
- PR Description: [PR description]

## Your Review Scope

### Design & Architecture
- [ ] Is this the right abstraction level?
- [ ] Does this introduce unnecessary coupling?
- [ ] Will this scale? (10x, 100x load)
- [ ] Is there a simpler solution?
- [ ] Does this follow SOLID principles?

### Structural Concerns
- [ ] Separation of concerns maintained
- [ ] Dependencies flow in the right direction
- [ ] API contracts are clean and well-defined
- [ ] Error boundaries are properly placed

### Maintainability
- [ ] Will this confuse future developers?
- [ ] Is the naming consistent with the rest of the codebase?
- [ ] Are there similar implementations elsewhere that differ?
- [ ] Is the approach documented where non-obvious?

### Scalability & Performance
- [ ] Database query efficiency
- [ ] Caching considerations
- [ ] Async operations where appropriate
- [ ] Resource cleanup

## Output Format
For each finding, provide:
- **Severity**: Critical / High / Medium / Low
- **Location**: file:line (or architectural scope)
- **Issue**: Description
- **Impact**: Why this matters for the codebase long-term
- **Recommendation**: Alternative approach or fix

Provide your verdict: APPROVE / REQUEST_CHANGES / COMMENT
```

---

## Phase 3: Parallel Review

All three reviewers conduct their reviews independently and in parallel. Each focuses exclusively on their domain.

---

## Phase 4: Cross-Challenge

After all reviewers complete their initial findings:

1. Each reviewer shares their findings with the team
2. Reviewers may challenge each other's findings:
   - "Is that really a security issue or an acceptable tradeoff?"
   - "The quality concern overlaps with this architecture issue"
   - "This finding is a false positive because..."
3. Challenged findings are reconsidered by the original reviewer

---

## Phase 5: Lead Integration

The Lead (this agent) synthesizes all findings into a unified review.

### Integration Process

1. **Collect** all findings from the three reviewers
2. **Deduplicate** overlapping findings (keep the most severe categorization)
3. **Prioritize** by severity: Critical > High > Medium > Low
4. **Determine verdict**:
   - Any Critical finding → **REQUEST_CHANGES** (mandatory)
   - Multiple High findings → **REQUEST_CHANGES**
   - Only Medium/Low findings → **APPROVE** with comments or **COMMENT**
   - No findings → **APPROVE**
5. **Generate** unified review report

---

## Output Format

```markdown
# Review: PR #[number]

## Reviewer Panel
| Reviewer | Focus | Findings | Verdict |
|----------|-------|----------|---------|
| Security Reviewer | OWASP, auth, injection | N findings | APPROVE/REQUEST_CHANGES |
| Quality Reviewer | Code quality, tests | N findings | APPROVE/REQUEST_CHANGES |
| Architecture Reviewer | Design, SOLID | N findings | APPROVE/REQUEST_CHANGES |

## Status: APPROVE | REQUEST_CHANGES | COMMENT

## Critical Findings

### Security Findings
| Issue | Severity | Location | Attack Vector | Recommendation |
|-------|----------|----------|---------------|----------------|
| [Issue] | Critical/High | file:line | [How to exploit] | [Fix] |

### Quality Findings
| Issue | Severity | Location | Evidence | Recommendation |
|-------|----------|----------|----------|----------------|
| [Issue] | Critical/High | file:line | [Why it's a bug] | [Fix] |

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

## Phase 6: Post Review to GitHub

### Structured Findings for Inline Comments

While generating the review report, internally track each finding that references a specific file and line as a structured inline comment. For each finding, record:
- **path**: File path relative to the repository root
- **line**: The line number in the new version of the file (must appear in the PR diff)
- **body**: A concise description including severity and recommendation

### Post Confirmation

**MANDATORY**: Ask the user whether to post the review to GitHub using the AskUserQuestion tool.

Prompt: **"Post this review to GitHub PR?"**

Explain what will be posted:
1. PR Review with the full summary as body
2. Inline comments on specific file locations
3. Review event: APPROVE / REQUEST_CHANGES / COMMENT

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

# Construct JSON payload and post
# Claude must dynamically build this JSON from actual review findings
cat <<'REVIEW_JSON' | gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  "/repos/$OWNER/$REPO/pulls/$PR_NUM/reviews" \
  --input -
{
  "body": "## Agent Team Review Summary\n\n...(full review body here)...",
  "event": "REQUEST_CHANGES",
  "comments": [
    {
      "path": "src/example.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "**[Security/Quality/Architecture - Severity]**: Description\n\nRecommendation"
    }
  ]
}
REVIEW_JSON
```

**Note**: The JSON above is illustrative. Claude must dynamically construct the actual payload from the review findings. Use proper JSON escaping for the body content.

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
