# CLAUDE.md

This file provides guidance to [Claude Code](https://claude.ai/product/claude-code) when working with code in this repository.

## Project Overview

Atlas (Autonomous Task Loop Agent System) is an autonomous task development agent that automates task implementation by iterating over a Backlog (`backlog.md`) and implementing tasks one by one using Claude Code.

## Architecture

```
atlas/                    # Installation directory (global)
├── atlas.sh              # Main executable (generic, don't modify)
├── atlas-rules.txt       # Core agent rules (generic, don't modify)
├── install.sh            # Global installer script
├── templates/            # Templates for project initialization
│   ├── project-rules.txt # Project configuration template
│   ├── backlog.md        # Backlog template
│   └── progress.txt      # Progress log template
└── README.md

.atlas/                   # Per-project directory (created by `atlas init`)
├── project-rules.txt     # Project-specific configuration
├── backlog.md            # Task backlog
├── progress.txt          # Development log
└── logs/                 # Execution logs
```

### Key Concepts

- **Two Operating Modes**: Backlog mode (auto-select tasks) and Prompt mode (Claude interprets natural language requests)
- **Two-Phase Execution**: Each task goes through an `implement` phase (branch, code, PR) then a `finalize` phase (merge, cleanup)
- **Iteration Loop**: Tasks can have multiple iterations until `READY_TO_MERGE` is signaled
- **Promises**: Special XML tags (`<promise>READY_TO_MERGE</promise>`, `<promise>FEATURE_DONE</promise>`, etc.) signal state transitions

### File Responsibilities

| File | Scope | Purpose |
|------|-------|---------|
| `atlas.sh` | Global | Bash orchestrator - handles CLI, loops, Claude invocations |
| `atlas-rules.txt` | Global | Agent behavior rules - iteration modes, quality checks, GitFlow |
| `project-rules.txt` | Per-project | Project config - commands, testing, conventions |
| `backlog.md` | Per-project | Task backlog with TODO/IN PROGRESS/DONE/DELAYED sections |
| `progress.txt` | Per-project | Development log with completed tasks |

## Commands

```bash
# Installation
./install.sh              # Install globally to /usr/local/bin/atlas

# Project initialization
atlas init                # Initialize Atlas in current project
atlas create-backlog      # Auto-generate backlog by analyzing codebase

# Execution
atlas 5                   # Process 5 tasks from backlog
atlas 5 3                 # 5 tasks with up to 3 iterations each
atlas "HIGH-004" 1        # Process specific task
atlas "fix bugs" 5        # Up to 5 tasks matching "fix bugs"

# Utilities
atlas --status            # Show backlog progress
atlas --dry-run 5         # Preview mode
atlas --resume            # Continue interrupted session
atlas update              # Update Atlas to the latest version
atlas --help              # Detailed help
```

## Backlog Format

The backlog uses Markdown with three sections:

```markdown
# Project Backlog

## TODO
Tasks waiting to be picked up.

### HIGH-001: Critical Task
- **Category:** bug
- **Description:** What needs to be done
- **Steps:**
  1. Step 1
  2. Step 2

### MEDIUM-001: Normal Task
...

## IN PROGRESS
Tasks currently being worked on (max 1 at a time).

## DONE
Completed tasks with dates and PR links.

### HIGH-001: Critical Task
- **Category:** bug
- **Description:** ...
- **Completed:** 2026-01-07
- **PR:** https://github.com/org/repo/pull/123
```

**Priority codes:**
- `HIGH-XXX`: Critical, execute first
- `MEDIUM-XXX`: Normal, after all HIGH
- `LOW-XXX`: Low priority, execute last

**Categories:** `bug`, `performance`, `technical-debt`, `functional`

**Task transitions:**
```
## TODO → ## IN PROGRESS → ## DONE
```

## Project Rules Format

The `project-rules.txt` file contains project-specific configuration:

```txt
PROJECT RULES - My Project
═══════════════════════════════════════════════════════════════════════════════

PROJECT INFO
Project Name: My App
Type: Next.js + TypeScript
Package Manager: pnpm

HOW TO RUN THE PROJECT
Development: npm run dev
Production: npm run build && npm start

TESTING STRATEGY
  - Unit tests: npm test
  - E2E tests: (none)

TYPE CHECKING
Command: pnpm typecheck

VISUAL VERIFICATION TOOLS
Preferred: Chrome MCP
Alternative: Playwright MCP

CODE STYLE & CONVENTIONS
- React functional components
- Tailwind CSS
```

## Quality Checklist

Atlas enforces these checks before accepting `READY_TO_MERGE`:

**Mandatory checks:**
1. Compilation/Type checking passes
2. No broken imports
3. No broken existing functionality
4. Visual verification passes

**Quality checks:**
5. Edge cases handled (empty, error, loading states)
6. No performance issues (memory leaks, excessive re-renders)
7. Security (no exposed secrets, input validation)
8. Error handling (try/catch, user-friendly messages)
9. Code consistency (follows existing patterns)

## Iterations Explained

The iterations parameter sets the **maximum** attempts per task:

```bash
atlas 3 5   # 3 tasks, up to 5 iterations each
```

Atlas exits the loop when Claude signals `READY_TO_MERGE`:

```
Task 1 (complex):
├── Iteration 1: Implement... not ready yet
├── Iteration 2: Fix issues... READY_TO_MERGE!
└── Finalize: Merge PR, move to DONE

Task 2 (simple):
├── Iteration 1: Implement... READY_TO_MERGE!
└── Finalize: Merge PR, move to DONE
```

## GitFlow Integration

Atlas follows GitFlow practices:

1. **Branch creation:** `feature/<task-name>`
2. **Commits:** Conventional commits (`feat:`, `fix:`, etc.)
3. **PR creation:** Via `gh pr create`
4. **Merge:** Squash & merge via `gh pr merge --squash --delete-branch`
5. **Cleanup:** Delete branch, return to main

## Logs

All executions are logged to `.atlas/logs/`:

```
logs/
├── atlas.log                           # Main log file
├── task_1_iter_1_20260107_143022.log   # Task 1, iteration 1
├── task_1_finalize_20260107_144022.log # Task 1, finalize phase
└── ...
```

## Agent Promises (Output Signals)

| Promise | When to Use |
|---------|-------------|
| `<promise>READY_TO_MERGE</promise>` | Task implemented, quality checks pass, PR ready |
| `<promise>FEATURE_DONE</promise>` | PR merged, task moved to DONE |
| `<promise>COMPLETE</promise>` | All tasks in Backlog are done |
| `<promise>SELECTOR_DONE</promise>` | No more tasks match the prompt (prompt mode) |
| `<promise>NO_PR_FOUND</promise>` | Error: expected PR doesn't exist |

## Development Guidelines

- The script uses `ATLAS_HOME` (stored in `~/.atlas-home`) to locate global files
- Project files live in `<project>/.atlas/` directory
- Signal handling with `trap` saves state on Ctrl+C for resume functionality
- Timeout commands use `gtimeout` on macOS (from coreutils)

## Performance Optimizations

Atlas uses several strategies to minimize execution time:

### Session Continuity (`--continue`)
- **Within a task**: Iterations 2+ use `--continue` to maintain context
- **Between tasks**: Each new task starts a fresh session (no `--continue`)
- This prevents context overflow while reducing re-processing within the same task

### Prompt Optimization
- **Iteration 1**: Full prompt with all `@files` (rules, project-rules, backlog, progress)
- **Iterations 2+**: Short prompt WITHOUT `@files` (already in context via `--continue`)
- This saves significant tokens and processing time on subsequent iterations

### Model Selection
- **Implement phase**: Uses default model (user can override with `--model`)
- **Finalize phase**: Uses `--model sonnet` (faster, task is simple: merge PR, update files)
- **Create-backlog**: Uses `--model sonnet` (analysis doesn't need heavy reasoning)

### Execution Flow
```
TASK 1:
  ├─ Iter 1: new session + full prompt with @files
  ├─ Iter 2: --continue + short prompt (no @files)
  ├─ Iter 3: --continue + short prompt (no @files)
  └─ Finalize: new session (--model sonnet)

TASK 2:
  ├─ Iter 1: new session + full prompt with @files
  ├─ Iter 2: --continue + short prompt (no @files)
  └─ Finalize: new session (--model sonnet)
```

## Testing Changes

After modifying `atlas.sh`:
1. Run `atlas --help` to verify CLI parsing
2. Run `atlas --status` in a project with backlog
3. Test `atlas init` in a new directory
4. Test `atlas --dry-run 1` to verify mode detection

## Contributing

**IMPORTANT**: For every change made to this project, you MUST update `CHANGELOG.md`:

1. Add your changes under the `[Unreleased]` section
2. Use the appropriate category: Added, Changed, Deprecated, Removed, Fixed, Security
3. When releasing, move unreleased changes to a new version section with date
4. Follow [Keep a Changelog](https://keepachangelog.com/) format
