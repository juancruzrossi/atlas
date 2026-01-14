#!/bin/bash
set -e

ATLAS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
NOTIFY_TELEGRAM="${ATLAS_NOTIFY_TELEGRAM:-true}"

DEFAULT_MAX_ITERATIONS=10
DEFAULT_STALE_SECONDS=0

ATLAS_DIR=".atlas"
RUNS_DIR="$ATLAS_DIR/runs"
ACTIVITY_LOG="$ATLAS_DIR/activity.log"
ERRORS_LOG="$ATLAS_DIR/errors.log"
PROGRESS_FILE="$ATLAS_DIR/progress.txt"
GUARDRAILS_FILE="$ATLAS_DIR/guardrails.md"
PRD_FILE="$ATLAS_DIR/prd.json"

case "${1:-}" in
    init)
        mkdir -p "$ATLAS_DIR" "$RUNS_DIR"
        [[ ! -f "$PRD_FILE" ]] && cp "$ATLAS_HOME/templates/prd.json" "$PRD_FILE" && echo "  Created: prd.json"
        if [[ ! -f "$PROGRESS_FILE" ]]; then
            cp "$ATLAS_HOME/templates/progress.txt" "$PROGRESS_FILE"
            sed -i "s/YYYY-MM-DD/$(date +%Y-%m-%d)/" "$PROGRESS_FILE" 2>/dev/null || sed -i '' "s/YYYY-MM-DD/$(date +%Y-%m-%d)/" "$PROGRESS_FILE"
            echo "  Created: progress.txt"
        fi
        [[ ! -f "$GUARDRAILS_FILE" ]] && cp "$ATLAS_HOME/templates/guardrails.md" "$GUARDRAILS_FILE" && echo "  Created: guardrails.md"
        [[ ! -f "$ACTIVITY_LOG" ]] && { echo "# Activity Log"; echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"; echo ""; echo "## Run Summary"; echo ""; echo "## Events"; echo ""; } > "$ACTIVITY_LOG" && echo "  Created: activity.log"
        [[ ! -f "$ERRORS_LOG" ]] && { echo "# Error Log"; echo ""; echo "> Failures and issues. Use this to add guardrails."; echo ""; } > "$ERRORS_LOG" && echo "  Created: errors.log"
        [[ -d "$ATLAS_HOME/references" ]] && [[ ! -d "$ATLAS_DIR/references" ]] && cp -r "$ATLAS_HOME/references" "$ATLAS_DIR/" && echo "  Created: references/"
        echo "✓ Initialized .atlas/ in $PROJECT_DIR"
        exit 0
        ;;
    update)
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }
        echo "Updating .atlas/"
        mkdir -p "$RUNS_DIR"
        UPDATED=0
        for template in "$ATLAS_HOME/templates/"*; do
            filename=$(basename "$template")
            if [[ ! -f "$ATLAS_DIR/$filename" ]]; then
                cp "$template" "$ATLAS_DIR/"
                echo "  Added: $filename"
                UPDATED=1
            fi
        done
        [[ ! -f "$ACTIVITY_LOG" ]] && { echo "# Activity Log"; echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"; echo ""; echo "## Run Summary"; echo ""; echo "## Events"; echo ""; } > "$ACTIVITY_LOG" && echo "  Added: activity.log" && UPDATED=1
        [[ ! -f "$ERRORS_LOG" ]] && { echo "# Error Log"; echo ""; echo "> Failures and issues."; echo ""; } > "$ERRORS_LOG" && echo "  Added: errors.log" && UPDATED=1
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
        echo "Atlas - Simple autonomous coding agent loop"
        echo ""
        echo "Usage: atlas [iterations] [--cb]"
        echo "       atlas init    - Initialize .atlas/ in current project"
        echo "       atlas update  - Add new files (preserves existing)"
        echo "       atlas 25      - Run 25 iterations"
        echo "       atlas --cb 20 - Run 20 iterations with backlog.md"
        echo ""
        echo "Environment:"
        echo "  ATLAS_STALE_SECONDS=3600    Reset stuck stories"
        echo "  ATLAS_NOTIFY_TELEGRAM=false Disable Telegram"
        exit 0
        ;;
esac

MAX_ITERATIONS="${ATLAS_MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
STALE_SECONDS="${ATLAS_STALE_SECONDS:-$DEFAULT_STALE_SECONDS}"
TASK_MODE="prd"

while [[ $# -gt 0 ]]; do
    case $1 in
        --cb) TASK_MODE="backlog"; shift ;;
        *) [[ "$1" =~ ^[0-9]+$ ]] && MAX_ITERATIONS="$1"; shift ;;
    esac
done

[[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }
mkdir -p "$RUNS_DIR"

log_activity() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ACTIVITY_LOG"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ERRORS_LOG"; }

git_head() { git rev-parse --short HEAD 2>/dev/null || echo ""; }

send_notification() {
    [[ "$NOTIFY_TELEGRAM" == "true" ]] && [[ -x "$ATLAS_HOME/notify-telegram.sh" ]] && "$ATLAS_HOME/notify-telegram.sh" "$1" "$MAX_ITERATIONS" "$PROJECT_NAME" "$2" &
}

get_quality_gates() {
    [[ ! -f "$PRD_FILE" ]] && return
    python3 - "$PRD_FILE" <<'PY' 2>/dev/null || true
import json, sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text())
    for g in data.get("qualityGates", []): print(f"- {g}")
except: pass
PY
}

RUN_TAG="$(date +%Y%m%d-%H%M%S)-$$"

echo "╔═══════════════════════════════════════════════════════╗"
echo "║  Atlas - Autonomous Coding Agent                      ║"
echo "╠═══════════════════════════════════════════════════════╣"
echo "║  Project: $PROJECT_NAME"
echo "║  Mode: $TASK_MODE | Iterations: $MAX_ITERATIONS"
echo "║  Run: $RUN_TAG"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

log_activity "RUN START run=$RUN_TAG mode=$TASK_MODE iterations=$MAX_ITERATIONS"
QUALITY_GATES=$(get_quality_gates)

for i in $(seq 1 $MAX_ITERATIONS); do
    echo "═══ ITERATION $i/$MAX_ITERATIONS ═══"

    ITER_START=$(date +%s)
    HEAD_BEFORE=$(git_head)
    LOG_FILE="$RUNS_DIR/run-$RUN_TAG-iter-$i.log"

    log_activity "ITERATION $i START"

    PROMPT="TASK_MODE=$TASK_MODE
PROJECT_DIR=$PROJECT_DIR
RUN_ID=$RUN_TAG
ITERATION=$i
QUALITY_GATES:
$QUALITY_GATES

$(cat "$ATLAS_HOME/prompt.md")"

    set +e
    OUTPUT=$(echo "$PROMPT" | claude --dangerously-skip-permissions -p 2>&1 | tee "$LOG_FILE" | tee /dev/stderr) || true
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
