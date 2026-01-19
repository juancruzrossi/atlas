---
name: atlas-state
description: |
  State file management for Atlas autonomous agent. ONLY use when running
  as Atlas agent. Covers: backlog.md structure, progress.txt format,
  errors.log format, activity.log. Use when: (1) moving tasks between states,
  (2) logging progress, (3) recording errors.
author: Atlas
version: 1.0.0
date: 2026-01-19
---

# Atlas State Management

**CRITICAL**: Only apply when running as Atlas agent.

## File Locations

All state files live in `.atlas/` directory:

```
.atlas/
├── backlog.md      # Task queue
├── progress.txt    # Completed task history
├── guardrails.md   # Learned rules
├── errors.log      # Error history
├── activity.log    # Run history (managed by atlas.sh)
├── runs/           # Per-iteration logs
└── specs/          # Feature specifications
```

## backlog.md Structure

```markdown
# [Project] Backlog

## TODO

### TASK-001: Task title
- **Category:** feature|fix|refactor|test|docs|chore
- **Spec:** .atlas/specs/spec-YYYYMMDD-HHMMSS.md (optional)
- **Description:** Brief description (optional)

### TASK-002: Another task
- **Category:** fix

## IN PROGRESS

### TASK-003: Current task (STARTED: 2026-01-19)
- **Category:** feature

## DONE

### TASK-004: Completed task (2026-01-19) - PR #123
- **Category:** feature

## DELAYED

### TASK-005: Blocked task (DELAYED: 2026-01-19)
- **Category:** feature
- **Delay reason:** Missing API credentials
```

### Moving Tasks

**TODO → IN PROGRESS**:
```markdown
# Before (in TODO)
### TASK-001: Add feature

# After (in IN PROGRESS)
### TASK-001: Add feature (STARTED: 2026-01-19)
```

**IN PROGRESS → DONE**:
```markdown
# Before (in IN PROGRESS)
### TASK-001: Add feature (STARTED: 2026-01-19)

# After (in DONE)
### TASK-001: Add feature (2026-01-19) - PR #45
```

**IN PROGRESS → DELAYED**:
```markdown
# Before (in IN PROGRESS)
### TASK-001: Add feature (STARTED: 2026-01-19)

# After (in DELAYED)
### TASK-001: Add feature (DELAYED: 2026-01-19)
- **Delay reason:** Build fails due to missing dependency
```

### Task Selection

1. If task in IN PROGRESS → continue that task
2. If no task in IN PROGRESS → pick FIRST task from TODO
3. If TODO and IN PROGRESS empty → session complete

**NEVER skip tasks. ALWAYS pick the first one.**

## progress.txt Format

Append after each completed task:

```markdown
## [DATE] - [TASK_ID]: [Title]
Summary: [1-2 sentences of what was done]
PR: #[number]
Notes: [any gotchas for future iterations]
```

**Example**:
```markdown
## 2026-01-19 - HIGH-001: Create user authentication
Summary: Implemented JWT auth with refresh tokens. Added login/logout endpoints.
PR: #45
Notes: Refresh token rotation requires Redis, see .env.example for config.

## 2026-01-19 - HIGH-002: Add password reset
Summary: Added forgot password flow with email verification.
PR: #46
Notes: Email templates in templates/email/. Requires SMTP config.
```

### What to Include

- **Summary**: What was implemented, high-level
- **PR**: The PR number for reference
- **Notes**: Things future iterations should know

### What NOT to Include

- Code snippets (too verbose)
- Full file paths (summarize instead)
- Debug information
- Time spent

## errors.log Format

One line per error:

```
[DATE] TASK_ID: Brief error description
```

**Examples**:
```
[2026-01-19] HIGH-003: Build failed - TypeScript error in UserService
[2026-01-19] MED-007: Tests failed - Mock not configured for external API
[2026-01-19] LOW-012: Blocked - Missing API credentials in .env
```

Keep it brief. Details go in progress.txt or guardrails.md.

## State Commits

After modifying state files, commit immediately:

```bash
# Starting task
git add .atlas/backlog.md
git commit -m "chore: start TASK-001"

# Completing task
git add .atlas/
git commit -m "chore: complete TASK-001"

# Delaying task
git add .atlas/
git commit -m "chore: delay TASK-001"
```

**IMPORTANT**: Push after commit when GIT_MODE=true:
```bash
git push
```

## Integration with Specs

If task has a `**Spec:**` field, read that spec for full context:

```markdown
### HIGH-005: Implement payment flow
- **Category:** feature
- **Spec:** .atlas/specs/spec-20260119-143022.md
```

The spec contains:
- Full requirements
- Acceptance criteria
- Technical decisions
- Edge cases

**ALWAYS read the spec before starting a task that has one.**

## Session Complete

When TODO and IN PROGRESS are both empty:

1. Print summary
2. Output `<promise>COMPLETE</promise>`
3. Atlas loop will exit

```markdown
=== SUMMARY ===
Task: [last task completed]
Status: DONE
Pending: 0
Loop: COMPLETE

<promise>COMPLETE</promise>
```
