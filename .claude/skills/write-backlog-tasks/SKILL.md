---
name: write-backlog-tasks
description: Use this skill when creating tasks for the Atlas backlog. Interviews the user, explores the codebase, and writes well-structured tasks.
---

This skill is invoked when the user wants to add tasks to the Atlas backlog (`.atlas/backlog.md`). Follow these steps, skipping any that aren't necessary.

## Process

1. **Gather Requirements**
   Ask the user for a detailed description of what they want to accomplish. Understand:
   - The problem or feature they're addressing
   - Any constraints or preferences
   - Expected outcome

2. **Explore the Codebase**
   If the task involves existing code, explore the repo to:
   - Verify the user's assertions
   - Understand current architecture
   - Identify files/modules that will be affected
   - Find patterns to follow

3. **Define Scope**
   Work with the user to clarify:
   - What IS included in this work
   - What is explicitly OUT of scope
   - Dependencies on other tasks (if any)

4. **Break Down into Atomic Tasks**
   Decompose the work into small, autonomous tasks that Atlas can execute in a single iteration. Each task should:
   - Be completable in ~15-30 minutes
   - Have clear, verifiable acceptance criteria
   - Be independent when possible (minimize dependencies)
   - Follow the Single Responsibility Principle

5. **Assign Priority**
   For each task, determine priority:
   - `HIGH` - Critical path, blocks other work, or urgent fix
   - `MED` - Important but not blocking
   - `LOW` - Nice to have, can be deferred

6. **Write to Backlog**
   Add tasks to `.atlas/backlog.md` under the `## TODO` section using the template below.

## Task Template

```markdown
### [PRIORITY]-[NUMBER]: [Short descriptive title]
- **Category:** [feature|bugfix|refactor|docs|test]
- **Description:** [1-2 sentences explaining what and why]
- **Steps:**
  1. [Concrete action 1]
  2. [Concrete action 2]
  3. [...]
- **Acceptance:** [How to verify the task is complete]
```

### Optional Fields

For tasks generated from `atlas plan`:
```markdown
- **Spec:** .atlas/specs/spec-YYYYMMDD-HHMMSS.md
```

For tasks with dependencies:
```markdown
- **Depends:** [PRIORITY]-[NUMBER]
```

## Guidelines

### Good Task Characteristics
- **Atomic**: One clear objective per task
- **Testable**: Clear acceptance criteria
- **Contextual**: Enough detail for autonomous execution
- **Ordered**: Steps are sequential and logical

### Numbering Convention
- Check existing tasks in backlog to continue numbering sequence
- Format: `HIGH-001`, `MED-042`, `LOW-007`

### Categories
- `feature` - New functionality
- `bugfix` - Fixing broken behavior
- `refactor` - Code improvement without behavior change
- `docs` - Documentation updates
- `test` - Adding or improving tests

## Example

```markdown
### HIGH-003: Add retry logic to API client
- **Category:** feature
- **Description:** HTTP requests to external API fail silently on timeout. Add exponential backoff retry.
- **Steps:**
  1. Create `retry.ts` utility with exponential backoff (max 3 retries)
  2. Wrap `fetchExternalData()` in `src/api/client.ts` with retry
  3. Add tests for retry behavior
- **Acceptance:** Transient failures retry up to 3 times with backoff; permanent failures surface error after retries exhausted

### MED-015: Extract validation into shared module
- **Category:** refactor
- **Description:** Validation logic duplicated in 3 controllers. Extract to reusable module.
- **Steps:**
  1. Create `src/validation/index.ts` with common validators
  2. Replace inline validation in `UserController`
  3. Replace inline validation in `OrderController`
  4. Replace inline validation in `ProductController`
- **Acceptance:** All 3 controllers use shared validation; existing tests pass
```

## Anti-patterns to Avoid

- **Vague tasks**: "Improve performance" → Be specific about what and where
- **Giant tasks**: "Implement auth system" → Break into login, logout, session, etc.
- **Missing acceptance**: Always include how to verify completion
- **Implementation in description**: Steps should be actionable, not code snippets
