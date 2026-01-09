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
SYMLINK_PATH="/usr/local/bin/atlas"
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

# Detect if running from local clone or curl pipe
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" 2>/dev/null )" 2>/dev/null && pwd 2>/dev/null )" || SCRIPT_DIR=""

if [[ -n "$SCRIPT_DIR" ]] && [[ -f "$SCRIPT_DIR/atlas.sh" ]] && [[ -f "$SCRIPT_DIR/atlas-rules.txt" ]]; then
    # Running from local clone
    echo -e "${BLUE}Installing from local directory...${NC}"
    SOURCE_DIR="$SCRIPT_DIR"
else
    # Running from curl pipe - download from GitHub
    echo -e "${BLUE}Downloading Atlas from GitHub...${NC}"

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

# Create symlink
echo -e "${BLUE}Creating symlink...${NC}"

if [[ ! -d "/usr/local/bin" ]]; then
    sudo mkdir -p /usr/local/bin
fi

if [[ -L "$SYMLINK_PATH" ]]; then
    sudo rm "$SYMLINK_PATH"
elif [[ -f "$SYMLINK_PATH" ]]; then
    echo -e "${RED}Error: $SYMLINK_PATH exists and is not a symlink${NC}"
    echo -e "Remove it manually and run again."
    exit 1
fi

sudo ln -s "$INSTALL_DIR/atlas.sh" "$SYMLINK_PATH"

# Done
echo ""
echo -e "${GREEN}${BOLD}✓ Atlas installed successfully!${NC}"
echo ""
echo -e "${BOLD}Quick start:${NC}"
echo -e "   ${CYAN}atlas${NC}                 Show help"
echo -e "   ${CYAN}atlas init${NC}            Initialize in your project"
echo -e "   ${CYAN}atlas create-backlog${NC}  Generate backlog from codebase"
echo -e "   ${CYAN}atlas 3${NC}               Process 3 tasks"
echo ""
echo -e "${BOLD}Update:${NC}"
echo -e "   ${CYAN}atlas update${NC}          Update to latest version"
echo ""
