---
allowed-tools: Read, Bash, Grep, Glob
argument-hint: [PR number]
description: Review a pull request critically for quality, security, and correctness
model: opus
---

# PR Review (Critical)

## Target
$ARGUMENTS

## Review Mode

**CRITICAL REVIEW MODE**

All reviews are conducted with adversarial thinking.

```bash
echo "*** CRITICAL REVIEW MODE ***"
echo ""
echo "This review will be thorough and critical:"
echo "  - Assume nothing is correct until verified"
echo "  - Look for hidden bugs, edge cases, and design flaws"
echo "  - Question every design decision"
echo "  - Check for security vulnerabilities aggressively"
echo "  - Verify consistency with existing codebase"
echo ""

PR_NUM=$(echo "$ARGUMENTS" | tr -d ' ')
echo "PR Number: $PR_NUM"
```

## PR Information
```bash
# Get PR details
gh pr view $1 2>/dev/null || echo "Provide PR number as argument"
```

## Review Context

### Changes Overview
```bash
echo "=== Files Changed ==="
# Base branch detection (using shared script)
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
gh pr diff $1 --stat 2>/dev/null || git diff "origin/${BASE_BRANCH}"...HEAD --stat
```

### Detailed Diff
```bash
echo ""
echo "=== Diff Preview (first 200 lines) ==="
# Base branch detection (using shared script)
_PD=""; for _d in .claude-paralell-dev-plugin ../.claude-paralell-dev-plugin ../../.claude-paralell-dev-plugin; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
gh pr diff $1 2>/dev/null | head -200 || git diff "origin/${BASE_BRANCH}"...HEAD | head -200
```

### CI Status
```bash
echo ""
echo "=== CI Checks ==="
gh pr checks $1 2>/dev/null || echo "Cannot fetch CI status"
```

## Apply Review Skills

**MANDATORY**: Apply the following skills for comprehensive review:

1. **Code Quality Skill** (`/pw:code-quality`):
   - Readability, maintainability, simplicity
   - Type safety, error handling
   - Naming conventions, code smells
   - Consistency with existing codebase patterns

2. **Security Review Skill** (`/pw:security-review`):
   - Authentication & authorization
   - Input validation & injection prevention
   - Data protection & secrets management
   - OWASP Top 10 vulnerabilities

Refer to the skill definitions for detailed checklists.

## Review Checklist Summary

### Code Quality
- [ ] Logic is correct and handles edge cases
- [ ] Code is readable and maintainable
- [ ] Follows existing patterns in the codebase
- [ ] No unnecessary complexity
- [ ] Proper error handling

### Codebase Consistency
- [ ] No contradictions with existing implementation (API contracts, data structures, business logic)
- [ ] Coding style matches existing codebase (naming conventions, formatting, idioms)
- [ ] Consistent use of libraries and utilities already in the project
- [ ] File/folder structure follows existing conventions

### Security
- [ ] No hardcoded secrets or credentials
- [ ] Input validation on external data
- [ ] No injection vulnerabilities (SQL, XSS, command)
- [ ] Sensitive data handled appropriately

### Testing & Documentation
- [ ] Tests added for new functionality
- [ ] Edge cases covered
- [ ] Code comments where needed

## Review Process

1. **Read the PR description** - Understand intent
2. **Review the diff** - Check each file changed
3. **Run tests locally** (if needed)
4. **Check CI status** - All checks passing?
5. **Provide feedback** - Be specific and constructive

---

## Critical Review Guidelines (Applied by Default)

Apply **adversarial thinking** to every review:

### Mindset
- **Assume bugs exist** - Your job is to find them
- **Question everything** - Why was this approach chosen? Are there better alternatives?
- **Think like an attacker** - How could this code be exploited?
- **Consider edge cases** - What happens with null, empty, negative, huge, or malformed inputs?
- **Check for regressions** - Does this break existing functionality?

### Additional Critical Checks

#### Design & Architecture
- [ ] Is this the right abstraction level?
- [ ] Does this introduce unnecessary coupling?
- [ ] Will this scale? What happens with 10x, 100x load?
- [ ] Is there a simpler solution?
- [ ] Does this follow SOLID principles?

#### Hidden Bugs
- [ ] Race conditions in concurrent code?
- [ ] Memory leaks or resource leaks?
- [ ] Off-by-one errors?
- [ ] Integer overflow/underflow?
- [ ] Null pointer dereferences?
- [ ] Unhandled exceptions that could crash the system?
- [ ] N+1 query problems (queries inside loops)?

#### Edge Cases
- [ ] Empty collections/strings
- [ ] Single element collections
- [ ] Maximum/minimum values
- [ ] Unicode and special characters
- [ ] Timezone issues
- [ ] Daylight saving time transitions

