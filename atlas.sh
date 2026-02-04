#!/bin/bash
set -e

ATLAS_HOME="${HOME}/.atlas"
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
NOTIFY_TELEGRAM="${ATLAS_NOTIFY_TELEGRAM:-true}"

DEFAULT_MAX_ITERATIONS=25
DEFAULT_STALE_SECONDS=7200
DEFAULT_TIMEOUT=1200

ATLAS_DIR=".atlas"
RUNS_DIR="$ATLAS_DIR/runs"
ACTIVITY_LOG="$ATLAS_DIR/activity.log"
ERRORS_LOG="$ATLAS_DIR/errors.log"
PROGRESS_FILE="$ATLAS_DIR/progress.txt"
GUARDRAILS_FILE="$ATLAS_DIR/guardrails.md"
BACKLOG_FILE="$ATLAS_DIR/backlog.md"

case "${1:-}" in
    init)
        mkdir -p "$ATLAS_DIR" "$RUNS_DIR"
        if [[ ! -f "$BACKLOG_FILE" ]]; then
            sed "s/\[PROJECT_NAME\]/$PROJECT_NAME/" "$ATLAS_HOME/templates/backlog.md" > "$BACKLOG_FILE"
            echo "  Created: backlog.md"
        fi
        if [[ ! -f "$PROGRESS_FILE" ]]; then
            cp "$ATLAS_HOME/templates/progress.txt" "$PROGRESS_FILE"
            sed -i "s/YYYY-MM-DD/$(date +%Y-%m-%d)/" "$PROGRESS_FILE" 2>/dev/null || sed -i '' "s/YYYY-MM-DD/$(date +%Y-%m-%d)/" "$PROGRESS_FILE"
            echo "  Created: progress.txt"
        fi
        [[ ! -f "$GUARDRAILS_FILE" ]] && cp "$ATLAS_HOME/templates/guardrails.md" "$GUARDRAILS_FILE" && echo "  Created: guardrails.md"
        [[ ! -f "$ACTIVITY_LOG" ]] && { echo "# Activity Log"; echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"; echo ""; } > "$ACTIVITY_LOG" && echo "  Created: activity.log"
        [[ ! -f "$ERRORS_LOG" ]] && { echo "# Error Log"; echo ""; } > "$ERRORS_LOG" && echo "  Created: errors.log"
        # Create .gitignore to exclude session logs (they're local debugging, not code)
        if [[ ! -f "$ATLAS_DIR/.gitignore" ]]; then
            cat > "$ATLAS_DIR/.gitignore" << 'GITIGNORE'
# Atlas session logs (local debugging files)
activity.log
errors.log
runs/

# Keep integration session tracked (needed for PR workflow)
!integration-session.json
GITIGNORE
            echo "  Created: .gitignore"
        fi
        [[ -d "$ATLAS_HOME/references" ]] && [[ ! -d "$ATLAS_DIR/references" ]] && cp -r "$ATLAS_HOME/references" "$ATLAS_DIR/" && echo "  Created: references/"

        # Install Atlas skills to ~/.claude/skills/
        if [[ -d "$ATLAS_HOME/skills" ]]; then
            mkdir -p "${HOME}/.claude/skills"
            for skill_dir in "$ATLAS_HOME/skills"/atlas-*; do
                skill_name=$(basename "$skill_dir")
                mkdir -p "${HOME}/.claude/skills/$skill_name"
                cp -r "$skill_dir"/* "${HOME}/.claude/skills/$skill_name/" 2>/dev/null || true
            done
            echo "  Installed: Atlas skills to ~/.claude/skills/"
        fi

        echo "✓ Initialized .atlas/ in $PROJECT_DIR"
        exit 0
        ;;
    update)
        REPO_URL="https://raw.githubusercontent.com/juancruzrossi/atlas/main"

        # Get current version (skip Unreleased, find first X.Y.Z)
        OLD_VERSION=$(grep -m1 "^## \[[0-9]" "$ATLAS_HOME/CHANGELOG.md" 2>/dev/null | sed 's/## \[\(.*\)\].*/\1/' || echo "unknown")

        # Download all files silently
        mkdir -p "$ATLAS_HOME/templates" "$ATLAS_HOME/references" "$ATLAS_HOME/skills"
        curl -fsSL "$REPO_URL/atlas.sh" -o "$ATLAS_HOME/atlas.sh" && chmod +x "$ATLAS_HOME/atlas.sh"
        curl -fsSL "$REPO_URL/prompt.md" -o "$ATLAS_HOME/prompt.md"
        curl -fsSL "$REPO_URL/plan_prompt.md" -o "$ATLAS_HOME/plan_prompt.md"
        rm -f "$ATLAS_HOME/PLAN_PROMPT.md"  # Remove old file if exists
        curl -fsSL "$REPO_URL/CHANGELOG.md" -o "$ATLAS_HOME/CHANGELOG.md"
        curl -fsSL "$REPO_URL/notify-telegram.sh" -o "$ATLAS_HOME/notify-telegram.sh" && chmod +x "$ATLAS_HOME/notify-telegram.sh"
        for f in backlog.md progress.txt guardrails.md; do curl -fsSL "$REPO_URL/templates/$f" -o "$ATLAS_HOME/templates/$f" 2>/dev/null; done
        for f in GUARDRAILS.md CONTEXT_ENGINEERING.md; do curl -fsSL "$REPO_URL/references/$f" -o "$ATLAS_HOME/references/$f" 2>/dev/null; done

        # Download and install Atlas skills
        SKILLS="atlas-integration-flow atlas-branching atlas-guardrails atlas-state"
        mkdir -p "${HOME}/.claude/skills"
        for skill in $SKILLS; do
            mkdir -p "$ATLAS_HOME/skills/$skill" "${HOME}/.claude/skills/$skill"
            curl -fsSL "$REPO_URL/skills/$skill/SKILL.md" -o "$ATLAS_HOME/skills/$skill/SKILL.md" 2>/dev/null || true
            [[ -f "$ATLAS_HOME/skills/$skill/SKILL.md" ]] && cp "$ATLAS_HOME/skills/$skill/SKILL.md" "${HOME}/.claude/skills/$skill/"
        done

        # Update binary in PATH if needed
        ATLAS_BIN=$(which atlas 2>/dev/null)
        [[ -n "$ATLAS_BIN" && -f "$ATLAS_BIN" && ! -L "$ATLAS_BIN" ]] && cp "$ATLAS_HOME/atlas.sh" "$ATLAS_BIN" && chmod +x "$ATLAS_BIN"

        # Get new version (skip Unreleased, find first X.Y.Z)
        NEW_VERSION=$(grep -m1 "^## \[[0-9]" "$ATLAS_HOME/CHANGELOG.md" | sed 's/## \[\(.*\)\].*/\1/')

        if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
            echo "✓ Atlas v$NEW_VERSION (already up to date)"
        else
            echo "✓ Atlas updated: v$OLD_VERSION → v$NEW_VERSION"
        fi
        echo "✓ Skills installed to ~/.claude/skills/"
        exit 0
        ;;
    plan)
        shift
        FEATURE_PROMPT="${1:-}"

        [[ -z "$FEATURE_PROMPT" ]] && { echo "Usage: atlas plan \"feature description\""; exit 1; }
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }

        mkdir -p "$ATLAS_DIR/specs"
        SPEC_FILE="$ATLAS_DIR/specs/spec-$(date +%Y%m%d-%H%M%S).md"

        # Export variables for envsubst
        export FEATURE_REQUEST="$FEATURE_PROMPT"
        export PROJECT_DIR PROJECT_NAME SPEC_FILE BACKLOG_FILE

        # Process plan_prompt.md with variable substitution
        PLAN_PROMPT=$(envsubst '$FEATURE_REQUEST $PROJECT_DIR $PROJECT_NAME $SPEC_FILE $BACKLOG_FILE' < "$ATLAS_HOME/plan_prompt.md")

        echo "╔═══════════════════════════════════════════════════════╗"
        echo "║  Atlas Plan - Feature Interview                       ║"
        echo "╠═══════════════════════════════════════════════════════╣"
        echo "║  Feature: $FEATURE_PROMPT"
        echo "║  Output:  $SPEC_FILE"
        echo "╚═══════════════════════════════════════════════════════╝"

        log_activity() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ACTIVITY_LOG"; }
        log_activity "PLAN: $FEATURE_PROMPT -> $SPEC_FILE"

        # Interactive mode (no -p) allows AskUserQuestionTool
        # --dangerously-skip-permissions avoids permission prompts
        claude --dangerously-skip-permissions "$PLAN_PROMPT"

        exit 0
        ;;
    resume)
        shift
        RESUME_ITERATIONS="${1:-$DEFAULT_MAX_ITERATIONS}"

        # Validar número si se proporciona
        [[ $# -gt 0 && ! "$1" =~ ^[0-9]+$ ]] && { echo "Error: iterations must be a number"; exit 1; }

        # Verificar .atlas/ existe
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }

        SESSION_FILE=".atlas/integration-session.json"

        # Verificar session file existe
        if [[ ! -f "$SESSION_FILE" ]]; then
            echo "❌ No active integration session found."
            echo ""
            echo "There is no session to resume. To start a new session:"
            echo "  atlas [N]    Start new session with N iterations"
            exit 1
        fi

        # Verificar jq disponible
        command -v jq &>/dev/null || { echo "Error: 'jq' required for session management."; exit 1; }

        # Leer session data
        SESSION_BRANCH=$(jq -r '.branch' "$SESSION_FILE" 2>/dev/null)
        SESSION_PR=$(jq -r '.pr_number' "$SESSION_FILE" 2>/dev/null)
        SESSION_NAME=$(jq -r '.session_name' "$SESSION_FILE" 2>/dev/null)

        # Validar datos
        [[ -z "$SESSION_PR" || "$SESSION_PR" == "null" ]] && { echo "❌ Invalid session file: missing pr_number"; exit 1; }
        [[ -z "$SESSION_BRANCH" || "$SESSION_BRANCH" == "null" ]] && { echo "❌ Invalid session file: missing branch"; exit 1; }

        # Verificar estado del PR
        echo "🔍 Checking session status..."
        PR_STATE=$(gh pr view "$SESSION_PR" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")

        case "$PR_STATE" in
            MERGED)
                echo "❌ Session already merged (PR #$SESSION_PR)."
                echo "   Use 'atlas' to start a new session."
                exit 1 ;;
            CLOSED)
                echo "❌ Session PR was closed (PR #$SESSION_PR)."
                echo "   Reopen on GitHub or delete .atlas/integration-session.json"
                exit 1 ;;
            UNKNOWN)
                echo "⚠️  Could not verify PR status (offline?). Continuing..." ;;
            OPEN)
                echo "✓ Session active: $SESSION_NAME (PR #$SESSION_PR)" ;;
        esac

        # Checkout a integration branch
        echo "📍 Switching to: $SESSION_BRANCH"
        if ! git checkout "$SESSION_BRANCH" 2>/dev/null; then
            if git show-ref --verify --quiet "refs/remotes/origin/$SESSION_BRANCH"; then
                git checkout -b "$SESSION_BRANCH" "origin/$SESSION_BRANCH" || { echo "❌ Failed to checkout"; exit 1; }
            else
                echo "❌ Branch not found: $SESSION_BRANCH"
                exit 1
            fi
        fi
        git pull origin "$SESSION_BRANCH" 2>/dev/null || echo "   ⚠️  Could not pull"

        # Exportar para loop
        export MAX_ITERATIONS="$RESUME_ITERATIONS"
        export RESUME_MODE="true"
        echo ""
        ;;
    help|--help|-h)
        echo "Atlas - Autonomous Task Loop Agent System"
        echo ""
        echo "Usage: atlas [iterations]"
        echo "       atlas init         - Initialize .atlas/ in current project"
        echo "       atlas plan \"...\"   - Interview and plan a feature"
        echo "       atlas resume [N]   - Resume interrupted integration session"
        echo "       atlas update       - Update Atlas from GitHub (preserves your data)"
        echo "       atlas 25           - Run 25 iterations"
        echo ""
        echo "Environment variables (all configurable):"
        echo "  ATLAS_MAX_ITERATIONS=25     Max iterations per run"
        echo "  ATLAS_TIMEOUT=1200          Timeout per iteration in seconds (20 min)"
        echo "  ATLAS_STALE_SECONDS=7200    Reset stuck tasks after N seconds (2 hours)"
        echo "  ATLAS_NOTIFY_TELEGRAM=false Disable Telegram notifications"
        echo "  ATLAS_TELEGRAM_BOT=...      Telegram bot token"
        echo "  ATLAS_TELEGRAM_CHAT=...     Telegram chat ID"
        exit 0
        ;;
