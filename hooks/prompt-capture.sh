#!/usr/bin/env bash
# Cascade Hook: Captures pre_user_prompt and appends to conversation history
# Fired BEFORE a user prompt is sent to Cascade

set -euo pipefail

resolve_wsc_dir() {
  if [[ -n "${WSC_DIR:-}" ]]; then
    printf '%s\n' "$WSC_DIR"
    return
  fi

  local settings_path
  for settings_path in \
    "$HOME/Library/Application Support/Windsurf/User/settings.json" \
    "$HOME/Library/Application Support/Code/User/settings.json"
  do
    if [[ -f "$settings_path" ]] && command -v python3 &>/dev/null; then
      local detected
      detected=$(python3 - "$settings_path" <<'PYEOF'
import json, os, sys
settings_path = sys.argv[1]
try:
    with open(settings_path) as f:
        data = json.load(f)
    value = data.get("cascadeCli.promptDir", "")
    if isinstance(value, str) and value.strip():
        print(os.path.expanduser(value.strip()))
except Exception:
    pass
PYEOF
)
      if [[ -n "$detected" ]]; then
        printf '%s\n' "$detected"
        return
      fi
    fi
  done

  printf '%s\n' "$HOME/.windsurf-cli"
}

WSC_DIR="$(resolve_wsc_dir)"
HOOK_LOG="$WSC_DIR/hook.log"

# Read active window ID for per-window files
ACTIVE_WINDOW=""
if [[ -f "$WSC_DIR/active-window.json" ]] && command -v python3 &>/dev/null; then
  ACTIVE_WINDOW=$(python3 -c "
import json
with open('$WSC_DIR/active-window.json') as f:
    print(json.load(f).get('windowId', ''))
" 2>/dev/null || echo "")
fi
export ACTIVE_WINDOW

mkdir -p "$WSC_DIR"

echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [prompt-hook] invoked" >> "$HOOK_LOG"

# Read JSON from stdin
export TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
cat > "$TMPFILE"

INPUT_SIZE=$(wc -c < "$TMPFILE" | tr -d ' ')
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [prompt-hook] stdin bytes=$INPUT_SIZE" >> "$HOOK_LOG"

# Save raw input for inspection
cp "$TMPFILE" "$WSC_DIR/hook-last-prompt-input.json"

export WSC_DIR

if command -v python3 &>/dev/null; then
  python3 << 'PYEOF'
import json, os, sys
from datetime import datetime

tmp = os.environ.get("TMPFILE", "")
wsc_dir = os.environ.get("WSC_DIR", os.path.expanduser("~/.windsurf-cli"))
history_file = os.path.join(wsc_dir, "conversation-history.json")
hook_log = os.path.join(wsc_dir, "hook.log")
active_window = os.environ.get("ACTIVE_WINDOW", "")
window_history_file = os.path.join(wsc_dir, f"conversation-history-{active_window}.json") if active_window else None

def log(msg):
    with open(hook_log, "a") as f:
        f.write(f"{datetime.utcnow().isoformat()}Z [prompt-hook-py] {msg}\n")

try:
    with open(tmp) as f:
        raw = f.read()
    if not raw.strip():
        log("empty input, exiting")
        sys.exit(0)

    data = json.loads(raw)
    log(f"parsed JSON, keys={list(data.keys())}")

except Exception as e:
    log(f"parse error: {e}")
    sys.exit(0)

# Extract user prompt text
prompt_text = ""

# Try tool_info.prompt first
prompt_text = (data.get("tool_info") or {}).get("prompt", "")
if not prompt_text:
    prompt_text = data.get("prompt", "")
if not prompt_text:
    prompt_text = data.get("text", "")
if not prompt_text:
    prompt_text = data.get("content", "")

if not prompt_text:
    log("no prompt text found in any path")
    sys.exit(0)

log(f"found prompt ({len(prompt_text)} chars)")

trajectory_id = data.get("trajectory_id", "")
timestamp = data.get("timestamp", datetime.utcnow().isoformat() + "Z")

# Write per-window prompt file (analogous to response-{window}.json)
prompt_output = {
    "prompt": prompt_text,
    "trajectory_id": trajectory_id,
    "timestamp": timestamp,
}

prompt_file = os.path.join(wsc_dir, "prompt-latest.json")
with open(prompt_file, "w") as f:
    json.dump(prompt_output, f, indent=2)
log(f"wrote prompt to {prompt_file} ({len(prompt_text)} chars)")

if active_window:
    window_prompt_file = os.path.join(wsc_dir, f"prompt-{active_window}.json")
    with open(window_prompt_file, "w") as f:
        json.dump(prompt_output, f, indent=2)
    log(f"wrote per-window prompt to {window_prompt_file}")

# Load existing history
history = {"messages": []}
try:
    if os.path.exists(history_file):
        with open(history_file) as f:
            history = json.load(f)
        if "messages" not in history:
            history["messages"] = []
except Exception:
    history = {"messages": []}

# Append user message
history["messages"].append({
    "role": "user",
    "content": prompt_text,
    "timestamp": timestamp,
    "trajectory_id": trajectory_id,
})

# Keep last 200 messages max
if len(history["messages"]) > 200:
    history["messages"] = history["messages"][-200:]

with open(history_file, "w") as f:
    json.dump(history, f, indent=2)

log(f"appended user prompt to history ({len(history['messages'])} total messages)")

# Also append to per-window history
if window_history_file:
    try:
        win_history = {"messages": [], "window": active_window}
        if os.path.exists(window_history_file):
            with open(window_history_file) as f:
                win_history = json.load(f)
            if "messages" not in win_history:
                win_history["messages"] = []

        win_history["messages"].append({
            "role": "user",
            "content": prompt_text,
            "timestamp": timestamp,
            "trajectory_id": trajectory_id,
        })

        if len(win_history["messages"]) > 200:
            win_history["messages"] = win_history["messages"][-200:]

        with open(window_history_file, "w") as f:
            json.dump(win_history, f, indent=2)

        log(f"appended user prompt to window history ({len(win_history['messages'])} total)")
    except Exception as win_err:
        log(f"window history append error: {win_err}")
PYEOF
fi

exit 0
