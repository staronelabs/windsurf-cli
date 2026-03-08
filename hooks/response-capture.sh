#!/usr/bin/env bash
# Cascade Hook: Captures post_cascade_response and writes to response file
# Used by wsc CLI's --wait flag to retrieve Cascade responses

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
RESPONSE_FILE="$WSC_DIR/response.json"
STATUS_FILE="$WSC_DIR/status.json"
HOOK_LOG="$WSC_DIR/hook.log"

mkdir -p "$WSC_DIR"

# Debug: log every invocation
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [hook] invoked" >> "$HOOK_LOG"

# Read JSON from stdin (Cascade hook input) into a temp file
export TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
cat > "$TMPFILE"

# Debug: log raw input size and first 500 chars
INPUT_SIZE=$(wc -c < "$TMPFILE" | tr -d ' ')
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [hook] stdin bytes=$INPUT_SIZE" >> "$HOOK_LOG"
head -c 500 "$TMPFILE" >> "$HOOK_LOG"
echo "" >> "$HOOK_LOG"

# Also save the full raw input for inspection
cp "$TMPFILE" "$WSC_DIR/hook-last-input.json"

export WSC_DIR

if command -v python3 &>/dev/null; then
  python3 << 'PYEOF'
import json, os, sys
from datetime import datetime

tmp = os.environ.get("TMPFILE", "")
wsc_dir = os.environ.get("WSC_DIR", os.path.expanduser("~/.windsurf-cli"))
response_file = os.path.join(wsc_dir, "response.json")
status_file = os.path.join(wsc_dir, "status.json")
hook_log = os.path.join(wsc_dir, "hook.log")

def log(msg):
    with open(hook_log, "a") as f:
        f.write(f"{datetime.utcnow().isoformat()}Z [hook-py] {msg}\n")

try:
    with open(tmp) as f:
        raw = f.read()
    log(f"raw length={len(raw)}")

    if not raw.strip():
        log("empty input, exiting")
        sys.exit(0)

    data = json.loads(raw)
    log(f"parsed JSON, top-level keys={list(data.keys())}")

    # Dump all top-level keys and their types/preview for debugging
    for k, v in data.items():
        preview = str(v)[:200]
        log(f"  key={k} type={type(v).__name__} preview={preview}")

except Exception as e:
    log(f"parse error: {e}")
    sys.exit(0)

# Try multiple paths to find the response text
response_text = ""

# Path 1: tool_info.response (documented)
if not response_text:
    response_text = (data.get("tool_info") or {}).get("response", "")
    if response_text:
        log(f"found response at tool_info.response ({len(response_text)} chars)")

# Path 2: response (direct key)
if not response_text:
    response_text = data.get("response", "")
    if response_text:
        log(f"found response at .response ({len(response_text)} chars)")

# Path 3: output (direct key)
if not response_text:
    response_text = data.get("output", "")
    if response_text:
        log(f"found response at .output ({len(response_text)} chars)")

# Path 4: result (direct key)
if not response_text:
    response_text = data.get("result", "")
    if response_text:
        log(f"found response at .result ({len(response_text)} chars)")

# Path 5: content (direct key)
if not response_text:
    response_text = data.get("content", "")
    if response_text:
        log(f"found response at .content ({len(response_text)} chars)")

# Path 6: text (direct key)
if not response_text:
    response_text = data.get("text", "")
    if response_text:
        log(f"found response at .text ({len(response_text)} chars)")

# Path 7: Walk nested dicts looking for any string > 50 chars
if not response_text:
    def find_long_string(obj, path=""):
        if isinstance(obj, str) and len(obj) > 50:
            return path, obj
        if isinstance(obj, dict):
            for k2, v2 in obj.items():
                result = find_long_string(v2, f"{path}.{k2}")
                if result:
                    return result
        if isinstance(obj, list):
            for i, v2 in enumerate(obj):
                result = find_long_string(v2, f"{path}[{i}]")
                if result:
                    return result
        return None

    found = find_long_string(data)
    if found:
        found_path, found_text = found
        response_text = found_text
        log(f"found long string at {found_path} ({len(found_text)} chars)")

if not response_text:
    log("NO response text found in any path")
    # Still write the raw data so user can see what was received
    with open(response_file, "w") as f:
        json.dump({"raw": data, "note": "no response text found"}, f, indent=2)
    sys.exit(0)

trajectory_id = data.get("trajectory_id", "")
execution_id = data.get("execution_id", "")
timestamp = data.get("timestamp", datetime.utcnow().isoformat() + "Z")

output = {
    "response": response_text,
    "trajectory_id": trajectory_id,
    "execution_id": execution_id,
    "timestamp": timestamp,
}
with open(response_file, "w") as f:
    json.dump(output, f, indent=2)

log(f"wrote response to {response_file} ({len(response_text)} chars)")

status = {
    "status": "response_captured",
    "message": f"Response captured ({len(response_text)} chars)",
    "timestamp": timestamp,
}
with open(status_file, "w") as f:
    json.dump(status, f, indent=2)
PYEOF
else
  # Minimal fallback without python
  cp "$TMPFILE" "$RESPONSE_FILE"
fi

exit 0
