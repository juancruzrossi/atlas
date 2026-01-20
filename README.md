<p align="center">
  <h1 align="center">ATLAS</h1>
  <p align="center"><strong>Autonomous Task Loop Agent System</strong></p>
  <p align="center">
    <em>Let Claude Code work through your backlog while you focus on what matters</em>
  </p>
</p>

<p align="center">
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#commands">Commands</a> •
  <a href="#how-it-works">How It Works</a>
</p>

---

## What is Atlas?

Atlas is an **A**utonomous **T**ask **L**oop **A**gent **S**ystem that processes tasks from a markdown backlog using [Claude Code](https://docs.anthropic.com/en/docs/claude-code). You define what needs to be done, Atlas handles everything else: branches, code, quality checks, PRs, and merges.

---

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/juancruzrossi/atlas/main/install.sh | bash
```

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Git (optional - enables branches, PRs, and commits)

---

## Quick Start

```bash
cd your-project
atlas init

# Edit .atlas/backlog.md with your tasks

atlas
```

---

## Commands

| Command | Description |
|---------|-------------|
| `atlas init` | Initialize `.atlas/` in current project |
| `atlas plan "..."` | Interactive feature planning (interview → spec → tasks) |
| `atlas [N]` | Run N iterations autonomously (default: 25) |
| `atlas update` | Update Atlas from GitHub (preserves your project data) |
| `atlas help` | Show help |

---

## Planning Mode

For complex features, use `atlas plan` to interview and decompose before autonomous execution:

```bash
atlas plan "add user authentication with JWT"
# → Interactive interview about requirements
# → Generates spec in .atlas/specs/
# → Creates tasks in backlog with **Spec:** field

atlas 5
# → Executes 5 tasks autonomously (no human intervention)
# → Each task reads the full spec for context (integral view)
```

---

## Configuration (optional)

Override defaults with `ATLAS_` environment variables:

```bash
export ATLAS_MAX_ITERATIONS=25      # Max iterations per run
export ATLAS_TIMEOUT=1200           # Timeout per iteration (seconds)
export ATLAS_STALE_SECONDS=7200     # Reset stuck tasks (seconds, 0 to disable)
export ATLAS_NOTIFY_TELEGRAM=true   # Enable Telegram notifications
export ATLAS_TELEGRAM_BOT="token"   # Telegram bot token
export ATLAS_TELEGRAM_CHAT="id"     # Telegram chat ID
```

---

## How It Works

```
for each iteration:
    1. Resume task in IN_PROGRESS, or pick first from TODO
    2. [git] Create branch: [type]/[TASK_ID]-[description]
    3. Move to IN_PROGRESS [git: + commit]
    4. Implement task
    5. Run quality gates (from CLAUDE.md)
    6. [git] Create PR → merge (squash) → return to main
    7. Move to DONE [git: + commit]
    8. Write to progress.txt and guardrails.md
    9. If error → move to DELAYED
   10. If no tasks → exit loop
```

**Modes:**
- **Git mode** (default): Full GitFlow with branches, PRs, and commits
- **Local mode**: Works without git - changes stay in working directory

**Features:**
- Context files pre-loaded (backlog, guardrails, progress, CLAUDE.md)
- Commits state changes immediately (crash recovery) [git mode]
- Stale tasks auto-reset to TODO after timeout

---

## Backlog Format

```markdown
## TODO
### HIGH-001: Task title
- **Category:** feature
- **Description:** What needs to be done

## IN_PROGRESS

## DONE
### HIGH-000: Completed task ✓
- **Completed:** 2026-01-15
- **PR:** #1

## DELAYED
### LOW-001: Blocked task
- **Reason:** Why it's blocked
```

---

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
    ├── specs/             # Feature specs (from atlas plan)
    └── runs/              # Iteration logs
```

---

## Quality Gates

Define in your project's `CLAUDE.md`:

```markdown
## Quality Gates
- `npm run build` must pass
- `npm test` must pass
```

Atlas reads CLAUDE.md before each task.
