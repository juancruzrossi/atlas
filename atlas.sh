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
        [[ -d "$ATLAS_HOME/references" ]] && [[ ! -d "$ATLAS_DIR/references" ]] && cp -r "$ATLAS_HOME/references" "$ATLAS_DIR/" && echo "  Created: references/"
        echo "✓ Initialized .atlas/ in $PROJECT_DIR"
        exit 0
        ;;
    update)
        REPO_URL="https://raw.githubusercontent.com/juancruzrossi/atlas/main"

        # Get current version (skip Unreleased, find first X.Y.Z)
        OLD_VERSION=$(grep -m1 "^## \[[0-9]" "$ATLAS_HOME/CHANGELOG.md" 2>/dev/null | sed 's/## \[\(.*\)\].*/\1/' || echo "unknown")

        # Download all files silently
        mkdir -p "$ATLAS_HOME/templates" "$ATLAS_HOME/references"
        curl -fsSL "$REPO_URL/atlas.sh" -o "$ATLAS_HOME/atlas.sh" && chmod +x "$ATLAS_HOME/atlas.sh"
        curl -fsSL "$REPO_URL/prompt.md" -o "$ATLAS_HOME/prompt.md"
        curl -fsSL "$REPO_URL/plan_prompt.md" -o "$ATLAS_HOME/plan_prompt.md"
        rm -f "$ATLAS_HOME/PLAN_PROMPT.md"  # Remove old file if exists
        curl -fsSL "$REPO_URL/CHANGELOG.md" -o "$ATLAS_HOME/CHANGELOG.md"
        curl -fsSL "$REPO_URL/notify-telegram.sh" -o "$ATLAS_HOME/notify-telegram.sh" && chmod +x "$ATLAS_HOME/notify-telegram.sh"
        for f in backlog.md progress.txt guardrails.md; do curl -fsSL "$REPO_URL/templates/$f" -o "$ATLAS_HOME/templates/$f" 2>/dev/null; done
        for f in GUARDRAILS.md CONTEXT_ENGINEERING.md; do curl -fsSL "$REPO_URL/references/$f" -o "$ATLAS_HOME/references/$f" 2>/dev/null; done

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
        exit 0
        ;;
    plan)
        shift
        FEATURE_PROMPT="${1:-}"

        [[ -z "$FEATURE_PROMPT" ]] && { echo "Usage: atlas plan \"feature description\""; exit 1; }
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }

        mkdir -p "$ATLAS_DIR/specs"
        SPEC_FILE="$ATLAS_DIR/specs/spec-$(date +%Y%m%d-%H%M%S).md"

        PLAN_PROMPT="FEATURE_REQUEST=$FEATURE_PROMPT
PROJECT_DIR=$PROJECT_DIR
PROJECT_NAME=$PROJECT_NAME
SPEC_FILE=$SPEC_FILE
BACKLOG_FILE=$BACKLOG_FILE

$(cat "$ATLAS_HOME/plan_prompt.md")"

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
    help|--help|-h)
        echo "Atlas - Autonomous Task Loop Agent System"
        echo ""
        echo "Usage: atlas [iterations]"
        echo "       atlas init         - Initialize .atlas/ in current project"
        echo "       atlas plan \"...\"   - Interview and plan a feature"
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

# Check for stale tasks in IN PROGRESS and move back to TODO
reset_stale_tasks() {
    [[ "$STALE_SECONDS" -eq 0 ]] && return

    # Check if there's a task in IN PROGRESS
    local in_progress_task=$(sed -n '/^## IN PROGRESS$/,/^## /{/^### /p;}' "$BACKLOG_FILE" | head -1)
    [[ -z "$in_progress_task" ]] && return

    # Find most recent run log to determine age
    local latest_run=$(ls -t "$RUNS_DIR"/*.log 2>/dev/null | head -1)
    [[ -z "$latest_run" ]] && return

    local last_mod=$(stat -c %Y "$latest_run" 2>/dev/null || stat -f %m "$latest_run" 2>/dev/null)
    local now=$(date +%s)
    local age=$((now - last_mod))

    [[ "$age" -le "$STALE_SECONDS" ]] && return

    echo "⚠️  Stale task in IN PROGRESS (${age}s old, threshold: ${STALE_SECONDS}s)"
    echo "   Resetting to TODO..."

    # Extract full task block from IN PROGRESS
    local task_block=$(sed -n '/^## IN PROGRESS$/,/^## DONE$/{/^## /d;p;}' "$BACKLOG_FILE")
    [[ -z "$task_block" ]] && return

    # Create temp file with task moved back to TODO (insert before IN PROGRESS)
    awk -v task="$task_block" '
        /^## IN PROGRESS$/ { print task; print ""; print; in_progress=1; next }
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

send_notification() {
    [[ "$NOTIFY_TELEGRAM" == "true" ]] && [[ -x "$ATLAS_HOME/notify-telegram.sh" ]] && "$ATLAS_HOME/notify-telegram.sh" "$1" "$MAX_ITERATIONS" "$PROJECT_NAME" "$2" &
}

RUN_TAG="$(date +%Y%m%d-%H%M%S)-$$"

# Handle Ctrl+C gracefully
cleanup() {
    echo ""
    echo "⛔ Interrupted by user"
    log_activity "RUN INTERRUPTED run=$RUN_TAG"
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

    # Extract spec file from current task in backlog (if exists)
    SPEC_FILE=""
    CURRENT_TASK_SPEC=$(grep -A15 "^### " "$BACKLOG_FILE" | grep -m1 "^\- \*\*Spec:\*\*" | sed 's/.*Spec:\*\* //' | tr -d ' ')
    if [[ -n "$CURRENT_TASK_SPEC" && -f "$CURRENT_TASK_SPEC" ]]; then
        SPEC_FILE="$CURRENT_TASK_SPEC"
        CONTEXT_FILES="$CONTEXT_FILES
- $CURRENT_TASK_SPEC (INTEGRAL VIEW - full feature spec)"
        echo "  📋 Spec found: $CURRENT_TASK_SPEC"
    fi

    # Build minimal prompt with file references only
    PROMPT="PROJECT_DIR=$PROJECT_DIR
PROJECT_NAME=$PROJECT_NAME
RUN_ID=$RUN_TAG
ITERATION=$i

PROMPT_FILE=$ATLAS_HOME/prompt.md

CONTEXT_FILES:$CONTEXT_FILES

---

You are Atlas. Read PROMPT_FILE for your instructions, then read all CONTEXT_FILES listed above."

    set +e
    OUTPUT=$(echo "$PROMPT" | timeout "$TIMEOUT_SECONDS" claude --dangerously-skip-permissions -p 2>&1 | tee "$LOG_FILE" | tee /dev/stderr) || true
    set -e

    ITER_END=$(date +%s)
    ITER_DURATION=$((ITER_END - ITER_START))
    HEAD_AFTER=$(git_head)

    SUMMARY=$(echo "$OUTPUT" | sed -n '/=== SUMMARY ===/,/Loop:/p' | head -10)
    [[ -z "$SUMMARY" ]] && SUMMARY="No summary found"

    log_activity "ITERATION $i END duration=${ITER_DURATION}s"
    send_notification "$i" "$SUMMARY"

    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        echo ""; echo "✅ ALL TASKS COMPLETED!"
        log_activity "RUN COMPLETE run=$RUN_TAG"
        exit 0
    fi

    sleep 2
done

echo ""; echo "🤖 MAX ITERATIONS REACHED"
log_activity "RUN END run=$RUN_TAG (max iterations)"
exit 0
