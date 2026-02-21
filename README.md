<p align="center">
  <h1 align="center">ATLAS</h1>
  <p align="center"><strong>Autonomous Task Loop Agent System</strong></p>
  <p align="center">
    <em>Let AI coding agents work through your backlog while you focus on what matters</em>
  </p>
</p>

<p align="center">
  <a href="#install">Install</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#commands">Commands</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#configuration">Configuration</a>
</p>

---

## What is Atlas?

Atlas is an **A**utonomous **T**ask **L**oop **A**gent **S**ystem that processes tasks from a markdown backlog using AI coding agents. You define what needs to be done, Atlas handles everything else: branches, code, quality checks, PRs, and merges.

---

## Install

```bash
npm install -g @jxtools/atlas
```

## Update

```bash
atlas update
```

### Requirements

- **Node.js 18+** (for npm installation)
- **AI Provider** (at least one):
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (default, recommended)
  - [OpenCode](https://opencode.ai)
  - [Codex](https://github.com/openai/codex)
- **Git** (optional - enables branches, PRs, and commits)

### AI Provider Configuration

Atlas supports multiple AI providers:

| Provider | Flag | Documentation |
|----------|------|---------------|
| Claude Code (default) | `--cli claudecode` | [docs.anthropic.com/claude-code](https://docs.anthropic.com/claude-code) |
| OpenCode | `--cli opencode` | [opencode.ai/docs](https://opencode.ai/docs) |
| Codex (OpenAI) | `--cli codex` | [developers.openai.com/codex/cli](https://developers.openai.com/codex/cli) |

```bash
# Use Claude Code (default)
atlas 25

# Use OpenCode
atlas --cli opencode 25

# Use Codex
atlas --cli codex 25

# Or set environment variable (persists across sessions)
export ATLAS_CLI=codex
atlas 25
```

**Recommendation**: Use Claude Code for `atlas plan` (interactive mode works best). For autonomous execution (`atlas [N]`), any provider works.

---

## Quick Start

```bash
cd your-project
atlas init

# Recommended flow (AI plans + executes)
atlas plan "add user authentication with JWT"
atlas 5
```

If you prefer manual planning, you can still edit `.atlas/backlog.md` directly:

```bash
# Manual flow (you write tasks)
# Edit .atlas/backlog.md with your tasks
atlas
```

---

## Commands

| Command | Description |
|---------|-------------|
| `atlas init` | Initialize `.atlas/` in current project |
| `atlas plan "..."` | Interactive feature planning (interview -> spec -> tasks) |
| `atlas [N]` | Run N iterations autonomously (default: 25) |
| `atlas review [--dry-run]` | Audit Atlas state and auto-fix inconsistencies (or report only with dry-run) |
| `atlas resume [N]` | Resume an interrupted session from its active integration branch/PR |
| `atlas clean [--all]` | Clean runtime artifacts from `.atlas/` |
| `atlas logs [--tail N]` | Show iteration logs (default: last 10) |
| `atlas logs --failed` | Show only failed iterations |
| `atlas logs --search <pat>` | Search logs for pattern |
| `atlas status` | Show task counts and active session info |
| `atlas doctor` | Check Atlas installation and dependencies |
| `atlas update` | Show how to update via NPM |
| `atlas help` | Show help |

---

## Planning Mode

For complex features, use `atlas plan` to interview and decompose before autonomous execution:

```bash
atlas plan "add user authentication with JWT"
# -> Interactive interview about requirements
# -> Generates spec in .atlas/specs/
# -> Creates tasks in backlog with **Spec:** field

atlas 5
# -> Executes 5 tasks autonomously (no human intervention)
# -> Each task reads the full spec for context (integral view)
```

---

## Resuming Sessions

If Atlas is interrupted (quota limit, error, Ctrl+C), resume with:

```bash
atlas resume      # Continue with default iterations
atlas resume 5    # Continue with 5 iterations
```

Resume will:
1. Find the active integration branch
2. Verify PR is not merged/closed
3. Continue processing tasks from backlog

---

## Reviewing Work

After Atlas completes (or is interrupted), audit and fix issues:

```bash
atlas review           # Detect and auto-fix issues
atlas review --dry-run # Report only, no changes
atlas --cli opencode review --dry-run # Same, using OpenCode
```

Review checks for:
- Tasks stuck in wrong state (multiple IN_PROGRESS, etc.)
- Orphaned PRs not merged to integration
- Backlog out of sync with merged PRs
- Uncommitted changes and unpushed commits

Auto-fixes safe issues and reports those requiring manual intervention.

---

## Cleaning Runtime Files

Use `clean` to remove local runtime artifacts:

```bash
atlas clean       # Remove .atlas/runs/*.log and temporary files
atlas clean --all # Also reset activity/errors logs and stale session metadata
```

---

## Configuration

Override defaults with `ATLAS_` environment variables:

```bash
export ATLAS_CLI=claudecode         # AI provider: claudecode (default), opencode, or codex
export ATLAS_MAX_ITERATIONS=25      # Max iterations per run
export ATLAS_TIMEOUT=1200           # Timeout per iteration (seconds)
export ATLAS_STALE_SECONDS=7200     # Reset stuck tasks (seconds, 0 to disable)
export ATLAS_DEFAULT_BRANCH=main    # Override auto-detected default branch
export ATLAS_NOTIFY_TELEGRAM=true   # Enable Telegram notifications
export ATLAS_TELEGRAM_BOT="token"   # Telegram bot token
export ATLAS_TELEGRAM_CHAT="id"     # Telegram chat ID
```

---

## How It Works

```
for each iteration:
    1. Resume task in IN_PROGRESS, or pick first from TODO
    2. [git] Create branch from integration: [type]/[TASK_ID]-[description]
    3. Move to IN_PROGRESS [git: + commit]
    4. Implement task
    5. Run quality gates (from CLAUDE.md)
    6. [git] Create PR -> merge (squash) to integration branch
    7. Move to DONE [git: + commit]
    8. Write to progress.txt and guardrails.md
    9. If error -> log to errors.log, move back to TODO
   10. If no tasks -> exit loop
```

**Modes:**
- **Git mode** (default): Creates integration branch, PRs merge there, human reviews before main
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
### HIGH-000: Completed task
- **Completed:** 2026-01-15
- **PR:** #1

## DELAYED
### LOW-001: Blocked task
- **Reason:** Why it's blocked
```

---

## Project Structure

After `atlas init` (`specs/` appears after `atlas plan`):

```
your-project/
├── CLAUDE.md              # Project rules + quality gates (you create this)
└── .atlas/
    ├── backlog.md         # Task list
    ├── progress.txt       # Learnings from completed tasks
    ├── guardrails.md      # Rules from past errors
    ├── errors.log         # Failure log
    ├── activity.log       # Run history
    ├── specs/             # Feature specs (created by atlas plan)
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

---

## License

ISC
