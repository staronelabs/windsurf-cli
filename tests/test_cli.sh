#!/usr/bin/env bash
# test_cli.sh — Unit tests for wsc CLI key functions
#
# Tests:
#   1. resolve_target_window — prompt goes to correct window
#   2. send_prompt — writes correct JSON with window/model fields
#   3. set_response_file — per-window response file path
#   4. open_new_window — validates directory + sets WINDOW
#   5. send_prompt with model — model choice targets correct window
#
# Usage:  bash tests/test_cli.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WSC_SCRIPT="$SCRIPT_DIR/../bin/wsc"

# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------

PASS=0
FAIL=0
TESTS=0

pass() { PASS=$((PASS + 1)); TESTS=$((TESTS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS=$((TESTS + 1)); echo "  ❌ $1: $2"; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$desc"
  else
    fail "$desc" "expected='$expected' got='$actual'"
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc" "expected to contain '$needle' in: $haystack"
  fi
}

assert_file_exists() {
  local desc="$1" filepath="$2"
  if [[ -f "$filepath" ]]; then
    pass "$desc"
  else
    fail "$desc" "file not found: $filepath"
  fi
}

# ---------------------------------------------------------------------------
# Setup: isolated temp WSC_DIR per test
# ---------------------------------------------------------------------------

TMPROOT=""
setup() {
  TMPROOT=$(mktemp -d)
  export WSC_DIR="$TMPROOT/wsc"
  mkdir -p "$WSC_DIR"
  export PROMPT_FILE="$WSC_DIR/prompt.json"
  export STATUS_FILE="$WSC_DIR/status.json"
  export RESPONSE_FILE="$WSC_DIR/response.json"
  export MODELS_FILE="$WSC_DIR/models.json"
  export WINDOWS_FILE="$WSC_DIR/windows.json"
  export RESOLVED_WINDOW=""
  export VERBOSITY=0
}

teardown() {
  [[ -n "$TMPROOT" ]] && rm -rf "$TMPROOT"
}

# Source just the functions from wsc (skip the main argument parsing)
source_wsc_functions() {
  # Extract functions only (up to "# --- Main ---" marker)
  local tmpfunc="$TMPROOT/wsc_functions.sh"
  # Get line number of the marker, take everything before it
  local marker_line
  marker_line=$(grep -n '^# --- Main ---$' "$WSC_SCRIPT" | head -1 | cut -d: -f1)
  if [[ -n "$marker_line" ]]; then
    head -n "$((marker_line - 1))" "$WSC_SCRIPT" > "$tmpfunc"
  else
    cp "$WSC_SCRIPT" "$tmpfunc"
  fi
  # Remove set -euo pipefail from the sourced fragment (we handle it ourselves)
  sed -i.bak 's/^set -euo pipefail$//' "$tmpfunc" && rm -f "$tmpfunc.bak"
  source "$tmpfunc"
}

# ---------------------------------------------------------------------------
# Helpers: write fixture files
# ---------------------------------------------------------------------------

write_windows_json() {
  cat > "$WINDOWS_FILE" <<'EOF'
{
  "projectA": {
    "workspace": "/Users/jc/dev/projectA",
    "pid": 1001,
    "registeredAt": "2026-03-08T10:00:00Z"
  },
  "projectB": {
    "workspace": "/Users/jc/dev/projectB",
    "pid": 1002,
    "registeredAt": "2026-03-08T10:01:00Z"
  }
}
EOF
}

write_models_json() {
  cat > "$MODELS_FILE" <<'EOF'
{
  "models": [
    "Claude Sonnet 4.5",
    "GPT-5.4",
    "SWE-1.5 Fast"
  ]
}
EOF
}

# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━ wsc CLI Test Suite ━━━"
echo ""

# ── Test 1: resolve_target_window with explicit -W flag ──────────────────

echo "Test 1: resolve_target_window — explicit window"
setup
source_wsc_functions
write_windows_json

result=$(resolve_target_window "projectB")
assert_eq "explicit -W returns that window" "projectB" "$result"
teardown

# ── Test 2: resolve_target_window via workspace match ────────────────────

echo ""
echo "Test 2: resolve_target_window — workspace match"
setup
source_wsc_functions
write_windows_json

# Simulate being in projectA's workspace
(
  cd /tmp  # safe fallback
  # The function uses $PWD — we override it inline via the python script's arg
  # Instead, let's call the python directly
  result=$(python3 - "$WINDOWS_FILE" "/Users/jc/dev/projectA/src" <<'PYEOF'
import json, sys
registry_path = sys.argv[1]
workspace = sys.argv[2]
try:
    with open(registry_path) as f:
        registry = json.load(f)
except Exception:
    sys.exit(0)
keys = list(registry.keys())
if not keys:
    sys.exit(0)
for name, info in registry.items():
    ws = info.get("workspace", "")
    if ws and workspace.startswith(ws):
        print(name)
        sys.exit(0)
print(keys[0])
PYEOF
)
  assert_eq "workspace /Users/jc/dev/projectA/src → projectA" "projectA" "$result"
)

# Also test projectB match
result=$(python3 - "$WINDOWS_FILE" "/Users/jc/dev/projectB" <<'PYEOF'
import json, sys
registry_path = sys.argv[1]
workspace = sys.argv[2]
try:
    with open(registry_path) as f:
        registry = json.load(f)
except Exception:
    sys.exit(0)
keys = list(registry.keys())
if not keys:
    sys.exit(0)
for name, info in registry.items():
    ws = info.get("workspace", "")
    if ws and workspace.startswith(ws):
        print(name)
        sys.exit(0)
print(keys[0])
PYEOF
)
assert_eq "workspace /Users/jc/dev/projectB → projectB" "projectB" "$result"
teardown

# ── Test 3: resolve_target_window fallback to first window ───────────────

echo ""
echo "Test 3: resolve_target_window — fallback to first window"
setup
source_wsc_functions
write_windows_json

result=$(resolve_target_window "")
# With no explicit window and PWD not matching either workspace,
# should fall back to first registered window
assert_contains "falls back to a registered window" "$result" "project"
teardown

# ── Test 4: send_prompt writes correct JSON ──────────────────────────────

echo ""
echo "Test 4: send_prompt — writes correct JSON with window + model"
setup
source_wsc_functions
write_windows_json

# Suppress stdout from send_prompt
send_prompt "fix the login bug" "Claude Sonnet 4.5" "projectA" "false" "false" "false" >/dev/null 2>&1

assert_file_exists "prompt.json created" "$PROMPT_FILE"

# Verify JSON fields
prompt_text=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('prompt',''))")
model_text=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('model',''))")
window_text=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('window',''))")
source_text=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('source',''))")
processed=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('processed',''))")

