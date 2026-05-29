---
allowed-tools: Read, Bash, Grep, Glob
argument-hint: "[branch name or 'HEAD']"
description: Pre-PR check for local verification, tests, code quality, and codebase consistency
model: opus
---

# Pre-PR Check

Run comprehensive checks before creating a pull request.

## Target
$ARGUMENTS

## Context
```bash
echo "=== Current Branch ==="
git branch --show-current

echo ""
echo "=== Base Branch Detection ==="
# Base branch detection (using shared script)
_PD=""; for _d in "${CLAUDE_PLUGIN_ROOT:-}" ./pw ../pw ../../pw "$HOME"/.claude/plugins/cache/claude-parallel-dev-plugin/pw/*; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
echo "Base branch: $BASE_BRANCH"

echo ""
echo "=== Changes Summary ==="
git diff ${BASE_BRANCH}...HEAD --stat 2>/dev/null || git diff HEAD~5 --stat
```

---

## Phase 1: Local Checks (Lint, Format, Type Check)

**MANDATORY**: All local checks must pass before PR creation.

### Detect and Run Project Checks
```bash
echo "=== Running Local Checks ==="

# Track overall status
CHECKS_PASSED=true

# Check for Makefile
if [ -f "Makefile" ]; then
  echo ""
  echo "--- Makefile checks ---"

  if grep -q "^lint:" Makefile; then
    echo "Running: make lint"
    if ! make lint; then
      CHECKS_PASSED=false
      echo "❌ make lint failed"
    else
      echo "✅ make lint passed"
    fi
  fi

  if grep -q "^format:" Makefile; then
    echo "Running: make format (check mode)"
    if ! make format 2>&1 | grep -i "error\|fail"; then
      echo "✅ format check passed"
    else
      CHECKS_PASSED=false
      echo "❌ format check failed"
    fi
  fi

  if grep -q "^typecheck:" Makefile; then
    echo "Running: make typecheck"
    if ! make typecheck; then
      CHECKS_PASSED=false
      echo "❌ make typecheck failed"
    else
      echo "✅ make typecheck passed"
    fi
  fi

  if grep -q "^check:" Makefile; then
    echo "Running: make check"
    if ! make check; then
      CHECKS_PASSED=false
      echo "❌ make check failed"
    else
      echo "✅ make check passed"
    fi
  fi
fi

# Node.js projects
if [ -f "package.json" ]; then
  echo ""
  echo "--- Node.js checks ---"

  if grep -q '"lint"' package.json; then
    echo "Running: npm run lint"
    if ! npm run lint 2>/dev/null; then
      CHECKS_PASSED=false
      echo "❌ npm run lint failed"
    else
      echo "✅ npm run lint passed"
    fi
  fi

  if grep -q '"typecheck"' package.json || grep -q '"type-check"' package.json; then
    echo "Running: npm run typecheck"
    if ! npm run typecheck 2>/dev/null && ! npm run type-check 2>/dev/null; then
      CHECKS_PASSED=false
      echo "❌ typecheck failed"
    else
      echo "✅ typecheck passed"
    fi
  fi

  if grep -q '"build"' package.json; then
    echo "Running: npm run build"
    if ! npm run build 2>/dev/null; then
      CHECKS_PASSED=false
      echo "❌ npm run build failed"
    else
      echo "✅ npm run build passed"
    fi
  fi
fi

# Python projects
if [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  echo ""
  echo "--- Python checks ---"

  # Ruff/flake8/pylint
  if command -v ruff &>/dev/null; then
    echo "Running: ruff check"
    if ! ruff check . 2>/dev/null; then
      CHECKS_PASSED=false
      echo "❌ ruff check failed"
    else
      echo "✅ ruff check passed"
    fi
  fi

  # mypy
  if command -v mypy &>/dev/null || [ -f "pyproject.toml" ]; then
    echo "Running: mypy"
    if ! uv run mypy . 2>/dev/null && ! mypy . 2>/dev/null; then
      CHECKS_PASSED=false
      echo "❌ mypy failed"
    else
      echo "✅ mypy passed"
    fi
  fi
fi

# Rust projects
if [ -f "Cargo.toml" ]; then
  echo ""
  echo "--- Rust checks ---"

  echo "Running: cargo check"
  if ! cargo check; then
    CHECKS_PASSED=false
    echo "❌ cargo check failed"
  else
    echo "✅ cargo check passed"
  fi

  echo "Running: cargo clippy"
  if ! cargo clippy -- -D warnings 2>/dev/null; then
    CHECKS_PASSED=false
    echo "❌ cargo clippy failed"
  else
    echo "✅ cargo clippy passed"
  fi
fi

# Go projects
if [ -f "go.mod" ]; then
  echo ""
  echo "--- Go checks ---"

  echo "Running: go vet"
  if ! go vet ./...; then
    CHECKS_PASSED=false
    echo "❌ go vet failed"
  else
    echo "✅ go vet passed"
  fi

  if command -v golangci-lint &>/dev/null; then
    echo "Running: golangci-lint"
    if ! golangci-lint run; then
      CHECKS_PASSED=false
      echo "❌ golangci-lint failed"
    else
      echo "✅ golangci-lint passed"
    fi
  fi
fi

echo ""
echo "=== Local Checks Summary ==="
if [ "$CHECKS_PASSED" = true ]; then
  echo "✅ All local checks passed"
else
  echo "❌ Some local checks failed - fix before creating PR"
fi
```

