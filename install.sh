#!/bin/bash
set -e

INSTALL_DIR="${ATLAS_INSTALL_DIR:-$HOME/.local/bin}"
REPO_URL="https://raw.githubusercontent.com/juancruzrossi/atlas/main"

echo "Installing Atlas to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"

# Download main files
curl -fsSL "$REPO_URL/atlas.sh" -o "$INSTALL_DIR/atlas"
curl -fsSL "$REPO_URL/prompt.md" -o "$INSTALL_DIR/prompt.md"
curl -fsSL "$REPO_URL/plan_prompt.md" -o "$INSTALL_DIR/plan_prompt.md"
curl -fsSL "$REPO_URL/notify-telegram.sh" -o "$INSTALL_DIR/notify-telegram.sh"

chmod +x "$INSTALL_DIR/atlas" "$INSTALL_DIR/notify-telegram.sh"

# Download templates
mkdir -p "$INSTALL_DIR/templates"
curl -fsSL "$REPO_URL/templates/backlog.md" -o "$INSTALL_DIR/templates/backlog.md"
curl -fsSL "$REPO_URL/templates/progress.txt" -o "$INSTALL_DIR/templates/progress.txt"
curl -fsSL "$REPO_URL/templates/guardrails.md" -o "$INSTALL_DIR/templates/guardrails.md"

# Download references
mkdir -p "$INSTALL_DIR/references"
curl -fsSL "$REPO_URL/references/CONTEXT_ENGINEERING.md" -o "$INSTALL_DIR/references/CONTEXT_ENGINEERING.md" 2>/dev/null || true

echo ""
echo "✓ Atlas installed!"
echo ""

# Check if in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "Add to your PATH (add to ~/.bashrc or ~/.zshrc):"
    echo ""
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    echo ""
fi

echo "Run 'atlas help' to get started."
