#!/bin/bash
set -e

ATLAS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
NOTIFY_TELEGRAM="${ATLAS_NOTIFY_TELEGRAM:-true}"

DEFAULT_MAX_ITERATIONS=10
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
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }
        echo "Updating .atlas/"
        mkdir -p "$RUNS_DIR"
        UPDATED=0
        if [[ ! -f "$BACKLOG_FILE" ]]; then
            sed "s/\[PROJECT_NAME\]/$PROJECT_NAME/" "$ATLAS_HOME/templates/backlog.md" > "$BACKLOG_FILE"
            echo "  Added: backlog.md"
            UPDATED=1
        fi
        [[ ! -f "$PROGRESS_FILE" ]] && cp "$ATLAS_HOME/templates/progress.txt" "$PROGRESS_FILE" && echo "  Added: progress.txt" && UPDATED=1
        [[ ! -f "$GUARDRAILS_FILE" ]] && cp "$ATLAS_HOME/templates/guardrails.md" "$GUARDRAILS_FILE" && echo "  Added: guardrails.md" && UPDATED=1
        [[ ! -f "$ACTIVITY_LOG" ]] && { echo "# Activity Log"; echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"; echo ""; } > "$ACTIVITY_LOG" && echo "  Added: activity.log" && UPDATED=1
        [[ ! -f "$ERRORS_LOG" ]] && { echo "# Error Log"; echo ""; } > "$ERRORS_LOG" && echo "  Added: errors.log" && UPDATED=1
        if [[ -d "$ATLAS_HOME/references" ]]; then
            mkdir -p "$ATLAS_DIR/references"
            for ref in "$ATLAS_HOME/references/"*; do
                refname=$(basename "$ref")
                [[ ! -f "$ATLAS_DIR/references/$refname" ]] && cp "$ref" "$ATLAS_DIR/references/" && echo "  Added: references/$refname" && UPDATED=1
            done
        fi
        [[ $UPDATED -eq 0 ]] && echo "  Everything up to date"
        echo "✓ Update complete"
        exit 0
        ;;
    help|--help|-h)
        echo "Atlas - Autonomous coding agent loop"
        echo ""
        echo "Usage: atlas [iterations]"
        echo "       atlas init    - Initialize .atlas/ in current project"
        echo "       atlas update  - Add new files (preserves existing)"
        echo "       atlas 25      - Run 25 iterations"
        echo ""
        echo "Environment variables (all configurable):"
        echo "  ATLAS_MAX_ITERATIONS=10     Max iterations per run"
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

while [[ $# -gt 0 ]]; do
    case $1 in
        *) [[ "$1" =~ ^[0-9]+$ ]] && MAX_ITERATIONS="$1"; shift ;;
    esac
done

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

echo "╔═══════════════════════════════════════════════════════╗"
echo "║  Atlas - Autonomous Coding Agent                      ║"
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

    PROMPT="PROJECT_DIR=$PROJECT_DIR
PROJECT_NAME=$PROJECT_NAME
RUN_ID=$RUN_TAG
ITERATION=$i

$(cat "$ATLAS_HOME/prompt.md")"

    set +e
    OUTPUT=$(echo "$PROMPT" | timeout "$TIMEOUT_SECONDS" claude --dangerously-skip-permissions -p 2>&1 | tee "$LOG_FILE" | tee /dev/stderr) || true
    set -e

    ITER_END=$(date +%s)
    ITER_DURATION=$((ITER_END - ITER_START))
    HEAD_AFTER=$(git_head)

    SUMMARY=$(echo "$OUTPUT" | sed -n '/=== RESUMEN ===/,/Loop:/p' | head -10)
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
