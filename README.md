<p align="center">
  <h1 align="center">ATLAS</h1>
  <p align="center"><strong>Autonomous Task Loop Agent System</strong></p>
  <p align="center">v1.1.0</p>
  <p align="center">
    <em>Let Claude Code work through your backlog while you focus on what matters</em>
  </p>
</p>

<p align="center">
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#usage">Usage</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#documentation">Docs</a>
</p>

---

## What is Atlas?

Atlas is an **A**utonomous **T**ask **L**oop **A**gent **S**ystem that processes tasks from a markdown backlog using [Claude Code](https://claude.ai/product/claude-code). You define what needs to be done, Atlas handles everything else—branches, code, quality checks, PRs, and merges.

---

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/juancruzrossi/atlas/main/install.sh | bash
```

### Requirements

- [Claude Code](https://claude.ai/product/claude-code)
- Git

---

## Quick Start

```bash
# See available commands
atlas

# Or show detailed help
atlas --help

# Initialize Atlas in your project
cd your-project
atlas init

# Auto-generate a backlog (optional)
atlas create-backlog

# Process 3 tasks
atlas 3
```

---

## Usage

### Syntax

```bash
atlas <tasks> [iterations]
```

| Argument | Description | Default |
|----------|-------------|---------|
| `tasks` | Number of tasks to process | required |
| `iterations` | Max attempts per task | 1 |

### Examples

```bash
# Show welcome screen and available commands
atlas

# Process 3 tasks (1 iteration each)
atlas 3

# Process 5 tasks with up to 3 iterations each
atlas 5 3

# Process tasks matching a description (max 10 tasks)
atlas "fix all bugs" 10

# Process tasks matching a description (max 5 tasks, 2 iterations each)
atlas "refactor components" 5 2

# Preview what would run (no changes)
atlas --dry-run 3

# Show backlog status
atlas --status

# Resume interrupted session
atlas --resume
```

### Commands

| Command | Description |
|---------|-------------|
| `atlas` | Show welcome screen |
| `atlas <N>` | Process N tasks from backlog |
| `atlas <N> <M>` | Process N tasks, up to M iterations each |
| `atlas "<prompt>" <N>` | Process up to N tasks matching prompt |
| `atlas init` | Initialize Atlas in current project |
| `atlas create-backlog` | Analyze codebase and generate backlog |
| `atlas update` | Update Atlas to latest version |
| `atlas --status` | Show backlog progress |
| `atlas --resume` | Continue interrupted session |
| `atlas --help` | Show all options |

---

## How It Works

Each task goes through two phases:

1. **Implement**: Create branch → Write code → Run quality checks → Create PR
2. **Finalize**: Merge PR → Update backlog → Delete branch

If quality checks fail, Atlas retries (up to the iteration limit you set).

**Priority order:** HIGH → MEDIUM → LOW

---

## Project Structure

After `atlas init`:

```
your-project/
└── .atlas/
    ├── backlog.md         # Task backlog
    ├── progress.txt       # Development log
    └── logs/              # Execution logs
```

### Backlog Format

```markdown
## TODO

### HIGH-001: Fix authentication bypass
- **Category:** bug
- **Description:** Users can access admin panel without login
- **Steps:**
  1. Add auth middleware to admin routes
  2. Verify session tokens

### MEDIUM-001: Add dark mode
- **Category:** functional
- **Description:** Implement theme toggle

## IN PROGRESS

## DONE
```

---

## Configuration

Atlas reads your project's `CLAUDE.md` file (if it exists) to understand your project.
This is the same file used by Claude Code, so there's nothing extra to configure.

If your project doesn't have a `CLAUDE.md`, Atlas will work without it—Claude Code
will analyze the project structure automatically.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No tasks found | Add tasks to `.atlas/backlog.md` |
| Claude timeout | `atlas 1 --timeout 3600` |
| Skip a task | Move it to DONE in backlog.md |
| State issues | Delete `.atlas/.atlas-state.json` |

---

## Documentation

- [CLAUDE.md](./CLAUDE.md) — Architecture & contributing
- [CHANGELOG.md](./CHANGELOG.md) — Version history
