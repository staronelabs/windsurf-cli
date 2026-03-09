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
for hook in prompt-capture.sh response-capture.sh log-prompt.sh log-transcript.sh; do
  if [[ -f "$SCRIPT_DIR/hooks/$hook" ]]; then
    cp "$SCRIPT_DIR/hooks/$hook" "$HOOKS_DIR/$hook"
    chmod +x "$HOOKS_DIR/$hook"
    echo -e "  ${GREEN}✓${NC} $hook"
  fi
done

# Generate hooks.json with correct path
HOOKS_JSON_USER="$HOME/.codeium/windsurf/hooks.json"
mkdir -p "$(dirname "$HOOKS_JSON_USER")"

# Build or merge hooks.json with all our hooks
if [[ -f "$HOOKS_JSON_USER" ]]; then
  echo -e "${DIM}  Existing hooks.json found, merging...${NC}"
fi

if command -v python3 &>/dev/null; then
  python3 -c "
import json, os

hooks_json_path = '$HOOKS_JSON_USER'
hooks_dir = '$HOOKS_DIR'

# Read existing or start fresh
existing = {}
if os.path.exists(hooks_json_path):
    with open(hooks_json_path) as f:
        existing = json.load(f)

hooks = existing.get('hooks', {})

# Define all hooks we want to register
our_hooks = {
    'pre_user_prompt': [
        f'bash {hooks_dir}/prompt-capture.sh',
        f'bash {hooks_dir}/log-prompt.sh',
    ],
    'post_cascade_response': [
        f'bash {hooks_dir}/response-capture.sh',
    ],
    'post_cascade_response_with_transcript': [
        f'bash {hooks_dir}/log-transcript.sh',
    ],
}

for event, commands in our_hooks.items():
    event_hooks = hooks.get(event, [])
    for cmd in commands:
        if not any(h.get('command') == cmd for h in event_hooks):
            event_hooks.append({'command': cmd, 'show_output': False})
            print(f'  Added {event}: {cmd.split("/")[-1]}')
    hooks[event] = event_hooks

existing['hooks'] = hooks
with open(hooks_json_path, 'w') as f:
    json.dump(existing, f, indent=2)
"
else
  cat > "$HOOKS_JSON_USER" <<EOF
{
  "hooks": {
    "pre_user_prompt": [
      { "command": "bash $HOOKS_DIR/prompt-capture.sh", "show_output": false },
      { "command": "bash $HOOKS_DIR/log-prompt.sh", "show_output": false }
    ],
    "post_cascade_response": [
      { "command": "bash $HOOKS_DIR/response-capture.sh", "show_output": false }
    ],
    "post_cascade_response_with_transcript": [
      { "command": "bash $HOOKS_DIR/log-transcript.sh", "show_output": false }
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
echo -e "  ${GREEN}✓${NC} Hooks:      $HOOKS_DIR/ (4 scripts)"
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
