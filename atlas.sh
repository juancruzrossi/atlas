#!/bin/bash
set -e

# Resolve ATLAS_HOME from script location (works with npm symlinks)
ATLAS_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$ATLAS_SOURCE" ]]; do
    ATLAS_LINK_DIR="$(cd "$(dirname "$ATLAS_SOURCE")" && pwd)"
    ATLAS_SOURCE="$(readlink "$ATLAS_SOURCE")"
    [[ "$ATLAS_SOURCE" != /* ]] && ATLAS_SOURCE="$ATLAS_LINK_DIR/$ATLAS_SOURCE"
done
ATLAS_HOME="$(cd "$(dirname "$ATLAS_SOURCE")" && pwd)"
PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
NOTIFY_TELEGRAM="${ATLAS_NOTIFY_TELEGRAM:-true}"

# Portable JSON value extractor (handles both string and integer values)
# Uses jq when available for robustness, falls back to awk
json_get() {
    local key="$1" file="$2"
    [[ ! -f "$file" ]] && return
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null
        return
    fi
    awk -v k="$key" '
        $0 ~ ("\"" k "\"") {
            sub(".*\"" k "\"[[:space:]]*:[[:space:]]*", "")
            sub(/^"/, "")
            sub(/".*/, "")
            sub(/,.*/, "")
            sub(/[[:space:]]*$/, "")
            print; exit
        }
    ' "$file"
}

# Atlas version (read from package.json, fallback to hardcoded)
ATLAS_VERSION=$(json_get "version" "$ATLAS_HOME/package.json")
[[ -z "$ATLAS_VERSION" ]] && ATLAS_VERSION="3.2.1"

# AI Provider configuration (claudecode | opencode | codex)
# Priority: --cli flag > ATLAS_CLI env var > default (claudecode)
ATLAS_CLI="${ATLAS_CLI:-claudecode}"

SHOW_HELP=false
SHOW_VERSION=false
REVIEW_DRY_RUN=false
CLEAN_ALL=false
LOGS_TAIL=""
LOGS_FAILED=false
LOGS_SEARCH=""
POSITIONAL_ARGS=()

# Parse global flags from any position
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cli)
            if [[ $# -lt 2 ]]; then
                echo "Error: --cli requires an argument (claudecode, opencode, or codex)"
                exit 1
            fi
            case "$2" in
                claudecode|opencode|codex)
                    ATLAS_CLI="$2"
                    ;;
                *)
                    echo "Error: --cli requires 'claudecode', 'opencode', or 'codex', got '$2'"
                    exit 1
                    ;;
            esac
            shift 2
            continue
            ;;
        --dry-run)
            REVIEW_DRY_RUN=true
            ;;
        --all)
            CLEAN_ALL=true
            ;;
        --tail)
            if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --tail requires a number"
                exit 1
            fi
            LOGS_TAIL="$2"
            shift 2
            continue
            ;;
        --failed)
            LOGS_FAILED=true
            ;;
        --search)
            if [[ $# -lt 2 ]]; then
                echo "Error: --search requires a pattern"
                exit 1
            fi
            LOGS_SEARCH="$2"
            shift 2
            continue
            ;;
        --version|-v)
            SHOW_VERSION=true
            ;;
        --help|-h)
            SHOW_HELP=true
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                POSITIONAL_ARGS+=("$1")
                shift
            done
            break
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            ;;
    esac
    shift
done

DEFAULT_MAX_ITERATIONS=25
DEFAULT_STALE_SECONDS=7200
DEFAULT_TIMEOUT=1200

PROMPT_FILE_TMP=""
ATLAS_DIR=".atlas"
RUNS_DIR="$ATLAS_DIR/runs"
ACTIVITY_LOG="$ATLAS_DIR/activity.log"
ERRORS_LOG="$ATLAS_DIR/errors.log"
PROGRESS_FILE="$ATLAS_DIR/progress.txt"
GUARDRAILS_FILE="$ATLAS_DIR/guardrails.md"
BACKLOG_FILE="$ATLAS_DIR/backlog.md"
SESSION_FILE="$ATLAS_DIR/integration-session.json"
DEFAULT_OPENCODE_PERMISSION='{"*":"allow"}'
GIT_MODE="false"
DEFAULT_BRANCH="${ATLAS_DEFAULT_BRANCH:-}"

