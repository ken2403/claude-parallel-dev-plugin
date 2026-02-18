# Parallel Workflow Plugin

A Claude Code plugin for parallel development environments using Git worktree and tmux.

## Overview

Maximizes development efficiency by decomposing large development tasks into multiple independent subtasks and executing them in parallel.

### Key Features

- **Issue-Driven Design**: Automatically generate implementation designs from GitHub Issues
- **Task Decomposition**: Split large tasks into parallelizable subtasks
- **Parallel Worker Management**: Provide independent work environments with Git worktree and tmux
- **Integrated Review**: Support for PR review, merge, and cleanup
- **Fast Exploration**: High-speed code exploration via Haiku model subagents

## Installation

### 1. Place the Plugin

Clone from GitHub. The plugin can be placed in **any directory**:

```bash
# Clone to any directory
cd /path/to/any-directory
git clone https://github.com/ken2403/claude-paralell-dev-plugin.git
```

Example layout:

```
/opt/claude-plugins/
└── claude-paralell-dev-plugin/   # This plugin
```

### 2. Enable the Plugin in Claude Code

#### Method A: Register as Marketplace (Recommended)

Registering the plugin as a Marketplace makes it available in any project:

```bash
# Add the plugin as a Marketplace
claude plugin marketplace add /path/to/any-directory/claude-paralell-dev-plugin

# Install the plugin
claude plugin install pw@claude-parallel-dev-plugin
```

#### Method B: Specify at Launch

To use only in a specific session, launch Claude Code with the `--plugin-dir` option:

```bash
cd your-project
claude --plugin-dir /path/to/any-directory/claude-paralell-dev-plugin
```

### 3. Place CLAUDE.md in Your Project (Recommended)

```bash
cp ../claude-paralell-dev-plugin/examples/CLAUDE.project-template.md ./CLAUDE.md
# Edit to fit your project
```

## Usage

### Workflow

This plugin supports two workflows:

#### A. Parallel Execution Workflow (For Large Tasks)

```
Receive spec → Design (with decomposition) → Parallel execution → Review → Merge → Cleanup
```

Use this when decomposing into multiple subtasks and executing in parallel with tmux.

#### B. Worktree Job Workflow (For Independent Tasks)

```
Issue/Task → wt-j → (Autonomous implementation) → Review → Merge → Cleanup
```

Use this when autonomously implementing independent tasks in an isolated environment.

### Command List

| Command | Description | Arguments |
|---------|-------------|-----------|
| `/pw:design` | Create design and decompose tasks from spec | `#issue-number` / `@file-reference` / `"text"` |
| `/pw:orchestrate` | Launch parallel workers | List of branch names |
| `/pw:worker` | Execute worker task | Task description |
| `/pw:wt-j` | Autonomous implementation in isolated worktree | `#issue-number` / `"task description"` `[--feature\|--fix]` |
| `/pw:wt-clean` | Clean up wt-j environment | `job-name` / `--all` |
| `/pw:status` | Check progress | (Optional) session name |
| `/pw:precheck` | Pre-check before PR creation | Branch name or `HEAD` |
| `/pw:rv` | Review PR (critical) | PR number |
| `/pw:fix` | Fix review feedback | Feedback content |
| `/pw:merge` | Merge PR | PR number `[--skip]` |
| `/pw:cleanup` | Clean up environment | List of branch names |
| `/pw:resolve-conflicts` | Resolve conflicts | Branch name |

### Examples

#### 1. Implement from GitHub Issue

```bash
# Design (includes task decomposition)
/pw:design #123

# Launch parallel workers
/pw:orchestrate feature/auth feature/api feature/tests

# Check progress
/pw:status

# PR review
/pw:rv 45

# Merge
/pw:merge 45

# Cleanup (after all PRs are merged)
/pw:cleanup feature/auth feature/api feature/tests
```

#### 2. Interactive Task Execution

```bash
# Specify spec directly
/pw:design "Add OAuth2 authentication with Google and GitHub providers"

# Claude may ask for details
```

#### 3. Single Task (No Parallelization)

