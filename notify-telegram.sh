#!/bin/bash
# Atlas -> Telegram Notification Script
#
# Configurar via variables de entorno:
#   ATLAS_TELEGRAM_BOT  - Token del bot de Telegram
#   ATLAS_TELEGRAM_CHAT - ID del chat/grupo
#
# Para desactivar: export ATLAS_NOTIFY_TELEGRAM=false

BOT_TOKEN="${ATLAS_TELEGRAM_BOT:-}"
CHAT_ID="${ATLAS_TELEGRAM_CHAT:-}"

# Salir silenciosamente si no está configurado
if [[ -z "$BOT_TOKEN" ]] || [[ -z "$CHAT_ID" ]]; then
    exit 0
fi

ITERATION="$1"
MAX_ITERATIONS="$2"
PROJECT_NAME="$3"
SUMMARY="$4"

# Barra de progreso más elegante
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

# Calcular porcentaje
PERCENT=$((ITERATION * 100 / MAX_ITERATIONS))
PROGRESS=$(progress_bar "$ITERATION" "$MAX_ITERATIONS")
TIMESTAMP=$(date "+%H:%M")

# Extraer campos del resumen
TASK_LINE=$(echo "$SUMMARY" | grep -E "^Tarea:" | head -1)
STATUS_LINE=$(echo "$SUMMARY" | grep -E "^Estado:" | head -1)
PENDING_LINE=$(echo "$SUMMARY" | grep -E "^Pendientes" | head -1)

# Limpiar valores
TASK=$(echo "$TASK_LINE" | sed 's/^Tarea: *//')
STATUS=$(echo "$STATUS_LINE" | sed 's/^Estado: *//')
PENDING=$(echo "$PENDING_LINE" | sed 's/^Pendientes en backlog: *//')

# Determinar emoji de estado
STATUS_EMOJI="⏳"
if [[ "$STATUS" == "HECHO" ]] || [[ "$STATUS" == "DONE" ]]; then
    STATUS_EMOJI="✅"
elif [[ "$STATUS" == "FALLÓ" ]] || [[ "$STATUS" == "FAILED" ]]; then
    STATUS_EMOJI="❌"
fi

# Determinar si es la última iteración o si terminó todo
FOOTER=""
if [[ "$PENDING" == "0" ]]; then
    FOOTER="
🎉 <b>¡Todas las tareas completadas!</b>"
elif [[ "$ITERATION" == "$MAX_ITERATIONS" ]]; then
    FOOTER="
⚠️ <i>Máximo de iteraciones alcanzado</i>"
fi

# Mensaje limpio y elegante
MESSAGE="<b>Atlas</b> › <code>${PROJECT_NAME}</code>

Iteración <b>${ITERATION}</b>/${MAX_ITERATIONS}  $PROGRESS

$STATUS_EMOJI  <b>${TASK:-Sin tarea}</b>
📋  <b>${PENDING:-?}</b> tareas pendientes en backlog${FOOTER}

<i>${TIMESTAMP}</i>"

# Enviar a Telegram
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "parse_mode=HTML" \
    --data-urlencode "text=${MESSAGE}" \
    > /dev/null 2>&1

exit 0
