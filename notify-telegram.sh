#!/bin/bash
# Atlas -> Telegram Notification Script
#
# Configure via environment variables:
#   ATLAS_TELEGRAM_BOT  - Telegram bot token
#   ATLAS_TELEGRAM_CHAT - Chat/group ID
#
# To disable: export ATLAS_NOTIFY_TELEGRAM=false

BOT_TOKEN="${ATLAS_TELEGRAM_BOT:-}"
CHAT_ID="${ATLAS_TELEGRAM_CHAT:-}"

# Exit silently if not configured
if [[ -z "$BOT_TOKEN" ]] || [[ -z "$CHAT_ID" ]]; then
    exit 0
fi

ITERATION="$1"
MAX_ITERATIONS="$2"
PROJECT_NAME="$3"
SUMMARY="$4"

# Progress bar
progress_bar() {
    local current=$1
    local max=$2
    local filled=$((current * 10 / max))
    local empty=$((10 - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

PROGRESS=$(progress_bar "$ITERATION" "$MAX_ITERATIONS")
TIMESTAMP=$(date "+%H:%M")

# Extract fields from summary
TASK_LINE=$(echo "$SUMMARY" | grep -E "^Task:" | head -1)
STATUS_LINE=$(echo "$SUMMARY" | grep -E "^Status:" | head -1)
PENDING_LINE=$(echo "$SUMMARY" | grep -E "^Pending:" | head -1)

# Clean values
TASK=$(echo "$TASK_LINE" | sed 's/^Task: *//')
STATUS=$(echo "$STATUS_LINE" | sed 's/^Status: *//')
PENDING=$(echo "$PENDING_LINE" | sed 's/^Pending: *//')

# Handle empty summary (output capture failed)
if [[ -z "$TASK" && -z "$STATUS" ]]; then
    TASK="Output not captured"
    STATUS="UNKNOWN"
    PENDING="?"
fi

# Determine status emoji (pattern matching for statuses with extra info like "SKIPPED (reason)")
STATUS_EMOJI="⏳"
if [[ "$STATUS" == DONE* ]]; then
    STATUS_EMOJI="✅"
elif [[ "$STATUS" == FAILED* ]]; then
    STATUS_EMOJI="❌"
elif [[ "$STATUS" == SKIPPED* ]]; then
    STATUS_EMOJI="⏭️"
elif [[ "$STATUS" == UNKNOWN* ]]; then
    STATUS_EMOJI="❓"
fi

# Determine footer
FOOTER=""
if [[ "$PENDING" == "0" ]]; then
    FOOTER="
🎉 <b>All tasks completed!</b>"
elif [[ "$ITERATION" == "$MAX_ITERATIONS" ]]; then
    FOOTER="
⚠️ <i>Max iterations reached</i>"
fi

# Build message
MESSAGE="<b>Atlas</b> › <code>${PROJECT_NAME}</code>

Iteration <b>${ITERATION}</b>/${MAX_ITERATIONS}  $PROGRESS

$STATUS_EMOJI  <b>${TASK:-No task}</b>
📋  <b>${PENDING:-?}</b> pending in backlog${FOOTER}

<i>${TIMESTAMP}</i>"

# Send to Telegram
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "parse_mode=HTML" \
    --data-urlencode "text=${MESSAGE}" \
    > /dev/null 2>&1

exit 0
