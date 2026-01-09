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
git clone https://github.com/juancruzrossi/atlas.git
cd atlas
./install.sh
```

After installation, you can delete the cloned repository if you want—Atlas is installed globally and will continue to work. However, if you plan to use `atlas update`, keep the repository (it needs git to pull updates).

### Requirements

- [Claude Code](https://claude.ai/product/claude-code) (the `claude` command)
- [GitHub CLI](https://cli.github.com/) (the `gh` command) — used for creating and merging PRs
- Git with configured credentials

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
    ├── project-rules.txt  # Project config (how to build, test, etc.)
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

Edit `.atlas/project-rules.txt` to tell Atlas how to build and test your project:

```txt
PROJECT INFO
Project Name: My App
Type: Next.js + TypeScript

HOW TO RUN
Development: npm run dev
Build: npm run build

TESTING
Unit tests: npm test
Type check: npm run typecheck

VISUAL VERIFICATION
Preferred: Chrome MCP
```

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
