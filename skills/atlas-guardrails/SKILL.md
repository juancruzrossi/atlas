---
name: atlas-guardrails
description: |
  Guardrails management for Atlas autonomous agent. ONLY use when running
  as Atlas agent. Covers: Signs methodology, when to add guardrails, error
  handling, learning from failures. Use when: (1) encountering errors,
  (2) learning something useful, (3) reading guardrails.md.

  IMPORTANT: When using Atlas specialized agents, invoke this skill for guardrails management.
author: Atlas
version: 1.1.0
date: 2026-01-23
---

# Atlas Guardrails System

**CRITICAL**: Only apply when running as Atlas agent.

## Overview

Guardrails are rules learned from past errors and discoveries. They prevent repeating mistakes and encode project-specific knowledge.

Location: `.atlas/guardrails.md`

## Sign Format

When you learn something useful, add a Sign:

```markdown
### Sign: [Descriptive Name]
- **Trigger**: [When to apply this rule]
- **Instruction**: [What to do or avoid]
- **Learned from**: [TASK_ID where this was learned]
```

**Example**:
```markdown
### Sign: Decimal Consistency
- **Trigger**: Working with financial calculations in Python
- **Instruction**: Always use Decimal, never float. Convert at API boundaries.
- **Learned from**: MED-005
```

## When to Add Signs

Add a Sign when you:

1. **Fix a bug** that wasn't obvious
2. **Discover a project pattern** that should be followed
3. **Find a workaround** for a framework limitation
4. **Learn a performance gotcha**
5. **Identify a security consideration**

**DO NOT add Signs for**:
- Generic programming knowledge
- Things already in CLAUDE.md
- Temporary fixes that will be removed

## Reading Guardrails

**MANDATORY**: Read guardrails.md BEFORE starting any task.

When you find a relevant Sign:
1. Apply the instruction
2. If the Sign is outdated, update it
3. If the Sign conflicts with CLAUDE.md, CLAUDE.md wins

## Error Handling

When a task fails:

### 1. Move Back to TODO

In backlog.md, move task back to TODO section (will be retried next iteration):

```markdown
### TASK-001: Feature description
- **Category:** feature
```

**Note:** DELAYED is only for tasks explicitly postponed by decision, not for build/test errors.

### 2. Log the Error

Append to `.atlas/errors.log`:

```
[2026-01-19] TASK-001: Build failed - missing dependency X
```

Keep it brief. One line per error.

### 3. Add Sign if Learnable

If the error teaches something preventable:

```markdown
### Sign: Dependency X Required
- **Trigger**: Using feature Y in this project
- **Instruction**: Ensure dependency X is installed first
- **Learned from**: TASK-001
```

### 4. Commit and Continue

```bash
git add .atlas/
git commit -m "chore: error TASK-001"
git push
```

Then move to next task (or retry the same task if it's first in TODO).

## Sign Categories

Organize Signs by type:

```markdown
# Guardrails

## Build & Dependencies
### Sign: Node Version
- **Trigger**: Running npm commands
- **Instruction**: Use Node 20+, check with `node -v`
- **Learned from**: SETUP-001

## API & Data
### Sign: Date Formatting
- **Trigger**: Sending dates to API
- **Instruction**: Use ISO 8601 format YYYY-MM-DD
- **Learned from**: BUG-015

## Security
### Sign: Environment Variables
- **Trigger**: Adding new secrets
- **Instruction**: Never commit .env, add to .env.example
- **Learned from**: SEC-001
```

## Updating Signs

If a Sign is wrong or outdated:

1. Update the Sign content
2. Update "Learned from" to current task
3. Commit with message: `chore: update guardrail [Sign Name]`

## Priority

When instructions conflict:

1. **CLAUDE.md** (project rules) - Highest
2. **Feature Spec** (current task spec)
3. **Guardrails.md** (learned rules)
4. **General knowledge** - Lowest

## Example guardrails.md

```markdown
# Guardrails

Rules learned from past iterations. READ before starting any task.

## API Patterns

### Sign: UTC Dates
- **Trigger**: Storing or comparing dates
- **Instruction**: Always use UTC in backend, convert to local only in frontend
- **Learned from**: BUG-023

### Sign: Pagination Required
- **Trigger**: Creating list endpoints
- **Instruction**: Always implement pagination, default limit 50
- **Learned from**: PERF-008

## Frontend

### Sign: No Transparency
- **Trigger**: Creating UI components
- **Instruction**: Use solid backgrounds (#121216), no glass effects
- **Learned from**: UI-012

## Testing

### Sign: Mock External Services
- **Trigger**: Writing tests that call external APIs
- **Instruction**: Always mock, never call real APIs in tests
- **Learned from**: TEST-005
```
