---
name: atlas-integration-flow
description: |
  Integration branch workflow for Atlas autonomous sessions. ONLY use when
  running as Atlas agent (detected by GIT_MODE=true in prompt context).
  Handles: creating integration branch, PR workflow to integration,
  draft PR to main. Use when: (1) starting Atlas session with git,
  (2) creating PRs during Atlas run, (3) completing Atlas session.
author: Atlas
version: 1.0.0
date: 2026-01-19
---

# Atlas Integration Branch Flow

**CRITICAL**: Only apply this workflow when running as Atlas agent with GIT_MODE=true.

## Overview

All Atlas work goes to an integration branch, NOT directly to main. This allows human review of all changes before merging to main.

```
main (protected)
  │
  └── integration/atlas-YYYYMMDD-HHMMSS  ← Draft PR to main (NO merge until review)
        │
        ├── feature/TASK-001  → PR to integration ✓ merged
        ├── feature/TASK-002  → PR to integration ✓ merged
        └── fix/TASK-003      → PR to integration ✓ merged
```

## Step 0: Initialize Integration Session

**On first iteration** (when `.claude/integration-session.json` does NOT exist):

```bash
# 1. Generate session name
SESSION_NAME="atlas-$(date +%Y%m%d-%H%M%S)"
BASE_BRANCH="integration/$SESSION_NAME"

# 2. Create integration branch from main
git checkout main && git pull origin main
git checkout -b "$BASE_BRANCH"
git push -u origin "$BASE_BRANCH"

# 3. Create draft PR to main (REQUIRED)
PR_URL=$(gh pr create --draft --base main \
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

# 4. Create session file
mkdir -p .claude
cat > .claude/integration-session.json << EOF
{
  "session_name": "$SESSION_NAME",
  "branch": "$BASE_BRANCH",
  "pr_number": $PR_NUMBER,
  "status": "active",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# 5. Commit session file
git add .claude/integration-session.json
git commit -m "chore: init integration session $SESSION_NAME"
git push
```

## Subsequent Iterations

**When `.claude/integration-session.json` EXISTS**:

```bash
# Read existing session
BASE_BRANCH=$(jq -r '.branch' .claude/integration-session.json)

# Checkout and pull latest
git checkout "$BASE_BRANCH"
git pull origin "$BASE_BRANCH"
```

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

## End of Session

The integration branch stays with draft PR open to main. Human reviews and merges when ready.

**DO NOT**:
- Merge integration PR to main automatically
- Mark integration PR as ready automatically
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