---

## Phase 2: Test Verification

**MANDATORY**: All tests must pass before PR creation.

### Run Project Tests
```bash
echo "=== Running Tests ==="

TESTS_PASSED=true

# Makefile test
if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
  echo "Running: make test"
  if ! make test; then
    TESTS_PASSED=false
    echo "❌ make test failed"
  else
    echo "✅ make test passed"
  fi
fi

# Node.js
if [ -f "package.json" ] && grep -q '"test"' package.json; then
  echo "Running: npm test"
  if ! npm test 2>/dev/null; then
    TESTS_PASSED=false
    echo "❌ npm test failed"
  else
    echo "✅ npm test passed"
  fi
fi

# Python
if [ -f "pyproject.toml" ] || [ -f "pytest.ini" ] || [ -d "tests" ]; then
  if [ -f "pyproject.toml" ]; then
    echo "Running: uv run pytest"
    if ! uv run pytest 2>/dev/null; then
      TESTS_PASSED=false
      echo "❌ pytest failed"
    else
      echo "✅ pytest passed"
    fi
  elif command -v pytest &>/dev/null; then
    echo "Running: pytest"
    if ! pytest 2>/dev/null; then
      TESTS_PASSED=false
      echo "❌ pytest failed"
    else
      echo "✅ pytest passed"
    fi
  fi
fi

# Rust
if [ -f "Cargo.toml" ]; then
  echo "Running: cargo test"
  if ! cargo test; then
    TESTS_PASSED=false
    echo "❌ cargo test failed"
  else
    echo "✅ cargo test passed"
  fi
fi

# Go
if [ -f "go.mod" ]; then
  echo "Running: go test"
  if ! go test ./...; then
    TESTS_PASSED=false
    echo "❌ go test failed"
  else
    echo "✅ go test passed"
  fi
fi

echo ""
echo "=== Test Summary ==="
if [ "$TESTS_PASSED" = true ]; then
  echo "✅ All tests passed"
else
  echo "❌ Some tests failed - fix before creating PR"
fi
```

---

## Phase 3: Code Quality & Codebase Consistency Review

**MANDATORY**: Use subagents to verify code quality and consistency.

### 3.1 Explore Existing Patterns

Before reviewing changes, use explorer to understand existing patterns:
```
Use explorer subagent to understand coding patterns, conventions, and architecture in this codebase
```

### 3.2 Apply Quality Skills

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

### 3.3 Review Changed Files

```bash
# Base branch detection (using shared script)
_PD=""; for _d in "${CLAUDE_PLUGIN_ROOT:-}" ./pw ../pw ../../pw "$HOME"/.claude/plugins/cache/claude-parallel-dev-plugin/pw/*; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")

echo "=== Changed Files for Review ==="
git diff ${BASE_BRANCH}...HEAD --name-only 2>/dev/null || git diff HEAD~5 --name-only

echo ""
echo "=== Diff Preview (first 300 lines) ==="
git diff ${BASE_BRANCH}...HEAD 2>/dev/null | head -300 || git diff HEAD~5 | head -300
```

### 3.4 Quality Checklist

