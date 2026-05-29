---
allowed-tools: Read, Bash, Grep, Glob
argument-hint: '[PR number]'
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
_PD=""; for _d in "${PW_PLUGIN_DIR:-}" "${CLAUDE_PLUGIN_ROOT:-}" ./pw ../pw ../../pw; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
gh pr diff $1 --stat 2>/dev/null || git diff "origin/${BASE_BRANCH}"...HEAD --stat
echo "=== Full Diff ==="
gh pr diff $1 2>/dev/null || git diff "origin/${BASE_BRANCH}"...HEAD
```

```bash
echo "=== CI Checks ==="
gh pr checks $1 2>/dev/null || echo "Cannot fetch CI status"
```

## Phase 0: Build Codebase Context (Lead Only)

**MANDATORY**: Before spawning any reviewers, the lead applies Steps 1-2 of `/pw:reviewing-codebase-consistency` to build a factual baseline.

### 0-1. Run Local Build

```bash
echo "=== Phase 0: Local Build Verification ==="
if [ -f "Makefile" ] && grep -q "^check:" Makefile; then
  timeout 180 make check 2>&1 | tail -100
elif [ -f "package.json" ]; then
  timeout 180 npm run build 2>&1 | tail -100
elif [ -f "Cargo.toml" ]; then
  timeout 180 cargo check 2>&1 | tail -100
elif [ -f "go.mod" ]; then
  timeout 180 go build ./... 2>&1 | tail -100
else
  echo "No build system detected — skip"
fi
```

### 0-2. Build Usage Graph

Apply Step 1 of `/pw:reviewing-codebase-consistency`:
- Extract changed entities from the diff (renamed identifiers, modified types, altered schemas, changed API contracts)
- Map usage graph for each entity using Grep/Glob — every file that imports, references, or depends on it
- Identify files in usage graph but NOT in the diff (candidates for missed changes)

### 0-3. Compile CONSISTENCY_BRIEFING

Summarize Phase 0 findings into a **concise** briefing (~50 lines max) for distribution to all reviewers:

```
CONSISTENCY_BRIEFING:
  PR_INTENT: [one-line summary]
  CHANGED_ENTITIES: [list of entities modified by the diff]
  BUILD_ERRORS: [categorized list or "none"]
  CANDIDATE_MISSED_FILES: [files in usage graph but not in diff]
```

This briefing gives every reviewer the codebase knowledge a senior reviewer has.

## Create Review Team

Create an agent team to review this PR. Adapt the number and focus of reviewers to the actual content of the changes.

Common useful review perspectives:
- Security (`/pw:security-review`) — injection, secrets, auth, data protection
- Code quality (`/pw:code-quality`) — readability, patterns, tests, consistency
- Architecture — coupling, SOLID, scalability, API contracts
- Codebase consistency (`/pw:reviewing-codebase-consistency`) — applies Steps 3-5 of the skill to verify changes propagated correctly beyond the diff

Adapt team size and focus to the PR content.

### Codebase Consistency Reviewer

Applies Steps 3-5 of `/pw:reviewing-codebase-consistency` using the CONSISTENCY_BRIEFING as a starting point:
- Reads each CANDIDATE_MISSED_FILE and confirms whether it needs updating
- Traces change propagation paths (Step 3)
- Verifies cross-layer consistency (Step 5)
- Focuses on what is MISSING from the diff, not what is wrong within it

Phase 0 provides the map; this reviewer walks the territory.

### Task List

Use the shared task list with 4 phases:
1. **Phase 0 — Context** (lead only): Build codebase context, run build, compile CONSISTENCY_BRIEFING
2. **Review** — each reviewer analyzes their assigned perspective (all parallel, no dependencies)
3. **Cross-challenge** — reviewers message each other to dispute findings (depends on phase 2)
4. **Synthesis** — lead collects surviving findings and determines verdict (depends on phase 3)

### Safety Context for ALL Reviewers

**CRITICAL**: Teammates do not inherit the lead's conversation history. Every spawn prompt MUST include:

> **Reviewer Rules** (include in every spawn prompt):
> - You are a READ-ONLY reviewer. NEVER use Edit, Write, or file-modifying Bash commands
> - NEVER run `git commit`, `git push`, or any git write commands
> - Use ONLY: Read, Grep, Glob, Bash (read-only)
> - Focus exclusively on your assigned perspective
> - Apply `/pw:security-review`, `/pw:code-quality`, or `/pw:reviewing-codebase-consistency` skills as appropriate
> - **CONSISTENCY_BRIEFING is provided below.** Use build errors and candidate missed files as your starting point.
> - **Do NOT limit your analysis to the diff.** Use Grep and Glob to search the broader codebase for related issues.

Also include in each spawn prompt: the full diff, CI status, files changed list, the reviewer's focus area, AND the CONSISTENCY_BRIEFING from Phase 0.

### Coordination

- Each reviewer provides findings as: Severity (Critical/High/Medium/Low), Location (file:line), Issue, Recommendation.
- In cross-challenge, reviewers **message each other directly** to **defend or concede** each finding. Only surviving findings enter synthesis.
- **Codebase Consistency Reviewer's findings about MISSING changes can only be challenged with evidence that the file does NOT need updating** (e.g., the reference is in dead code, or the entity is used in a different context).
- **If Phase 0 found build errors, ALL reviewers should verify whether errors relate to their domain before reporting new issues in the same area.**
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