# Install Atlas skills to all available AI providers
install_skills() {
    [[ ! -d "$ATLAS_HOME/skills" ]] && return
    local providers=()
    command -v claude >/dev/null 2>&1 && providers+=("${HOME}/.claude/skills")
    command -v opencode >/dev/null 2>&1 && providers+=("${HOME}/.config/opencode/skills")
    command -v codex >/dev/null 2>&1 && providers+=("${HOME}/.codex/skills")
    for target_dir in "${providers[@]}"; do
        mkdir -p "$target_dir"
        for skill_dir in "$ATLAS_HOME/skills"/atlas-*; do
            [[ ! -d "$skill_dir" ]] && continue
            local skill_name
            skill_name=$(basename "$skill_dir")
            mkdir -p "$target_dir/$skill_name"
            cp -r "$skill_dir"/* "$target_dir/$skill_name/" 2>/dev/null || true
        done
        : # silent
    done
}

# Cross-platform timeout function
run_with_timeout() {
    local timeout_seconds=$1
    shift

    # Try GNU timeout (Linux)
    if command -v timeout >/dev/null 2>&1; then
        timeout --foreground "$timeout_seconds" "$@"
        return $?
    fi

    # Try gtimeout (macOS with brew install coreutils)
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout --foreground "$timeout_seconds" "$@"
        return $?
    fi

    # Fallback: run without timeout (macOS without coreutils)
    "$@"
    return $?
}

require_command() {
    local command_name="$1" install_hint="$2"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Error: $command_name not found. $install_hint"
        exit 1
    fi
}

validate_cli_installed() {
    case "$ATLAS_CLI" in
        claudecode)
            if ! command -v claude >/dev/null 2>&1; then
                echo "❌ Error: Claude Code not found"
                echo "   Install it: https://docs.anthropic.com/en/docs/claude-code"
                echo "   Or use OpenCode: curl -fsSL https://opencode.ai/install | bash"
                exit 1
            fi
            ;;
        opencode)
            if ! command -v opencode >/dev/null 2>&1; then
                echo "❌ Error: OpenCode not found"
                echo "   Install it: curl -fsSL https://opencode.ai/install | bash"
                echo "   Or use Claude Code: https://docs.anthropic.com/en/docs/claude-code"
                exit 1
            fi
            ;;
        codex)
            if ! command -v codex >/dev/null 2>&1; then
                echo "❌ Error: Codex CLI not found"
                echo "   Install it: npm install -g @openai/codex"
                echo "   Or use Claude Code: https://docs.anthropic.com/en/docs/claude-code"
                exit 1
            fi
            ;;
    esac
}

detect_default_branch() {
    local detected_branch="${ATLAS_DEFAULT_BRANCH:-}"

    if [[ -z "$detected_branch" ]]; then
        detected_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || detected_branch="main"
        [[ -z "$detected_branch" ]] && detected_branch="main"
    fi

    echo "$detected_branch"
}

get_pr_state() {
    local pr_number="$1"

    if [[ -z "$pr_number" || "$pr_number" == "null" ]] || ! command -v gh >/dev/null 2>&1; then
        echo "UNKNOWN"
        return
    fi

    gh pr view "$pr_number" --json state -q '.state' 2>/dev/null || echo "UNKNOWN"
}

file_mtime() {
    local file="$1"
    stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null || echo 0
}

cleanup_prompt_file() {
    [[ -n "$PROMPT_FILE_TMP" ]] && rm -f "$PROMPT_FILE_TMP"
    PROMPT_FILE_TMP=""
}

log_activity() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ACTIVITY_LOG"
}

# Invoke the selected AI provider with a prompt file
# Usage: run_provider <mode> <prompt_file> [timeout_seconds] [output_last_message_file]
# Modes: plan, review, build (opencode agent names; ignored by codex/claude)
run_provider() {
    local mode="$1" prompt_file="$2" timeout_seconds="${3:-}" output_last_message_file="${4:-}"

    case "$ATLAS_CLI" in
        opencode)
            export OPENCODE_PERMISSION="${OPENCODE_PERMISSION:-$DEFAULT_OPENCODE_PERMISSION}"
            if [[ -n "$timeout_seconds" ]]; then
                run_with_timeout "$timeout_seconds" opencode run --agent "$mode" "Follow the attached instructions file exactly." --file "$prompt_file"
            else
                opencode run --agent "$mode" "Follow the attached instructions file exactly." --file "$prompt_file"
            fi
            ;;
        codex)
            if [[ -n "$timeout_seconds" ]]; then
                if [[ -n "$output_last_message_file" ]]; then
                    run_with_timeout "$timeout_seconds" codex exec --yolo -o "$output_last_message_file" - < "$prompt_file"
                else
                    run_with_timeout "$timeout_seconds" codex exec --yolo - < "$prompt_file"
                fi
            else
                if [[ -n "$output_last_message_file" ]]; then
                    codex exec --yolo -o "$output_last_message_file" - < "$prompt_file"
                else
                    codex exec --yolo - < "$prompt_file"
                fi
            fi
            ;;
        *)
            if [[ "$mode" == "build" ]]; then
                if [[ -n "$timeout_seconds" ]]; then
                    run_with_timeout "$timeout_seconds" claude --dangerously-skip-permissions -p < "$prompt_file"
                else
                    claude --dangerously-skip-permissions -p < "$prompt_file"
                fi
            else
                claude --dangerously-skip-permissions "$(cat "$prompt_file")"
            fi
            ;;
    esac
}

print_help() {
    echo "Atlas - Autonomous Task Loop Agent System v$ATLAS_VERSION"
    echo ""
    echo "Usage: atlas [options] [command]"
    echo ""
    echo "Commands:"
    echo "  atlas init                  Initialize .atlas/ in current project"
    echo "  atlas plan <description>    Interview and plan a feature"
    echo "  atlas review [--dry-run]    Audit issues (and optionally auto-fix)"
    echo "  atlas resume [iterations]   Resume interrupted integration session"
    echo "  atlas clean [--all]         Clean runtime artifacts from .atlas/"
    echo "  atlas logs [--tail N]       Show iteration logs (default: last 10)"
    echo "  atlas logs --failed         Show only failed iterations"
    echo "  atlas logs --search <pat>   Search logs for pattern"
    echo "  atlas status                Show task counts and session info"
    echo "  atlas doctor                Check Atlas installation and dependencies"
    echo "  atlas update                Show how to update via NPM"
    echo "  atlas [iterations]          Run N iterations autonomously (default: 25)"
    echo ""
    echo "Options:"
    echo "  --cli <provider>            AI provider: claudecode (default) | opencode | codex"
    echo "  --dry-run                   Review mode: report only (no auto-fixes)"
    echo "  --all                       Clean mode: also reset activity/errors logs and session"
    echo "  --version, -v               Show version information"
    echo "  --help, -h                  Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  ATLAS_CLI=claudecode        Default AI provider (claudecode | opencode | codex)"
    echo "  ATLAS_MAX_ITERATIONS=25     Max iterations per run"
    echo "  ATLAS_TIMEOUT=1200          Timeout per iteration in seconds (20 min)"
    echo "  ATLAS_STALE_SECONDS=7200    Reset stuck tasks after N seconds (2 hours)"
    echo "  ATLAS_NOTIFY_TELEGRAM=true  Enable Telegram notifications"
    echo "  ATLAS_TELEGRAM_BOT=...      Telegram bot token"
    echo "  ATLAS_TELEGRAM_CHAT=...     Telegram chat ID"
    echo ""
    echo "Examples:"
    echo "  atlas 25                              # Run with Claude Code (default)"
    echo "  atlas --cli opencode review           # Review with OpenCode"
    echo "  atlas review --dry-run                # Report-only review"
    echo "  atlas --cli codex 25                  # Run with Codex"
    echo "  atlas clean                           # Remove .atlas/runs logs"
    echo "  atlas clean --all                     # Reset logs + session metadata"
}

if [[ "$SHOW_VERSION" == "true" ]]; then
    echo "Atlas v$ATLAS_VERSION"
    exit 0
fi

COMMAND=""
COMMAND_ARGS=()
if [[ "$SHOW_HELP" == "true" ]]; then
    COMMAND="help"
elif [[ ${#POSITIONAL_ARGS[@]} -eq 0 ]]; then
    COMMAND="run"
elif [[ "${POSITIONAL_ARGS[0]}" == "init" || "${POSITIONAL_ARGS[0]}" == "update" || "${POSITIONAL_ARGS[0]}" == "plan" || "${POSITIONAL_ARGS[0]}" == "resume" || "${POSITIONAL_ARGS[0]}" == "review" || "${POSITIONAL_ARGS[0]}" == "clean" || "${POSITIONAL_ARGS[0]}" == "status" || "${POSITIONAL_ARGS[0]}" == "doctor" || "${POSITIONAL_ARGS[0]}" == "logs" || "${POSITIONAL_ARGS[0]}" == "help" ]]; then
    COMMAND="${POSITIONAL_ARGS[0]}"
    COMMAND_ARGS=("${POSITIONAL_ARGS[@]:1}")
elif [[ "${POSITIONAL_ARGS[0]}" =~ ^[0-9]+$ ]]; then
    COMMAND="run"
    COMMAND_ARGS=("${POSITIONAL_ARGS[@]}")
else
    echo "Error: Unknown command '${POSITIONAL_ARGS[0]}'"
    echo "Run 'atlas help' for usage"
    exit 1
fi

if [[ "$REVIEW_DRY_RUN" == "true" && "$COMMAND" != "review" && "$COMMAND" != "help" ]]; then
    echo "Error: --dry-run is only valid with 'atlas review'"
    exit 1
fi

if [[ "$CLEAN_ALL" == "true" && "$COMMAND" != "clean" && "$COMMAND" != "help" ]]; then
    echo "Error: --all is only valid with 'atlas clean'"
    exit 1
fi

# Count tasks in backlog (bash-verified, not model-dependent)
count_tasks() {
    local file="$1"
    [[ ! -f "$file" ]] && echo "0 0 0" && return

    local in_section=""
    local todo=0 in_progress=0 done=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^##[[:space:]]+(TODO|IN_PROGRESS|IN\ PROGRESS|DONE|DELAYED) ]]; then
            in_section="${BASH_REMATCH[1]}"
            [[ "$in_section" == "IN PROGRESS" ]] && in_section="IN_PROGRESS"
        elif [[ "$line" =~ ^###[[:space:]] ]]; then
            case "$in_section" in
                TODO) todo=$((todo + 1)) ;;
                IN_PROGRESS) in_progress=$((in_progress + 1)) ;;
                DONE) done=$((done + 1)) ;;
            esac
        fi
    done < "$file"

    echo "$todo $in_progress $done"
}

case "$COMMAND" in
    init)
        mkdir -p "$ATLAS_DIR" "$RUNS_DIR"
        if [[ ! -f "$BACKLOG_FILE" ]]; then
            sed "s/\[PROJECT_NAME\]/$PROJECT_NAME/" "$ATLAS_HOME/templates/backlog.md" > "$BACKLOG_FILE"
        fi
        [[ ! -f "$PROGRESS_FILE" ]] && cp "$ATLAS_HOME/templates/progress.txt" "$PROGRESS_FILE"
        [[ ! -f "$GUARDRAILS_FILE" ]] && cp "$ATLAS_HOME/templates/guardrails.md" "$GUARDRAILS_FILE"
        [[ ! -f "$ACTIVITY_LOG" ]] && { echo "# Activity Log"; echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"; echo ""; } > "$ACTIVITY_LOG"
        [[ ! -f "$ERRORS_LOG" ]] && { echo "# Error Log"; echo ""; } > "$ERRORS_LOG"
        if [[ ! -f "$ATLAS_DIR/.gitignore" ]]; then
            cat > "$ATLAS_DIR/.gitignore" << 'GITIGNORE'
# Atlas session logs (local debugging files)
activity.log
errors.log
runs/

# Keep integration session tracked (needed for PR workflow)
!integration-session.json
GITIGNORE
        fi
        [[ -d "$ATLAS_HOME/references" ]] && [[ ! -d "$ATLAS_DIR/references" ]] && cp -r "$ATLAS_HOME/references" "$ATLAS_DIR/"

        install_skills

        echo "✓ Initialized .atlas/ in $PROJECT_DIR"
        exit 0
        ;;
    update)
        echo "Atlas is now distributed via NPM."
        echo ""
        echo "To update, run:"
        echo "  npm update -g @jxtools/atlas"
        echo ""
        echo "To check your current version:"
        echo "  atlas --version"
        echo ""
        echo "To check the latest available version:"
        echo "  npm view @jxtools/atlas version"
        exit 0
        ;;
    plan)
        FEATURE_PROMPT="${COMMAND_ARGS[*]}"
        [[ ${#COMMAND_ARGS[@]} -eq 0 ]] && { echo "Usage: atlas plan <feature description>"; exit 1; }
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }

        if [[ "$ATLAS_CLI" != "claudecode" ]]; then
            echo "Warning: 'atlas plan' works best with Claude Code (interactive mode)."
            echo "Current provider: $ATLAS_CLI"
            read -r -p "Continue anyway? [y/N] " confirm
            [[ "$confirm" != [yY] ]] && { echo "Aborted."; exit 0; }
        fi

        mkdir -p "$ATLAS_DIR/specs"
        SPEC_FILE="$ATLAS_DIR/specs/spec-$(date +%Y%m%d-%H%M%S).md"

        export FEATURE_REQUEST="$FEATURE_PROMPT"
        export PROJECT_DIR PROJECT_NAME SPEC_FILE BACKLOG_FILE
        require_command envsubst "Install gettext to use 'atlas plan'."
        PLAN_PROMPT=$(envsubst '$FEATURE_REQUEST $PROJECT_DIR $PROJECT_NAME $SPEC_FILE $BACKLOG_FILE' < "$ATLAS_HOME/plan_prompt.md")

        echo "╔═══════════════════════════════════════════════════════╗"
        echo "║  Atlas Plan - Feature Interview                       ║"
        echo "╠═══════════════════════════════════════════════════════╣"
        echo "║  Feature: $FEATURE_PROMPT"
        echo "║  Output:  $SPEC_FILE"
        echo "╚═══════════════════════════════════════════════════════╝"

        log_activity "PLAN: $FEATURE_PROMPT -> $SPEC_FILE"

        PROMPT_FILE_TMP=$(mktemp)
        printf '%s\n' "$PLAN_PROMPT" > "$PROMPT_FILE_TMP"
        run_provider plan "$PROMPT_FILE_TMP"
        cleanup_prompt_file

        exit 0
        ;;
    resume)
        [[ ${#COMMAND_ARGS[@]} -gt 1 ]] && { echo "Usage: atlas resume [iterations]"; exit 1; }
        [[ ${#COMMAND_ARGS[@]} -eq 1 && ! "${COMMAND_ARGS[0]}" =~ ^[0-9]+$ ]] && { echo "Error: iterations must be a number"; exit 1; }
        RESUME_ITERATIONS="${COMMAND_ARGS[0]:-$DEFAULT_MAX_ITERATIONS}"

        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }

        if [[ ! -f "$SESSION_FILE" ]]; then
            echo "❌ No active integration session found."
            echo ""
            echo "There is no session to resume. To start a new session:"
            echo "  atlas [N]    Start new session with N iterations"
            exit 1
        fi

        SESSION_BRANCH=$(json_get "branch" "$SESSION_FILE")
        SESSION_PR=$(json_get "pr_number" "$SESSION_FILE")
        SESSION_NAME=$(json_get "session_name" "$SESSION_FILE")

        [[ -z "$SESSION_PR" || "$SESSION_PR" == "null" ]] && { echo "❌ Invalid session file: missing pr_number"; exit 1; }
        [[ -z "$SESSION_BRANCH" || "$SESSION_BRANCH" == "null" ]] && { echo "❌ Invalid session file: missing branch"; exit 1; }

        echo "🔍 Checking session status..."
        if ! command -v gh >/dev/null 2>&1; then
            echo "⚠️  gh CLI not found; cannot verify PR status. Continuing..."
            PR_STATE="UNKNOWN"
        else
            PR_STATE=$(get_pr_state "$SESSION_PR")
        fi

        case "$PR_STATE" in
            MERGED)
                echo "❌ Session already merged (PR #$SESSION_PR)."
                echo "   Use 'atlas' to start a new session."
                exit 1 ;;
            CLOSED)
                echo "❌ Session PR was closed (PR #$SESSION_PR)."
                echo "   Reopen on GitHub or delete $SESSION_FILE"
                exit 1 ;;
            UNKNOWN)
                echo "⚠️  Could not verify PR status (offline?). Continuing..." ;;
            OPEN)
                echo "✓ Session active: $SESSION_NAME (PR #$SESSION_PR)" ;;
        esac

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

        export MAX_ITERATIONS="$RESUME_ITERATIONS"
        export RESUME_MODE="true"
        echo ""
        ;;
    review)
        [[ ${#COMMAND_ARGS[@]} -gt 0 ]] && { echo "Usage: atlas review [--dry-run]"; exit 1; }
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }
        [[ ! -f "$ATLAS_HOME/review_prompt.md" ]] && { echo "Error: review_prompt.md not found in $ATLAS_HOME. Run 'npm update -g @jxtools/atlas' to fix."; exit 1; }

        echo "╔═══════════════════════════════════════════════════════╗"
        echo "║  Atlas Review - AI Audit & Repair                    ║"
        echo "╚═══════════════════════════════════════════════════════╝"
        echo ""

        GIT_MODE="false"
        [[ -d ".git" ]] && GIT_MODE="true"

        CLAUDE_MD="CLAUDE.md"
        [[ ! -f "$CLAUDE_MD" ]] && CLAUDE_MD=""

        export PROJECT_DIR PROJECT_NAME GIT_MODE
        export BACKLOG_FILE GUARDRAILS_FILE PROGRESS_FILE ERRORS_LOG ACTIVITY_LOG
        export CLAUDE_MD
        require_command envsubst "Install gettext to use 'atlas review'."

        REVIEW_SESSION_FILE="$SESSION_FILE"
        [[ ! -f "$REVIEW_SESSION_FILE" ]] && REVIEW_SESSION_FILE=""

        REVIEW_PROMPT=$(SESSION_FILE="$REVIEW_SESSION_FILE" envsubst '$PROJECT_DIR $PROJECT_NAME $GIT_MODE $BACKLOG_FILE $GUARDRAILS_FILE $PROGRESS_FILE $ERRORS_LOG $CLAUDE_MD $ACTIVITY_LOG $SESSION_FILE' < "$ATLAS_HOME/review_prompt.md")

        if [[ "$REVIEW_DRY_RUN" == "true" ]]; then
            REVIEW_PROMPT="$REVIEW_PROMPT

## DRY RUN MODE (STRICT)
- You are in report-only mode.
- DO NOT modify files.
- DO NOT run git commit/push/merge/rebase commands.
- DO NOT run commands that mutate project state.
- Only inspect and report findings + recommended fixes."
        fi

        REVIEW_MODE_LABEL="APPLY FIXES"
        [[ "$REVIEW_DRY_RUN" == "true" ]] && REVIEW_MODE_LABEL="DRY-RUN (report only)"

        echo "🔍 Analyzing project state with AI..."
        echo "   Provider: $ATLAS_CLI"
        echo "   Git mode: $GIT_MODE"
        echo "   Mode: $REVIEW_MODE_LABEL"
        echo ""

        PROMPT_FILE_TMP=$(mktemp)
        printf '%s\n' "$REVIEW_PROMPT" > "$PROMPT_FILE_TMP"

        if [[ "$ATLAS_CLI" == "codex" ]]; then
            mkdir -p "$RUNS_DIR"
            REVIEW_RUN_TAG="$(date +%Y%m%d-%H%M%S)-$$"
            REVIEW_LOG_FILE="$RUNS_DIR/review-$REVIEW_RUN_TAG.log"
            REVIEW_LAST_MESSAGE_FILE="$RUNS_DIR/review-$REVIEW_RUN_TAG-last-message.txt"

            if run_provider review "$PROMPT_FILE_TMP" "" "$REVIEW_LAST_MESSAGE_FILE" > "$REVIEW_LOG_FILE" 2>&1; then
                echo "✅ Codex review completed (non-interactive mode)"
                echo "   Log: $REVIEW_LOG_FILE"
            else
                echo "❌ Codex review failed"
                echo "   Log: $REVIEW_LOG_FILE"
                tail -n 40 "$REVIEW_LOG_FILE" 2>/dev/null || true
                exit 1
            fi
        else
            run_provider review "$PROMPT_FILE_TMP"
        fi

        cleanup_prompt_file

        exit 0
        ;;
    clean)
        [[ ${#COMMAND_ARGS[@]} -gt 0 ]] && { echo "Usage: atlas clean [--all]"; exit 1; }
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }

        mkdir -p "$RUNS_DIR"
        RUN_LOGS_REMOVED=$(find "$RUNS_DIR" -maxdepth 1 -type f -name '*.log' | wc -l | tr -d ' ')
        if [[ "$RUN_LOGS_REMOVED" -gt 0 ]]; then
            find "$RUNS_DIR" -maxdepth 1 -type f -name '*.log' -delete
        fi

        TMP_FILES_REMOVED=$(find "$ATLAS_DIR" -maxdepth 1 -type f -name '*.tmp' | wc -l | tr -d ' ')
        if [[ "$TMP_FILES_REMOVED" -gt 0 ]]; then
            find "$ATLAS_DIR" -maxdepth 1 -type f -name '*.tmp' -delete
        fi

        SESSION_STATUS="not-found"
        if [[ -f "$SESSION_FILE" ]]; then
            SESSION_STATUS="kept"
            SESSION_PR=$(json_get "pr_number" "$SESSION_FILE")
            SESSION_BRANCH=$(json_get "branch" "$SESSION_FILE")
            PR_STATE=$(get_pr_state "$SESSION_PR")

            if [[ "$CLEAN_ALL" == "true" || "$PR_STATE" == "MERGED" || "$PR_STATE" == "CLOSED" ]]; then
                rm -f "$SESSION_FILE"
                SESSION_STATUS="removed"
                if [[ -n "$SESSION_BRANCH" ]] && git show-ref --verify --quiet "refs/heads/$SESSION_BRANCH" 2>/dev/null; then
                    git branch -D "$SESSION_BRANCH" 2>/dev/null || true
                fi
            fi
        fi

        if [[ "$CLEAN_ALL" == "true" ]]; then
            { echo "# Activity Log"; echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"; echo ""; } > "$ACTIVITY_LOG"
            { echo "# Error Log"; echo ""; } > "$ERRORS_LOG"
        fi

        echo "🧹 Atlas clean completed"
        echo "   Removed run logs: $RUN_LOGS_REMOVED"
        echo "   Removed temp files: $TMP_FILES_REMOVED"
        echo "   Integration session: $SESSION_STATUS"
        [[ "$CLEAN_ALL" == "true" ]] && echo "   Reset activity/errors logs: yes"
        exit 0
        ;;
    logs)
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }
        [[ ${#COMMAND_ARGS[@]} -gt 0 ]] && { echo "Usage: atlas logs [--tail N] [--failed] [--search <pattern>]"; exit 1; }

        LOGS_LIMIT="${LOGS_TAIL:-10}"

        # Collect log files sorted by modification time (newest first)
        LOG_FILES=()
        while IFS= read -r -d '' f; do
            LOG_FILES+=("$f")
        done < <(
            while IFS= read -r -d '' f; do
                printf '%s\t%s\0' "$(file_mtime "$f")" "$f"
            done < <(find "$RUNS_DIR" -maxdepth 1 -name '*.log' -print0 2>/dev/null) |
                sort -z -t$'\t' -k1,1rn |
                cut -z -f2-
        )

        if [[ ${#LOG_FILES[@]} -eq 0 ]]; then
            echo "No iteration logs found in $RUNS_DIR/"
            exit 0
        fi

        # Parse a log file and print a summary line
        show_log_entry() {
            local logfile="$1"

            local summary
            summary=$(sed -n '/=== SUMMARY ===/,/^$/p' "$logfile" 2>/dev/null | head -10)

            local task_line status_line
            task_line=$(echo "$summary" | grep "^Task:" | head -1)
            status_line=$(echo "$summary" | grep "^Status:" | head -1)

            [[ -z "$task_line" ]] && task_line="(no summary)"
            [[ -z "$status_line" ]] && status_line="Status: UNKNOWN"

            local status_val
            status_val=$(echo "$status_line" | sed 's/Status: //')

            local emoji="  "
            case "$status_val" in
                DONE*|COMPLETE*|MERGED*) emoji="OK" ;;
                SKIP*) emoji="--" ;;
                FAIL*|ERROR*) emoji="!!" ;;
            esac

            local mod_epoch mod_date
            mod_epoch=$(file_mtime "$logfile")
            mod_date=$(date -d "@$mod_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$mod_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")

            printf "[%s] %s  %-40s  %s\n" "$emoji" "$mod_date" "$task_line" "$status_line"
        }

        # Apply filters and display
        displayed=0
        for logfile in "${LOG_FILES[@]}"; do
            [[ $displayed -ge $LOGS_LIMIT ]] && break

            # --failed filter
            if [[ "$LOGS_FAILED" == "true" ]]; then
                local_summary_status=$(sed -n '/=== SUMMARY ===/,/^$/p' "$logfile" 2>/dev/null | grep "^Status:" | head -1)
                if ! echo "$local_summary_status" | grep -qiE "FAIL|ERROR|SKIP"; then
                    continue
                fi
            fi

            # --search filter
            if [[ -n "$LOGS_SEARCH" ]]; then
                if ! grep -qi "$LOGS_SEARCH" "$logfile" 2>/dev/null; then
                    continue
                fi
            fi

            show_log_entry "$logfile"
            displayed=$((displayed + 1))
        done

        if [[ $displayed -eq 0 ]]; then
            echo "No matching logs found."
        else
            echo ""
            echo "$displayed of ${#LOG_FILES[@]} logs shown"
        fi
        exit 0
        ;;
    status)
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }

        IFS=' ' read -r TODO_N IP_N DONE_N <<< "$(count_tasks "$BACKLOG_FILE")"

        echo "Atlas Status - $PROJECT_NAME"
        echo ""
        echo "Tasks:  TODO=$TODO_N  IN_PROGRESS=$IP_N  DONE=$DONE_N"

        if [[ -f "$SESSION_FILE" ]]; then
            S_NAME=$(json_get "session_name" "$SESSION_FILE")
            S_PR=$(json_get "pr_number" "$SESSION_FILE")
            echo "Session: $S_NAME (PR #$S_PR)"
        else
            echo "Session: none"
        fi

        if [[ -d ".git" ]]; then
            echo "Branch:  $(git branch --show-current 2>/dev/null || echo 'N/A')"
        fi
        exit 0
        ;;
    doctor)
        echo "=== Atlas Doctor ==="
        echo ""
        OK="[OK]" WARN="[WARN]" FAIL="[FAIL]"

        # Check AI CLI
        case "$ATLAS_CLI" in
            claudecode) CLI_BIN="claude" ;;
            opencode)   CLI_BIN="opencode" ;;
            codex)      CLI_BIN="codex" ;;
        esac
        if command -v "$CLI_BIN" >/dev/null 2>&1; then
            echo "$OK $ATLAS_CLI ($CLI_BIN found)"
        else
            echo "$FAIL $ATLAS_CLI ($CLI_BIN not found)"
        fi

        # Check prompts
        for p in prompt.md plan_prompt.md review_prompt.md; do
            if [[ -f "$ATLAS_HOME/$p" ]]; then
                echo "$OK $p"
            else
                echo "$FAIL $p missing in $ATLAS_HOME"
            fi
        done

        # Check envsubst
        if command -v envsubst >/dev/null 2>&1; then
            echo "$OK envsubst"
        else
            echo "$WARN envsubst not found (install gettext)"
        fi

        # Check git
        if command -v git >/dev/null 2>&1; then
            echo "$OK git ($(git --version | awk '{print $3}'))"
        else
            echo "$WARN git not found (local mode only)"
        fi

        # Check gh CLI
        if command -v gh >/dev/null 2>&1; then
            echo "$OK gh CLI ($(gh --version | head -1 | awk '{print $3}'))"
        else
            echo "$WARN gh CLI not found (no PR workflow)"
        fi

        exit 0
        ;;
    help)
        print_help
        exit 0
        ;;
    run)
        ;;
esac

if [[ "$COMMAND" == "run" ]]; then
    [[ ${#COMMAND_ARGS[@]} -gt 1 ]] && { echo "Usage: atlas [iterations]"; exit 1; }
    if [[ ${#COMMAND_ARGS[@]} -eq 1 ]]; then
        [[ "${COMMAND_ARGS[0]}" =~ ^[0-9]+$ ]] || { echo "Error: iterations must be a number"; exit 1; }
        RUN_ITERATIONS_OVERRIDE="${COMMAND_ARGS[0]}"
    fi
fi

validate_cli_installed

if [[ -z "${MAX_ITERATIONS:-}" ]]; then
    MAX_ITERATIONS="${ATLAS_MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
fi
STALE_SECONDS="${ATLAS_STALE_SECONDS:-$DEFAULT_STALE_SECONDS}"
TIMEOUT_SECONDS="${ATLAS_TIMEOUT:-$DEFAULT_TIMEOUT}"
[[ -n "${RUN_ITERATIONS_OVERRIDE:-}" ]] && MAX_ITERATIONS="$RUN_ITERATIONS_OVERRIDE"

[[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }
[[ ! -f "$BACKLOG_FILE" ]] && { echo "Error: .atlas/backlog.md not found. Run 'atlas init' or create it manually."; exit 1; }
[[ ! -f "$ATLAS_HOME/prompt.md" ]] && { echo "Error: prompt.md not found in $ATLAS_HOME. Run 'npm update -g @jxtools/atlas' to fix."; exit 1; }
require_command envsubst "Install gettext to run Atlas prompts."
mkdir -p "$RUNS_DIR"

# Check for stale tasks in IN_PROGRESS and move back to TODO
reset_stale_tasks() {
    [[ "$STALE_SECONDS" -eq 0 ]] && return

    # Quick check: any ### task under IN_PROGRESS?
    local in_progress_task
    in_progress_task=$(awk '/^## IN.PROGRESS/{f=1;next} /^## /{f=0} f && /^### /{print;exit}' "$BACKLOG_FILE")
    [[ -z "$in_progress_task" ]] && return

    # Check staleness: prefer STARTED metadata, fallback to log timestamp
    local now started_ts age
    now=$(date +%s)

    # Try to extract STARTED timestamp from IN_PROGRESS task
    local started_str
    started_str=$(awk '/^## IN.PROGRESS/{f=1;next} /^## /{f=0} f && /- \*\*Started:\*\*/{gsub(/.*Started:\*\* */,""); print; exit}' "$BACKLOG_FILE")

    if [[ -n "$started_str" ]]; then
        # Parse ISO timestamp to epoch
        started_ts=$(date -d "$started_str" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "$started_str" +%s 2>/dev/null || echo "")
    fi

    if [[ -z "$started_ts" ]]; then
        # Fallback: use most recent run log modification time
        local latest_run
        latest_run=$(ls -t "$RUNS_DIR"/*.log 2>/dev/null | head -1)
        [[ -z "$latest_run" ]] && return
        started_ts=$(file_mtime "$latest_run")
    fi

    age=$((now - started_ts))
    [[ "$age" -le "$STALE_SECONDS" ]] && return

    echo "⚠️  Stale task in IN_PROGRESS (${age}s old, threshold: ${STALE_SECONDS}s)"
    echo "   Resetting to TODO..."

    # Block-based rewrite: move IN_PROGRESS tasks to TODO, strip Started field
    awk '
        /^## IN.PROGRESS/ { ip_header = $0; in_ip = 1; next }
        in_ip && /^## / {
            printf "%s", ip_content
            print ip_header
            print ""
            in_ip = 0
            print; next
        }
        in_ip && /^- \*\*Started:\*\*/ { next }
        in_ip { ip_content = ip_content $0 "\n"; next }
        { print }
        END { if (in_ip) { printf "%s", ip_content; print ip_header } }
    ' "$BACKLOG_FILE" > "$BACKLOG_FILE.tmp" && mv "$BACKLOG_FILE.tmp" "$BACKLOG_FILE"

    log_activity "STALE RESET: Moved task back to TODO after ${age}s"
    echo "✓ Task moved back to TODO"
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
    cleanup_prompt_file
    log_activity "RUN INTERRUPTED run=$RUN_TAG"
    [[ "$GIT_MODE" == "true" && -n "${DEFAULT_BRANCH:-}" ]] && git checkout "$DEFAULT_BRANCH" 2>/dev/null || true
    exit 130
}
trap cleanup_prompt_file EXIT
trap cleanup SIGINT SIGTERM

echo "╔═══════════════════════════════════════════════════════╗"
echo "║  Atlas - Autonomous Task Loop Agent System            ║"
echo "╠═══════════════════════════════════════════════════════╣"
echo "║  Project: $PROJECT_NAME"
echo "║  AI Provider: $ATLAS_CLI"
echo "║  Iterations: $MAX_ITERATIONS"
echo "║  Run: $RUN_TAG"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

log_activity "RUN START run=$RUN_TAG iterations=$MAX_ITERATIONS"

reset_stale_tasks

# Skip branch setup in resume mode because checkout already happened.
if [[ "${RESUME_MODE:-false}" == "true" ]]; then
    export GIT_MODE="true"
    export DEFAULT_BRANCH="$(detect_default_branch)"
    echo "📍 Resumed session - skipping branch setup"
    echo ""
elif [[ -d "$PROJECT_DIR/.git" ]]; then
    export GIT_MODE="true"

    # Detect default branch (main, master, or configured)
    export DEFAULT_BRANCH="$(detect_default_branch)"

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
    if [[ -f "$SESSION_FILE" ]]; then
        SESSION_PR=$(json_get "pr_number" "$SESSION_FILE")
        if [[ -n "$SESSION_PR" && "$SESSION_PR" != "null" ]]; then
            PR_STATE=$(get_pr_state "$SESSION_PR")
            if [[ "$PR_STATE" == "MERGED" ]]; then
                echo "   🧹 Cleaning up merged integration session (PR #$SESSION_PR)..."
                OLD_BRANCH=$(json_get "branch" "$SESSION_FILE")
                [[ -n "$OLD_BRANCH" ]] && git branch -D "$OLD_BRANCH" 2>/dev/null || true
                rm -f "$SESSION_FILE"
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

for ((i=1; i<=MAX_ITERATIONS; i++)); do
    echo "═══ ITERATION $i/$MAX_ITERATIONS ═══"

    ITER_START=$(date +%s)
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
    [[ -f "$SESSION_FILE" ]] && CONTEXT_FILES="$CONTEXT_FILES
- $SESSION_FILE (INTEGRATION SESSION - use branch as BASE_BRANCH)"

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

        # Run AI CLI and capture output
        OUTPUT=$(run_provider build "$PROMPT_FILE_TMP" "$TIMEOUT_SECONDS" 2>&1) || true

        # Check for CLI errors
        CLI_ERROR=""
        if [[ -z "$OUTPUT" ]]; then
            CLI_ERROR="No output captured"
        elif [[ "$OUTPUT" == *"Error: No messages returned"* ]]; then
            CLI_ERROR="API rate limit or timeout"
        elif [[ "$OUTPUT" == *"Error: API"* ]]; then
            CLI_ERROR="API error"
        elif [[ "$OUTPUT" == *"Error: Network"* ]]; then
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

    cleanup_prompt_file

    # Handle complete failure after all retries exhausted
    if [[ "$CLI_SUCCESS" == "false" ]]; then
        CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
        echo "❌ Failed after $MAX_RETRIES attempts"
        echo "$OUTPUT" > "$LOG_FILE"

        IFS=' ' read -r ERROR_TODO ERROR_IP ERROR_DONE <<< "$(count_tasks "$BACKLOG_FILE")"

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

    SUMMARY=$(echo "$OUTPUT" | sed -n '/=== SUMMARY ===/,/Loop:/p' | head -10)
    [[ -z "$SUMMARY" ]] && SUMMARY="No summary found"

    # Bash-verified task count (don't trust model's count)
    IFS=' ' read -r TODO_COUNT IN_PROGRESS_COUNT DONE_COUNT <<< "$(count_tasks "$BACKLOG_FILE")"
    echo ""
    echo "📊 Pending: $TODO_COUNT"

    # Append count to summary for Telegram
    SUMMARY="$SUMMARY
Pending: $TODO_COUNT"

    log_activity "ITERATION $i END duration=${ITER_DURATION}s pending=$TODO_COUNT"
    send_notification "$i" "$SUMMARY"

    if [[ "$OUTPUT" == *"<promise>COMPLETE</promise>"* ]]; then
        echo ""; echo "✅ ALL TASKS COMPLETED!"
        log_activity "RUN COMPLETE run=$RUN_TAG"
        [[ "$GIT_MODE" == "true" ]] && git checkout "${DEFAULT_BRANCH:-main}" 2>/dev/null || true
        exit 0
    fi

    sleep "${ATLAS_SLEEP_BETWEEN:-2}"
done

[[ "$GIT_MODE" == "true" ]] && git checkout "${DEFAULT_BRANCH:-main}" 2>/dev/null || true
echo ""; echo "🤖 MAX ITERATIONS REACHED"
log_activity "RUN END run=$RUN_TAG (max iterations)"
exit 0
