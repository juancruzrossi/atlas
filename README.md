# Atlas

**Autonomous Task Loop Agent System**

Simple autonomous coding agent that processes tasks from a backlog using Claude Code.

---

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/juancruzrossi/atlas/main/install.sh | bash
```

Or with custom install directory:
```bash
ATLAS_INSTALL_DIR=/usr/local/bin curl -fsSL https://raw.githubusercontent.com/juancruzrossi/atlas/main/install.sh | bash
```

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Git
- Bash

---

## Quick Start

```bash
cd your-project
atlas init

# Edit .atlas/backlog.md with your tasks

atlas 10
```

---

## Usage

```bash
atlas [command] [options]
```

| Command | Description |
|---------|-------------|
| `atlas init` | Initialize `.atlas/` in current project |
| `atlas update` | Add new template files (preserves existing) |
| `atlas help` | Show help |
| `atlas [N]` | Run N iterations |

### Environment Variables

All settings are configurable via environment variables with the `ATLAS_` prefix:

| Variable | Description | Default |
|----------|-------------|---------|
| `ATLAS_MAX_ITERATIONS` | Max iterations per run | `10` |
| `ATLAS_TIMEOUT` | Timeout per iteration (seconds) | `1200` (20 min) |
| `ATLAS_STALE_SECONDS` | Reset stuck tasks after N seconds | `7200` (2 hours) |
| `ATLAS_NOTIFY_TELEGRAM` | Enable Telegram notifications | `true` |
| `ATLAS_TELEGRAM_BOT` | Telegram bot token | - |
| `ATLAS_TELEGRAM_CHAT` | Telegram chat ID | - |

Example:
```bash
ATLAS_MAX_ITERATIONS=25 ATLAS_TIMEOUT=900 atlas
```

### Timeout

Each iteration has a 20-minute timeout by default. If Claude hangs, the iteration is killed and the next one starts.

```bash
ATLAS_TIMEOUT=600 atlas 10   # 10 min timeout per iteration
```

### Stale Task Recovery

If a task is stuck in `IN PROGRESS` for more than 2 hours (default), it's automatically moved back to `TODO` on the next run. This handles crashes or interrupted sessions.

```bash
ATLAS_STALE_SECONDS=3600 atlas 10  # Reset after 1 hour
ATLAS_STALE_SECONDS=0 atlas 10     # Disable stale detection
```

---

## Backlog Format

```markdown
# Project Backlog

## TODO

### HIGH-001: Setup project structure
- **Category:** feature
- **Description:** Initialize the project with proper folder structure
- **Steps:**
  1. Create src/ directory
  2. Add package.json

### HIGH-002: Add authentication
- **Category:** feature
- **Description:** Implement user login

## IN PROGRESS

## DONE

### HIGH-000: Initial setup ✓
- **Completed:** 2026-01-14
- **PR:** #1

## DELAYED

### LOW-001: Nice to have feature
- **Reason:** Blocked by external API
```

**Sections:**
- **TODO** - Pending tasks (first = highest priority)
- **IN PROGRESS** - Currently being worked on
- **DONE** - Completed tasks with date and PR
- **DELAYED** - Blocked tasks with reason

---

## How It Works

```
for each iteration:
    1. Check IN_PROGRESS first (resume interrupted task)
    2. If none, pick first TODO task
    3. Create branch: atlas/[TASK_ID]
    4. Move to IN_PROGRESS + commit
    5. Implement completely
    6. Run quality gates (from CLAUDE.md)
    7. Create PR → merge (squash) → return to main
    8. Move to DONE + commit
    9. If error → move to DELAYED + commit
   10. If no tasks left → exit loop
```

**Key features:**
- Context files are pre-loaded (no tool calls to read them)
- Commits backlog.md changes immediately (crash recovery)
- Handles errors by moving tasks to DELAYED
- Stale tasks in IN_PROGRESS auto-reset to TODO

---

## Project Structure

After `atlas init`:

```
your-project/
├── CLAUDE.md              # Project rules + quality gates
└── .atlas/
    ├── backlog.md         # Tasks
    ├── progress.txt       # Codebase learnings
    ├── guardrails.md      # Rules from past errors
    ├── activity.log       # Run history
    ├── errors.log         # Failure log
    └── runs/              # Iteration logs
```

---

## Quality Gates

Define quality gates in your project's `CLAUDE.md`:

```markdown
## Quality Gates

- `npm run build` must pass
- `npm test` must pass
- No TypeScript errors
```

Atlas pre-loads CLAUDE.md content into each iteration's context.

---

## Telegram Notifications

```bash
export ATLAS_TELEGRAM_BOT="your-bot-token"
export ATLAS_TELEGRAM_CHAT="your-chat-id"
```

To disable: `export ATLAS_NOTIFY_TELEGRAM=false`
