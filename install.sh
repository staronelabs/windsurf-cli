#!/usr/bin/env bash
# Installer for Windsurf Cascade CLI (wsc)
# Installs the CLI tool, extension, and hooks

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WSC_DIR="$HOME/.windsurf-cli"
BIN_DIR="$HOME/.local/bin"
HOOKS_DIR="$WSC_DIR/hooks"

echo -e "${BOLD}━━━ Windsurf Cascade CLI Installer ━━━${NC}"
echo ""

# 1. Create directories
echo -e "${BLUE}[1/5]${NC} Creating directories..."
mkdir -p "$WSC_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$HOOKS_DIR"

# 2. Install CLI tool
echo -e "${BLUE}[2/5]${NC} Installing wsc CLI..."
cp "$SCRIPT_DIR/bin/wsc" "$BIN_DIR/wsc"
chmod +x "$BIN_DIR/wsc"

# Check if BIN_DIR is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo -e "${YELLOW}  ⚠ $BIN_DIR is not in your PATH${NC}"
  echo -e "${DIM}  Add this to your ~/.zshrc or ~/.bashrc:${NC}"
  echo -e "${DIM}    export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
  
  # Offer to add it (idempotent: skip if already present)
  if grep -q "# Windsurf Cascade CLI" "$HOME/.zshrc" 2>/dev/null; then
    echo -e "${DIM}  Already in ~/.zshrc${NC}"
  else
    read -rp "  Add to ~/.zshrc now? [Y/n] " add_path
    if [[ "${add_path:-Y}" =~ ^[Yy]$ ]]; then
      echo '' >> "$HOME/.zshrc"
      echo '# Windsurf Cascade CLI' >> "$HOME/.zshrc"
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
      echo -e "${GREEN}  ✓ Added to ~/.zshrc (restart terminal or run: source ~/.zshrc)${NC}"
    fi
  fi
fi

# 3. Install hooks
echo -e "${BLUE}[3/5]${NC} Installing Cascade hooks..."
cp "$SCRIPT_DIR/hooks/response-capture.sh" "$HOOKS_DIR/response-capture.sh"
chmod +x "$HOOKS_DIR/response-capture.sh"

# Generate hooks.json with correct path
HOOKS_JSON_USER="$HOME/.codeium/windsurf/hooks.json"
mkdir -p "$(dirname "$HOOKS_JSON_USER")"

# Check if hooks.json already exists and merge
if [[ -f "$HOOKS_JSON_USER" ]]; then
  echo -e "${DIM}  Existing hooks.json found, merging...${NC}"
  if command -v python3 &>/dev/null; then
    python3 -c "
import json

# Read existing
with open('$HOOKS_JSON_USER') as f:
    existing = json.load(f)

# Add our hook
hooks = existing.get('hooks', {})
post_resp = hooks.get('post_cascade_response', [])

# Check if our hook already exists
our_cmd = 'bash $HOOKS_DIR/response-capture.sh'
already = any(h.get('command') == our_cmd for h in post_resp)

if not already:
    post_resp.append({
        'command': our_cmd,
        'show_output': False
    })
    hooks['post_cascade_response'] = post_resp
    existing['hooks'] = hooks
    with open('$HOOKS_JSON_USER', 'w') as f:
        json.dump(existing, f, indent=2)
    print('  Added response capture hook')
else:
    print('  Hook already installed')
"
  fi
else
  cat > "$HOOKS_JSON_USER" <<EOF
{
  "hooks": {
    "post_cascade_response": [
      {
        "command": "bash $HOOKS_DIR/response-capture.sh",
        "show_output": false
      }
    ]
  }
}
EOF
  echo -e "${GREEN}  ✓ Created hooks.json${NC}"
fi

# 4. Install extension symlink for Windsurf
echo -e "${BLUE}[4/5]${NC} Installing VS Code extension..."

# Windsurf extensions directory
EXTENSIONS_DIR="$HOME/.windsurf/extensions"
if [[ ! -d "$EXTENSIONS_DIR" ]]; then
  # Try alternate location
  EXTENSIONS_DIR="$HOME/.vscode/extensions"
fi
mkdir -p "$EXTENSIONS_DIR"

EXT_TARGET="$EXTENSIONS_DIR/cascade-cli-0.1.0"
if [[ -L "$EXT_TARGET" || -d "$EXT_TARGET" ]]; then
  rm -rf "$EXT_TARGET"
fi
ln -s "$SCRIPT_DIR" "$EXT_TARGET"
echo -e "${GREEN}  ✓ Extension linked to $EXT_TARGET${NC}"

# 5. Summary
echo -e "${BLUE}[5/5]${NC} Verifying..."
echo ""
echo -e "${GREEN}━━━ Installation Complete ━━━${NC}"
echo ""
echo -e "${BOLD}Components installed:${NC}"
echo -e "  ${GREEN}✓${NC} CLI tool:   $BIN_DIR/wsc"
echo -e "  ${GREEN}✓${NC} Hooks:      $HOOKS_DIR/response-capture.sh"
echo -e "  ${GREEN}✓${NC} Hooks cfg:  $HOOKS_JSON_USER"
echo -e "  ${GREEN}✓${NC} Extension:  $EXT_TARGET"
echo ""
echo -e "${BOLD}Quick start:${NC}"
echo -e "  ${CYAN}wsc \"explain this codebase\"${NC}"
echo -e "  ${CYAN}wsc -m \"Claude 4 Sonnet\" \"refactor auth\"${NC}"
echo -e "  ${CYAN}wsc -i${NC}  ${DIM}(interactive mode)${NC}"
echo -e "  ${CYAN}wsc -l${NC}  ${DIM}(list models)${NC}"
echo ""
echo -e "${DIM}Restart Windsurf to activate the extension.${NC}"
