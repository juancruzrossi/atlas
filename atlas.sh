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

# Atlas version
ATLAS_VERSION="3.1.0"

# AI Provider configuration (claudecode | opencode | codex)
# Priority: --cli flag > ATLAS_CLI env var > default (claudecode)
ATLAS_CLI="${ATLAS_CLI:-claudecode}"

SHOW_HELP=false
SHOW_VERSION=false
REVIEW_DRY_RUN=false
CLEAN_ALL=false
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

ATLAS_DIR=".atlas"
RUNS_DIR="$ATLAS_DIR/runs"
ACTIVITY_LOG="$ATLAS_DIR/activity.log"
ERRORS_LOG="$ATLAS_DIR/errors.log"
PROGRESS_FILE="$ATLAS_DIR/progress.txt"
GUARDRAILS_FILE="$ATLAS_DIR/guardrails.md"
BACKLOG_FILE="$ATLAS_DIR/backlog.md"

# Portable JSON value extractor (handles both string and integer values)
json_get() {
    local key="$1" file="$2"
    [[ ! -f "$file" ]] && return
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

# Invoke the selected AI provider with a prompt
# Usage: run_provider <mode> <prompt>
# Modes: plan, review, build (opencode agent names; ignored by codex/claude)
run_provider() {
    local mode="$1" prompt="$2"
    case "$ATLAS_CLI" in
        opencode)
            export OPENCODE_PERMISSION='{"*":"allow"}'
            opencode run --agent "$mode" "$prompt"
            ;;
        codex)
            codex exec --yolo "$prompt"
            ;;
        *)
            claude --dangerously-skip-permissions "$prompt"
            ;;
    esac
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
elif [[ "${POSITIONAL_ARGS[0]}" == "init" || "${POSITIONAL_ARGS[0]}" == "update" || "${POSITIONAL_ARGS[0]}" == "plan" || "${POSITIONAL_ARGS[0]}" == "resume" || "${POSITIONAL_ARGS[0]}" == "review" || "${POSITIONAL_ARGS[0]}" == "clean" || "${POSITIONAL_ARGS[0]}" == "status" || "${POSITIONAL_ARGS[0]}" == "doctor" || "${POSITIONAL_ARGS[0]}" == "help" ]]; then
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
        PLAN_PROMPT=$(envsubst '$FEATURE_REQUEST $PROJECT_DIR $PROJECT_NAME $SPEC_FILE $BACKLOG_FILE' < "$ATLAS_HOME/plan_prompt.md")

        echo "╔═══════════════════════════════════════════════════════╗"
        echo "║  Atlas Plan - Feature Interview                       ║"
        echo "╠═══════════════════════════════════════════════════════╣"
        echo "║  Feature: $FEATURE_PROMPT"
        echo "║  Output:  $SPEC_FILE"
        echo "╚═══════════════════════════════════════════════════════╝"

        log_activity() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ACTIVITY_LOG"; }
        log_activity "PLAN: $FEATURE_PROMPT -> $SPEC_FILE"

        run_provider plan "$PLAN_PROMPT"

        exit 0
        ;;
    resume)
        [[ ${#COMMAND_ARGS[@]} -gt 1 ]] && { echo "Usage: atlas resume [iterations]"; exit 1; }
        [[ ${#COMMAND_ARGS[@]} -eq 1 && ! "${COMMAND_ARGS[0]}" =~ ^[0-9]+$ ]] && { echo "Error: iterations must be a number"; exit 1; }
        RESUME_ITERATIONS="${COMMAND_ARGS[0]:-$DEFAULT_MAX_ITERATIONS}"

        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }

        SESSION_FILE=".atlas/integration-session.json"
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

        SESSION_FILE="$ATLAS_DIR/integration-session.json"
        [[ ! -f "$SESSION_FILE" ]] && SESSION_FILE=""

        export PROJECT_DIR PROJECT_NAME GIT_MODE
        export BACKLOG_FILE GUARDRAILS_FILE PROGRESS_FILE ERRORS_LOG ACTIVITY_LOG
        export CLAUDE_MD SESSION_FILE

        REVIEW_PROMPT=$(envsubst '$PROJECT_DIR $PROJECT_NAME $GIT_MODE $BACKLOG_FILE $GUARDRAILS_FILE $PROGRESS_FILE $ERRORS_LOG $CLAUDE_MD $ACTIVITY_LOG $SESSION_FILE' < "$ATLAS_HOME/review_prompt.md")

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

        if [[ "$ATLAS_CLI" == "codex" ]]; then
            mkdir -p "$RUNS_DIR"
            REVIEW_RUN_TAG="$(date +%Y%m%d-%H%M%S)-$$"
            REVIEW_LOG_FILE="$RUNS_DIR/review-$REVIEW_RUN_TAG.log"
            REVIEW_LAST_MESSAGE_FILE="$RUNS_DIR/review-$REVIEW_RUN_TAG-last-message.txt"

            if codex exec --yolo -o "$REVIEW_LAST_MESSAGE_FILE" "$REVIEW_PROMPT" > "$REVIEW_LOG_FILE" 2>&1; then
                echo "✅ Codex review completed (non-interactive mode)"
                echo "   Log: $REVIEW_LOG_FILE"
            else
                echo "❌ Codex review failed"
                echo "   Log: $REVIEW_LOG_FILE"
                tail -n 40 "$REVIEW_LOG_FILE" 2>/dev/null || true
                exit 1
            fi
        else
            run_provider review "$REVIEW_PROMPT"
        fi

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
        if [[ -f "$ATLAS_DIR/integration-session.json" ]]; then
            SESSION_STATUS="kept"
            SESSION_PR=$(json_get "pr_number" "$ATLAS_DIR/integration-session.json")
            SESSION_BRANCH=$(json_get "branch" "$ATLAS_DIR/integration-session.json")
            PR_STATE="UNKNOWN"
            if command -v gh >/dev/null 2>&1 && [[ -n "$SESSION_PR" && "$SESSION_PR" != "null" ]]; then
                PR_STATE=$(gh pr view "$SESSION_PR" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
            fi

            if [[ "$CLEAN_ALL" == "true" || "$PR_STATE" == "MERGED" || "$PR_STATE" == "CLOSED" ]]; then
                rm -f "$ATLAS_DIR/integration-session.json"
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
    status)
        [[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }

        # Reuse count_tasks (defined later, but we need it here)
        local_count() {
            local file="$1" in_section="" todo=0 ip=0 done=0
            while IFS= read -r line; do
                if [[ "$line" =~ ^##[[:space:]]+(TODO|IN_PROGRESS|IN\ PROGRESS|DONE|DELAYED) ]]; then
                    in_section="${BASH_REMATCH[1]}"
                    [[ "$in_section" == "IN PROGRESS" ]] && in_section="IN_PROGRESS"
                elif [[ "$line" =~ ^###[[:space:]] ]]; then
                    case "$in_section" in TODO) ((todo++)) ;; IN_PROGRESS) ((ip++)) ;; DONE) ((done++)) ;; esac
                fi
            done < "$file"
            echo "$todo $ip $done"
        }

        read TODO_N IP_N DONE_N <<< $(local_count "$BACKLOG_FILE")

        echo "Atlas Status - $PROJECT_NAME"
        echo ""
        echo "Tasks:  TODO=$TODO_N  IN_PROGRESS=$IP_N  DONE=$DONE_N"

        if [[ -f "$ATLAS_DIR/integration-session.json" ]]; then
            S_NAME=$(json_get "session_name" "$ATLAS_DIR/integration-session.json")
            S_PR=$(json_get "pr_number" "$ATLAS_DIR/integration-session.json")
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

# Validate that the selected AI CLI is installed
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

if [[ -z "${MAX_ITERATIONS:-}" ]]; then
    MAX_ITERATIONS="${ATLAS_MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
fi
STALE_SECONDS="${ATLAS_STALE_SECONDS:-$DEFAULT_STALE_SECONDS}"
TIMEOUT_SECONDS="${ATLAS_TIMEOUT:-$DEFAULT_TIMEOUT}"
[[ -n "${RUN_ITERATIONS_OVERRIDE:-}" ]] && MAX_ITERATIONS="$RUN_ITERATIONS_OVERRIDE"

[[ ! -d "$ATLAS_DIR" ]] && { echo "Error: .atlas/ not found. Run 'atlas init' first."; exit 1; }
[[ ! -f "$BACKLOG_FILE" ]] && { echo "Error: .atlas/backlog.md not found. Run 'atlas init' or create it manually."; exit 1; }
[[ ! -f "$ATLAS_HOME/prompt.md" ]] && { echo "Error: prompt.md not found in $ATLAS_HOME. Run 'npm update -g @jxtools/atlas' to fix."; exit 1; }
mkdir -p "$RUNS_DIR"

log_activity() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ACTIVITY_LOG"; }

# Check for stale tasks in IN_PROGRESS and move back to TODO
reset_stale_tasks() {
    [[ "$STALE_SECONDS" -eq 0 ]] && return

    # Quick check: any ### task under IN_PROGRESS?
    local in_progress_task
    in_progress_task=$(awk '/^## IN.PROGRESS/{f=1;next} /^## /{f=0} f && /^### /{print;exit}' "$BACKLOG_FILE")
    [[ -z "$in_progress_task" ]] && return

    # Check staleness via most recent run log
    local latest_run
    latest_run=$(ls -t "$RUNS_DIR"/*.log 2>/dev/null | head -1)
    [[ -z "$latest_run" ]] && return

    local last_mod now age
    last_mod=$(stat -c %Y "$latest_run" 2>/dev/null || stat -f %m "$latest_run" 2>/dev/null)
    now=$(date +%s)
    age=$((now - last_mod))

    [[ "$age" -le "$STALE_SECONDS" ]] && return

    echo "⚠️  Stale task in IN_PROGRESS (${age}s old, threshold: ${STALE_SECONDS}s)"
    echo "   Resetting to TODO..."

    # Block-based rewrite: collect IN_PROGRESS content and insert before its header
    awk '
        /^## IN.PROGRESS/ { ip_header = $0; in_ip = 1; next }
        in_ip && /^## / {
            printf "%s", ip_content
            print ip_header
            print ""
            in_ip = 0
            print; next
        }
        in_ip { ip_content = ip_content $0 "\n"; next }
        { print }
        END { if (in_ip) { printf "%s", ip_content; print ip_header } }
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
echo "║  AI Provider: $ATLAS_CLI"
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
    if [[ -z "$DEFAULT_BRANCH" ]]; then
        DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || DEFAULT_BRANCH="main"
        [[ -z "$DEFAULT_BRANCH" ]] && DEFAULT_BRANCH="main"
    fi
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
    if [[ -f ".atlas/integration-session.json" ]]; then
        SESSION_PR=$(json_get "pr_number" .atlas/integration-session.json)
        if [[ -n "$SESSION_PR" && "$SESSION_PR" != "null" ]]; then
            PR_STATE=$(gh pr view "$SESSION_PR" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
            if [[ "$PR_STATE" == "MERGED" ]]; then
                echo "   🧹 Cleaning up merged integration session (PR #$SESSION_PR)..."
                OLD_BRANCH=$(json_get "branch" .atlas/integration-session.json)
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

        # Run AI CLI and capture output
        if [[ "$ATLAS_CLI" == "opencode" ]]; then
            export OPENCODE_PERMISSION='{"*":"allow"}'
            OUTPUT=$(run_with_timeout "$TIMEOUT_SECONDS" opencode run --agent build "$(cat "$PROMPT_FILE_TMP")" 2>&1) || true
        elif [[ "$ATLAS_CLI" == "codex" ]]; then
            OUTPUT=$(run_with_timeout "$TIMEOUT_SECONDS" codex exec --yolo "$(cat "$PROMPT_FILE_TMP")" 2>&1) || true
        else
            OUTPUT=$(run_with_timeout "$TIMEOUT_SECONDS" claude --dangerously-skip-permissions -p < "$PROMPT_FILE_TMP" 2>&1) || true
        fi

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
