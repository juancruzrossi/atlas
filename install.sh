#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
# Atlas Installer
# Autonomous Task Loop Agent System
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo ""
echo -e "${BOLD}    █████╗ ████████╗██╗      █████╗ ███████╗${NC}"
echo -e "${BOLD}   ██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝${NC}"
echo -e "${BOLD}   ███████║   ██║   ██║     ███████║███████╗${NC}"
echo -e "${BOLD}   ██╔══██║   ██║   ██║     ██╔══██║╚════██║${NC}"
echo -e "${BOLD}   ██║  ██║   ██║   ███████╗██║  ██║███████║${NC}"
echo -e "${BOLD}   ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝${NC}"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check required files exist
if [[ ! -f "$SCRIPT_DIR/atlas.sh" ]]; then
    echo -e "${RED}Error: atlas.sh not found in $SCRIPT_DIR${NC}"
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/atlas-rules.txt" ]]; then
    echo -e "${RED}Error: atlas-rules.txt not found in $SCRIPT_DIR${NC}"
    exit 1
fi

if [[ ! -d "$SCRIPT_DIR/templates" ]]; then
    echo -e "${RED}Error: templates/ directory not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Make atlas.sh executable
chmod +x "$SCRIPT_DIR/atlas.sh"

echo -e "${BLUE}Installing Atlas...${NC}"
echo ""

# Save ATLAS_HOME (silently)
ATLAS_HOME_FILE="$HOME/.atlas-home"
echo "$SCRIPT_DIR" > "$ATLAS_HOME_FILE"

# Create symlink in /usr/local/bin
SYMLINK_PATH="/usr/local/bin/atlas"

# Check if /usr/local/bin exists
if [[ ! -d "/usr/local/bin" ]]; then
    sudo mkdir -p /usr/local/bin
fi

# Remove existing symlink if present
if [[ -L "$SYMLINK_PATH" ]]; then
    sudo rm "$SYMLINK_PATH"
elif [[ -f "$SYMLINK_PATH" ]]; then
    echo -e "${RED}Error: $SYMLINK_PATH exists and is not a symlink${NC}"
    echo -e "Please remove it manually and run this script again."
    exit 1
fi

# Create symlink (silently)
sudo ln -s "$SCRIPT_DIR/atlas.sh" "$SYMLINK_PATH"

echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo -e "   1. cd to your project directory"
echo -e "   2. Run ${CYAN}atlas init${NC} to initialize"
echo -e "   3. Edit ${YELLOW}.atlas/project-rules.txt${NC} with your project config"
echo -e "   4. Add tasks to ${YELLOW}.atlas/backlog.md${NC}"
echo -e "   5. Enjoy!"
echo ""
echo -e "${BOLD}Usage:${NC}"
echo -e "   ${CYAN}atlas init${NC}            Initialize Atlas in current project"
echo -e "   ${CYAN}atlas create-backlog${NC}  Auto-generate backlog from project"
echo -e "   ${CYAN}atlas${NC}                 Show help and status"
echo -e "   ${CYAN}atlas 3${NC}               Process 3 tasks from backlog"
echo -e "   ${CYAN}atlas 5 3${NC}             Process 5 tasks, 3 iterations per task"
echo -e "   ${CYAN}atlas --status${NC}        Show backlog status"
echo ""
