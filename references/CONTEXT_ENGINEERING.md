# Context Engineering Reference

## The Core Problem

Each Atlas iteration runs with a fresh context. The agent doesn't remember previous iterations. This is similar to memory allocation:

- **malloc()**: Loading context (reading files, understanding code)
- **free()**: Context is lost at iteration end
- **Problem**: You can malloc() but never free() - context only grows

## Solution: State in Files, Not Memory

Since context resets each iteration, persist state in files:

| What | Where |
|------|-------|
| Task progress | `backlog.md` (TODO/IN PROGRESS/DONE sections) |
| Learnings | `progress.txt` |
| Error patterns | `guardrails.md` |
| Recent failures | `errors.log` |
| Run history | `activity.log` |
| Feature specs | `specs/` (from `atlas plan`, for integral view) |

## The Atlas Context Flow

```
┌─────────────────────────────────────────────────┐
│  START OF ITERATION                             │
├─────────────────────────────────────────────────┤
│  1. Read guardrails.md (rules from past errors) │
│  2. Read progress.txt (codebase knowledge)      │
│  3. Read errors.log (recent failures)           │
│  4. Read CLAUDE.md (project rules)              │
│  5. Read backlog.md (find first TODO task)      │
│  6. IF task has **Spec:** → load spec file      │
│     (integral view: full feature context)       │
├─────────────────────────────────────────────────┤
│  WORK ON ONE TASK                               │
├─────────────────────────────────────────────────┤
│  END OF ITERATION                               │
│  - Update backlog.md (move task to DONE)        │
│  - Update progress.txt (learnings)              │
│  - Update guardrails.md (if error learned)      │
│  - Print summary for next iteration             │
└─────────────────────────────────────────────────┘
```

## Integral View (from `atlas plan`)

When tasks are created via `atlas plan`, they include a `**Spec:**` field pointing to a detailed feature specification. Each iteration automatically loads this spec, giving the agent:

1. **Full feature context** - understands the whole, implements one part
2. **Consistent decisions** - all tasks share the same requirements
3. **No drift** - spec is source of truth across iterations

## Key Principles

### 1. One Task Per Iteration
Don't try to do multiple tasks. Complete one fully, persist state, let next iteration handle the next task.

### 2. Write Learnings Immediately
Don't wait until the end. If you learn something important, write it to progress.txt or guardrails.md right away.

### 3. Trust the Files
The files are your memory. If something isn't in a file, the next iteration won't know about it.

### 4. Explicit Over Implicit
Write down assumptions, decisions, and discoveries. The next iteration can't read your mind.

## Anti-Patterns

| Anti-Pattern | Why It's Bad | Solution |
|--------------|--------------|----------|
| Doing 3 tasks in one iteration | Risk of partial completion | One task, full GitFlow |
| Not reading guardrails | Repeating same mistakes | Always read at start |
| Not updating progress.txt | Losing knowledge | Write after each learning |
| Assuming context persists | Next iteration starts fresh | Persist to files |

## Summary

Atlas uses files as external memory. Each iteration is stateless, but the filesystem is not. By reading state at the start and writing state at the end, the agent maintains continuity across iterations.