esac

MAX_ITERATIONS="${ATLAS_MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
STALE_SECONDS="${ATLAS_STALE_SECONDS:-$DEFAULT_STALE_SECONDS}"
TIMEOUT_SECONDS="${ATLAS_TIMEOUT:-$DEFAULT_TIMEOUT}"

# Validate arguments - only numbers allowed at this point
if [[ $# -gt 0 ]]; then
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
    else
        echo "Error: Unknown command '$1'"
        echo "Run 'atlas help' for usage"
        exit 1
    fi
fi

[[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }
[[ ! -f "$BACKLOG_FILE" ]] && { echo "Error: .atlas/backlog.md not found. Run 'atlas init' or create it manually."; exit 1; }
mkdir -p "$RUNS_DIR"

log_activity() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ACTIVITY_LOG"; }

# Check for stale tasks in IN_PROGRESS and move back to TODO
reset_stale_tasks() {
    [[ "$STALE_SECONDS" -eq 0 ]] && return

    # Check if there's a task in IN_PROGRESS
    local in_progress_task=$(sed -n '/^## IN_PROGRESS$/,/^## /{/^### /p;}' "$BACKLOG_FILE" | head -1)
    [[ -z "$in_progress_task" ]] && return

    # Find most recent run log to determine age
    local latest_run=$(ls -t "$RUNS_DIR"/*.log 2>/dev/null | head -1)
    [[ -z "$latest_run" ]] && return

    local last_mod=$(stat -c %Y "$latest_run" 2>/dev/null || stat -f %m "$latest_run" 2>/dev/null)
    local now=$(date +%s)
    local age=$((now - last_mod))

    [[ "$age" -le "$STALE_SECONDS" ]] && return

    echo "⚠️  Stale task in IN_PROGRESS (${age}s old, threshold: ${STALE_SECONDS}s)"
    echo "   Resetting to TODO..."

    # Extract full task block from IN_PROGRESS
    local task_block=$(sed -n '/^## IN_PROGRESS$/,/^## DONE$/{/^## /d;p;}' "$BACKLOG_FILE")
    [[ -z "$task_block" ]] && return

    # Create temp file with task moved back to TODO (insert before IN_PROGRESS)
    awk -v task="$task_block" '
        /^## IN_PROGRESS$/ { print task; print ""; print; in_progress=1; next }
        /^## DONE$/ { in_progress=0 }
        in_progress && /^### / { next }
        in_progress && /^- \*\*/ { next }
        in_progress && /^  [0-9]+\./ { next }
        { print }
    ' "$BACKLOG_FILE" > "$BACKLOG_FILE.tmp" && mv "$BACKLOG_FILE.tmp" "$BACKLOG_FILE"

    log_activity "STALE RESET: Moved task back to TODO after ${age}s"
    echo "✓ Task moved back to TODO"
}

git_head() { git rev-parse --short HEAD 2>/dev/null || echo ""; }

# Count tasks in backlog (bash-verified, not model-dependent)
count_tasks() {
    local file="$1"
    [[ ! -f "$file" ]] && echo "0 0 0" && return

    local in_section=""
    local todo=0 in_progress=0 done=0

    while IFS= read -r line; do
        # Detect section headers
        if [[ "$line" =~ ^##[[:space:]]+(TODO|IN_PROGRESS|IN\ PROGRESS|DONE|DELAYED) ]]; then
            in_section="${BASH_REMATCH[1]}"
            [[ "$in_section" == "IN PROGRESS" ]] && in_section="IN_PROGRESS"
        # Count tasks (lines starting with ### )
        elif [[ "$line" =~ ^###[[:space:]] ]]; then
            case "$in_section" in
                TODO) ((todo++)) ;;
                IN_PROGRESS) ((in_progress++)) ;;
                DONE) ((done++)) ;;
            esac
        fi
    done < "$file"

    echo "$todo $in_progress $done"
}

send_notification() {
    [[ "$NOTIFY_TELEGRAM" == "true" ]] && [[ -x "$ATLAS_HOME/notify-telegram.sh" ]] && "$ATLAS_HOME/notify-telegram.sh" "$1" "$MAX_ITERATIONS" "$PROJECT_NAME" "$2" &
}

RUN_TAG="$(date +%Y%m%d-%H%M%S)-$$"
CONSECUTIVE_ERRORS=0
MAX_CONSECUTIVE_ERRORS=3

# Handle Ctrl+C gracefully
cleanup() {
    echo ""
    echo "⛔ Interrupted by user"
    log_activity "RUN INTERRUPTED run=$RUN_TAG"
    [[ "$GIT_MODE" == "true" ]] && git checkout "${DEFAULT_BRANCH:-main}" 2>/dev/null || true
    exit 130
}
trap cleanup SIGINT SIGTERM

echo "╔═══════════════════════════════════════════════════════╗"
echo "║  Atlas - Autonomous Task Loop Agent System            ║"
echo "╠═══════════════════════════════════════════════════════╣"
echo "║  Project: $PROJECT_NAME"
echo "║  Iterations: $MAX_ITERATIONS"
echo "║  Run: $RUN_TAG"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

log_activity "RUN START run=$RUN_TAG iterations=$MAX_ITERATIONS"

reset_stale_tasks

# Si estamos en resume mode, saltar setup de branch (ya hicimos checkout)
if [[ "${RESUME_MODE:-false}" == "true" ]]; then
    export GIT_MODE="true"
    export DEFAULT_BRANCH="${ATLAS_DEFAULT_BRANCH:-}"
    [[ -z "$DEFAULT_BRANCH" ]] && DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || DEFAULT_BRANCH="main"
    echo "📍 Resumed session - skipping branch setup"
    echo ""
elif [[ -d "$PROJECT_DIR/.git" ]]; then
    export GIT_MODE="true"

    # Detect default branch (main, master, or configured)
    export DEFAULT_BRANCH="${ATLAS_DEFAULT_BRANCH:-}"
    if [[ -z "$DEFAULT_BRANCH" ]]; then
        DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || DEFAULT_BRANCH="main"
        [[ -z "$DEFAULT_BRANCH" ]] && DEFAULT_BRANCH="main"
    fi

    # CRITICAL: Always start from default branch to ensure clean state
    echo "📍 Ensuring clean git state..."
    CURRENT_BRANCH=$(git branch --show-current)

    # Handle empty repo (no commits yet) - skip branch switching
    if [[ -z "$CURRENT_BRANCH" ]] && ! git rev-parse HEAD &>/dev/null; then
        echo "   ⚠️  New repository with no commits yet - skipping branch check"
    elif [[ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]]; then
        echo "   Switching from '$CURRENT_BRANCH' to $DEFAULT_BRANCH..."

        # Check for uncommitted changes that would block checkout
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            echo "❌ Cannot switch branches: you have uncommitted changes"
            echo "   Please commit or stash your changes first:"
            git status --short
            exit 1
        fi

        # Try checkout, showing the actual error if it fails
        if ! git checkout "$DEFAULT_BRANCH" 2>&1; then
            # Branch might not exist locally - try to create from remote
            if git show-ref --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH" 2>/dev/null; then
                echo "   Creating local branch from origin/$DEFAULT_BRANCH..."
                git checkout -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" || {
                    echo "❌ Failed to create local branch $DEFAULT_BRANCH"
                    exit 1
                }
            else
                echo "❌ Branch '$DEFAULT_BRANCH' does not exist locally or on remote"
                echo "   Available branches:"
                git branch -a
                echo ""
                echo "   Hint: Set ATLAS_DEFAULT_BRANCH to your main branch name, or create the branch first"
                exit 1
            fi
        fi
    fi
    git pull origin "$DEFAULT_BRANCH" 2>/dev/null || echo "   ⚠️  Could not pull (offline or no remote)"

    # Check for merged integration session and cleanup
    if [[ -f ".atlas/integration-session.json" ]] && command -v jq &>/dev/null; then
        SESSION_PR=$(jq -r '.pr_number' .atlas/integration-session.json 2>/dev/null)
        if [[ -n "$SESSION_PR" && "$SESSION_PR" != "null" ]]; then
            PR_STATE=$(gh pr view "$SESSION_PR" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
            if [[ "$PR_STATE" == "MERGED" ]]; then
                echo "   🧹 Cleaning up merged integration session (PR #$SESSION_PR)..."
                OLD_BRANCH=$(jq -r '.branch' .atlas/integration-session.json 2>/dev/null)
                [[ -n "$OLD_BRANCH" ]] && git branch -D "$OLD_BRANCH" 2>/dev/null || true
                rm -f .atlas/integration-session.json
                echo "   ✓ Cleaned up. New session will be created."
            fi
        fi
    fi
    echo ""
else
    export GIT_MODE="false"
    echo "⚠️  No git repository detected - running in LOCAL MODE"
    echo "   (no branches, commits, or PRs will be created)"
    echo ""
fi

for i in $(seq 1 $MAX_ITERATIONS); do
    echo "═══ ITERATION $i/$MAX_ITERATIONS ═══"

    ITER_START=$(date +%s)
    HEAD_BEFORE=$(git_head)
    LOG_FILE="$RUNS_DIR/run-$RUN_TAG-iter-$i.log"

    log_activity "ITERATION $i START"

    # Build list of context files that exist
    CONTEXT_FILES=""
    [[ -f "$BACKLOG_FILE" ]] && CONTEXT_FILES="$CONTEXT_FILES
- $BACKLOG_FILE (REQUIRED - task queue)"
    [[ -f "$GUARDRAILS_FILE" ]] && CONTEXT_FILES="$CONTEXT_FILES
- $GUARDRAILS_FILE (rules from past errors)"
    [[ -f "$PROGRESS_FILE" ]] && CONTEXT_FILES="$CONTEXT_FILES
- $PROGRESS_FILE (history of completed tasks)"
    [[ -f "$ERRORS_LOG" ]] && CONTEXT_FILES="$CONTEXT_FILES
- $ERRORS_LOG (recent failures)"
    [[ -f "CLAUDE.md" ]] && CONTEXT_FILES="$CONTEXT_FILES
- CLAUDE.md (project rules and quality gates)"
    [[ -f ".atlas/integration-session.json" ]] && CONTEXT_FILES="$CONTEXT_FILES
- .atlas/integration-session.json (INTEGRATION SESSION - use branch as BASE_BRANCH)"

    # Extract spec file from CURRENT task only (IN_PROGRESS first, then first TODO)
    SPEC_FILE=""
    CURRENT_TASK_SPEC=""

    # Get the current task block (IN_PROGRESS first, then TODO if empty)
    CURRENT_TASK_BLOCK=$(awk '
        /^## IN_PROGRESS/ { section="IP"; next }
        /^## TODO/ { if (section != "IP" || !found) section="TODO"; next }
        /^## / { section=""; next }
        section && /^### / {
            found=1
            print
            while ((getline line) > 0) {
                if (line ~ /^### / || line ~ /^## /) break
                print line
            }
            exit
        }
    ' "$BACKLOG_FILE")

    # Extract spec from the current task block only
    if [[ -n "$CURRENT_TASK_BLOCK" ]]; then
        CURRENT_TASK_SPEC=$(echo "$CURRENT_TASK_BLOCK" | grep "^\- \*\*Spec:\*\*" | sed 's/.*Spec:\*\* //' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    if [[ -n "$CURRENT_TASK_SPEC" && -f "$CURRENT_TASK_SPEC" ]]; then
        SPEC_FILE="$CURRENT_TASK_SPEC"
        CONTEXT_FILES="$CONTEXT_FILES
- $CURRENT_TASK_SPEC (INTEGRAL VIEW - full feature spec)"
        echo "  📋 Spec: $CURRENT_TASK_SPEC"
    fi

    # Export variables for envsubst
    export PROJECT_DIR PROJECT_NAME
    export RUN_ID="$RUN_TAG"
    export ITERATION="$i"

    # Process prompt.md with variable substitution
    PROMPT_CONTENT=$(envsubst '$PROJECT_DIR $PROJECT_NAME $RUN_ID $ITERATION $GIT_MODE' < "$ATLAS_HOME/prompt.md")

    # Build prompt with processed instructions inline
    PROMPT="CONTEXT_FILES:$CONTEXT_FILES

---

$PROMPT_CONTENT"

    set +e
    # Write prompt to temp file to avoid pipe issues with signals
    PROMPT_FILE_TMP=$(mktemp)
    echo "$PROMPT" > "$PROMPT_FILE_TMP"

    # Retry loop for transient CLI errors (rate limits, timeouts, network)
    MAX_RETRIES=3
    RETRY_DELAY=10
    RETRY_COUNT=0
    CLI_SUCCESS=false
    CLI_ERROR=""

    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))

        # Run claude and capture output
        OUTPUT=$(timeout --foreground "$TIMEOUT_SECONDS" claude --dangerously-skip-permissions -p < "$PROMPT_FILE_TMP" 2>&1) || true

        # Check for CLI errors
        CLI_ERROR=""
        if [[ -z "$OUTPUT" ]]; then
            CLI_ERROR="No output captured"
        elif echo "$OUTPUT" | grep -q "Error: No messages returned"; then
            CLI_ERROR="API rate limit or timeout"
        elif echo "$OUTPUT" | grep -q "Error: API"; then
            CLI_ERROR="API error"
        elif echo "$OUTPUT" | grep -q "Error: Network"; then
            CLI_ERROR="Network error"
        fi

        if [[ -z "$CLI_ERROR" ]]; then
            CLI_SUCCESS=true
            break
        fi

        # Log retry attempt (console only, no notification yet)
        echo "⚠️  CLI Error: $CLI_ERROR (attempt $RETRY_COUNT/$MAX_RETRIES)"
        log_activity "ITERATION $i RETRY $RETRY_COUNT: $CLI_ERROR"

        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
            echo "   Retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi
    done

    rm -f "$PROMPT_FILE_TMP"

    # Handle complete failure after all retries exhausted
    if [[ "$CLI_SUCCESS" == "false" ]]; then
        CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
        echo "❌ Failed after $MAX_RETRIES attempts"
        echo "$OUTPUT" > "$LOG_FILE"

        read ERROR_TODO ERROR_IP ERROR_DONE <<< $(count_tasks "$BACKLOG_FILE")

        if [[ $CONSECUTIVE_ERRORS -ge $MAX_CONSECUTIVE_ERRORS ]]; then
            echo "🛑 Too many consecutive failed iterations ($CONSECUTIVE_ERRORS). Stopping run."
            send_notification "$i" "Task: CLI Error - $CLI_ERROR
Status: STOPPED
Pending: $ERROR_TODO"
            log_activity "RUN STOPPED: $CONSECUTIVE_ERRORS consecutive failed iterations"
            exit 1
        fi

        # Notify only after all retries failed
        send_notification "$i" "Task: CLI Error - $CLI_ERROR (after $MAX_RETRIES retries)
Status: SKIPPED
Pending: $ERROR_TODO"
        log_activity "ITERATION $i FAILED after $MAX_RETRIES retries, moving to next"
        continue
    fi

    # Reset error counter on successful iteration
    CONSECUTIVE_ERRORS=0

    # Write output to log file and display to terminal
    echo "$OUTPUT" | tee "$LOG_FILE"
    set -e

    ITER_END=$(date +%s)
    ITER_DURATION=$((ITER_END - ITER_START))
    HEAD_AFTER=$(git_head)

    SUMMARY=$(echo "$OUTPUT" | sed -n '/=== SUMMARY ===/,/Loop:/p' | head -10)
    [[ -z "$SUMMARY" ]] && SUMMARY="No summary found"

    # Bash-verified task count (don't trust model's count)
    read TODO_COUNT IN_PROGRESS_COUNT DONE_COUNT <<< $(count_tasks "$BACKLOG_FILE")
    echo ""
    echo "📊 Pending: $TODO_COUNT"

    # Append count to summary for Telegram
    SUMMARY="$SUMMARY
Pending: $TODO_COUNT"

    log_activity "ITERATION $i END duration=${ITER_DURATION}s pending=$TODO_COUNT"
    send_notification "$i" "$SUMMARY"

    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        echo ""; echo "✅ ALL TASKS COMPLETED!"
        log_activity "RUN COMPLETE run=$RUN_TAG"
        [[ "$GIT_MODE" == "true" ]] && git checkout "${DEFAULT_BRANCH:-main}" 2>/dev/null || true
        exit 0
    fi

    sleep 2
done

[[ "$GIT_MODE" == "true" ]] && git checkout "${DEFAULT_BRANCH:-main}" 2>/dev/null || true
echo ""; echo "🤖 MAX ITERATIONS REACHED"
log_activity "RUN END run=$RUN_TAG (max iterations)"
exit 0
