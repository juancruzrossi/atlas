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

curl -fsSL "$REPO_URL/atlas.sh" -o "$ATLAS_HOME/atlas.sh" && chmod +x "$ATLAS_HOME/atlas.sh" || true
curl -fsSL "$REPO_URL/prompt.md" -o "$ATLAS_HOME/prompt.md" || true
curl -fsSL "$REPO_URL/plan_prompt.md" -o "$ATLAS_HOME/plan_prompt.md" || true
curl -fsSL "$REPO_URL/review_prompt.md" -o "$ATLAS_HOME/review_prompt.md" || true
curl -fsSL "$REPO_URL/notify-telegram.sh" -o "$ATLAS_HOME/notify-telegram.sh" && chmod +x "$ATLAS_HOME/notify-telegram.sh" || true
curl -fsSL "$REPO_URL/CHANGELOG.md" -o "$ATLAS_HOME/CHANGELOG.md" || true

for f in backlog.md progress.txt guardrails.md; do
    curl -fsSL "$REPO_URL/templates/$f" -o "$ATLAS_HOME/templates/$f" 2>/dev/null || true
done

for f in CONTEXT_ENGINEERING.md GUARDRAILS.md; do
    curl -fsSL "$REPO_URL/references/$f" -o "$ATLAS_HOME/references/$f" 2>/dev/null || true
done

SKILLS="atlas-integration-flow atlas-branching atlas-guardrails atlas-state"
for skill in $SKILLS; do
    mkdir -p "$ATLAS_HOME/skills/$skill"
    curl -fsSL "$REPO_URL/skills/$skill/SKILL.md" -o "$ATLAS_HOME/skills/$skill/SKILL.md" 2>/dev/null || true
done

# Install to Claude Code if available
if command -v claude >/dev/null 2>&1; then
    mkdir -p "${HOME}/.claude/skills"
    for skill in $SKILLS; do
        mkdir -p "${HOME}/.claude/skills/$skill"
        if [[ -f "$ATLAS_HOME/skills/$skill/SKILL.md" ]]; then cp "$ATLAS_HOME/skills/$skill/SKILL.md" "${HOME}/.claude/skills/$skill/"; fi
    done
fi

# Install to OpenCode if available
if command -v opencode >/dev/null 2>&1; then
    mkdir -p "${HOME}/.config/opencode/skills"
    for skill in $SKILLS; do
        mkdir -p "${HOME}/.config/opencode/skills/$skill"
        if [[ -f "$ATLAS_HOME/skills/$skill/SKILL.md" ]]; then cp "$ATLAS_HOME/skills/$skill/SKILL.md" "${HOME}/.config/opencode/skills/$skill/"; fi
    done
fi

# Install to Codex if available
if command -v codex >/dev/null 2>&1; then
    mkdir -p "${HOME}/.codex/skills"
    for skill in $SKILLS; do
        mkdir -p "${HOME}/.codex/skills/$skill"
        if [[ -f "$ATLAS_HOME/skills/$skill/SKILL.md" ]]; then cp "$ATLAS_HOME/skills/$skill/SKILL.md" "${HOME}/.codex/skills/$skill/"; fi
    done
fi

rm -f "$BIN_DIR/atlas"
ln -s "$ATLAS_HOME/atlas.sh" "$BIN_DIR/atlas" 2>/dev/null || cp "$ATLAS_HOME/atlas.sh" "$BIN_DIR/atlas"

MISSING=()
for f in atlas.sh prompt.md plan_prompt.md review_prompt.md CHANGELOG.md; do
    if [[ ! -f "$ATLAS_HOME/$f" ]]; then MISSING+=("$f"); fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    echo "✗ Error: Installation failed - missing critical file(s):"
    for f in "${MISSING[@]}"; do echo "  - $f"; done
    echo ""
    echo "Check your internet connection and try again."
    exit 1
fi

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
