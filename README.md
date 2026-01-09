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

Atlas is an autonomous task loop agent that processes tasks from a markdown backlog using [Claude Code](https://claude.ai/code). You define what needs to be done, Atlas handles everything else—branches, code, quality checks, PRs, and merges.

```bash
$ atlas
```

That's it. Atlas reads your backlog and starts working.

---

## Features

| Feature | Description |
|---------|-------------|
| **Autonomous** | Processes tasks without manual intervention |
| **Quality-First** | Type checks, tests, and verification before completing |
| **GitFlow** | Branches, commits, PRs, and merges automatically |
| **Resumable** | Ctrl+C anytime, resume later with `--resume` |
| **Two Modes** | Auto-select from backlog or natural language prompts |
| **Iterative** | Retries until quality checks pass |

---

## Installation

```bash
git clone https://github.com/juancruzrossi/atlas.git
cd atlas
./install.sh
```

### Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
- [GitHub CLI](https://cli.github.com/) (`gh`)
- Git with configured credentials
- Bash 4.0+

---

## Quick Start

```bash
# Initialize Atlas in your project
cd your-project
atlas init

# Auto-generate a backlog (optional)
atlas create-backlog

# Run Atlas
atlas
```

---

## Usage

### Basic Syntax

```bash
atlas [tasks] [iterations]
```

| Argument | Description | Default |
|----------|-------------|---------|
| `tasks` | Number of tasks to process | 1 |
| `iterations` | Max attempts per task | 2 |

### Examples

```bash
# Process 1 task with up to 2 iterations (default)
atlas

# Process 3 tasks
atlas 3

# Process 5 tasks, up to 4 iterations each
atlas 5 4

# Process a specific task
atlas "HIGH-001"

# Process tasks matching a description
atlas "fix all bugs" 10

# Preview what would run (no changes)
atlas --dry-run 3
```

### Commands

| Command | Description |
|---------|-------------|
| `atlas` | Process tasks from backlog |
| `atlas init` | Initialize Atlas in current project |
| `atlas create-backlog` | Analyze codebase and generate backlog |
| `atlas update` | Update Atlas to latest version |
| `atlas --status` | Show backlog progress |
| `atlas --resume` | Continue interrupted session |
| `atlas --help` | Show all options |

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                         ATLAS                                │
│            Autonomous Task Loop Agent System                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   📋 Backlog           🔄 Loop                  ✅ Done      │
│                                                              │
│   TODO ──────────►  1. Pick task                             │
│   • HIGH-001        2. Create branch                         │
│   • MEDIUM-002      3. Implement            ───────────►     │
│   • LOW-003         4. Quality checks        PR merged       │
│                     5. Create PR             Task done       │
│   IN PROGRESS       6. Merge & cleanup                       │
│   • (current)                                                │
│                     ↺ Retry if checks fail                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Each task goes through:**
1. **Implement**: Branch → Code → Checks → PR
2. **Finalize**: Merge → Update Backlog → Cleanup

---

## Project Structure

After `atlas init`:

```
your-project/
└── .atlas/
    ├── backlog.md         # Task backlog
    ├── project-rules.txt  # Project config
    ├── progress.txt       # Dev log
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

**Priority order:** HIGH → MEDIUM → LOW

---

## Configuration

Edit `.atlas/project-rules.txt`:

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

---

## License

MIT

---

<p align="center">
  <sub>Built for developers who'd rather ship than babysit.</sub>
</p>