#### Code Quality
- [ ] Logic is correct and handles edge cases
- [ ] Code is readable and maintainable
- [ ] Follows existing patterns in the codebase
- [ ] No unnecessary complexity
- [ ] Proper error handling
- [ ] No dead code or unused imports

#### Codebase Consistency
- [ ] No contradictions with existing implementation (API contracts, data structures, business logic)
- [ ] Coding style matches existing codebase (naming conventions, formatting, idioms)
- [ ] Consistent use of libraries and utilities already in the project
- [ ] File/folder structure follows existing conventions
- [ ] Import ordering matches existing files

#### Security
- [ ] No hardcoded secrets or credentials
- [ ] Input validation on external data
- [ ] No injection vulnerabilities (SQL, XSS, command)
- [ ] Sensitive data handled appropriately

#### Testing & Documentation
- [ ] Tests added for new functionality
- [ ] Edge cases covered in tests
- [ ] Code comments where needed for complex logic

---

## Phase 4: Specification Alignment Check

### 4.1 Check Related Issues/Specs

```bash
echo "=== Related Context ==="

# Check for issue references in commits
echo "--- Issue References in Commits ---"
# Base branch detection (using shared script)
_PD=""; for _d in "${CLAUDE_PLUGIN_ROOT:-}" ./pw ../pw ../../pw "$HOME"/.claude/plugins/cache/claude-parallel-dev-plugin/pw/*; do [ -d "$_d/scripts" ] && _PD="$_d" && break; done 2>/dev/null; [ -n "${PW_PLUGIN_DIR:-}" ] && _PD="$PW_PLUGIN_DIR"
BASE_BRANCH=$("$_PD/scripts/detect-base-branch.sh" 2>/dev/null || echo "main")
git log ${BASE_BRANCH}..HEAD --oneline 2>/dev/null | grep -oE "#[0-9]+" || echo "No issue references found in commits"

# Check branch name for issue reference
echo ""
echo "--- Branch Issue Reference ---"
BRANCH=$(git branch --show-current)
echo "$BRANCH" | grep -oE "[0-9]+" | head -1 || echo "No issue number in branch name"
```

### 4.2 Specification Alignment Questions

Verify the implementation against specifications:

1. **Functionality**: Does the implementation match the expected behavior?
2. **Scope**: Are there any changes outside the specified scope?
3. **Edge Cases**: Are all edge cases from the spec handled?
4. **API Contract**: Does the interface match the specification?
5. **Backwards Compatibility**: Are there any breaking changes?

---

## Output Format

```markdown
# Pre-PR Check Report

## Summary
- **Branch**: [current branch]
- **Base Branch**: [base branch]
- **Files Changed**: [count]

## Check Results

### Phase 1: Local Checks
| Check | Status |
|-------|--------|
| Lint | ✅/❌ |
| Format | ✅/❌ |
| Type Check | ✅/❌ |
| Build | ✅/❌ |

### Phase 2: Tests
| Test Suite | Status |
|------------|--------|
| Unit Tests | ✅/❌ |
| Integration Tests | ✅/❌ |

### Phase 3: Code Quality & Consistency
| Criteria | Status | Notes |
|----------|--------|-------|
| Code Quality | ✅/❌ | [details] |
| Codebase Consistency | ✅/❌ | [details] |
| Security | ✅/❌ | [details] |

### Phase 4: Specification Alignment
| Aspect | Status | Notes |
|--------|--------|-------|
| Functionality | ✅/❌ | [details] |
| Scope | ✅/❌ | [details] |
| Edge Cases | ✅/❌ | [details] |

## Overall Status

**Ready for PR**: ✅ Yes / ❌ No

## Issues to Address
- [ ] [Issue 1 - file:line]
- [ ] [Issue 2 - file:line]

## Recommendations
- [Recommendation 1]
- [Recommendation 2]

## Next Steps
- If all checks pass: Create PR with `/pw:worker` or manually with `gh pr create`
- If issues found: Fix issues and run `/pw:precheck` again
```

---

## Actions After Precheck

- **All Passed**: Proceed to create PR
- **Local Checks Failed**: Fix lint/format/type errors first
- **Tests Failed**: Fix failing tests
- **Quality Issues**: Refactor code to match standards
- **Consistency Issues**: Align with existing codebase patterns
- **Spec Mismatch**: Adjust implementation to match specifications
