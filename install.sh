#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
# Atlas Installer
# Autonomous Task Loop Agent System
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/juancruzrossi/atlas/main/install.sh | bash
#
# Or clone and run locally:
#   git clone https://github.com/juancruzrossi/atlas.git && cd atlas && ./install.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# Config
REPO_URL="https://github.com/juancruzrossi/atlas"
INSTALL_DIR="$HOME/.atlas"
ATLAS_HOME_FILE="$HOME/.atlas-home"

show_banner() {
    echo ""
    echo -e "${BOLD}    █████╗ ████████╗██╗      █████╗ ███████╗${NC}"
    echo -e "${BOLD}   ██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝${NC}"
    echo -e "${BOLD}   ███████║   ██║   ██║     ███████║███████╗${NC}"
    echo -e "${BOLD}   ██╔══██║   ██║   ██║     ██╔══██║╚════██║${NC}"
    echo -e "${BOLD}   ██║  ██║   ██║   ███████╗██║  ██║███████║${NC}"
    echo -e "${BOLD}   ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝${NC}"
    echo -e "    ${DIM}Autonomous Task Loop Agent System${NC}"
    echo ""
}

show_banner

# Check for required commands
if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
    echo -e "${RED}Error: curl or wget is required${NC}"
    exit 1
fi

if ! command -v tar &> /dev/null; then
    echo -e "${RED}Error: tar is required${NC}"
    exit 1
fi

# Detect if running from pipe (stdin is not a terminal)
# AND check if we're in a directory with atlas files
SCRIPT_DIR=""
if [[ -t 0 ]]; then
    # stdin is a terminal, so NOT running from pipe
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" 2>/dev/null )" 2>/dev/null && pwd 2>/dev/null )" || SCRIPT_DIR=""
fi

if [[ -n "$SCRIPT_DIR" ]] && [[ -f "$SCRIPT_DIR/atlas.sh" ]] && [[ -f "$SCRIPT_DIR/atlas-rules.txt" ]]; then
    # Running from local clone
    echo -e "${BLUE}Installing from local directory...${NC}"
    SOURCE_DIR="$SCRIPT_DIR"
else
    # Running from curl pipe - download from GitHub
    echo -e "${BLUE}Downloading Atlas...${NC}"

    TMP_DIR=$(mktemp -d)
    trap "rm -rf $TMP_DIR" EXIT

    # Download tarball
    if command -v curl &> /dev/null; then
        curl -sSL "${REPO_URL}/archive/main.tar.gz" | tar -xz -C "$TMP_DIR"
    else
        wget -qO- "${REPO_URL}/archive/main.tar.gz" | tar -xz -C "$TMP_DIR"
    fi

    SOURCE_DIR="$TMP_DIR/atlas-main"

    if [[ ! -f "$SOURCE_DIR/atlas.sh" ]]; then
        echo -e "${RED}Error: Download failed or invalid archive${NC}"
        exit 1
    fi
fi

# Verify required files
for file in "atlas.sh" "atlas-rules.txt"; do
    if [[ ! -f "$SOURCE_DIR/$file" ]]; then
        echo -e "${RED}Error: $file not found${NC}"
        exit 1
    fi
done

if [[ ! -d "$SOURCE_DIR/templates" ]]; then
    echo -e "${RED}Error: templates/ directory not found${NC}"
    exit 1
fi

echo -e "${BLUE}Installing to ${INSTALL_DIR}...${NC}"

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy files
cp -f "$SOURCE_DIR/atlas.sh" "$INSTALL_DIR/"
cp -f "$SOURCE_DIR/atlas-rules.txt" "$INSTALL_DIR/"
cp -rf "$SOURCE_DIR/templates" "$INSTALL_DIR/"

# Copy docs if they exist
[[ -f "$SOURCE_DIR/README.md" ]] && cp -f "$SOURCE_DIR/README.md" "$INSTALL_DIR/"
[[ -f "$SOURCE_DIR/CHANGELOG.md" ]] && cp -f "$SOURCE_DIR/CHANGELOG.md" "$INSTALL_DIR/"
[[ -f "$SOURCE_DIR/CLAUDE.md" ]] && cp -f "$SOURCE_DIR/CLAUDE.md" "$INSTALL_DIR/"

# Make executable
chmod +x "$INSTALL_DIR/atlas.sh"

# Save ATLAS_HOME
echo "$INSTALL_DIR" > "$ATLAS_HOME_FILE"

# Create symlink - try multiple locations
echo -e "${BLUE}Creating command...${NC}"

SYMLINK_CREATED=false

# Option 1: /usr/local/bin (requires sudo on most systems)
if [[ -d "/usr/local/bin" ]] && [[ -w "/usr/local/bin" ]]; then
    ln -sf "$INSTALL_DIR/atlas.sh" "/usr/local/bin/atlas"
    SYMLINK_CREATED=true
    SYMLINK_PATH="/usr/local/bin/atlas"
elif [[ -d "/usr/local/bin" ]]; then
    # Try with sudo
    if sudo -n true 2>/dev/null; then
        sudo ln -sf "$INSTALL_DIR/atlas.sh" "/usr/local/bin/atlas"
        SYMLINK_CREATED=true
        SYMLINK_PATH="/usr/local/bin/atlas"
    fi
fi

# Option 2: ~/bin (no sudo needed)
if [[ "$SYMLINK_CREATED" == "false" ]]; then
    mkdir -p "$HOME/bin"
    ln -sf "$INSTALL_DIR/atlas.sh" "$HOME/bin/atlas"
    SYMLINK_CREATED=true
    SYMLINK_PATH="$HOME/bin/atlas"

    # Check if ~/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        echo ""
        echo -e "${YELLOW}Note: Add ~/bin to your PATH by adding this to ~/.zshrc or ~/.bashrc:${NC}"
        echo -e "  ${CYAN}export PATH=\"\$HOME/bin:\$PATH\"${NC}"
        echo ""
    fi
fi

# Done
echo ""
echo -e "${GREEN}${BOLD}✓ Atlas installed successfully!${NC}"
echo ""
echo -e "${BOLD}Quick start:${NC}"
echo -e "   ${CYAN}atlas${NC}                 Show help"
echo -e "   ${CYAN}atlas init${NC}            Initialize in your project"
echo -e "   ${CYAN}atlas create-backlog${NC}  Analyze codebase and generate backlog"
echo -e "   ${CYAN}atlas 3 2${NC}             Process 3 tasks with 2 iterations each"
echo ""
