# wsc — Windsurf Cascade CLI

**Talk to Cascade from any terminal.** wsc is a command-line interface and VS Code extension that bridges your shell to [Windsurf](https://windsurf.com)'s Cascade AI assistant. Send prompts, switch models, manage multiple windows, capture responses, and maintain full conversation logs — all without touching the Windsurf GUI. If you automate development workflows, run AI-assisted tasks from scripts, or just prefer living in the terminal, wsc gives you programmatic control over Cascade with a single command.

## Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| **[Windsurf IDE](https://windsurf.com)** | Any | Must be running for prompts to be delivered |
| **macOS** | 12+ | Required for AppleScript-based prompt delivery |
| **bash** | 4+ | Ships with macOS (zsh also works to invoke `wsc`) |
| **python3** | 3.8+ | Used for JSON handling in hooks (ships with macOS) |

> **Platform note:** macOS is currently required — the prompt delivery mechanism uses AppleScript to interact with the Windsurf UI. Linux/Windows support is planned.

## Quick Install

```bash
git clone https://github.com/staronelabs/windsurf-cli.git
cd windsurf-cli
./install.sh
```

Then **restart Windsurf** (or run `Cmd+Shift+P` → `Developer: Reload Window`).

Verify:

```bash
wsc --version
wsc -s
```

### What the installer does

| Step | What | Where |
|------|------|-------|
| 1 | Copies `wsc` CLI to PATH | `~/.local/bin/wsc` |
| 2 | Installs all Cascade hooks | `~/.windsurf-cli/hooks/` |
| 3 | Registers hooks in Windsurf config | `~/.codeium/windsurf/hooks.json` |
| 4 | Symlinks extension into Windsurf | `~/.windsurf/extensions/cascade-cli-0.1.0` |
| 5 | Adds `~/.local/bin` to PATH | Appends to `~/.zshrc` (with confirmation) |

### Manual Install

If you prefer to install manually:

```bash
# 1. Clone the repo
git clone https://github.com/staronelabs/windsurf-cli.git
cd windsurf-cli

# 2. Copy CLI to somewhere in your PATH
cp bin/wsc ~/.local/bin/wsc
chmod +x ~/.local/bin/wsc

# 3. Symlink extension into Windsurf
ln -sf "$(pwd)" ~/.windsurf/extensions/cascade-cli-0.1.0

# 4. Install hooks
mkdir -p ~/.windsurf-cli/hooks
for hook in prompt-capture.sh response-capture.sh log-prompt.sh log-transcript.sh; do
  cp "hooks/$hook" "$HOME/.windsurf-cli/hooks/$hook"
  chmod +x "$HOME/.windsurf-cli/hooks/$hook"
done

# 5. Register hooks (create or merge into existing hooks.json)
mkdir -p ~/.codeium/windsurf
cat > ~/.codeium/windsurf/hooks.json << 'EOF'
{
  "hooks": {
    "pre_user_prompt": [
      {
        "command": "bash ~/.windsurf-cli/hooks/prompt-capture.sh",
        "show_output": false
      },
      {
        "command": "bash ~/.windsurf-cli/hooks/log-prompt.sh",
        "show_output": false
      }
    ],
    "post_cascade_response": [
      {
        "command": "bash ~/.windsurf-cli/hooks/response-capture.sh",
        "show_output": false
      }
    ],
    "post_cascade_response_with_transcript": [
      {
        "command": "bash ~/.windsurf-cli/hooks/log-transcript.sh",
        "show_output": false
      }
    ]
  }
}
EOF

# 6. Ensure ~/.local/bin is in your PATH (add to ~/.zshrc if needed)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 7. Restart Windsurf
```

### Uninstall

```bash
rm ~/.local/bin/wsc
rm -rf ~/.windsurf/extensions/cascade-cli-0.1.0
rm -rf ~/.windsurf-cli
# Optionally remove the hook from ~/.codeium/windsurf/hooks.json
```

## Usage

### Send a prompt

```bash
wsc "explain this codebase"
```

### Choose a model

```bash
wsc -m "Claude Sonnet 4.5" "refactor the auth module"
wsc -l                           # list available models
wsc -m "GPT-5.4"                 # switch model without sending a prompt
```

### Wait for the response

```bash
wsc -w "what does this function do?"
```

The `-w` flag waits for Cascade to finish and prints the response to stdout.

### Open a new Windsurf window

```bash
wsc -N ~/projects/myapp           # open new window at directory
wsc -N                             # open new window at current directory
wsc -N ~/projects/myapp "fix bug"  # open window + send prompt
```

### Target a specific window

```bash
wsc --windows                         # list open windows
wsc -W myproject "fix the login bug"  # send to specific window
```

### Pipe and file input

```bash
echo "fix the bug in main.py" | wsc
cat error.log | wsc "explain this error"
wsc -f prompt.txt
```

### Interactive mode

```bash
wsc -i                    # multi-line input, Ctrl+D to send
wsc -i -m "GPT-5.4"      # interactive with model selection
```

### Auto-accept changes

```bash
wsc -a "add error handling to api.js"   # auto-accept after response
wsc -A                                   # click "Accept all" button now
```

### Execute any Windsurf command

```bash
wsc --exec windsurf.cascadePanel.focus
wsc --exec windsurf.openGenericUrl --args '["https://docs.windsurf.com"]'
wsc -c                                   # list all discovered commands
```

### Verbose output

```bash
wsc -V "explain this file"      # show request details + status
wsc -VV -w "summarize changes"  # show everything including timing
```

### Diagnostics

```bash
wsc -s          # show current status
wsc -L          # show extension log (last 50 lines)
wsc --tabs      # show Cascade conversations
```

## All Options

```
wsc [OPTIONS] [PROMPT]
wsc --exec COMMAND_ID [--args JSON]
echo "prompt" | wsc
wsc -i

Options:
  -m, --model MODEL       Select LLM model (e.g. "Claude Sonnet 4.5", "GPT-5.4")
  -a, --accept            Auto-accept code changes after Cascade responds
  -A, --accept-all        Click the "Accept all" button once (one-shot)
  -W, --window NAME       Target a specific Windsurf window
  -N, --new-window [DIR]  Open a new Windsurf window (default: current dir)
  -n, --new               Start a new Cascade conversation
  -w, --wait              Wait for response and print it to stdout
  -t, --timeout SEC       Timeout for --wait (default: 120)
  -f, --file FILE         Send file contents as the prompt
  -i, --interactive       Multi-line input mode (Ctrl+D to send)
  -V, --verbose           Verbose output (repeat: -VV for more)
  -x, --exec CMD          Execute any Windsurf/VS Code command by ID
      --args JSON         JSON array of arguments for --exec
  -l, --list-models       List available models
  -s, --status            Show current status
  -c, --commands          List discovered Windsurf commands
  -L, --log               Show extension diagnostic log
  --windows               List open Windsurf windows
  --tabs                  List Cascade conversations
  -h, --help              Show help
  -v, --version           Show version
```

## How It Works

```
Terminal (wsc)              Windsurf Extension              Cascade
    │                            │                            │
    ├── writes prompt.json ─────►│ fs.watch detects change    │
    │   (~/.windsurf-cli/)       │                            │
    │                            ├── reads prompt + model     │
    │                            ├── focuses Cascade panel    │
    │                            ├── pastes + submits ───────►│
    │                            │                            │
    │   ◄── reads response.json ─┤◄── hook captures resp ────┤
    │   (~/.windsurf-cli/)       │  (post_cascade_response)   │
```

**Three components work together:**

1. **`wsc` CLI** (`bin/wsc`) — Bash script that writes prompt JSON to a watched directory
2. **Cascade CLI Bridge extension** (`src/extension.js`) — Windsurf extension that picks up prompts and delivers them to Cascade via AppleScript UI automation
3. **Cascade hooks** (`hooks/`) — Windsurf lifecycle hooks that capture prompts, responses, and conversation transcripts

### File protocol

All communication happens through JSON files in `~/.windsurf-cli/`:

| File | Purpose |
|------|---------|
| `prompt.json` | CLI → Extension: prompt, model, command requests |
| `status.json` | Extension → CLI: processing status updates |
| `response.json` | Hook → CLI: captured Cascade responses (global) |
| `response-{window}.json` | Hook → CLI: captured response (per-window) |
| `prompt-latest.json` | Hook → CLI: last captured prompt (global) |
| `prompt-{window}.json` | Hook → CLI: last captured prompt (per-window) |
| `active-window.json` | Extension → Hooks: currently focused Windsurf window |
| `windows.json` | Extension → CLI: registered Windsurf windows |
| `models.json` | Extension → CLI: available model list |
| `tabs.json` | Extension → CLI: conversation tracking |
| `conversation-history.json` | Hook: full prompt/response history (global) |
| `conversation-history-{window}.json` | Hook: full history (per-window) |
| `cascade-logs/{window}_{trajectory}.jsonl` | Hook: structured per-window, per-conversation log |
| `extension.log` | Extension diagnostics (view with `wsc -L`) |
| `hook.log` | Hook diagnostics |

### Cascade hooks

wsc uses [Windsurf Cascade Hooks](https://docs.windsurf.com/windsurf/cascade/hooks) to capture data from every Cascade interaction — even those initiated directly in the Windsurf GUI (not just via the CLI).

| Hook | Script | Purpose |
|------|--------|---------|
| `pre_user_prompt` | `prompt-capture.sh` | Captures every user prompt and appends to conversation history |
| `pre_user_prompt` | `log-prompt.sh` | Logs prompts to per-window, per-conversation JSONL files |
| `post_cascade_response` | `response-capture.sh` | Captures Cascade responses for `wsc -w` and conversation history |
| `post_cascade_response_with_transcript` | `log-transcript.sh` | Copies full conversation transcripts to per-window, per-conversation logs |

Hooks are registered in `~/.codeium/windsurf/hooks.json` and fire for **all** Cascade usage across all Windsurf windows.

#### Log structure

Per-window, per-conversation logs are stored in `~/.windsurf-cli/cascade-logs/`:

```
cascade-logs/
├── myproject_abc123-def4-5678.jsonl    # window "myproject", conversation abc123...
├── myproject_fff999-aaa1-2222.jsonl    # window "myproject", different conversation
└── otherproject_bbb444-ccc5-6666.jsonl # window "otherproject"
```

Each `.jsonl` file contains one JSON object per line — user prompts, transcript updates, and full structured conversation steps.

### Multi-window support

Each Windsurf window registers itself with a unique ID (derived from its workspace folder name). The extension tracks which window is focused via `active-window.json`, updated on:

- Extension activation
- Window focus changes (`onDidChangeWindowState`)
- CLI prompt processing

This allows hooks to route data to the correct per-window files automatically, even when multiple Windsurf instances are running.

## Configuration

### Extension settings

Set in Windsurf's `settings.json` or via the Settings UI:

| Setting | Default | Description |
|---------|---------|-------------|
| `cascadeCli.promptDir` | `~/.windsurf-cli/` | Directory for all CLI ↔ extension communication |
| `cascadeCli.autoStart` | `true` | Start watching for prompts on Windsurf launch |

### Environment variable

```bash
export WSC_DIR="$HOME/.windsurf-cli"   # override prompt directory
```

## Troubleshooting

### "Is the Cascade CLI extension running?"

The extension must be active in Windsurf. Check:

```bash
wsc -s    # should show "watching" status
wsc -L    # check extension log for errors
```

If no status, restart Windsurf or run `Cmd+Shift+P` → `Cascade CLI: Start Watching for Prompts`.

### Prompt sent but nothing happens

1. Check the extension log: `wsc -L`
2. Make sure Windsurf is in the foreground (AppleScript needs it visible)
3. Check if the right window is targeted: `wsc --windows`

### Response not captured with `-w`

The response hook must be registered. Verify:

```bash
cat ~/.codeium/windsurf/hooks.json
```

Should contain a `post_cascade_response` entry pointing to `response-capture.sh`.

### `wsc: command not found`

Ensure `~/.local/bin` is in your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Multiple Windsurf windows

By default, prompts go to the first registered window. Use `-W` to target a specific one:

```bash
wsc --windows                        # see registered windows
wsc -W myproject "fix the bug"       # target by workspace name
```

### Conversation logs not appearing per-window

Ensure the extension is updated and reloaded (`Cmd+Shift+P` → `Developer: Reload Window`). The extension must write `active-window.json` on focus change for hooks to route correctly.

## Project Structure

```
cascade-cli-extension/
├── bin/
│   ├── wsc                      # CLI tool (bash)
│   └── detect_blue_button.py    # Helper for Accept All detection
├── hooks/
│   ├── prompt-capture.sh        # pre_user_prompt: conversation history
│   ├── response-capture.sh      # post_cascade_response: response capture
│   ├── log-prompt.sh            # pre_user_prompt: per-window/conversation logging
│   ├── log-transcript.sh        # post_cascade_response_with_transcript: transcript logging
│   ├── hooks.json               # Hook registration template (CLI hooks)
│   └── hooks-logging.json       # Hook registration template (logging hooks)
├── src/
│   └── extension.js             # Windsurf extension (prompt delivery, window management)
├── package.json                 # Extension manifest
├── install.sh                   # Automated installer
├── COMMANDS_REFERENCE.md        # Windsurf command documentation
└── README.md
```

## License

MIT
