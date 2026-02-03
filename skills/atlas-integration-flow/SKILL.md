---
name: atlas-integration-flow
description: |
  Integration branch workflow for Atlas autonomous sessions. ONLY use when
  running as Atlas agent (detected by GIT_MODE=true in prompt context).
  Handles: creating integration branch, PR workflow to integration,
  PR to main (Ready for Review). Use when: (1) starting Atlas session with git,
  (2) creating PRs during Atlas run, (3) completing Atlas session.

  IMPORTANT: When using Atlas specialized agents, invoke this skill for git operations.
author: Atlas
version: 1.1.0
date: 2026-01-23
---

# Atlas Integration Branch Flow

**CRITICAL**: Only apply this workflow when running as Atlas agent with GIT_MODE=true.

## Overview

All Atlas work goes to an integration branch, NOT directly to main. This allows human review of all changes before merging to main.

```
main (protected)
  │
  └── integration/atlas-YYYYMMDD-HHMMSS  ← PR to main (Ready for Review, NO merge until review)
        │
        ├── feature/TASK-001  → PR to integration ✓ merged
        ├── feature/TASK-002  → PR to integration ✓ merged
        └── fix/TASK-003      → PR to integration ✓ merged
```

## Step 0: Start Every Iteration

**CRITICAL**: ALWAYS start from main, then check for existing session.

```bash
# 1. ALWAYS start from main
git checkout main && git pull origin main

# 2. Check for existing session
if [[ -f .atlas/integration-session.json ]]; then
  PR_NUMBER=$(jq -r '.pr_number' .atlas/integration-session.json)
  PR_STATE=$(gh pr view "$PR_NUMBER" --json state -q '.state')

  if [[ "$PR_STATE" == "MERGED" ]]; then
    # Session was merged - cleanup locally and create new
    BRANCH=$(jq -r '.branch' .atlas/integration-session.json)
    git branch -D "$BRANCH" 2>/dev/null || true  # Delete local branch
    rm .atlas/integration-session.json  # Delete locally (no commit to main - it's protected)
    # Continue to create new session below
  else
    # Session still active - use it
    BASE_BRANCH=$(jq -r '.branch' .atlas/integration-session.json)
    git checkout "$BASE_BRANCH" && git pull origin "$BASE_BRANCH"
    # Skip to step 1
  fi
fi
```

## Creating New Integration Session

**When no session exists** (first iteration or after cleanup):

```bash
# 1. Generate session name
SESSION_NAME="atlas-$(date +%Y%m%d-%H%M%S)"
BASE_BRANCH="integration/$SESSION_NAME"

# 2. Create integration branch (already on main from step 0)
git checkout -b "$BASE_BRANCH"
git push -u origin "$BASE_BRANCH"

# 3. Create PR to main - Ready for Review, NOT draft (REQUIRED)
PR_URL=$(gh pr create --base main \
  --title "🔄 Integration: $SESSION_NAME" \
  --body "## Integration Branch

⚠️ **NO MERGEAR** hasta revisión completa.

### PRs incluidos
_Se actualizará con cada feature mergeada_

### Checklist
- [ ] Code review completo
- [ ] Tests passing
- [ ] Sin conflictos con main
")
PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')

# 4. Create session file (.atlas/ already exists from atlas init)
cat > .atlas/integration-session.json << EOF
{
  "session_name": "$SESSION_NAME",
  "branch": "$BASE_BRANCH",
  "pr_number": $PR_NUMBER,
  "status": "active",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# 5. Commit session file
git add .atlas/integration-session.json
git commit -m "chore: init integration session $SESSION_NAME"
git push
```

## Why Start from Main?

If you start directly on an old integration branch:
1. The user may have already merged the PR on GitHub
2. You'd be working on a stale branch
3. New Atlas runs would start from the wrong base

By ALWAYS starting from main and checking PR state, we ensure:
- Fresh state on every iteration start
- Automatic cleanup of merged sessions
- New sessions created from latest main

## Creating Feature Branches

Always create from integration branch:

```bash
# CORRECT
git checkout "$BASE_BRANCH"
git pull origin "$BASE_BRANCH"
git checkout -b feature/TASK-001-description

# WRONG - never branch from main during Atlas session
git checkout main  # NO!
```

## Creating PRs

**Target integration branch, NOT main**:

```bash
# CORRECT
gh pr create --base "$BASE_BRANCH" --title "feat: description"

# WRONG
gh pr create --base main  # NO! Never during Atlas session
```

## Merging PRs

```bash
# Squash merge to integration
gh pr merge --squash --delete-branch

# Return to integration branch
git checkout "$BASE_BRANCH"
git pull origin "$BASE_BRANCH"
```

## CRITICAL: Update Backlog After Merge

**IMMEDIATELY after merging a PR, you MUST update the backlog:**

```bash
# 1. Move task from IN_PROGRESS to DONE in backlog.md
#    Add completion date and PR number

# 2. Append to progress.txt with summary

# 3. Commit and push state changes
git add .atlas/
git commit -m "chore: complete [TASK_ID]"
git push
```

**NEVER proceed to the next task without updating the backlog.**
This is the most common source of state drift - tasks get completed but backlog shows them as pending.

**Verification**: Before starting a new task, confirm the previous task appears in the DONE section of backlog.md.

## End of Session

The integration branch stays with PR open to main (Ready for Review). Human reviews and merges when ready.

**DO NOT**:
- Merge integration PR to main automatically
- Delete integration branch before human review

## Session File Format

```json
{
  "session_name": "atlas-20260119-155537",
  "branch": "integration/atlas-20260119-155537",
  "pr_number": 28,
  "status": "active",
  "created_at": "2026-01-19T15:55:37Z"
}
```

## Error Recovery

If integration branch gets out of sync:
```bash
git checkout "$BASE_BRANCH"
git pull origin "$BASE_BRANCH"
# If conflicts, resolve them on integration branch
```

If session file is corrupted, check GitHub for the integration branch and PR number, then recreate the file.