```bash
# Use the worker command directly for small tasks
/pw:worker Fix the null pointer exception in src/auth/login.ts
```

#### 4. Worktree Job Workflow (Recommended)

A workflow for autonomously implementing independent tasks in an isolated environment.

##### Pattern A: Design from Issue then Implement

```bash
# 1. Create design from Issue (understand requirements)
/pw:design #123

# 2. Start autonomous implementation with wt-j
#    - A worktree is created at worktrees/issue-123/
#    - Work on feature/issue-123 branch
#    - Automatically runs through to PR creation
/pw:wt-j #123

# 3. Review PR (critical review by default)
/pw:rv <PR-number>

# 4. Merge if review passes
#    --skip: Skip human Approval (for self-review)
/pw:merge <PR-number> --skip

# 5. Cleanup (delete worktree & update default branch)
/pw:wt-clean issue-123
```

##### Pattern B: Implement with Direct Task Specification

```bash
# 1. Start implementation directly with free text
#    - A worktree is created at worktrees/add-dark-mode-toggle/
#    - Work on feature/add-dark-mode-toggle branch
/pw:wt-j "Add dark mode toggle to settings page"

# For bug fixes, specify --fix
/pw:wt-j "Fix null pointer in auth module" --fix
# -> fix/fix-null-pointer-in-auth-module branch is created

# 2. Review → Merge → Cleanup
/pw:rv <PR-number>
/pw:merge <PR-number> --skip
/pw:wt-clean add-dark-mode-toggle
```

##### Running Multiple Tasks Simultaneously

```bash
# Can run simultaneously in separate terminals
Terminal 1: /pw:wt-j #100
Terminal 2: /pw:wt-j #200
Terminal 3: /pw:wt-j "Refactor utils"

# Cleanup all at once after all are merged
/pw:wt-clean --all
```

##### Worktree Job Features

| Feature | Description |
|---------|-------------|
| **Isolated Environment** | Creates independent worktrees under `worktrees/` |
| **Safety** | Never modifies parent directory or main branch |
| **Autonomous Execution** | Runs automatically through PR creation without approval |
| **Concurrent Execution** | Can run multiple tasks simultaneously |
| **Branch Naming** | Specify prefix with `--feature` (default) or `--fix` |

**Note**: Deleting worktrees before PRs are merged is prohibited. `wt-clean` only deletes branches that have been merged.

## Dependencies

### Component Dependency Diagram

```
                                    ┌─────────────────┐
                                    │   /pw:design    │
                                    │(Design + Decomp)│
                                    └────────┬────────┘
                                             │ uses
                                             ▼
                              ┌──────────────────────────────┐
                              │         explorer             │
                              │    (Code Exploration)        │
                              └──────────────────────────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          /pw:orchestrate                                 │
│                      (Worker Launch & Management)                        │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  calls spinup.sh → creates worktrees + tmux sessions            │    │
│  │  spawns status-monitor subagent (background)                    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ spawns
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
   │ /pw:worker  │      │ /pw:worker  │      │ /pw:worker  │
   │ (Worker 1)  │      │ (Worker 2)  │      │ (Worker N)  │
   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘
          │ uses               │ uses               │ uses
          ▼                    ▼                    ▼
   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
   │  explorer   │      │  explorer   │      │  explorer   │
   │  analyzer   │      │  analyzer   │      │  analyzer   │
   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘
          │ applies            │ applies            │ applies
          ▼                    ▼                    ▼
   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
   │code-quality │      │code-quality │      │code-quality │
   │security-rev │      │security-rev │      │security-rev │
   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘
          │ creates PR         │ creates PR         │ creates PR
          └────────────────────┼────────────────────┘
                               ▼
                      ┌─────────────────┐
                      │   /pw:status    │◄──── status-monitor (bg)
                      │(Progress Check) │
                      └────────┬────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │    /pw:rv       │
                      │  (PR Review)    │
                      └────────┬────────┘
                               │ uses
                               ▼
                      ┌─────────────────┐
                      │   code-quality  │
                      │  security-review│
                      └────────┬────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    │                    ▼
   ┌─────────────┐             │             ┌─────────────┐
   │  /pw:fix    │◄────────────┘             │ /pw:resolve │
   │(Fix Issues) │                           │ -conflicts  │
   └─────────────┘                           └─────────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │   /pw:merge     │
                      │  (PR Merge)     │
                      │ ⚠️ CI+Approval  │
                      └────────┬────────┘
                               │
                               ▼
                      ┌─────────────────┐
                      │  /pw:cleanup    │
                      │(Env Cleanup)    │
                      │ calls teardown.sh│
                      │ ⚠️ Human Review │
                      └─────────────────┘
```

