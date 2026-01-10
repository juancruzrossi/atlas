#!/bin/bash
#
#  █████╗ ████████╗██╗      █████╗ ███████╗
# ██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝
# ███████║   ██║   ██║     ███████║███████╗
# ██╔══██║   ██║   ██║     ██╔══██║╚════██║
# ██║  ██║   ██║   ███████╗██║  ██║███████║
# ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝
#
# Autonomous Task Loop Agent System
#

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_NAME="atlas"
VERSION="1.0.1"

# Detect ATLAS_HOME (where atlas is installed globally)
if [[ -f "$HOME/.atlas-home" ]]; then
    ATLAS_HOME="$(cat "$HOME/.atlas-home")"
else
    # Fallback: script directory (for development or non-installed usage)
    ATLAS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Project directory (where user runs atlas from)
PROJECT_DIR="$(pwd)"

# File paths - Global (from installation)
RULES_FILE="$ATLAS_HOME/atlas-rules.txt"
TEMPLATES_DIR="$ATLAS_HOME/templates"

# File paths - Project specific (in .atlas/ of current project)
ATLAS_PROJECT_DIR="$PROJECT_DIR/.atlas"
PROJECT_CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"  # Optional: project's own CLAUDE.md
BACKLOG_FILE="$ATLAS_PROJECT_DIR/backlog.md"
PROGRESS_FILE="$ATLAS_PROJECT_DIR/progress.txt"
LOG_DIR="$ATLAS_PROJECT_DIR/logs"
STATE_FILE="$ATLAS_PROJECT_DIR/.atlas-state.json"

# Timeouts (in seconds)
CLAUDE_TIMEOUT=1800  # 30 minutes per Claude execution

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# TUI: Clear screen and move cursor to top
clear_screen() {
    printf '\033[2J\033[H'
}

# Reset terminal settings (disable focus reporting, show cursor, reset modes)
reset_terminal() {
    # Disable focus reporting (prevents ^[[O^[[I garbage)
    printf '\033[?1004l'
    # Show cursor (in case it was hidden)
    printf '\033[?25h'
    # Reset character attributes
    printf '\033[0m'
}

# ═══════════════════════════════════════════════════════════════════════════════
# SIGNAL HANDLING & CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

cleanup() {
    local exit_code=$?

    # Reset terminal first (disable focus reporting, show cursor)
    reset_terminal

    echo ""
    log WARN "🛑 Atlas interrupted"
    log INFO "Cleaning up..."

    # Kill any Claude process we might have started
    if [[ -n "$CLAUDE_PID" ]] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
        kill "$CLAUDE_PID" 2>/dev/null || true
    fi

    # Save state for resume
    if [[ -n "$TASKS" ]] && [[ -n "$current_task" ]]; then
        save_state
        log INFO "State saved. Resume with: $SCRIPT_NAME --resume"
    fi

    log INFO "Goodbye!"
    exit $exit_code
}

trap cleanup SIGINT SIGTERM

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)    echo -e "${BLUE}[$timestamp]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$timestamp]${NC} ✅ $message" ;;
        WARN)    echo -e "${YELLOW}[$timestamp]${NC} ⚠️  $message" ;;
        ERROR)   echo -e "${RED}[$timestamp]${NC} ❌ $message" ;;
        FEATURE) echo -e "${PURPLE}[$timestamp]${NC} 📦 $message" ;;
        ITER)    echo -e "${CYAN}[$timestamp]${NC} 🔄 $message" ;;
        DEBUG)   [[ "$VERBOSE" == "true" ]] && echo -e "${GRAY}[$timestamp]${NC} $message" ;;
    esac

    # Also log to file
    mkdir -p "$LOG_DIR"
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/atlas.log"
}

# Get the timeout command (macOS doesn't have timeout by default)
get_timeout_cmd() {
    if command -v timeout &> /dev/null; then
        echo "timeout"
    elif command -v gtimeout &> /dev/null; then
        echo "gtimeout"
    else
        echo ""
    fi
}

TIMEOUT_CMD=$(get_timeout_cmd)

# Run Claude with retry logic for lock acquisition errors
# This handles the case where multiple Claude Code sessions compete for the version lock
run_claude_with_retry() {
    local log_file="$1"
    shift  # Remove log_file from arguments, rest are claude args

    local max_retries=3
    local retry_delay=2
    local attempt=1

    while [[ $attempt -le $max_retries ]]; do
        # Execute Claude
        if [[ -n "$TIMEOUT_CMD" ]]; then
            $TIMEOUT_CMD "${CLAUDE_TIMEOUT}s" claude "$@" > "$log_file" 2>&1 || true
        else
            claude "$@" > "$log_file" 2>&1 || true
        fi

        # Check if it's a lock error
        if grep -q "Lock acquisition failed" "$log_file" 2>/dev/null; then
            if [[ $attempt -lt $max_retries ]]; then
                echo -e "    ${YELLOW}↻ Lock conflict detected, retrying in ${retry_delay}s... (attempt $((attempt+1))/$max_retries)${NC}"
                sleep $retry_delay
                retry_delay=$((retry_delay * 2))  # Exponential backoff: 2s, 4s, 8s
                attempt=$((attempt + 1))
                continue
            else
                echo -e "    ${RED}⚠ Lock conflict persists after $max_retries attempts${NC}"
            fi
        fi

        # Success or non-lock error, exit loop
        break
    done
}

# Check if backlog only has template/placeholder tasks (tasks with [...] in title)
is_template_only_backlog() {
    if [[ ! -f "$BACKLOG_FILE" ]]; then
        return 1
    fi

    # Get all task titles from TODO section
    local all_tasks=$(sed -n '/^## TODO$/,/^## IN PROGRESS$/p' "$BACKLOG_FILE" 2>/dev/null | grep '^### ' 2>/dev/null)

    # If no tasks, not a template-only backlog
    if [[ -z "$all_tasks" ]]; then
        return 1
    fi

    # Check if ALL tasks have [...] placeholder pattern in title
    local real_tasks=$(echo "$all_tasks" | grep -v '\[.*\]' 2>/dev/null)

    # If there are no real tasks (all have placeholders), return true
    [[ -z "$real_tasks" ]]
}

# Count tasks in TODO section (between ## TODO and ## IN PROGRESS)
# Excludes template/placeholder tasks (those with [...] in title)
get_pending_count() {
    if [[ -f "$BACKLOG_FILE" ]]; then
        # Count tasks that DON'T have [...] placeholder in title
        local count=$(sed -n '/^## TODO$/,/^## IN PROGRESS$/p' "$BACKLOG_FILE" 2>/dev/null | grep '^### ' | grep -cv '\[.*\]' 2>/dev/null)
        echo "${count:-0}"
    else
        echo "0"
    fi
}

# Count tasks in IN PROGRESS section (between ## IN PROGRESS and ## DONE)
get_in_progress_count() {
    if [[ -f "$BACKLOG_FILE" ]]; then
        local count=$(sed -n '/^## IN PROGRESS$/,/^## DONE$/p' "$BACKLOG_FILE" 2>/dev/null | grep -c '^### ' 2>/dev/null)
        echo "${count:-0}"
    else
        echo "0"
    fi
}

# Count tasks in DONE section (between ## DONE and ## DELAYED)
get_completed_count() {
    if [[ -f "$BACKLOG_FILE" ]]; then
        local count=$(sed -n '/^## DONE$/,/^## DELAYED$/p' "$BACKLOG_FILE" 2>/dev/null | grep -c '^### ' 2>/dev/null)
        echo "${count:-0}"
    else
        echo "0"
    fi
}

# Count tasks in DELAYED section (after ## DELAYED)
get_delayed_count() {
    if [[ -f "$BACKLOG_FILE" ]]; then
        local count=$(sed -n '/^## DELAYED$/,$p' "$BACKLOG_FILE" 2>/dev/null | grep -c '^### ' 2>/dev/null)
        echo "${count:-0}"
    else
        echo "0"
    fi
}

