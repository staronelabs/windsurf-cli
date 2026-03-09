#!/usr/bin/env bash
# Cascade Hook: Logs full conversation transcripts with window context
# Fired AFTER Cascade completes a response (with full transcript)

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
LOG_DIR="$WSC_DIR/cascade-logs"
HOOK_LOG="$WSC_DIR/hook.log"

mkdir -p "$LOG_DIR"

# Read active window ID
ACTIVE_WINDOW=""
if [[ -f "$WSC_DIR/active-window.json" ]] && command -v python3 &>/dev/null; then
  ACTIVE_WINDOW=$(python3 -c "
import json
try:
    with open('$WSC_DIR/active-window.json') as f:
        print(json.load(f).get('windowId', ''))
except:
    pass
" 2>/dev/null || echo "")
fi

# Read JSON from stdin
export TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
cat > "$TMPFILE"

export WSC_DIR LOG_DIR ACTIVE_WINDOW

if command -v python3 &>/dev/null; then
  python3 << 'PYEOF'
import json, os, sys, shutil
from datetime import datetime

tmp = os.environ.get("TMPFILE", "")
wsc_dir = os.environ.get("WSC_DIR", os.path.expanduser("~/.windsurf-cli"))
log_dir = os.environ.get("LOG_DIR", "")
hook_log = os.path.join(wsc_dir, "hook.log")
active_window = os.environ.get("ACTIVE_WINDOW", "unknown")

def log(msg):
    with open(hook_log, "a") as f:
        f.write(f"{datetime.utcnow().isoformat()}Z [log-transcript] {msg}\n")

try:
    with open(tmp) as f:
        data = json.load(f)
    
    trajectory_id = data.get("trajectory_id", "unknown")
    timestamp = data.get("timestamp", datetime.utcnow().isoformat() + "Z")
    execution_id = data.get("execution_id", "")
    
    # Extract transcript path
    transcript_path = (data.get("tool_info") or {}).get("transcript_path", "")
    
    if not transcript_path or not os.path.exists(transcript_path):
        log(f"no transcript at {transcript_path}")
        sys.exit(0)
    
    log(f"window={active_window} trajectory={trajectory_id[:8]} transcript={transcript_path}")
    
    # Create per-window, per-conversation log file
    safe_window = active_window.replace("/", "_").replace("\\", "_")
    safe_trajectory = trajectory_id.replace("/", "_").replace("\\", "_")
    log_file = os.path.join(log_dir, f"{safe_window}_{safe_trajectory}.jsonl")
    
    # Copy the entire transcript to our log file
    # The transcript is already in JSONL format with full conversation history
    # We'll append a metadata entry first, then copy the transcript
    
    metadata = {
        "type": "transcript_update",
        "timestamp": timestamp,
        "trajectory_id": trajectory_id,
        "execution_id": execution_id,
        "window": active_window,
        "source_transcript": transcript_path,
    }
    
    with open(log_file, "a") as f:
        f.write(json.dumps(metadata) + "\n")
    
    # Append the full transcript content
    with open(transcript_path, "r") as src:
        with open(log_file, "a") as dst:
            for line in src:
                # Each line is already a complete JSON object
                dst.write(line)
    
    # Get file size for logging
    size = os.path.getsize(log_file)
    log(f"appended transcript to {log_file} (total size: {size} bytes)")

except Exception as e:
    log(f"error: {e}")
    import traceback
    log(traceback.format_exc())
    sys.exit(0)
PYEOF
fi

exit 0