#### Security (Aggressive)
- [ ] Can user input reach this code path?
- [ ] Is there any way to bypass validation?
- [ ] Could timing attacks leak information?
- [ ] Are error messages leaking sensitive data?
- [ ] Is logging capturing sensitive information?

#### Consistency Issues
- [ ] Does this contradict existing patterns?
- [ ] Are there similar implementations elsewhere that differ?
- [ ] Will this confuse future developers?
- [ ] Is the naming consistent with the rest of the codebase?

## Output Format

```markdown
# Review: PR #[number]

## Summary
[Brief description of what this PR does]

## Status: ✅ Approved | ⚠️ Changes Requested | ❌ Rejected

## Critical Findings

### Design Issues
| Issue | Severity | Location | Recommendation |
|-------|----------|----------|----------------|
| [Issue] | High/Medium/Low | file:line | [Fix] |

### Potential Bugs
| Bug | Impact | Location | Evidence |
|-----|--------|----------|----------|
| [Bug] | [Impact] | file:line | [Why this is a bug] |

### Security Concerns
| Concern | Risk Level | Attack Vector | Mitigation |
|---------|------------|---------------|------------|
| [Concern] | Critical/High/Medium | [How to exploit] | [Fix] |

### Consistency Problems
- [ ] [Problem with file:line reference]

### Questions for Author
1. Why did you choose [X] instead of [Y]?
2. What happens when [edge case]?
3. Have you considered [alternative approach]?

### Positive Notes
- [What was done well - be specific]

## Verdict
[Detailed explanation of decision]

## Required Changes (Must Fix)
1. [ ] [Change 1 - file:line]
2. [ ] [Change 2 - file:line]

## Recommended Changes (Should Fix)
1. [ ] [Change 1]
2. [ ] [Change 2]

## Next Steps
- [What should happen after this review]
- If changes requested: Fix issues and run `/pw:rv [pr]` again
```

## Structured Findings for GitHub Posting

While generating the review report, internally track each finding that references a specific file and line as a structured inline comment. For each finding, record:
- **path**: File path relative to the repository root (e.g., `src/auth/login.ts`)
- **line**: The line number in the new version of the file (must appear in the PR diff)
- **body**: A concise description including severity and recommendation

These will be used when posting the review to GitHub.

## Post Review to GitHub

**MANDATORY**: After generating the review report, ALWAYS ask the user whether to post the review to GitHub using the AskUserQuestion tool.

Prompt: **「このレビュー結果をGitHub PRにコメントとして投稿しますか？」**

Explain what will be posted:
1. PR Review としてサマリー（レビュー全体の要約）をbodyに投稿
2. 指摘箇所にインラインコメントを投稿
3. レビュー結果に応じて APPROVE / REQUEST_CHANGES / COMMENT として送信

### If the user confirms (yes):

#### 1. Determine review event type

Map the review verdict to a GitHub review event:
- `Status: ✅ Approved` → `APPROVE`
- `Status: ⚠️ Changes Requested` → `REQUEST_CHANGES`
- `Status: ❌ Rejected` → `REQUEST_CHANGES`
- その他 → `COMMENT`

#### 2. Construct review body

Use the full review markdown report (Summary, Critical Findings, Verdict, Required Changes, Recommended Changes) as the review body.

#### 3. Collect inline comments

From all findings tables (Design Issues, Potential Bugs, Security Concerns, Consistency Problems, Required Changes, Recommended Changes), extract entries with `file:line` locations. For each, create:

```json
{
  "path": "relative/path/to/file.ext",
  "line": 42,
  "side": "RIGHT",
  "body": "**[Severity]**: [Issue description]\n\n[Recommendation]"
}
```

**Important**: The `line` must refer to a line present in the PR diff (right side). If a line number is not in the diff, skip that inline comment and include the finding only in the review body.

If no findings have specific `file:line` references, post only the review body with an empty comments array.

#### 4. Post via gh api

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
  "body": "## Review Summary\n\n...(full review body here)...",
  "event": "REQUEST_CHANGES",
  "comments": [
    {
      "path": "src/example.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "**High**: Description of issue and recommendation"
    }
  ]
}
REVIEW_JSON
```

**Note**: The JSON above is illustrative. Claude must dynamically construct the actual payload from the review findings. Use proper JSON escaping for the body content.

#### 5. Report result

After posting, report:
```markdown
### ✅ Review Posted to GitHub

- **Review type**: APPROVE / REQUEST_CHANGES / COMMENT
- **Inline comments**: N件投稿
- **PR URL**: [link]
```

If the API call fails, report the error and suggest retrying or manual posting.

### If the user declines (no):

Do not post. Proceed to the Actions section.

---

## Actions

After review:
- **Approved**: `/pw:merge [pr-number]`
- **Changes needed**: `/pw:fix [review feedback]` (in worker session)
- **Discussion needed**: Comment on PR via `gh pr comment`