# Count all real tasks (excludes template/placeholder tasks)
get_total_count() {
    if [[ -f "$BACKLOG_FILE" ]]; then
        # Count tasks that DON'T have [...] placeholder in title
        local count=$(grep '^### ' "$BACKLOG_FILE" 2>/dev/null | grep -cv '\[.*\]' 2>/dev/null)
        echo "${count:-0}"
    else
        echo "0"
    fi
}

save_state() {
    cat > "$STATE_FILE" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "current_task": $current_task,
    "total_tasks": $TASKS,
    "iterations": $ITERATIONS,
    "completed_tasks": $successful_tasks,
    "total_iterations_done": $total_iterations
}
EOF
}

load_state() {
    if [[ -f "$STATE_FILE" ]] && command -v jq &> /dev/null; then
        current_task=$(jq -r '.current_task' "$STATE_FILE")
        TASKS=$(jq -r '.total_tasks' "$STATE_FILE")
        ITERATIONS=$(jq -r '.iterations' "$STATE_FILE")
        successful_tasks=$(jq -r '.completed_tasks' "$STATE_FILE")
        total_iterations=$(jq -r '.total_iterations_done' "$STATE_FILE")
        return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# WELCOME & HELP SCREENS
# ═══════════════════════════════════════════════════════════════════════════════

show_banner() {
    echo ""
    echo -e "   ${BOLD}${WHITE} █████╗ ████████╗██╗      █████╗ ███████╗${NC}"
    echo -e "   ${BOLD}${WHITE}██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝${NC}"
    echo -e "   ${BOLD}${WHITE}███████║   ██║   ██║     ███████║███████╗${NC}"
    echo -e "   ${BOLD}${WHITE}██╔══██║   ██║   ██║     ██╔══██║╚════██║${NC}"
    echo -e "   ${BOLD}${WHITE}██║  ██║   ██║   ███████╗██║  ██║███████║${NC}"
    echo -e "   ${BOLD}${WHITE}╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝${NC}"
    echo -e "    ${DIM}Autonomous Task Loop Agent System${NC}"
    echo ""
}

show_welcome() {
    clear_screen
    show_banner

    echo -e "${BOLD}${WHITE}Welcome to Atlas!${NC}"
    echo ""
    echo -e "Atlas is an autonomous development agent that implements tasks from your"
    echo -e "Backlog one by one, using Claude Code."
    echo ""

    # Check if Atlas is initialized in this project
    if [[ ! -d "$ATLAS_PROJECT_DIR" ]]; then
        echo -e "${YELLOW}⚠ Atlas is not initialized in this project${NC}"
        echo ""
        echo -e "${BOLD}To get started:${NC}"
        echo -e "   ${CYAN}$SCRIPT_NAME init${NC}    Initialize Atlas in this directory"
        echo ""
        echo -e "${DIM}This will create a .atlas/ directory with:${NC}"
        echo -e "   ${DIM}- backlog.md (your task backlog)${NC}"
        echo -e "   ${DIM}- progress.txt (development log)${NC}"
        echo ""
        return
    fi

    # Show current Backlog status
    if [[ -f "$BACKLOG_FILE" ]]; then
        local total=$(get_total_count)
        local pending=$(get_pending_count)
        local in_progress=$(get_in_progress_count)
        local completed=$(get_completed_count)
        local delayed=$(get_delayed_count)

        # Check if backlog only has template placeholders
        if is_template_only_backlog && [[ $completed -eq 0 ]] && [[ $in_progress -eq 0 ]]; then
            echo -e "${YELLOW}📝 Backlog contains only template placeholders${NC}"
            echo -e "   Edit ${CYAN}.atlas/backlog.md${NC} to add your tasks"
            echo -e "   Or run ${CYAN}$SCRIPT_NAME create-backlog${NC} to auto-generate from code"
            echo ""
            echo -e "${DIM}For more information, run: $SCRIPT_NAME --help${NC}"
            echo ""
            return
        elif [[ $total -gt 0 ]] || [[ $completed -gt 0 ]]; then
            echo -e "${BOLD}📊 Current Backlog Status:${NC}"
            echo -e "   ${GREEN}●${NC} Done:        $completed"
            echo -e "   ${YELLOW}●${NC} In Progress: $in_progress"
            echo -e "   ${BLUE}●${NC} Todo:        $pending"
            echo -e "   ${GRAY}●${NC} Delayed:     $delayed"
            echo -e "   ${WHITE}●${NC} Total:       $total"
            echo ""
        fi
    fi

    # Check for resumable state
    if [[ -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}💾 Resumable session found!${NC}"
        echo -e "   Run ${CYAN}$SCRIPT_NAME --resume${NC} to continue where you left off."
        echo ""
    fi

    echo -e "${BOLD}🚀 Quick Start:${NC}"
    echo ""
    echo -e "   ${DIM}# Backlog mode (auto-select from TODO):${NC}"
    echo -e "   ${CYAN}$SCRIPT_NAME 5${NC}                   Process 5 tasks"
    echo -e "   ${CYAN}$SCRIPT_NAME 5 3${NC}                 Process 5 tasks, 3 iterations each"
    echo ""
    echo -e "   ${DIM}# Prompt mode (tell Claude what to work on):${NC}"
    echo -e "   ${CYAN}$SCRIPT_NAME \"HIGH-004\" 1${NC}         Work on HIGH-004"
    echo -e "   ${CYAN}$SCRIPT_NAME \"all bugs\" 5${NC}         Up to 5 bug tasks"
    echo -e "   ${CYAN}$SCRIPT_NAME \"performance\" 3 2${NC}    Up to 3 tasks, 2 iterations per task"
    echo ""
    echo -e "${BOLD}📖 More Options:${NC}"
    echo ""
    echo -e "   ${CYAN}$SCRIPT_NAME --help${NC}              Show detailed help"
    echo -e "   ${CYAN}$SCRIPT_NAME --status${NC}            Show Backlog status"
    echo -e "   ${CYAN}$SCRIPT_NAME --dry-run 3${NC}         Preview mode"
    echo ""
    echo -e "${DIM}For more information, run: $SCRIPT_NAME --help${NC}"
    echo ""
}

show_help() {
    show_banner

    echo -e "${BOLD}${WHITE}DESCRIPTION${NC}"
    echo -e "    Atlas is an autonomous development agent that uses Claude Code to implement"
    echo -e "    tasks from your Backlog (backlog.md) one by one."
    echo ""
    echo -e "${BOLD}${WHITE}USAGE${NC}"
    echo ""
    echo -e "    ${DIM}# Backlog mode - auto-select from TODO section:${NC}"
    echo -e "    ${CYAN}./$SCRIPT_NAME${NC} ${GREEN}<count>${NC} ${DIM}[iterations_per_task]${NC}"
    echo ""
    echo -e "    ${DIM}# Prompt mode - tell Claude what to work on:${NC}"
    echo -e "    ${CYAN}./$SCRIPT_NAME${NC} ${GREEN}\"<request>\"${NC} ${GREEN}<max_tasks>${NC} ${DIM}[iterations_per_task]${NC}"
    echo ""
    echo -e "${BOLD}${WHITE}ARGUMENTS${NC}"
    echo -e "    ${GREEN}count${NC}           Number of tasks to process (backlog mode)"
    echo -e "    ${GREEN}request${NC}         What to work on - Claude interprets this (prompt mode)"
    echo -e "    ${GREEN}max_tasks${NC}       Maximum tasks to process (prompt mode)"
    echo -e "    ${GREEN}iterations_per_task${NC}  Max attempts per task ${DIM}(default: 1)${NC}"
    echo ""
    echo -e "${BOLD}${WHITE}COMMANDS${NC}"
    echo -e "    ${GREEN}init${NC}                  Initialize Atlas in current project"
    echo -e "    ${GREEN}create-backlog${NC}        Analyze project and auto-generate backlog"
    echo -e "    ${GREEN}update${NC}                Update Atlas to the latest version"
    echo ""
    echo -e "${BOLD}${WHITE}OPTIONS${NC}"
    echo -e "    ${GREEN}-h, --help${NC}            Show this help message"
    echo -e "    ${GREEN}--status${NC}              Show current Backlog status"
    echo -e "    ${GREEN}--dry-run${NC}             Preview what would happen"
    echo -e "    ${GREEN}--resume${NC}              Resume from last interrupted session"
    echo -e "    ${GREEN}--timeout <seconds>${NC}   Claude timeout ${DIM}(default: 1800)${NC}"
    echo -e "    ${GREEN}-v, --verbose${NC}         Show detailed output"
    echo ""
    echo -e "${BOLD}${WHITE}PROMPT MODE${NC}"
    echo ""
    echo -e "    In prompt mode, Claude interprets your request and finds matching tasks."
    echo -e "    You can use natural language - Claude understands context from backlog.md."
    echo ""
    echo -e "    ${DIM}Examples of what you can say:${NC}"
    echo -e "    ${CYAN}\"HIGH-004\"${NC}                    A specific task code"
    echo -e "    ${CYAN}\"all the bugs\"${NC}                Tasks with category: bug"
    echo -e "    ${CYAN}\"HIGH priority\"${NC}               All HIGH-XXX tasks"
    echo -e "    ${CYAN}\"performance issues\"${NC}          Tasks related to performance"
    echo -e "    ${CYAN}\"fix authentication\"${NC}          Claude finds relevant tasks"
    echo ""
    echo -e "${BOLD}${WHITE}EXAMPLES${NC}"
    echo ""
    echo -e "    ${DIM}# Backlog mode:${NC}"
    echo -e "    ${CYAN}./$SCRIPT_NAME 5${NC}                      Process 5 tasks"
    echo -e "    ${CYAN}./$SCRIPT_NAME 3 2${NC}                    3 tasks, 2 iterations each"
    echo ""
    echo -e "    ${DIM}# Prompt mode:${NC}"
    echo -e "    ${CYAN}./$SCRIPT_NAME \"HIGH-004\" 1${NC}           Work on HIGH-004"
    echo -e "    ${CYAN}./$SCRIPT_NAME \"all bugs\" 5${NC}           Up to 5 bug tasks"
    echo -e "    ${CYAN}./$SCRIPT_NAME \"performance\" 3 2${NC}      Up to 3 tasks, 2 iterations per task"
    echo ""
    echo -e "    ${DIM}# Dry run:${NC}"
    echo -e "    ${CYAN}./$SCRIPT_NAME --dry-run 5${NC}             Preview backlog mode"
    echo -e "    ${CYAN}./$SCRIPT_NAME --dry-run \"bugs\" 5${NC}      Preview prompt mode"
    echo ""
    echo -e "${BOLD}${WHITE}HOW IT WORKS${NC}"
    echo -e "    For each task, Atlas runs two phases:"
    echo ""
    echo -e "    ${CYAN}1. IMPLEMENT PHASE${NC} ${DIM}(inner loop)${NC}"
    echo -e "       ${BLUE}•${NC} Selects highest priority pending task"
    echo -e "       ${BLUE}•${NC} Creates feature branch"
    echo -e "       ${BLUE}•${NC} Implements the task"
    echo -e "       ${BLUE}•${NC} Runs quality checks (typecheck, visual verification)"
    echo -e "       ${BLUE}•${NC} Creates PR (but does NOT merge)"
    echo -e "       ${BLUE}•${NC} Exits when ready OR continues if not (up to max iterations per task)"
    echo ""
    echo -e "    ${GREEN}2. FINALIZE PHASE${NC}"
    echo -e "       ${BLUE}•${NC} Merges the PR (squash & merge)"
    echo -e "       ${BLUE}•${NC} Moves task to DONE section in backlog.md"
    echo -e "       ${BLUE}•${NC} Updates progress.txt"
    echo -e "       ${BLUE}•${NC} Cleans up (deletes branch, kills processes)"
    echo ""
    echo -e "    ${YELLOW}Note:${NC} Claude exits the loop when genuinely ready. If a simple"
    echo -e "    task completes in 1 iteration, it won't waste more."
    echo ""
    echo -e "${BOLD}${WHITE}FILES${NC} ${DIM}(in .atlas/)${NC}"
    echo -e "    ${YELLOW}backlog.md${NC}          Task backlog with TODO/IN PROGRESS/DONE sections"
    echo -e "    ${YELLOW}progress.txt${NC}        Development progress log"
    echo -e "    ${YELLOW}logs/${NC}               Execution logs for each iteration"
    echo ""
    echo -e "${BOLD}${WHITE}PROJECT CONTEXT${NC}"
    echo -e "    Atlas reads ${YELLOW}CLAUDE.md${NC} from your project root (if it exists)"
    echo -e "    for project-specific configuration and conventions."
    echo ""
    echo -e "${BOLD}${WHITE}SIGNALS${NC}"
    echo -e "    ${RED}Ctrl+C${NC}             Graceful shutdown, saves state for resume"
    echo ""
    echo -e "${BOLD}${WHITE}EXIT CODES${NC}"
    echo -e "    ${GREEN}0${NC}                  Success (all tasks completed)"
    echo -e "    ${RED}1${NC}                  Error (invalid arguments, missing files, etc.)"
    echo -e "    ${YELLOW}130${NC}                Interrupted by user (Ctrl+C)"
    echo ""
}

show_status() {
    clear_screen
    show_banner

    if [[ ! -f "$BACKLOG_FILE" ]]; then
        echo -e "${RED}Error: Backlog file not found: $BACKLOG_FILE${NC}"
        exit 1
    fi

    local total=$(get_total_count)
    local pending=$(get_pending_count)
    local in_progress=$(get_in_progress_count)
    local completed=$(get_completed_count)
    local delayed=$(get_delayed_count)

    # Check if backlog only has template placeholders
    if is_template_only_backlog && [[ $completed -eq 0 ]] && [[ $in_progress -eq 0 ]]; then
        echo -e "${YELLOW}📝 Backlog contains only template placeholders${NC}"
        echo ""
        echo -e "   Edit ${CYAN}.atlas/backlog.md${NC} to add your tasks"
        echo -e "   Or run ${CYAN}$SCRIPT_NAME create-backlog${NC} to auto-generate tasks"
        echo ""
        exit 0
    fi

    echo -e "${BOLD}📊 Backlog Status${NC}"
    echo ""

    # Progress bar (based on done vs todo+in_progress, excludes delayed)
    local actionable=$((pending + in_progress + completed))
    local percent=0
    if [[ $actionable -gt 0 ]]; then
        percent=$((completed * 100 / actionable))
    fi
    local bar_width=40
    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))

    printf "   ["
    printf "${GREEN}%${filled}s${NC}" | tr ' ' '█'
    printf "${GRAY}%${empty}s${NC}" | tr ' ' '░'
    printf "] %d%%\n" $percent
    echo ""

    echo -e "   ${GREEN}✅ Done:${NC}        $completed"
    echo -e "   ${YELLOW}🔄 In Progress:${NC} $in_progress"
    echo -e "   ${BLUE}📋 Todo:${NC}        $pending"
    echo -e "   ${GRAY}⏸️  Delayed:${NC}     $delayed"
    echo -e "   ${WHITE}📊 Total:${NC}       $total"
    echo ""

    # Show next TODO tasks (first 5 ### headers in TODO section, excluding templates)
    if [[ $pending -gt 0 ]]; then
        echo -e "${BOLD}📋 Next TODO Tasks:${NC}"
        echo ""
        sed -n '/^## TODO$/,/^## IN PROGRESS$/p' "$BACKLOG_FILE" 2>/dev/null | grep '^### ' | grep -v '\[.*\]' | head -5 | sed 's/^### /   /'
        echo ""
    fi

    # Show IN PROGRESS tasks
    if [[ $in_progress -gt 0 ]]; then
        echo -e "${BOLD}🔄 Currently In Progress:${NC}"
        echo ""
        sed -n '/^## IN PROGRESS$/,/^## DONE$/p' "$BACKLOG_FILE" 2>/dev/null | grep '^### ' | sed 's/^### /   /'
        echo ""
    fi

    # Resume hint
    if [[ -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}💾 Resumable session available.${NC} Run: ${CYAN}./$SCRIPT_NAME --resume${NC}"
        echo ""
    fi
}

show_dry_run() {
    local count=$1
    clear_screen
    show_banner

    echo -e "${BOLD}${WHITE}🔍 DRY RUN - Preview Mode${NC}"
    echo -e "${DIM}No changes will be made. This shows what WOULD happen.${NC}"
    echo ""

    if [[ ! -f "$BACKLOG_FILE" ]]; then
        echo -e "${RED}Error: Backlog file not found: $BACKLOG_FILE${NC}"
        exit 1
    fi

    # Check if backlog only has template placeholders
    if is_template_only_backlog; then
        echo -e "${YELLOW}📝 Backlog contains only template placeholders${NC}"
        echo ""
        echo -e "   Edit ${CYAN}.atlas/backlog.md${NC} to add your tasks"
        echo -e "   Or run ${CYAN}$SCRIPT_NAME create-backlog${NC} to auto-generate tasks"
        echo ""
        exit 0
    fi

    echo -e "${BOLD}Would process ${GREEN}$count${NC}${BOLD} task(s) with ${GREEN}$ITERATIONS${NC}${BOLD} iteration(s) each:${NC}"
    echo ""

    # Show TODO tasks (first $count, excluding templates)
    local todo_tasks=$(sed -n '/^## TODO$/,/^## IN PROGRESS$/p' "$BACKLOG_FILE" 2>/dev/null | grep '^### ' | grep -v '\[.*\]' | head -$count | sed 's/^### /   /')
    # Show IN PROGRESS tasks
    local in_progress_tasks=$(sed -n '/^## IN PROGRESS$/,/^## DONE$/p' "$BACKLOG_FILE" 2>/dev/null | grep '^### ' | sed 's/^### /   [IN PROGRESS] /')

    if [[ -n "$in_progress_tasks" ]]; then
        echo "$in_progress_tasks"
    fi
    if [[ -n "$todo_tasks" ]]; then
        echo "$todo_tasks"
    fi
    if [[ -z "$todo_tasks" ]] && [[ -z "$in_progress_tasks" ]]; then
        echo -e "   ${YELLOW}No TODO tasks found${NC}"
    fi

    echo ""
    echo -e "${BOLD}${WHITE}Execution flow per task:${NC}"
    echo ""
    for ((i=1; i<=$ITERATIONS; i++)); do
        echo -e "   ${CYAN}Iteration $i:${NC} implement → test → PR"
    done
    echo -e "   ${GREEN}Finalize:${NC} merge → move to DONE → cleanup"
    echo ""
    echo -e "${DIM}To execute for real, run: ${CYAN}./$SCRIPT_NAME $count${NC}"
    echo ""
}

# Dry run for prompt mode (Claude interprets the request)
show_dry_run_prompt() {
    clear_screen
    show_banner

    echo -e "${BOLD}${WHITE}🔍 DRY RUN - Prompt Mode Preview${NC}"
    echo -e "${DIM}No changes will be made. This shows what WOULD happen.${NC}"
    echo ""

    if [[ ! -f "$BACKLOG_FILE" ]]; then
        echo -e "${RED}Error: Backlog file not found: $BACKLOG_FILE${NC}"
        exit 1
    fi

    echo -e "${BOLD}Request:${NC} ${CYAN}\"$CUSTOM_PROMPT\"${NC}"
    echo -e "${BOLD}Max tasks:${NC} ${GREEN}$TASKS${NC}"
    echo -e "${BOLD}Iterations per task:${NC} ${GREEN}$ITERATIONS${NC}"
    echo ""

    echo -e "${BOLD}${WHITE}How it works:${NC}"
    echo -e "   Claude will interpret your request and select matching tasks from backlog.md"
    echo -e "   Examples of what Claude can understand:"
    echo -e "   ${DIM}• \"HIGH-004\" → specific task${NC}"
    echo -e "   ${DIM}• \"all HIGH priority\" → all HIGH-XXX tasks${NC}"
    echo -e "   ${DIM}• \"the bugs\" → tasks with category: bug${NC}"
    echo -e "   ${DIM}• \"performance issues\" → tasks related to performance${NC}"
    echo -e "   ${DIM}• \"fix the auth problems\" → Claude finds relevant tasks${NC}"
    echo ""

    echo -e "${BOLD}${WHITE}Execution flow:${NC}"
    echo ""
    echo -e "   For up to ${GREEN}$TASKS${NC} matching task(s):"
    for ((i=1; i<=$ITERATIONS; i++)); do
        echo -e "      ${CYAN}Iteration $i:${NC} implement → test → PR"
    done
    echo -e "      ${GREEN}Finalize:${NC} merge → move to DONE → cleanup"
    echo ""
    echo -e "   Claude stops when:"
    echo -e "   ${DIM}• All matching tasks are done, OR${NC}"
    echo -e "   ${DIM}• Max tasks ($TASKS) reached${NC}"
    echo ""
    echo -e "${DIM}To execute for real, run: ${CYAN}./$SCRIPT_NAME \"$CUSTOM_PROMPT\" $TASKS $ITERATIONS${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════════════════════

TASKS=""
ITERATIONS=1
VERBOSE=false
DRY_RUN=false
RESUME=false
current_task=1
successful_tasks=0
total_iterations=0
selector_done=false

# Variables for prompt mode
MODE="backlog"          # backlog | prompt
CUSTOM_PROMPT=""        # The user's request (Claude interprets it)

# ═══════════════════════════════════════════════════════════════════════════════
# INIT COMMAND
# ═══════════════════════════════════════════════════════════════════════════════

do_init() {
    clear_screen
    echo ""
    echo -e "${BOLD}Initializing Atlas in: ${CYAN}$PROJECT_DIR${NC}"
    echo ""

    # Check if already initialized
    if [[ -d "$ATLAS_PROJECT_DIR" ]]; then
        echo -e "${YELLOW}Warning: .atlas/ already exists in this directory${NC}"
        echo ""
        read -p "Overwrite existing files? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}Aborted.${NC}"
            exit 1
        fi
    fi

    # Check templates exist
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        echo -e "${RED}Error: Templates directory not found: $TEMPLATES_DIR${NC}"
        echo -e "Please reinstall Atlas."
        exit 1
    fi

    # Create .atlas directory
    mkdir -p "$ATLAS_PROJECT_DIR"
    mkdir -p "$LOG_DIR"

    # Copy templates
    cp "$TEMPLATES_DIR/backlog.md" "$BACKLOG_FILE"
    cp "$TEMPLATES_DIR/progress.txt" "$PROGRESS_FILE"

    # Try to detect project name from directory or package.json
    PROJECT_NAME=$(basename "$PROJECT_DIR")
    if [[ -f "$PROJECT_DIR/package.json" ]]; then
        DETECTED_NAME=$(grep -m1 '"name"' "$PROJECT_DIR/package.json" 2>/dev/null | sed 's/.*"name".*"\(.*\)".*/\1/' | head -1)
        if [[ -n "$DETECTED_NAME" ]]; then
            PROJECT_NAME="$DETECTED_NAME"
        fi
    fi

    # Replace placeholders in templates
    sed -i '' "s/\[PROJECT_NAME\]/$PROJECT_NAME/g" "$BACKLOG_FILE" 2>/dev/null || \
        sed -i "s/\[PROJECT_NAME\]/$PROJECT_NAME/g" "$BACKLOG_FILE"

    echo -e "${GREEN}✓${NC} Created .atlas/ directory"
    echo -e "${GREEN}✓${NC} Created backlog.md"
    echo -e "${GREEN}✓${NC} Created progress.txt"
    echo -e "${GREEN}✓${NC} Created logs/"
    echo ""
    echo -e "${BOLD}${GREEN}Atlas initialized successfully!${NC}"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo -e "   1. Add tasks to ${YELLOW}.atlas/backlog.md${NC}"
    echo -e "   2. Run ${CYAN}atlas 1${NC} to process your first task"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# CREATE-BACKLOG COMMAND
# ═══════════════════════════════════════════════════════════════════════════════

show_backlog_summary() {
    local high=$(grep -c '^### HIGH-' "$BACKLOG_FILE" 2>/dev/null || echo "0")
    local medium=$(grep -c '^### MEDIUM-' "$BACKLOG_FILE" 2>/dev/null || echo "0")
    local low=$(grep -c '^### LOW-' "$BACKLOG_FILE" 2>/dev/null || echo "0")
    local total=$((high + medium + low))

    echo ""
    echo -e "${GREEN}${BOLD}✅ Backlog created successfully!${NC}"
    echo ""
    echo -e "${BOLD}📊 Summary${NC}"
    echo ""
    echo -e "   ${RED}🔴 HIGH priority:${NC}   $high tasks"
    echo -e "   ${YELLOW}🟡 MEDIUM priority:${NC} $medium tasks"
    echo -e "   ${BLUE}🔵 LOW priority:${NC}    $low tasks"
    echo -e "   ─────────────────────────"
    echo -e "   ${WHITE}📋 Total:${NC}           $total tasks"
    echo ""
    echo -e "${BOLD}🚀 Next steps${NC}"
    echo ""
    echo -e "   1. Review ${YELLOW}.atlas/backlog.md${NC}"
    echo -e "   2. Adjust priorities if needed"
    echo -e "   3. Run ${CYAN}atlas 1${NC} to start processing"
    echo ""
}

do_create_backlog() {
    echo ""

    # Check if atlas is initialized
    if [[ ! -d "$ATLAS_PROJECT_DIR" ]]; then
        echo -e "${RED}Error: Atlas not initialized in this project${NC}"
        echo -e "Run ${CYAN}atlas init${NC} first."
        exit 1
    fi

    # Check if backlog.md exists
    if [[ -f "$BACKLOG_FILE" ]]; then
        read -p "Overwrite existing backlog? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}Aborted.${NC}"
            exit 1
        fi
        echo ""
    fi

    # Detect project name
    PROJECT_NAME=$(basename "$PROJECT_DIR")
    if [[ -f "$PROJECT_DIR/package.json" ]]; then
        DETECTED_NAME=$(grep -m1 '"name"' "$PROJECT_DIR/package.json" 2>/dev/null | sed 's/.*"name".*"\(.*\)".*/\1/' | head -1)
        [[ -n "$DETECTED_NAME" ]] && PROJECT_NAME="$DETECTED_NAME"
    fi

    # Build prompt for Claude
    CREATE_BACKLOG_PROMPT="Analyze this project and create a comprehensive backlog.

PROJECT: $PROJECT_NAME
DIRECTORY: $PROJECT_DIR
OUTPUT FILE: $BACKLOG_FILE

PERFORMANCE OPTIMIZATION:
Use the Task tool with multiple Explore agents IN PARALLEL to speed up analysis:
- Agent 1: Scan for bugs, errors, and broken code
- Agent 2: Analyze performance issues and technical debt
- Agent 3: Review tasks, UX, and functional improvements

ANALYSIS CHECKLIST:

1. BUGS (Category: bug) - HIGH priority
   - Console errors, broken imports, missing dependencies
   - Type errors, unsafe casts, incorrect logic
   - Race conditions, memory leaks, unhandled exceptions
   - Security vulnerabilities (exposed secrets, XSS, injection)

2. PERFORMANCE (Category: performance) - MEDIUM priority
   - N+1 queries, excessive API calls
   - Unnecessary re-renders, missing memoization
   - Large bundle sizes, missing lazy loading
   - Unoptimized images, blocking operations

3. TECHNICAL DEBT (Category: technical-debt) - MEDIUM/LOW priority
   - TODO/FIXME comments in code
   - Hardcoded values, magic numbers
   - Duplicated code, inconsistent patterns
   - Outdated dependencies, missing error handling
   - Missing documentation

4. FUNCTIONAL (Category: functional) - varies
   - Incomplete implementations, missing validations
   - UX improvements, accessibility issues
   - Mobile responsiveness gaps

PRIORITY RULES:
- HIGH-XXX: Security issues, crashes, blocking bugs, data loss risks
- MEDIUM-XXX: Performance problems, significant tech debt, important tasks
- LOW-XXX: Minor improvements, cosmetic fixes, nice-to-haves

OUTPUT FORMAT (write to $BACKLOG_FILE):

# $PROJECT_NAME Backlog

## TODO

### HIGH-001: [Specific Title]
- **Category:** [bug|performance|technical-debt|functional]
- **Description:** [Clear, actionable description. Reference files/lines if possible]
- **Steps:**
  1. [Concrete step]
  2. [Concrete step]

### HIGH-002: ...
### MEDIUM-001: ...
### LOW-001: ...

## IN PROGRESS

## DONE

## DELAYED

RULES:
1. Be SPECIFIC - reference actual files and line numbers
2. Be ACTIONABLE - each task completable independently
3. Be REALISTIC - prioritize by impact, not quantity
4. Number sequentially within each priority (HIGH-001, HIGH-002, etc.)
5. Minimum 5 tasks, maximum 20 (focus on meaningful ones)
6. Don't create trivial tasks just to fill space

Write the file directly to: $BACKLOG_FILE
When done, confirm: 'Backlog created with X tasks (Y high, Z medium, W low)'"

    # Create log
    mkdir -p "$LOG_DIR"
    BACKLOG_LOG="$LOG_DIR/create_backlog_$(date '+%Y%m%d_%H%M%S').log"

    # Execute Claude in background with animated progress
    # Uses sonnet for faster backlog generation
    claude --model sonnet --permission-mode bypassPermissions -p "$CREATE_BACKLOG_PROMPT" > "$BACKLOG_LOG" 2>&1 &
    CLAUDE_PID=$!

    # Hide cursor during animation
    printf '\033[?25l'

    # Animated dots while Claude is running
    local dots=""
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    while kill -0 $CLAUDE_PID 2>/dev/null; do
        for dots in "." ".." "..."; do
            if ! kill -0 $CLAUDE_PID 2>/dev/null; then
                break
            fi
            printf "\r${BLUE}[$timestamp]${NC} Creating Backlog%-3s" "$dots"
            sleep 0.5
        done
    done

    # Show cursor again and clear the line
    printf '\033[?25h'
    printf "\r%-60s\r" ""
    wait $CLAUDE_PID
    local exit_code=$?

    # Reset terminal after Claude (disable focus reporting)
    reset_terminal

    if [[ $exit_code -eq 0 ]] && [[ -f "$BACKLOG_FILE" ]]; then
        show_backlog_summary
    elif [[ $exit_code -eq 0 ]]; then
        log ERROR "Backlog file was not created"
        log INFO "Check logs: $BACKLOG_LOG"
        exit 1
    else
        log ERROR "Failed to analyze project"
        log INFO "Check logs: $BACKLOG_LOG"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# UPDATE COMMAND
# ═══════════════════════════════════════════════════════════════════════════════

REPO_URL="https://github.com/juancruzrossi/atlas"

do_update() {
    clear_screen
    show_banner
    echo -e "${BOLD}${WHITE}Checking for updates...${NC}"
    echo ""

    # Verify ATLAS_HOME exists
    if [[ ! -d "$ATLAS_HOME" ]]; then
        echo -e "${RED}Error: Atlas installation not found at: $ATLAS_HOME${NC}"
        exit 1
    fi

    local current_version="$VERSION"
    echo -e "  ${DIM}Current version:${NC} v$current_version"
    echo ""

    # Download latest version to temp
    echo -e "${CYAN}  ▸ Downloading latest version...${NC}"

    local tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    if command -v curl &> /dev/null; then
        if ! curl -sSL "${REPO_URL}/archive/main.tar.gz" | tar -xz -C "$tmp_dir" 2>/dev/null; then
            echo -e "${RED}Error: Failed to download. Check your internet connection.${NC}"
            exit 1
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -qO- "${REPO_URL}/archive/main.tar.gz" | tar -xz -C "$tmp_dir" 2>/dev/null; then
            echo -e "${RED}Error: Failed to download. Check your internet connection.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Error: curl or wget is required${NC}"
        exit 1
    fi

    local source_dir="$tmp_dir/atlas-main"

    if [[ ! -f "$source_dir/atlas.sh" ]]; then
        echo -e "${RED}Error: Download failed or invalid archive${NC}"
        exit 1
    fi

    # Get new version
    local new_version=$(grep '^VERSION=' "$source_dir/atlas.sh" | cut -d'"' -f2)

    if [[ "$current_version" == "$new_version" ]]; then
        echo ""
        echo -e "${GREEN}  ✓ Atlas is already up to date! (v$current_version)${NC}"
        echo ""
        exit 0
    fi

    echo ""
    echo -e "${BOLD}${WHITE}  Update available: v$current_version → v$new_version${NC}"
    echo ""

    # Confirm update
    read -p "  Apply update? (Y/n) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}  Update cancelled.${NC}"
        exit 0
    fi

    # Apply update
    echo ""
    echo -e "${CYAN}  ▸ Applying update...${NC}"

    cp -f "$source_dir/atlas.sh" "$ATLAS_HOME/"
    cp -f "$source_dir/atlas-rules.txt" "$ATLAS_HOME/"
    cp -rf "$source_dir/templates" "$ATLAS_HOME/"
    [[ -f "$source_dir/README.md" ]] && cp -f "$source_dir/README.md" "$ATLAS_HOME/"
    [[ -f "$source_dir/CHANGELOG.md" ]] && cp -f "$source_dir/CHANGELOG.md" "$ATLAS_HOME/"
    [[ -f "$source_dir/CLAUDE.md" ]] && cp -f "$source_dir/CLAUDE.md" "$ATLAS_HOME/"

    chmod +x "$ATLAS_HOME/atlas.sh"

    echo ""
    echo -e "${GREEN}${BOLD}  ✓ Updated to v$new_version${NC}"
    echo ""
}

# No arguments - show welcome
if [[ $# -eq 0 ]]; then
    show_welcome
    exit 0
fi

# Handle 'init' command first (before other argument parsing)
if [[ "$1" == "init" ]]; then
    do_init
    exit 0
fi

# Handle 'create-backlog' command
if [[ "$1" == "create-backlog" ]]; then
    do_create_backlog
    exit 0
fi

# Handle 'update' command
if [[ "$1" == "update" ]]; then
    do_update
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --tasks|-t)
            TASKS="$2"
            shift 2
            ;;
        --iterations|-i)
            ITERATIONS="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --status)
            show_status
            exit 0
            ;;
        --resume)
            RESUME=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            if [[ -n "$2" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                # ./atlas.sh --dry-run 5
                TASKS="$2"
                MODE="backlog"
                shift 2
            elif [[ -n "$2" ]] && [[ ! "$2" =~ ^- ]]; then
                # ./atlas.sh --dry-run "prompt" [max_tasks]
                CUSTOM_PROMPT="$2"
                MODE="prompt"
                shift 2
                # Check for optional max_tasks after prompt
                if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                    TASKS="$1"
                    shift
                fi
            else
                shift
            fi
            ;;
        --timeout)
            CLAUDE_TIMEOUT="$2"
            shift 2
            ;;
        -*)
            echo -e "${RED}Error: Unknown option $1${NC}"
            echo ""
            echo -e "Run ${CYAN}'./$SCRIPT_NAME --help'${NC} for usage information."
            exit 1
            ;;
        *)
            # Positional arguments
            # First arg: number (backlog mode) or string (prompt mode)
            if [[ -z "$TASKS" ]] && [[ -z "$CUSTOM_PROMPT" ]]; then
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    # ./atlas.sh 5 [iterations]
                    TASKS="$1"
                    MODE="backlog"
                else
                    # ./atlas.sh "prompt" <max_tasks> [iterations]
                    CUSTOM_PROMPT="$1"
                    MODE="prompt"
                fi
            elif [[ "$MODE" == "prompt" ]] && [[ -z "$TASKS" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                # Second arg after prompt is max_tasks (required)
                TASKS="$1"
            elif [[ "$MODE" == "prompt" ]] && [[ -n "$TASKS" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                # Third arg after prompt is iterations
                ITERATIONS="$1"
            elif [[ "$MODE" == "backlog" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                # Second arg in backlog mode is iterations
                ITERATIONS="$1"
            fi
            shift
            ;;
    esac
done

# Handle resume
if [[ "$RESUME" == "true" ]]; then
    if load_state; then
        log INFO "Resuming from task $current_task/$TASKS"
    else
        echo -e "${RED}Error: No resumable state found${NC}"
        exit 1
    fi
fi

# Handle dry-run
if [[ "$DRY_RUN" == "true" ]]; then
    if [[ "$MODE" == "prompt" ]]; then
        if [[ -z "$TASKS" ]]; then
            TASKS=5  # Default max tasks for prompt mode dry-run
        fi
        show_dry_run_prompt
    else
        if [[ -z "$TASKS" ]]; then
            TASKS=3  # Default for backlog mode dry-run
        fi
        show_dry_run "$TASKS"
    fi
    exit 0
fi

# Validate arguments
if [[ "$MODE" == "prompt" ]]; then
    # Prompt mode requires max_tasks
    if [[ -z "$TASKS" ]]; then
        echo -e "${RED}Error: Prompt mode requires max tasks count${NC}"
        echo ""
        echo -e "Usage: ${CYAN}./$SCRIPT_NAME \"<request>\" <max_tasks> [iterations_per_task]${NC}"
        echo ""
        echo -e "Examples:"
        echo -e "  ${CYAN}./$SCRIPT_NAME \"HIGH-004\" 1${NC}          Process HIGH-004"
        echo -e "  ${CYAN}./$SCRIPT_NAME \"all bugs\" 5${NC}          Up to 5 bug tasks"
        echo -e "  ${CYAN}./$SCRIPT_NAME \"performance\" 3 2${NC}     Up to 3 tasks, 2 iterations per task"
        echo ""
        exit 1
    fi
else
    # Backlog mode requires tasks count
    if [[ -z "$TASKS" ]]; then
        echo -e "${RED}Error: Number of tasks is required${NC}"
        echo ""
        echo -e "Run ${CYAN}'./$SCRIPT_NAME --help'${NC} for usage information."
        exit 1
    fi
fi

if ! [[ "$TASKS" =~ ^[0-9]+$ ]] || [[ "$TASKS" -lt 1 ]]; then
    echo -e "${RED}Error: Tasks must be a positive integer${NC}"
    exit 1
fi

if ! [[ "$ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$ITERATIONS" -lt 1 ]]; then
    echo -e "${RED}Error: Iterations per task must be a positive integer${NC}"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SETUP & VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Validate Atlas is installed (global rules file)
if [[ ! -f "$RULES_FILE" ]]; then
    echo -e "${RED}Error: Atlas is not properly installed${NC}"
    echo -e "${DIM}Rules file not found: $RULES_FILE${NC}"
    echo -e ""
    echo -e "Please reinstall Atlas or check ~/.atlas-home"
    exit 1
fi

# Validate project is initialized (has .atlas/ directory)
if [[ ! -d "$ATLAS_PROJECT_DIR" ]]; then
    echo -e "${RED}Error: Atlas not initialized in this project${NC}"
    echo -e ""
    echo -e "Run ${CYAN}atlas init${NC} to initialize Atlas in this directory."
    echo -e ""
    exit 1
fi

# Create logs directory
mkdir -p "$LOG_DIR"

# Validate project files exist
if [[ ! -f "$BACKLOG_FILE" ]]; then
    echo -e "${RED}Error: Backlog file not found: $BACKLOG_FILE${NC}"
    echo -e ""
    echo -e "Run ${CYAN}atlas init${NC} to recreate project files."
    exit 1
fi

# Check if backlog only has template placeholders (not in resume mode)
if [[ "$RESUME" != "true" ]] && is_template_only_backlog; then
    echo -e "${RED}Error: Backlog contains only template placeholders${NC}"
    echo -e ""
    echo -e "Edit ${CYAN}.atlas/backlog.md${NC} to add your tasks"
    echo -e "Or run ${CYAN}$SCRIPT_NAME create-backlog${NC} to auto-generate tasks"
    echo -e ""
    exit 1
fi

# Create progress file if it doesn't exist
if [[ ! -f "$PROGRESS_FILE" ]]; then
    cat > "$PROGRESS_FILE" << EOF
# Atlas Progress Log
# Created: $(date '+%Y-%m-%d %H:%M:%S')

EOF
fi

# Note: jq is no longer required since we use backlog.md (Markdown format)

# Build context files string (includes CLAUDE.md if it exists)
if [[ -f "$PROJECT_CLAUDE_MD" ]]; then
    CONTEXT_FILES="@$RULES_FILE @$PROJECT_CLAUDE_MD @$BACKLOG_FILE @$PROGRESS_FILE"
else
    CONTEXT_FILES="@$RULES_FILE @$BACKLOG_FILE @$PROGRESS_FILE"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

clear_screen
show_banner
echo -e "${DIM}Processing $TASKS task(s), up to $ITERATIONS iteration(s) each${NC}"

start_time=$(date +%s)

# ═══════════════════════════════════════════════════════════════════════════════
# OUTER LOOP: Tasks
# ═══════════════════════════════════════════════════════════════════════════════

for ((f=$current_task; f<=$TASKS; f++)); do
    current_task=$f

    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    if [[ "$MODE" == "prompt" ]]; then
        echo -e "${PURPLE}  TASK $f/$TASKS${NC} ${DIM}(matching: \"$CUSTOM_PROMPT\")${NC}"
    else
        echo -e "${PURPLE}  TASK $f/$TASKS${NC}"
    fi
    echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"

    task_start_time=$(date +%s)
    task_ready=false
    task_iterations=0
    task_first_iteration=true  # Track if this is the first iteration of the task

    for ((i=1; i<=$ITERATIONS; i++)); do
        echo ""
        if [[ "$task_first_iteration" == "true" ]]; then
            echo -e "${CYAN}  ▸ Iteration $i/$ITERATIONS${NC}"
        else
            echo -e "${CYAN}  ▸ Iteration $i/$ITERATIONS${NC} ${DIM}(continuing session)${NC}"
        fi

        task_iterations=$((task_iterations + 1))
        total_iterations=$((total_iterations + 1))

        # Create log file for this iteration
        iter_log="$LOG_DIR/task_${f}_iter_${i}_$(date '+%Y%m%d_%H%M%S').log"

        # Build the prompt based on mode and iteration
        # For iterations 2+ with --continue, we don't need to re-send all files (already in context)
        if [[ "$task_first_iteration" == "true" ]]; then
            # FIRST ITERATION: Full prompt with all @files
            if [[ "$MODE" == "prompt" ]]; then
                # PROMPT MODE: Claude interprets the user's request
                IMPLEMENT_PROMPT="$CONTEXT_FILES

ITERATION_MODE=implement
CURRENT_ITERATION=$i
MAX_ITERATIONS=$ITERATIONS
TASK_NUMBER=$f
MAX_TASKS=$TASKS

USER REQUEST: \"$CUSTOM_PROMPT\"

Follow the rules in atlas-rules.txt. The user has given you a request to work on specific task(s).

BACKLOG.MD FORMAT:
- Tasks in '## TODO' section are pending
- Tasks in '## IN PROGRESS' section are being worked on
- Tasks in '## DONE' section are completed
- Each task starts with '### CODE: Title'

YOUR TASK:
1. If a task is already in IN PROGRESS section, CONTINUE working on it
2. Otherwise, interpret the user's request and find matching task(s) in TODO section
   - The request could be: a specific code (HIGH-004), a pattern (all bugs),
     a category (performance), or a natural language description
3. Pick ONE task that matches the request and move it to IN PROGRESS
4. Implement that task

This is task $f of up to $TASKS. If no more tasks match the request, output:
<promise>SELECTOR_DONE</promise>

CRITICAL REMINDERS FOR IMPLEMENT MODE:
- Create feature branch: YES (if not exists)
- Make commits: YES
- Create PR: YES (if not exists)
- Run quality checks: YES (see QUALITY CHECKLIST in atlas-rules.txt)
- Merge PR: NO (wait for finalize phase)
- Move to DONE: NO (wait for finalize phase)

COMPLETION RULES (CRITICAL - DO NOT LIE):
- Output <promise>READY_TO_MERGE</promise> ONLY when ALL quality checks pass
- Output <promise>SELECTOR_DONE</promise> if no more tasks match the request
- If something is broken, incomplete, or you're unsure, do NOT output the promise
- Being honest saves iterations - lying wastes them"
            else
                # BACKLOG MODE: Let Claude pick the next task from TODO
                IMPLEMENT_PROMPT="$CONTEXT_FILES

ITERATION_MODE=implement
CURRENT_ITERATION=$i
MAX_ITERATIONS=$ITERATIONS
TASK_NUMBER=$f

Follow the rules in atlas-rules.txt to implement the next task from backlog.md.

BACKLOG.MD FORMAT:
- Tasks in '## TODO' section are pending
- Tasks in '## IN PROGRESS' section are being worked on
- Tasks in '## DONE' section are completed
- Each task starts with '### CODE: Title'

CRITICAL REMINDERS FOR IMPLEMENT MODE:
- If a task is in IN PROGRESS section, CONTINUE working on it
- If no task in IN PROGRESS, pick the first one from TODO section
- Create feature branch: YES (if not exists)
- Make commits: YES
- Create PR: YES (if not exists)
- Run quality checks: YES (see QUALITY CHECKLIST in atlas-rules.txt)
- Merge PR: NO (wait for finalize phase)
- Move to DONE: NO (wait for finalize phase)
- Move task to IN PROGRESS section: YES (if picking from TODO)

COMPLETION RULES (CRITICAL - DO NOT LIE):
- Output <promise>READY_TO_MERGE</promise> ONLY when ALL quality checks pass
- If something is broken, incomplete, or you're unsure, do NOT output the promise
- The loop will continue automatically if you don't signal ready
- Being honest saves iterations - lying wastes them

If ALL tasks are in DONE section (nothing in TODO or IN PROGRESS):
Output: <promise>COMPLETE</promise>"
            fi
        else
            # ITERATIONS 2+: Short prompt without @files (already in context via --continue)
            if [[ "$MODE" == "prompt" ]]; then
                IMPLEMENT_PROMPT="ITERATION_MODE=implement
CURRENT_ITERATION=$i
MAX_ITERATIONS=$ITERATIONS
TASK_NUMBER=$f
MAX_TASKS=$TASKS

Continue working on the task in IN PROGRESS section.
Check git log, git status, and PR status (gh pr list) to see what was done in previous iterations.

USER REQUEST: \"$CUSTOM_PROMPT\"

If no more tasks match the request: <promise>SELECTOR_DONE</promise>
When task is complete and all quality checks pass: <promise>READY_TO_MERGE</promise>

Remember: Do NOT merge PR, do NOT move to DONE (wait for finalize phase)."
            else
                IMPLEMENT_PROMPT="ITERATION_MODE=implement
CURRENT_ITERATION=$i
MAX_ITERATIONS=$ITERATIONS
TASK_NUMBER=$f

Continue working on the task in IN PROGRESS section.
Check git log, git status, and PR status (gh pr list) to see what was done in previous iterations.

When task is complete and all quality checks pass: <promise>READY_TO_MERGE</promise>
If ALL tasks are in DONE section: <promise>COMPLETE</promise>

Remember: Do NOT merge PR, do NOT move to DONE (wait for finalize phase)."
            fi
        fi

        # Execute Claude (ignore exit code - check output for promises instead)
        # Use --continue for iterations 2+ within the same task to maintain context
        CONTINUE_FLAG=""
        if [[ "$task_first_iteration" == "false" ]]; then
            CONTINUE_FLAG="--continue"
        fi

        # Show working indicator
        echo -e "    ${DIM}Claude is working...${NC}"
        iter_start=$(date +%s)

        # Use retry logic to handle lock conflicts with other Claude Code sessions
        if [[ -n "$CONTINUE_FLAG" ]]; then
            run_claude_with_retry "$iter_log" $CONTINUE_FLAG --permission-mode bypassPermissions -p "$IMPLEMENT_PROMPT"
        else
            run_claude_with_retry "$iter_log" --permission-mode bypassPermissions -p "$IMPLEMENT_PROMPT"
        fi

        # Reset terminal after Claude (disable focus reporting)
        reset_terminal

        iter_end=$(date +%s)
        iter_duration=$((iter_end - iter_start))

        # Mark first iteration as done
        task_first_iteration=false

        # Always read the result
        result=$(cat "$iter_log" 2>/dev/null || echo "")

        # Check for selector done (prompt mode - no more matching tasks)
        if [[ "$result" == *"<promise>SELECTOR_DONE</promise>"* ]]; then
            echo ""
            echo -e "${GREEN}  ✓ No more matching tasks${NC}"
            selector_done=true
            break 2
        fi

        # Check for Backlog complete (all tasks done)
        if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
            end_time=$(date +%s)
            duration=$((end_time - start_time))

            echo ""
            echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}  ✓ BACKLOG COMPLETE${NC}"
            echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"
            echo ""
            echo -e "  Tasks: $successful_tasks | Time: $((duration / 60))m $((duration % 60))s"
            echo ""

            rm -f "$STATE_FILE"

            if command -v tt &> /dev/null; then
                tt notify "Backlog complete! $successful_tasks tasks in $((duration / 60))m"
            fi

            exit 0
        fi

        # Atlas Philosophy: Exit when truly ready
        if [[ "$result" == *"<promise>READY_TO_MERGE</promise>"* ]]; then
            echo -e "${GREEN}    ✓ Ready to merge${NC} ${DIM}($((iter_duration / 60))m $((iter_duration % 60))s)${NC}"
            task_ready=true
            break
        fi

        # Check if output is empty or just a CLI error (no useful work done)
        if [[ -z "$result" ]] || [[ "$result" == "{"*'"is_error":true'* && ! "$result" == *"<promise>"* ]]; then
            if [[ $i -lt $ITERATIONS ]]; then
                echo -e "${YELLOW}    ↻ Issue detected, retrying...${NC} ${DIM}($((iter_duration / 60))m $((iter_duration % 60))s)${NC}"
                sleep 2
                continue
            fi
        fi

        # Not ready yet - continue to next iteration if available
        if [[ $i -lt $ITERATIONS ]]; then
            echo -e "${DIM}    → Work in progress, continuing...${NC} ${DIM}($((iter_duration / 60))m $((iter_duration % 60))s)${NC}"
            sleep 2
        else
            echo -e "${DIM}    → Iteration complete${NC} ${DIM}($((iter_duration / 60))m $((iter_duration % 60))s)${NC}"
        fi
    done

    echo ""
    echo -e "${GREEN}  ▸ Finalizing...${NC}"

    finalize_log="$LOG_DIR/task_${f}_finalize_$(date '+%Y%m%d_%H%M%S').log"

    # FINALIZE PROMPT: Same for both modes (Claude finds what's in IN PROGRESS)
    FINALIZE_PROMPT="$CONTEXT_FILES

ITERATION_MODE=finalize
TASK_NUMBER=$f

The implementation phase is complete. Now finalize the current task in IN PROGRESS section.

BACKLOG.MD FORMAT:
- Tasks in '## TODO' section are pending
- Tasks in '## IN PROGRESS' section are being worked on
- Tasks in '## DONE' section are completed
- Each task starts with '### CODE: Title'

FINALIZE STEPS:
1. IDENTIFY: Find the task in '## IN PROGRESS' section of backlog.md
2. CHECK: Verify there is a PR ready to merge for this task
3. MERGE: Merge the PR using squash & merge (gh pr merge --squash --delete-branch)
4. MOVE TO DONE: Move the task from IN PROGRESS to DONE section in backlog.md
   - Add '- **Completed:** YYYY-MM-DD' line
   - Add '- **PR:** <url>' line
5. UPDATE PROGRESS: Add summary to progress.txt with date, task title, and PR link
6. CLEANUP:
   - Delete feature branch if not already deleted
   - Kill any background processes (servers, dev tools, etc.)
   - Return to main branch
   - Pull latest changes

When done successfully, output: <promise>FEATURE_DONE</promise>

If there's no PR to merge (error state), output: <promise>NO_PR_FOUND</promise>"

    # Execute Claude (ignore exit code - check output for promises instead)
    # Finalize uses --model sonnet for faster execution (it's a simple task)
    # Note: Finalize is always a NEW session (no --continue) to avoid context buildup
    echo -e "    ${DIM}Merging PR and updating backlog...${NC}"

    # Use retry logic to handle lock conflicts with other Claude Code sessions
    run_claude_with_retry "$finalize_log" --model sonnet --permission-mode bypassPermissions -p "$FINALIZE_PROMPT"

    # Reset terminal after Claude (disable focus reporting)
    reset_terminal

    # Always read the result
    finalize_result=$(cat "$finalize_log" 2>/dev/null || echo "")

    # Check finalization result
    task_end_time=$(date +%s)
    task_duration=$((task_end_time - task_start_time))

    if [[ "$finalize_result" == *"<promise>FEATURE_DONE</promise>"* ]]; then
        echo ""
        echo -e "${GREEN}  ✓ Task $f completed${NC} ${DIM}($((task_duration / 60))m $((task_duration % 60))s)${NC}"
        successful_tasks=$((successful_tasks + 1))
    elif [[ "$finalize_result" == *"<promise>NO_PR_FOUND</promise>"* ]]; then
        echo ""
        echo -e "${RED}  ✗ Task $f: No PR found${NC}"
    else
        echo ""
        echo -e "${YELLOW}  ~ Task $f completed${NC} ${DIM}($((task_duration / 60))m $((task_duration % 60))s)${NC}"
        successful_tasks=$((successful_tasks + 1))
    fi

    save_state
done

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}  SUMMARY${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Cleanup state file on successful completion
if [[ $successful_tasks -eq $TASKS ]]; then
    rm -f "$STATE_FILE"
    echo -e "  ${GREEN}✓ $successful_tasks/$TASKS tasks completed${NC}"
elif [[ "$selector_done" == "true" ]]; then
    rm -f "$STATE_FILE"
    echo -e "  ${GREEN}✓ $successful_tasks tasks completed${NC} ${DIM}(no more matching tasks)${NC}"
else
    echo -e "  ${YELLOW}~ $successful_tasks/$TASKS tasks completed${NC}"
fi
echo -e "  ${DIM}Total time: $((duration / 60))m $((duration % 60))s${NC}"
echo ""

# Send notification if available
if command -v tt &> /dev/null; then
    tt notify "Atlas: $successful_tasks/$TASKS tasks in $((duration / 60))m"
fi

# Reset terminal before exit (disable focus reporting, show cursor)
reset_terminal

exit 0
