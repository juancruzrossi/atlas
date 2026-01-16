# Atlas

Autonomous coding agent that processes tasks from a backlog using Claude Code.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/juancruzrossi/atlas/main/install.sh | bash
```

**Requirements:** [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Git, Bash

## Quick Start

```bash
cd your-project
atlas init          # Creates .atlas/ directory
# Edit .atlas/backlog.md with your tasks
atlas 10            # Run 10 iterations
```

## Commands

| Command | Description |
|---------|-------------|
| `atlas init` | Initialize `.atlas/` in current project |
| `atlas update` | Update Atlas from GitHub (preserves your project data) |
| `atlas [N]` | Run N iterations (default: 10) |
| `atlas help` | Show help |

## Configuration

All settings use environment variables with `ATLAS_` prefix:

```bash
export ATLAS_MAX_ITERATIONS=10      # Max iterations per run
export ATLAS_TIMEOUT=1200           # Timeout per iteration (seconds)
export ATLAS_STALE_SECONDS=7200     # Reset stuck tasks (seconds, 0 to disable)
export ATLAS_NOTIFY_TELEGRAM=true   # Enable Telegram notifications
export ATLAS_TELEGRAM_BOT="token"   # Telegram bot token
export ATLAS_TELEGRAM_CHAT="id"     # Telegram chat ID
```

## How It Works

```
for each iteration:
    1. Resume task in IN_PROGRESS, or pick first from TODO
    2. Create branch: [type]/[TASK_ID]-[description]
    3. Move to IN_PROGRESS + commit
    4. Implement task
    5. Run quality gates (from CLAUDE.md)
    6. Create PR → merge (squash) → return to main
    7. Move to DONE + commit
    8. Write to progress.txt and guardrails.md
    9. If error → move to DELAYED
   10. If no tasks → exit loop
```

**Features:**
- Context files pre-loaded (backlog, guardrails, progress, CLAUDE.md)
- Commits state changes immediately (crash recovery)
- Stale tasks auto-reset to TODO after timeout

## Backlog Format

```markdown
## TODO
### HIGH-001: Task title
- **Category:** feature
- **Description:** What needs to be done

## IN PROGRESS

## DONE
### HIGH-000: Completed task ✓
- **Completed:** 2026-01-15
- **PR:** #1

## DELAYED
### LOW-001: Blocked task
- **Reason:** Why it's blocked
```

## Project Structure

After `atlas init`:

```
your-project/
├── CLAUDE.md              # Project rules + quality gates (you create this)
└── .atlas/
    ├── backlog.md         # Task list
    ├── progress.txt       # Learnings from completed tasks
    ├── guardrails.md      # Rules from past errors
    ├── errors.log         # Failure log
    ├── activity.log       # Run history
    └── runs/              # Iteration logs
```

## Quality Gates

Define in your project's `CLAUDE.md`:

```markdown
## Quality Gates
- `npm run build` must pass
- `npm test` must pass
```

Atlas reads CLAUDE.md before each task.
