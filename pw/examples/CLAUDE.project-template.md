# [Project Name] Development Guide

## Overview

Brief description of this project.

## Git Configuration

| Setting | Value |
|---------|-------|
| **Base Branch** | `main` |
| **Branch Prefix** | `feature/`, `fix/`, `docs/` |
| **PR Target** | Always merge to base branch |

> **Note**: The `Base Branch` setting is used by the parallel-workflow plugin to detect the default branch for creating feature branches and PRs. Change this if your project uses `develop`, `master`, or another branch as the primary branch.

## Technology Stack

| Component | Technology |
|-----------|------------|
| Language | [Python 3.12+ / TypeScript / Go / etc.] |
| Framework | [Framework name] |
| Package Manager | [uv / npm / go modules / etc.] |
| Linter | [ruff / eslint / golint / etc.] |
| Type Checker | [mypy / tsc / etc.] |

## Git Workflow

**CRITICAL**: Follow these rules strictly.

### Branch Protection

- **NEVER** push directly to `main` or `release` branches
- Always create a feature branch from `main`
- Submit all changes via Pull Request
- Wait for CI checks to pass before merging

### Standard Workflow

```bash
git checkout main
git pull origin main
git checkout -b feature/your-feature-name
# ... make changes ...
git add .
git commit -m "feat: description"
git push -u origin feature/your-feature-name
gh pr create --title "feat: description" --body "explanation"
```

## Development Commands

```bash
# Install dependencies
[make install / npm install / uv sync]

# Run linter
[make lint / npm run lint / uv run ruff check]

# Run type checker
[make typecheck / npm run typecheck / uv run mypy]

# Run all checks
[make check / npm run check]

# Run tests
[make test / npm test / uv run pytest]
```

---

## Claude Code Configuration

### Parallel Workflow Plugin

This project uses the parallel-workflow plugin for large-scale tasks.

**Plugin location**: `../.claude-paralell-dev-plugin/` (relative to this repository)

### Available Commands

| Command | Purpose |
|---------|---------|
| `/pw:design [spec]` | Create implementation design and decompose into subtasks |
| `/pw:orchestrate` | Start parallel workers |
| `/pw:worker [task]` | Execute assigned worker task |
| `/pw:status` | Check all workers status |
| `/pw:rv [pr]` | Review a PR |
| `/pw:fix [feedback]` | Address review feedback |
| `/pw:merge [pr]` | Merge a PR |
| `/pw:cleanup [branches]` | Clean up worker environments |

### Subagent Usage

**IMPORTANT**: Always use subagents for exploration before implementation.

```
# For quick file/pattern searches
Use explorer subagent to find [what you're looking for]

# For deep architecture analysis
Use analyzer subagent to understand [component/system]
```

### Default Behavior for Implementation Tasks

When implementing features or fixing bugs:

1. **First**: Use `explorer` subagent to find relevant code
2. **Then**: Plan minimal changes based on existing patterns
3. **Implement**: Follow this project's code style
4. **Verify**: Run `[make check / npm run check]` before committing
5. **For large tasks**: Consider `/pw:design` for parallel execution

### Specification Input

When receiving task specifications:

1. **GitHub Issue**: `/pw:design #123`
2. **File reference**: `/pw:design See @docs/spec.md`
3. **Direct text**: `/pw:design Add feature X with Y`

---

## Code Quality Rules

### [Language-specific rules - customize for your project]

| Rule | Requirement |
|------|-------------|
| Type Annotations | All functions must have type annotations |
| Line Length | Maximum [88/100/120] characters |
| Formatting | Use [formatter name] |
| Imports | Sort with [tool name] |

### File Modification Rules

- **DO NOT** modify files outside your assigned scope
- **DO NOT** delete or rename files without explicit instruction
- **DO NOT** modify [config files] unless required
- **ALWAYS** preserve existing functionality when making changes

### Testing Requirements

- Run existing tests after making changes
- Add tests for new functionality
- Do not disable or skip tests without justification

### Security Rules

- **NEVER** hardcode credentials, API keys, or secrets
- **NEVER** log sensitive information
- **ALWAYS** validate external input
- **ALWAYS** use environment variables for configuration

---

## Project Structure

```
project/
├── src/                    # Source code
│   ├── [module]/          # Module directory
│   └── ...
├── tests/                  # Test files
├── docs/                   # Documentation
├── [config files]          # Configuration
└── CLAUDE.md              # This file
```

---

## Resources

- [Project documentation URL]
- [API documentation URL]
- [Related resources]