### Command → Subagent Dependencies

| Command | Required Subagents | Optional |
|---------|-------------------|----------|
| `/pw:design` | `explorer` | `analyzer` |
| `/pw:orchestrate` | - | `status-monitor` (background) |
| `/pw:worker` | `explorer` | `analyzer` |
| `/pw:wt-j` | `explorer` | `analyzer` |
| `/pw:wt-clean` | - | - |
| `/pw:status` | - | - |
| `/pw:precheck` | `explorer` | `analyzer` |
| `/pw:rv` | - | `explorer`, `analyzer` |
| `/pw:fix` | `explorer` | - |
| `/pw:merge` | - | - |
| `/pw:cleanup` | - | - |
| `/pw:resolve-conflicts` | - | - |

### Command → Skill Dependencies

| Command | Applied Skills |
|---------|---------------|
| `/pw:worker` | `code-quality`, `security-review` |
| `/pw:wt-j` | `code-quality`, `security-review` |
| `/pw:precheck` | `code-quality`, `security-review` |
| `/pw:rv` | `code-quality`, `security-review` |
| `/pw:fix` | `code-quality` |

### Command → Script Dependencies

| Command | Script Used | Function |
|---------|------------|----------|
| `/pw:orchestrate` | `spinup.sh` | Create worktrees, launch tmux sessions |
| `/pw:cleanup` | `teardown.sh` | Delete worktrees, terminate tmux sessions |

### Subagent List

| Subagent | Model | Purpose | Tools |
|----------|-------|---------|-------|
| `explorer` | Haiku | Fast file/pattern search | Read, Grep, Glob |
| `analyzer` | Sonnet | Detailed architecture analysis | Read, Grep, Glob, Bash |
| `status-monitor` | Haiku | Background progress monitoring (30s interval) | Bash |

### Skill List

| Skill | Auto-Applied When | Content |
|-------|-------------------|---------|
| `code-quality` | During code review, implementation | Readability, maintainability, type safety, coding style consistency |
| `security-review` | During security-related changes | OWASP Top 10, authentication/authorization, input validation |

## Subagent Details

### explorer (Haiku)

For fast code exploration. Used for file search and pattern discovery.

```
Use explorer subagent to find authentication-related files
```

### analyzer (Sonnet)

For detailed code analysis. Used for architecture understanding and complex dependency analysis.

```
Use analyzer subagent to understand the payment system architecture
```

### status-monitor (Haiku)

For background monitoring. Automatically monitors progress after orchestrator launches.

- **Monitoring Interval**: 30 seconds
- **Maximum Monitoring Duration**: 30 minutes
- **Detects**: PR creation, errors, completion

## Skills

### code-quality

Quality standards automatically applied during code review.

### security-review

Checklist automatically applied during security-related code changes.

## Hooks

### General Hooks (Built into Plugin)

- **File Protection**: Blocks editing of `.env`, `credentials`, etc.
- **Notification**: Desktop notification on work completion
- **Logging**: Logs session completion

### Language-Specific Hooks (Configured per Project)

The `examples/` directory contains language-specific Hooks configuration examples:

- `hooks-python.json` - For Python (ruff lint/format + mypy type checking)
- `hooks-javascript.json` - For JavaScript/TypeScript (prettier/eslint)
- `hooks-go.json` - For Go (gofmt/goimports)

To apply to your project:

```bash
mkdir -p .claude
cp ../claude-paralell-dev-plugin/examples/hooks-python.json .claude/settings.json
```

## Auto-Detection

Scripts automatically detect the following (no configuration file needed):

| Item | Detection Method |
|------|-----------------|
| **Git Repository** | Auto-detected from current directory → subdirectories |
| **Project Name** | Directory name of the Git repository |
| **Base Branch** | `main` → `master` → current branch (in priority order) |

Session names are automatically generated in the format `{project-name}__{branch-name}`.

### Running from Parent Directory

You can launch a Claude session from the **parent directory** of a Git repository and run `/pw:orchestrate` and `/pw:cleanup`:

```
/workspace/              ← Launch Claude session here
├── my-project/          ← Git repository (auto-detected)
├── wt-feature-auth/     ← worktree 1 (auto-created)
├── wt-feature-api/      ← worktree 2 (auto-created)
└── wt-feature-tests/    ← worktree 3 (auto-created)
```

With this setup:
- Worktrees are created at the same level as the repository
- All worktrees are easily accessible from the Claude session
- If there are multiple repositories, specify with the `GIT_REPO` environment variable

```bash
# How to specify when there are multiple repositories
GIT_REPO=/workspace/my-project ./scripts/spinup.sh feature/auth
```

**Note**: Commands such as `review`, `merge`, `fix`, and `resolve-conflicts` must be run from within a worktree or git repository.

## Directory Structure

```
claude-paralell/
├── plugin.json              # Plugin manifest
│
├── commands/                # Slash commands
│   ├── design.md
│   ├── orchestrate.md
│   ├── worker.md
│   ├── wt-j.md              # Autonomous implementation in isolated worktree
│   ├── wt-clean.md          # wt-j environment cleanup
│   ├── status.md
│   ├── precheck.md
│   ├── rv.md
│   ├── fix.md
│   ├── merge.md
│   ├── cleanup.md
│   └── resolve-conflicts.md
│
├── agents/                  # Subagents
│   ├── explorer.md          # Fast exploration (Haiku)
│   ├── analyzer.md          # Detailed analysis (Sonnet)
│   └── status-monitor.md    # Background monitoring (Haiku)
│
├── skills/                  # Auto-applied skills
│   ├── code-quality/
│   │   └── SKILL.md
│   └── security-review/
│       └── SKILL.md
│
├── hooks/                   # General Hooks
│   └── hooks.json
│
├── examples/                # Configuration examples
│   ├── CLAUDE.project-template.md
│   ├── hooks-python.json
│   ├── hooks-javascript.json
│   └── hooks-go.json
│
├── scripts/                 # Execution scripts
│   ├── spinup.sh            # Launch parallel environment
│   └── teardown.sh          # Remove parallel environment
│
└── README.md               # This file
```

## Best Practices

### Task Decomposition

- **Independence**: Each subtask should not edit the same files
- **Self-Containment**: Each subtask should produce a PR that can be merged independently
- **Appropriate Granularity**: 2-5 subtasks is optimal

### Parallel Execution

- Prompts should **always be written in English** (even for Japanese output)
- Regularly check progress with `/pw:status`
- Intervene early if there are blockers

### Cleanup

- **Do not clean up until all PRs are merged**
- Verify with `gh pr list --state open` before running

## Troubleshooting

### Session Not Found

```bash
tmux list-sessions
```

### Worktree Not Found

```bash
git worktree list
```

### Force Cleanup

```bash
# Force remove worktree
git worktree remove --force /path/to/worktree

# Force kill tmux session
tmux kill-session -t session-name

# Remove orphaned worktree entries
git worktree prune
```

## Related Documentation

- [Claude Code Official Documentation](https://docs.anthropic.com/claude-code)
- [Plugins](https://code.claude.com/docs/en/plugins)
- [Commands](https://code.claude.com/docs/en/slash-commands)
- [Subagents](https://code.claude.com/docs/en/sub-agents)
- [Skills](https://code.claude.com/docs/en/skills)
- [Hooks](https://code.claude.com/docs/en/hooks-guide)