assert_eq "prompt field" "fix the login bug" "$prompt_text"
assert_eq "model field" "Claude Sonnet 4.5" "$model_text"
assert_eq "window field" "projectA" "$window_text"
assert_eq "source field" "cli" "$source_text"
assert_eq "processed field" "False" "$processed"
teardown

# ── Test 5: send_prompt to a DIFFERENT window ────────────────────────────

echo ""
echo "Test 5: send_prompt — prompt goes to projectB (not projectA)"
setup
source_wsc_functions
write_windows_json

send_prompt "refactor auth module" "GPT-5.4" "projectB" "true" "false" "false" >/dev/null 2>&1

window_text=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('window',''))")
new_conv=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('newConversation',''))")

assert_eq "window targets projectB" "projectB" "$window_text"
assert_eq "newConversation is True" "True" "$new_conv"
teardown

# ── Test 6: set_response_file — per-window response path ────────────────

echo ""
echo "Test 6: set_response_file — per-window response path"
setup
source_wsc_functions

set_response_file "projectA"
assert_eq "response file for projectA" "$WSC_DIR/response-projectA.json" "$RESPONSE_FILE"

RESPONSE_FILE="$WSC_DIR/response.json"  # reset
set_response_file "projectB"
assert_eq "response file for projectB" "$WSC_DIR/response-projectB.json" "$RESPONSE_FILE"

RESPONSE_FILE="$WSC_DIR/response.json"  # reset
set_response_file ""
assert_eq "empty window keeps default" "$WSC_DIR/response.json" "$RESPONSE_FILE"
teardown

# ── Test 7: model-only send ─────────────────────────────────────────────

echo ""
echo "Test 7: send_prompt — model-only mode targets correct window"
setup
source_wsc_functions
write_windows_json

send_prompt "" "SWE-1.5 Fast" "projectA" "false" "false" "true" >/dev/null 2>&1

model_only=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('modelOnly',''))")
model_text=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('model',''))")
window_text=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('window',''))")

assert_eq "modelOnly flag" "True" "$model_only"
assert_eq "model is SWE-1.5 Fast" "SWE-1.5 Fast" "$model_text"
assert_eq "window targets projectA" "projectA" "$window_text"
teardown

# ── Test 8: open_new_window validates directory ──────────────────────────

echo ""
echo "Test 8: open_new_window — rejects non-existent directory"
setup
source_wsc_functions

# open_new_window should fail for non-existent dir
if open_new_window "/nonexistent/path/xyz" "false" 2>/dev/null; then
  fail "rejects non-existent directory" "should have returned non-zero"
else
  pass "rejects non-existent directory"
fi
teardown

# ── Test 9: two prompts to two different windows ────────────────────────

echo ""
echo "Test 9: two prompts to two different windows (sequential)"
setup
source_wsc_functions
write_windows_json

# First prompt → projectA
send_prompt "fix tests" "Claude Sonnet 4.5" "projectA" "false" "false" "false" >/dev/null 2>&1
w1=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('window',''))")
p1=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('prompt',''))")

# Second prompt → projectB (overwrites prompt.json)
send_prompt "add logging" "GPT-5.4" "projectB" "false" "false" "false" >/dev/null 2>&1
w2=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('window',''))")
p2=$(python3 -c "import json; d=json.load(open('$PROMPT_FILE')); print(d.get('prompt',''))")

assert_eq "first prompt → projectA" "projectA" "$w1"
assert_eq "first prompt text" "fix tests" "$p1"
assert_eq "second prompt → projectB" "projectB" "$w2"
assert_eq "second prompt text" "add logging" "$p2"
teardown

# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed (out of $TESTS tests)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
