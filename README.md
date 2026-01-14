# Atlas

**Autonomous Task Loop Agent System**

Simple autonomous coding agent that processes tasks from a PRD using Claude Code.

---

## Installation

```bash
# Clone the repo
git clone https://github.com/juancruzrossi/atlas.git

# Add to PATH (add to .bashrc/.zshrc)
export PATH="$PATH:$HOME/atlas"
```

### Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Git
- Bash

---

## Quick Start

```bash
# Initialize Atlas in your project
cd your-project
atlas init

# Edit .atlas/prd.json with your tasks

# Run 10 iterations
atlas 10
```

---

## Usage

```bash
atlas [command] [options]
```

### Commands

| Command | Description |
|---------|-------------|
| `atlas init` | Initialize `.atlas/` in current project |
| `atlas update` | Add new template files (preserves existing) |
| `atlas help` | Show help |
| `atlas [N]` | Run N iterations using prd.json |
| `atlas --cb [N]` | Run N iterations using backlog.md |

### Examples

```bash
# Initialize Atlas
atlas init

# Run 5 iterations
atlas 5

# Run 20 iterations with backlog.md instead of prd.json
atlas --cb 20

# Show help
atlas help
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ATLAS_MAX_ITERATIONS` | Default max iterations | 10 |
| `ATLAS_STALE_SECONDS` | Reset stuck stories after N seconds | 0 (disabled) |
| `ATLAS_NOTIFY_TELEGRAM` | Enable Telegram notifications | true |
| `ATLAS_TELEGRAM_BOT` | Telegram bot token | - |
| `ATLAS_TELEGRAM_CHAT` | Telegram chat ID | - |

---

## How It Works

Atlas runs a simple loop:

```
for each iteration:
    1. Read prd.json, find pending task
    2. Implement task completely
    3. Verify quality gates pass
    4. Create PR and merge
    5. Mark task as done
    6. If no pending tasks → exit
```

Each iteration is **stateless**. The agent reads state from files at the start and writes state to files at the end.

---

## Project Structure

After `atlas init`:

```
your-project/
└── .atlas/
    ├── prd.json           # Tasks (PRD format)
    ├── progress.txt       # Codebase learnings
    ├── guardrails.md      # Rules from past errors
    ├── activity.log       # Run history
    ├── errors.log         # Failure log
    ├── runs/              # Iteration logs
    └── references/        # Documentation
```

---

## PRD Format

```json
{
  "projectName": "my-project",
  "qualityGates": [
    "npm run build must pass",
    "npm test must pass"
  ],
  "userStories": [
    {
      "id": "US-001",
      "title": "Setup project",
      "description": "Initialize the project structure",
      "acceptanceCriteria": [
        "package.json exists",
        "src/ directory created"
      ],
      "priority": 1,
      "passes": false,
      "status": "pending",
      "dependsOn": []
    }
  ]
}
```

### Task Fields

| Field | Description |
|-------|-------------|
| `id` | Unique identifier (e.g., US-001) |
| `title` | Short task name |
| `description` | What needs to be done |
| `acceptanceCriteria` | List of requirements |
| `priority` | Lower = higher priority |
| `passes` | `false` = pending, `true` = done |
| `status` | pending, in_progress, done, skipped |
| `dependsOn` | Array of task IDs that must complete first |

---

## Backlog Mode (--cb)

Alternative to prd.json using markdown:

```markdown
## Tasks
- [ ] US-001: Setup project structure
- [ ] US-002: Add authentication
- [x] US-003: This task is done (skipped)
```

Run with: `atlas --cb 10`

---

## Guardrails (Signs)

When the agent encounters errors, it adds "Signs" to `guardrails.md`:

```markdown
### Sign: Always Check Dependencies
- **Trigger**: Before adding imports
- **Instruction**: Verify package is in package.json
- **Type**: Preventive
- **Learned from**: US-003
```

The agent reads these at the start of each iteration to avoid repeating mistakes.

---

## Telegram Notifications

Set environment variables to receive notifications:

```bash
export ATLAS_TELEGRAM_BOT="your-bot-token"
export ATLAS_TELEGRAM_CHAT="your-chat-id"
```

Each iteration sends a status update with:
- Progress bar
- Current task
- Pending tasks count

To disable: `export ATLAS_NOTIFY_TELEGRAM=false`

---

## Workflow Per Task

1. Read `.atlas/guardrails.md` (rules)
2. Read `.atlas/progress.txt` (context)
3. Read `.atlas/errors.log` (recent failures)
4. Read `CLAUDE.md` if exists (project rules)
5. Pick ONE pending task from prd.json
6. Create feature branch
7. Implement completely
8. Verify quality gates pass
9. Create PR and merge (squash)
10. Mark task `passes: true` in prd.json
11. Return to main branch
12. Update progress.txt with learnings

---

## Context Engineering

Each iteration starts with **fresh context**. State persists in files:

| What | Where |
|------|-------|
| Task status | `prd.json` |
| Learnings | `progress.txt` |
| Error patterns | `guardrails.md` |
| Recent failures | `errors.log` |

See `references/CONTEXT_ENGINEERING.md` for details.

---

## License

MIT
