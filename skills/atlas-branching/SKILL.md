---
name: atlas-branching
description: |
  Git branching conventions for Atlas autonomous agent. ONLY use when running
  as Atlas agent. Covers: branch naming, conventional commits, PR workflow,
  squash merge strategy. Use when: (1) creating branches, (2) writing commits,
  (3) creating PRs, (4) merging PRs.

  IMPORTANT: When using Atlas specialized agents, invoke this skill for branching conventions.
author: Atlas
version: 1.1.0
date: 2026-01-23
---

# Atlas Branching Conventions

**CRITICAL**: Only apply when running as Atlas agent with GIT_MODE=true.

## Branch Naming

Format: `[type]/[TASK_ID]-[short-description]`

| Type | When |
|------|------|
| `feature/` | New functionality |
| `fix/` | Bug fixes |
| `refactor/` | Code restructuring |
| `test/` | Adding/fixing tests |
| `docs/` | Documentation |
| `chore/` | Maintenance tasks |

**Examples**:
```
feature/HIGH-001-payment-system
fix/BUG-042-login-redirect
refactor/MED-015-api-client
test/LOW-008-unit-tests
```

**Rules**:
- Use TASK_ID from backlog.md
- Lowercase, kebab-case
- Max 50 chars for description part
- No special characters except hyphens

## Conventional Commits

Format: `[type]: [description]`

| Type | When |
|------|------|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `refactor:` | Code change (no feature/fix) |
| `test:` | Tests only |
| `docs:` | Documentation |
| `chore:` | Maintenance (deps, config) |
| `style:` | Formatting only |
| `perf:` | Performance improvement |

**Examples**:
```
feat: add payment processing endpoint
fix: resolve null pointer in user service
refactor: extract validation logic to service
test: add unit tests for auth module
chore: update dependencies
```

**Rules**:
- Lowercase type
- No period at end
- Imperative mood ("add" not "added")
- Max 72 chars total
- Body optional, separated by blank line

**DO NOT include**:
- "Co-Authored-By: Claude" or similar
- References to AI/Claude in commit messages
- Emoji in commit messages

## PR Workflow

### Creating PR

```bash
# Push branch first
git push -u origin [branch-name]

# Create PR with gh CLI
gh pr create \
  --base [BASE_BRANCH] \
  --title "[type]: [description]" \
  --body "## Summary
Brief description of changes.

## Changes
- Change 1
- Change 2

## Testing
How to test these changes.
"
```

**PR Title**: Same format as conventional commits

### Merging PR

**ALWAYS use squash merge**:
```bash
gh pr merge --squash --delete-branch
```

Why squash:
- Clean history on integration branch
- One commit per feature/fix
- Easier to review and revert

### After Merge

```bash
# Return to base branch
git checkout [BASE_BRANCH]
git pull origin [BASE_BRANCH]
```

## State Commits

Atlas uses special commits for state tracking:

```bash
# Starting a task
git commit -m "chore: start [TASK_ID]"

# Completing a task
git commit -m "chore: complete [TASK_ID]"

# Delaying a task
git commit -m "chore: delay [TASK_ID]"
```

These commits include changes to `.atlas/` files only.

## Common Mistakes

**WRONG**:
```bash
git commit -m "Added new feature"        # Past tense
git commit -m "Feat: Add feature"        # Capitalized type
git commit -m "feat: add feature."       # Period at end
git commit -m "feat add feature"         # Missing colon
gh pr merge                              # Missing --squash
```

**CORRECT**:
```bash
git commit -m "feat: add payment endpoint"
gh pr merge --squash --delete-branch
```
