#!/bin/bash
set -e

ATLAS_HOME="$HOME/.atlas"
BIN_DIR="${ATLAS_INSTALL_DIR:-$HOME/.local/bin}"
REPO_URL="https://raw.githubusercontent.com/juancruzrossi/atlas/main"

echo "Installing Atlas..."
echo "  Home: $ATLAS_HOME"
echo "  Binary: $BIN_DIR/atlas"

# Create directories
mkdir -p "$ATLAS_HOME/templates" "$ATLAS_HOME/references" "$ATLAS_HOME/skills" "$BIN_DIR"

# Download core files to ATLAS_HOME
curl -fsSL "$REPO_URL/atlas.sh" -o "$ATLAS_HOME/atlas.sh" && chmod +x "$ATLAS_HOME/atlas.sh"
curl -fsSL "$REPO_URL/prompt.md" -o "$ATLAS_HOME/prompt.md"
curl -fsSL "$REPO_URL/plan_prompt.md" -o "$ATLAS_HOME/plan_prompt.md"
curl -fsSL "$REPO_URL/notify-telegram.sh" -o "$ATLAS_HOME/notify-telegram.sh" && chmod +x "$ATLAS_HOME/notify-telegram.sh"
curl -fsSL "$REPO_URL/CHANGELOG.md" -o "$ATLAS_HOME/CHANGELOG.md"

# Download templates
for f in backlog.md progress.txt guardrails.md; do
    curl -fsSL "$REPO_URL/templates/$f" -o "$ATLAS_HOME/templates/$f" 2>/dev/null || true
done

# Download references
for f in CONTEXT_ENGINEERING.md GUARDRAILS.md; do
    curl -fsSL "$REPO_URL/references/$f" -o "$ATLAS_HOME/references/$f" 2>/dev/null || true
done

# Download and install Atlas skills
SKILLS="atlas-integration-flow atlas-branching atlas-guardrails atlas-state"
mkdir -p "${HOME}/.claude/skills"
for skill in $SKILLS; do
    mkdir -p "$ATLAS_HOME/skills/$skill" "${HOME}/.claude/skills/$skill"
    curl -fsSL "$REPO_URL/skills/$skill/SKILL.md" -o "$ATLAS_HOME/skills/$skill/SKILL.md" 2>/dev/null || true
    [[ -f "$ATLAS_HOME/skills/$skill/SKILL.md" ]] && cp "$ATLAS_HOME/skills/$skill/SKILL.md" "${HOME}/.claude/skills/$skill/"
done

# Create symlink or copy binary to PATH
rm -f "$BIN_DIR/atlas"
ln -s "$ATLAS_HOME/atlas.sh" "$BIN_DIR/atlas" 2>/dev/null || cp "$ATLAS_HOME/atlas.sh" "$BIN_DIR/atlas"

echo ""
echo "✓ Atlas installed!"
echo ""

# Check if in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "Add to your PATH (add to ~/.bashrc or ~/.zshrc):"
    echo ""
    echo "  export PATH=\"\$PATH:$BIN_DIR\""
    echo ""
fi

echo "Run 'atlas help' to get started."
