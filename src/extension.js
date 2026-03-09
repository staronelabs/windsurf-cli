const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const os = require("os");

const PROMPT_DIR_NAME = ".windsurf-cli";
const PROMPT_FILE = "prompt.json";
const RESPONSE_FILE = "response.json";
const STATUS_FILE = "status.json";
const MODELS_FILE = "models.json";
const WINDOWS_FILE = "windows.json";

let fileWatcher = null;
let statusBarItem = null;
let promptDir = "";
let isProcessing = false;
let log = null;
let windowId = "";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getPromptDir() {
  const config = vscode.workspace.getConfiguration("cascadeCli");
  const custom = config.get("promptDir");
  if (custom && custom.trim()) return custom.trim();
  return path.join(os.homedir(), PROMPT_DIR_NAME);
}

function getWorkspacePath() {
  const folders = vscode.workspace.workspaceFolders;
  return folders && folders.length > 0 ? folders[0].uri.fsPath : "";
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function getExtensionRoot() {
  return path.resolve(__dirname, "..");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function fileLog(msg) {
  try {
    const logPath = path.join(promptDir, "extension.log");
    const ts = new Date().toISOString();
    fs.appendFileSync(logPath, `${ts} [${windowId}] ${msg}\n`);
  } catch {
    // Non-critical
  }
}

function _log(msg) {
  if (log) log.appendLine(`[${windowId}] ${msg}`);
  fileLog(msg);
}

function formatError(err) {
  return String(err && (err.message || err) ? err.message || err : err).substring(0, 200);
}

function writeActiveWindow() {
  try {
    const activeWindowPath = path.join(promptDir, "active-window.json");
    fs.writeFileSync(activeWindowPath, JSON.stringify({
      windowId,
      workspace: getWorkspacePath(),
      pid: process.pid,
      timestamp: new Date().toISOString(),
    }, null, 2));
  } catch {
    // Non-critical
  }
}

function writeStatus(status, message) {
  const statusPath = path.join(promptDir, STATUS_FILE);
  const data = {
    status,
    message,
    timestamp: new Date().toISOString(),
    pid: process.pid,
    window: windowId,
  };
  fs.writeFileSync(statusPath, JSON.stringify(data, null, 2));
}

function writeModelsFile() {
  const modelsPath = path.join(promptDir, MODELS_FILE);
  const models = [
    "Claude Opus 4.6 Thinking",
    "Claude Sonnet 4.6 Thinking",
    "Claude Sonnet 4.5",
    "GPT-5.4",
    "GPT-5.3-Codex X-High",
    "SWE-1.5 Fast",
  ];
  fs.writeFileSync(modelsPath, JSON.stringify({ models }, null, 2));
}

// ---------------------------------------------------------------------------
// Window registry — lets the CLI discover and target specific windows
// ---------------------------------------------------------------------------

function registerWindow() {
  const wsPath = getWorkspacePath();
  windowId = wsPath ? path.basename(wsPath) : `pid-${process.pid}`;

  const registryPath = path.join(promptDir, WINDOWS_FILE);
  let registry = {};
  try {
    if (fs.existsSync(registryPath)) {
      registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
    }
  } catch {
    registry = {};
  }

  registry[windowId] = {
    workspace: wsPath,
    pid: process.pid,
    registeredAt: new Date().toISOString(),
  };

  fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2));
}

function shouldProcessPrompt(data) {
  // If no window specified in the prompt, use the FIRST registered window
  // (or the one whose workspace matches CWD)
  if (!data.window) {
    // Check if we're the first/primary window
    try {
      const registryPath = path.join(promptDir, WINDOWS_FILE);
      if (fs.existsSync(registryPath)) {
        const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
        const keys = Object.keys(registry);

        // If a workspace path was provided (from CLI CWD), match it
        if (data.workspace) {
          const wsPath = getWorkspacePath();
          if (wsPath && data.workspace.startsWith(wsPath)) {
            return true;
          }
          // Not our workspace
          return false;
        }

        // No workspace specified — only first registered window processes
        if (keys.length > 0 && keys[0] === windowId) {
          return true;
        }
        return false;
      }
    } catch {
      // Fall through
    }
    // If registry doesn't exist, process it (single window)
    return true;
  }

  // Window specified — match by name or workspace path
  const wsPath = getWorkspacePath();
  if (data.window === windowId) return true;
  if (wsPath && data.window === wsPath) return true;
  if (wsPath && wsPath.endsWith(data.window)) return true;

  return false;
}

// ---------------------------------------------------------------------------
// Conversation tracking — track CLI-opened Cascade conversations
// ---------------------------------------------------------------------------

const TABS_FILE = "tabs.json";
let conversations = []; // { id, openedAt, model, promptCount, lastPromptAt }
let currentConversationId = 0;

function recordNewConversation(model) {
  currentConversationId++;
  const conv = {
    id: currentConversationId,
    openedAt: new Date().toISOString(),
    model: model || "(default)",
    promptCount: 0,
    lastPromptAt: null,
  };
  conversations.push(conv);
  writeConversations();
  return conv;
}

function recordPromptSent() {
  if (conversations.length > 0) {
    const current = conversations[conversations.length - 1];
    current.promptCount++;
    current.lastPromptAt = new Date().toISOString();
    writeConversations();
  }
}

function writeConversations() {
  try {
    const data = {
      window: windowId,
      timestamp: new Date().toISOString(),
      activeConversation: conversations.length > 0 ? conversations[conversations.length - 1] : null,
      conversations,
    };
    fs.writeFileSync(path.join(promptDir, TABS_FILE), JSON.stringify(data, null, 2));
  } catch (e) {
    _log(`[conv] Error writing conversations: ${String(e.message || e).substring(0, 100)}`);
  }
}

// ---------------------------------------------------------------------------
// Auto-accept — automatically accept all Cascade changes after response
// ---------------------------------------------------------------------------

let autoAcceptWatcher = null;

function startAutoAcceptWatch() {
  const responsePath = path.join(promptDir, RESPONSE_FILE);

  // Stop any existing watcher
  if (autoAcceptWatcher) {
    autoAcceptWatcher.close();
    autoAcceptWatcher = null;
  }

  _log("[accept] Watching for response to auto-accept changes...");

  // Watch for response.json to be created/modified
  autoAcceptWatcher = fs.watch(promptDir, async (eventType, filename) => {
    if (filename === RESPONSE_FILE) {
      // Response received — stop watching
      if (autoAcceptWatcher) {
        autoAcceptWatcher.close();
        autoAcceptWatcher = null;
      }

      _log("[accept] Response detected, waiting for UI to render...");
      await sleep(2000); // wait for Accept buttons to appear

      await acceptAllChanges();
    }
  });

  // Auto-timeout after 5 minutes
  setTimeout(() => {
    if (autoAcceptWatcher) {
      autoAcceptWatcher.close();
      autoAcceptWatcher = null;
      _log("[accept] Timed out waiting for response");
    }
  }, 5 * 60 * 1000);
}

async function acceptAllChanges() {
  _log("[accept] Attempting to accept all changes...");

  if (process.platform === "darwin") {
    const appleScriptAccepted = await acceptAllChangesViaAppleScript();
    if (appleScriptAccepted) {
      _log("[accept] Auto-accept complete via AppleScript");
      return;
    }
    _log("[accept] AppleScript path did not confirm acceptance, falling back to commands");
  }

  const accepted = await acceptAllChangesViaCommands();
  if (accepted) {
    _log("[accept] Auto-accept complete via commands");
  } else {
    _log("[accept] No changes to accept (response may not have included code changes)");
  }
}

async function acceptAllChangesViaAppleScript() {
  _log("[accept] Trying AppleScript UI accept flow...");

  const script = `
    tell application "Windsurf"
      activate
    end tell
    delay 0.3

    tell application "System Events"
      tell process "Windsurf"
        set frontmost to true

        repeat with passNumber from 1 to 8
          set clickedSomething to false

          try
            set acceptAllButtons to (every button of entire contents of window 1 whose name is "Accept all")
            if (count of acceptAllButtons) > 0 then
              set bestButton to item 1 of acceptAllButtons
              set bestX to 0
              repeat with b in acceptAllButtons
                try
                  set p to position of b
                  if item 1 of p ≥ bestX then
                    set bestX to item 1 of p
                    set bestButton to b
                  end if
                end try
              end repeat
              click bestButton
              set clickedSomething to true
              delay 0.2
            end if
          end try

          if clickedSomething is false then
            try
              set acceptAllButtonsAlt to (every button of entire contents of window 1 whose name is "Accept All")
              if (count of acceptAllButtonsAlt) > 0 then
                set bestButtonAlt to item 1 of acceptAllButtonsAlt
                set bestXAlt to 0
                repeat with b in acceptAllButtonsAlt
                  try
                    set p to position of b
                    if item 1 of p ≥ bestXAlt then
                      set bestXAlt to item 1 of p
                      set bestButtonAlt to b
                    end if
                  end try
                end repeat
                click bestButtonAlt
                set clickedSomething to true
                delay 0.2
              end if
            end try
          end if

          if clickedSomething is false then
            exit repeat
          end if

          delay 0.5
        end repeat
      end tell
    end tell
  `;

  return await _runAppleScript(script, null, "accept-all");
}

async function clickAcceptAllOnce() {
  _log("[accept] Trying screenshot-based detect+click for Cascade panel Accept all...");

  const result = await detectAndClickBlueButton();
  if (result && result.clicked) {
    _log(`[accept] Blue button clicked at ${result.x},${result.y} (${result.bluePixels} blue pixels)`);
    return true;
  }
  if (result && result.found) {
    _log(`[accept] Blue button found at ${result.x},${result.y} but CGEvent click failed`);
  } else {
    _log(`[accept] Blue button not detected — no click performed`);
  }
  return false;
}

async function detectAndClickBlueButton() {
  if (process.platform !== "darwin") {
    return null;
  }

  const helperPath = path.join(getExtensionRoot(), "bin", "detect_blue_button.py");
  if (!fs.existsSync(helperPath)) {
    _log(`[accept] Blue-button helper missing: ${helperPath}`);
    return null;
  }

  return new Promise((resolve) => {
    const { execFile } = require("child_process");
    execFile(
      "python3",
      [helperPath],
      {
        env: {
          ...process.env,
          APP_NAME: "Windsurf",
          CLICK: "1",
          CAPTURE_W: "420",
          CAPTURE_H: "180",
        },
        timeout: 15000,
      },
      (err, stdout, stderr) => {
        if (err) {
          _log(`[accept] Blue-button helper failed: ${String(stderr || err.message || err).substring(0, 200)}`);
          resolve(null);
          return;
        }

        try {
          const parsed = JSON.parse(stdout || "{}");
          if (parsed.ok) {
            resolve({
              found: true,
              clicked: !!parsed.clicked,
              x: parsed.clickX,
              y: parsed.clickY,
              bluePixels: parsed.bluePixels || 0,
            });
            return;
          }
          _log(`[accept] Blue-button helper: ${parsed.error || "not found"} (${parsed.bluePixels || 0} blue px)`);
        } catch (parseErr) {
          _log(`[accept] Blue-button helper parse error: ${String(parseErr.message || parseErr).substring(0, 200)}`);
        }
        resolve(null);
      }
    );
  });
}

async function acceptAllChangesViaCommands() {
  // Try multiple accept commands — some may not apply but that's fine
  const acceptCommands = [
    "windsurf.cascade.acceptCascadeStep",
    "windsurf.prioritized.cascadeAcceptAllInFile",
    "windsurf.command.accept",
  ];

  let accepted = false;
  for (const cmd of acceptCommands) {
    try {
      await vscode.commands.executeCommand(cmd);
      _log(`[accept] OK: ${cmd}`);
      accepted = true;
    } catch (e) {
      _log(`[accept] SKIP: ${cmd} — ${String(e.message || e).substring(0, 80)}`);
    }
  }

  if (accepted) {
    for (let i = 0; i < 5; i++) {
      await sleep(500);
      try {
        await vscode.commands.executeCommand("windsurf.cascade.acceptCascadeStep");
        _log(`[accept] OK: acceptCascadeStep (pass ${i + 2})`);
      } catch {
        break;
      }
    }
  }

  return accepted;
}

async function openNewWindow(dirPath) {
  _log(`[window] Opening new window at: ${dirPath}`);
  try {
    const uri = vscode.Uri.file(dirPath);
    await vscode.commands.executeCommand("vscode.openFolder", uri, { forceNewWindow: true });
    _log(`[window] OK: opened new window at ${dirPath}`);
    return true;
  } catch (err) {
    _log(`[window] FAIL: vscode.openFolder — ${formatError(err)}`);
    return false;
  }
}

async function executeArbitraryCommand(commandId, args) {
  _log(`[command] Executing: ${commandId} args=${JSON.stringify(args || [])}`);

  if (commandId === "cascadeCli.acceptAllOnce") {
    const success = await clickAcceptAllOnce();
    if (success) {
      _log("[command] OK: cascadeCli.acceptAllOnce");
      return { success: true, result: { clicked: true } };
    }
    _log("[command] FAIL: cascadeCli.acceptAllOnce — Accept all button not found or AppleScript failed");
    return { success: false, error: "Accept all button not found or AppleScript failed" };
  }

  try {
    const normalizedArgs = Array.isArray(args) ? args : [];
    const result = await vscode.commands.executeCommand(commandId, ...normalizedArgs);
    _log(`[command] OK: ${commandId}`);
    return { success: true, result };
  } catch (err) {
    const message = formatError(err);
    _log(`[command] FAIL: ${commandId} — ${message}`);
    return { success: false, error: message };
  }
}

// ---------------------------------------------------------------------------
// Send strategies
// ---------------------------------------------------------------------------

// Track whether we've opened a Cascade conversation in this session
let cascadeSessionActive = false;

async function focusCascadeAndSend(promptText, model, newConversation, autoAccept, modelOnly) {
  if (modelOnly) {
    _log(`[send] MODEL-ONLY: model=${model || "(none)"}`);
  } else {
    _log(`[send] prompt="${promptText.substring(0, 80)}..." model=${model || "(default)"} new=${!!newConversation} sessionActive=${cascadeSessionActive}`);
  }

  const wantNew = !modelOnly && (newConversation || !cascadeSessionActive);

  if (process.platform === "darwin") {
    // Phase 1: Open/focus Cascade and get input focused
    let focusOk;
    if (modelOnly) {
      // Model-only: just ensure panel is open
      focusOk = cascadeSessionActive ? await focusExistingCascade() : await openNewCascade();
    } else if (wantNew) {
      focusOk = await openNewCascade();
    } else {
      focusOk = await focusExistingCascade();
    }

    if (!focusOk) {
      _log("[send] Focus failed, aborting");
      return false;
    }

    // Track new conversations
    if (wantNew) {
      recordNewConversation(model);
    }

    // Phase 2: Select model (if specified) — AFTER Cascade is open
    if (model) {
      await selectModel(model);
    }

    // Model-only mode: done after selecting model
    if (modelOnly) {
      cascadeSessionActive = true;
      _log("[send] Model-only: selection complete");
      return true;
    }

    // Phase 3: Paste prompt + submit
    const result = await pasteAndSubmit(promptText);
    if (result) {
      cascadeSessionActive = true;
      recordPromptSent();

      // Start auto-accept watcher if requested
      if (autoAccept) {
        startAutoAcceptWatch();
      }
    }
    return result;
  }

  // Non-macOS fallback
  return await tryProgrammaticSend(promptText);
}

// Focus the correct Windsurf window by windowId before sending keystrokes.
// Uses System Events (reliable) instead of tell application "Windsurf" (not scriptable).
async function focusCorrectWindow() {
  const escapedWinId = windowId.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const script = `
    tell application "System Events"
      tell process "Windsurf"
        set targetFound to false
        set winNames to {}
        set winCount to count of windows
        repeat with i from 1 to winCount
          set wName to name of window i
          set end of winNames to wName
          if wName contains "${escapedWinId}" then
            -- Perform AXRaise to bring this window to front
            perform action "AXRaise" of window i
            set targetFound to true
            exit repeat
          end if
        end repeat
        set frontmost to true
      end tell
    end tell
    tell application "Windsurf" to activate
    delay 0.3
    return "targetFound:" & (targetFound as string) & "|count:" & (winCount as string)
  `;
  
  const result = await runAppleScriptForOutput(script, "focus-window");
  _log(`[focus] Window targeting result: ${result}`);
  
  if (result && result.includes("targetFound:true")) {
    _log(`[focus] Correct window focused: ${windowId}`);
    return true;
  } else {
    _log(`[focus] WARNING: Could not find window containing "${windowId}". Result: ${result}`);
    // Fallback: just activate Windsurf (better than nothing)
    await _runAppleScript(`tell application "Windsurf" to activate\ndelay 0.3`, null, "focus-fallback");
    return false;
  }
}

// Phase 1a: Open NEW Cascade conversation via Cmd+Shift+L (proven to focus input)
async function openNewCascade() {
  _log("[focus] Opening new conversation via Cmd+Shift+L");

  // Ensure correct window has OS focus first
  await focusCorrectWindow();

  const script = `
    tell application "System Events"
      keystroke "l" using {command down, shift down}
    end tell
  `;
  const ok = await _runAppleScript(script, null, "open-new");
  if (ok) await sleep(800); // wait for panel to fully open
  return ok;
}

// Phase 1b: Focus EXISTING Cascade conversation
async function focusExistingCascade() {
  _log("[focus] Focusing existing conversation");

  // First ensure panel is visible via VS Code API
  try {
    await vscode.commands.executeCommand("windsurf.cascadePanel.focus");
    _log("[focus] OK: cascadePanel.focus (panel visible)");
  } catch (e) {
    _log(`[focus] FAIL: cascadePanel.focus — ${String(e.message || e).substring(0, 100)}`);
  }
  await sleep(200);

  // Then use prioritized.chat.open via VS Code API to focus the INPUT
  // (API calls typically don't toggle like keyboard shortcuts do)
  try {
    await vscode.commands.executeCommand("windsurf.prioritized.chat.open");
    _log("[focus] OK: prioritized.chat.open (input focused)");
    await sleep(400);
    return true;
  } catch (e) {
    _log(`[focus] FAIL: prioritized.chat.open — ${String(e.message || e).substring(0, 100)}`);
  }

  // Fallback: use Cmd+Shift+L (creates new tab but at least works)
  _log("[focus] Falling back to Cmd+Shift+L");
  return await openNewCascade();
}

// Phase 2: Select model AFTER Cascade panel is open and focused
async function selectModel(model) {
  _log(`[model] Selecting: ${model}`);

  // Step 1: Toggle the model selector dropdown via VS Code API
  // (API always runs in the correct window's extension host — no OS focus needed)
  try {
    await vscode.commands.executeCommand("windsurf.cascade.toggleModelSelector");
    _log("[model] OK: toggleModelSelector opened");
  } catch (e) {
    _log(`[model] FAIL: toggleModelSelector — ${String(e.message || e).substring(0, 100)}`);
    _log("[model] Model selection unavailable — using current default");
    return;
  }

  await sleep(400); // wait for dropdown to start rendering

  // Step 2: NOW focus the correct window at OS level so keystrokes go there
  await focusCorrectWindow();
  await sleep(300); // let OS focus settle

  // Step 3: Type model name to filter, arrow down to highlight, Enter to select
  const escaped = model.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const typeScript = `
    tell application "System Events"
      tell process "Windsurf"
        -- Type model name to filter the dropdown
        keystroke "${escaped}"
        delay 0.5

        -- Down arrow to highlight the first filtered result
        key code 125
        delay 0.2

        -- Enter to confirm selection
        key code 36
      end tell
    end tell
  `;
  await _runAppleScript(typeScript, null, "model-select");
  await sleep(400);
  _log(`[model] Selected: ${model}`);
}

// Phase 3: Paste prompt text and submit with Enter
async function pasteAndSubmit(promptText) {
  const tmpFile = path.join(os.tmpdir(), "wsc-prompt.txt");
  fs.writeFileSync(tmpFile, promptText);

  // Ensure correct window has OS focus before pasting
  await focusCorrectWindow();

  const script = `
    set oldClip to the clipboard
    set promptText to (read POSIX file "${tmpFile}")
    set the clipboard to promptText

    tell application "System Events"
      -- Paste prompt into the focused Cascade input
      keystroke "v" using command down
      delay 0.3

      -- Submit with Enter
      key code 36
    end tell

    delay 0.2
    set the clipboard to oldClip
  `;

  return await _runAppleScript(script, tmpFile, "paste-submit");
}

async function tryProgrammaticSend(promptText) {
  const strategies = [
    { name: "sendChatActionMessage", cmd: "windsurf.sendChatActionMessage", args: { text: promptText } },
    { name: "executeCascadeAction", cmd: "windsurf.executeCascadeAction", args: { text: promptText } },
  ];
  for (const { name, cmd, args } of strategies) {
    try {
      await vscode.commands.executeCommand(cmd, args);
      _log(`[send] OK: ${name}`);
      return true;
    } catch (e) {
      _log(`[send] FAIL: ${name} — ${String(e.message || e).substring(0, 120)}`);
    }
  }
  return false;
}

// Helper to run AppleScript via temp file
async function _runAppleScript(script, tmpFileToClean, label) {
  const { exec } = require("child_process");
  const scriptFile = path.join(os.tmpdir(), "wsc-send.scpt");
  fs.writeFileSync(scriptFile, script);

  return new Promise((resolve) => {
    exec(`osascript "${scriptFile}"`, (err, stdout, stderr) => {
      try { fs.unlinkSync(scriptFile); } catch {}
      if (tmpFileToClean) { try { fs.unlinkSync(tmpFileToClean); } catch {} }
      if (err) {
        _log(`[applescript:${label}] FAIL: ${String(stderr || err.message || err).substring(0, 200)}`);
        resolve(false);
      } else {
        _log(`[applescript:${label}] OK`);
        resolve(true);
      }
    });
  });
}

async function runAppleScriptForOutput(script, label) {
  const { exec } = require("child_process");
  const scriptFile = path.join(os.tmpdir(), "wsc-output.scpt");
  fs.writeFileSync(scriptFile, script);

  return new Promise((resolve) => {
    exec(`osascript "${scriptFile}"`, (err, stdout, stderr) => {
      try { fs.unlinkSync(scriptFile); } catch {}
      if (err) {
        _log(`[applescript:${label}] FAIL: ${String(stderr || err.message || err).substring(0, 200)}`);
        resolve(null);
      } else {
        _log(`[applescript:${label}] OK`);
        resolve(String(stdout || "").trim());
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Prompt file processing
// ---------------------------------------------------------------------------

async function processPromptFile() {
  if (isProcessing) return;

  const promptPath = path.join(promptDir, PROMPT_FILE);
  if (!fs.existsSync(promptPath)) return;

  let data;
  try {
    const raw = fs.readFileSync(promptPath, "utf8");
    data = JSON.parse(raw);
  } catch (err) {
    _log(`[process] Parse error: ${err.message}`);
    writeStatus("error", `Failed to parse prompt file: ${err.message}`);
    return;
  }

  if ((!data.prompt && !data.modelOnly && !data.command && !data.openWindow) || data.processed) return;

  // Handle openWindow action — open a new Windsurf window at the specified directory
  if (data.openWindow) {
    if (!shouldProcessPrompt(data)) {
      _log(`[process] Skipping openWindow — not our target`);
      return;
    }
    isProcessing = true;
    _log(`[process] Opening new window at: ${data.openWindow}`);
    writeStatus("processing", `Opening new window at ${data.openWindow}...`);
    statusBarItem.text = "$(loading~spin) Cascade CLI: Opening window...";
    try {
      const success = await openNewWindow(data.openWindow);
      data.processed = true;
      data.processedAt = new Date().toISOString();
      data.processedBy = windowId;
      data.success = success;
      fs.writeFileSync(promptPath, JSON.stringify(data, null, 2));
      if (success) {
        writeStatus("sent", `New window opened at ${data.openWindow}`);
        statusBarItem.text = "$(check) Cascade CLI: Window opened";
      } else {
        writeStatus("error", `Failed to open window at ${data.openWindow}`);
        statusBarItem.text = "$(error) Cascade CLI: Failed";
      }
    } catch (err) {
      _log(`[process] openWindow error: ${err.message}`);
      writeStatus("error", err.message);
      statusBarItem.text = "$(error) Cascade CLI: Error";
    } finally {
      isProcessing = false;
      setTimeout(() => { statusBarItem.text = "$(terminal) Cascade CLI: Watching"; }, 3000);
    }
    return;
  }

  // Window targeting — skip if this prompt is for a different window
  if (!shouldProcessPrompt(data)) {
    _log(`[process] Skipping — prompt targets window="${data.window || "(default)"}", workspace="${data.workspace || ""}", we are "${windowId}"`);
    return;
  }

  isProcessing = true;
  const action = data.command ? `command ${data.command}` : (data.modelOnly ? "model selection" : "prompt");
  _log(`[process] Processing ${action} from ${data.source || "unknown"}`);
  writeStatus("processing", data.command ? `Executing command ${data.command}...` : (data.modelOnly ? "Selecting model..." : "Sending prompt to Cascade..."));

  // Write active-window marker so hooks can write per-window files
  writeActiveWindow();

  statusBarItem.text = "$(loading~spin) Cascade CLI: Sending...";

  try {
    let success;
    let commandResult;
    if (data.command) {
      commandResult = await executeArbitraryCommand(data.command, data.args);
      success = commandResult.success;
    } else {
      success = await focusCascadeAndSend(
        data.prompt || "", data.model, data.newConversation,
        data.autoAccept, data.modelOnly
      );
    }

    // Mark as processed
    data.processed = true;
    data.processedAt = new Date().toISOString();
    data.processedBy = windowId;
    data.success = success;
    if (data.command) {
      if (commandResult && commandResult.error) {
        data.error = commandResult.error;
      }
      if (commandResult && commandResult.result !== undefined) {
        data.result = commandResult.result;
      }
    }
    fs.writeFileSync(promptPath, JSON.stringify(data, null, 2));

    if (success) {
      _log(`[process] ${data.command ? "Command executed" : "Prompt sent"} successfully`);
      writeStatus("sent", data.command ? `Command executed: ${data.command}` : "Prompt sent to Cascade successfully");
      statusBarItem.text = "$(check) Cascade CLI: Sent";
      vscode.window.showInformationMessage(
        data.command
          ? `Cascade CLI: Command executed: ${data.command}`
          : `Cascade CLI: Prompt sent${data.model ? ` (model: ${data.model})` : ""}`
      );
    } else {
      _log("[process] All strategies failed");
      writeStatus("error", data.command ? `Failed to execute command: ${data.command}` : "Failed to send prompt to Cascade");
      statusBarItem.text = "$(error) Cascade CLI: Failed";
      vscode.window.showErrorMessage(
        data.command
          ? `Cascade CLI: Could not execute command ${data.command} — check wsc -L for details`
          : "Cascade CLI: Could not send prompt — check wsc -L for details"
      );
    }
  } catch (err) {
    _log(`[process] Error: ${err.message}`);
    writeStatus("error", err.message);
    statusBarItem.text = "$(error) Cascade CLI: Error";
  } finally {
    isProcessing = false;
    setTimeout(() => {
      statusBarItem.text = "$(terminal) Cascade CLI: Watching";
    }, 3000);
  }
}

// ---------------------------------------------------------------------------
// File watcher
// ---------------------------------------------------------------------------

function startWatching(context) {
  if (fileWatcher) {
    return;
  }

  promptDir = getPromptDir();
  ensureDir(promptDir);
  writeModelsFile();
  registerWindow();
  writeStatus("watching", `Extension watching (window: ${windowId})`);

  // Use fs.watch for file changes
  fileWatcher = fs.watch(promptDir, (eventType, filename) => {
    if (filename === PROMPT_FILE) {
      setTimeout(() => processPromptFile(), 150);
    }
  });

  statusBarItem.text = `$(terminal) wsc: ${windowId}`;
  statusBarItem.show();

  _log(`[watch] Started watching`);
}

function stopWatching() {
  if (fileWatcher) {
    fileWatcher.close();
    fileWatcher = null;
    writeStatus("stopped", "Extension stopped watching");
    statusBarItem.text = "$(circle-slash) Cascade CLI: Stopped";
  }
}

// ---------------------------------------------------------------------------
// Activation
// ---------------------------------------------------------------------------

function activate(context) {
  promptDir = getPromptDir();
  ensureDir(promptDir);

  // Output channel for diagnostics (View > Output > "Cascade CLI")
  log = vscode.window.createOutputChannel("Cascade CLI");
  context.subscriptions.push(log);

  const wsPath = getWorkspacePath();
  windowId = wsPath ? path.basename(wsPath) : `pid-${process.pid}`;

  _log(`[init] activated — workspace="${wsPath}" windowId="${windowId}"`);

  // Status bar — shows which window this is
  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Left,
    100
  );
  statusBarItem.command = "cascadeCli.showStatus";
  statusBarItem.text = `$(terminal) wsc: ${windowId}`;
  context.subscriptions.push(statusBarItem);

  // Commands
  context.subscriptions.push(
    vscode.commands.registerCommand("cascadeCli.sendPrompt", async () => {
      const prompt = await vscode.window.showInputBox({
        prompt: "Enter prompt for Cascade",
        placeHolder: "What would you like Cascade to do?",
      });
      if (prompt) {
        const data = {
          prompt,
          window: windowId,
          timestamp: new Date().toISOString(),
          source: "command-palette",
        };
        fs.writeFileSync(
          path.join(promptDir, PROMPT_FILE),
          JSON.stringify(data, null, 2)
        );
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("cascadeCli.executeCommand", async () => {
      const commandId = await vscode.window.showInputBox({
        prompt: "Enter command ID to execute",
        placeHolder: "windsurf.cascadePanel.focus",
      });
      if (!commandId) {
        return;
      }

      const rawArgs = await vscode.window.showInputBox({
        prompt: "Enter optional JSON array of command arguments",
        placeHolder: "[]",
        value: "[]",
      });
      if (rawArgs === undefined) {
        return;
      }

      let args;
      try {
        args = rawArgs.trim() ? JSON.parse(rawArgs) : [];
      } catch (err) {
        vscode.window.showErrorMessage(`Cascade CLI: Invalid JSON args — ${formatError(err)}`);
        return;
      }

      if (!Array.isArray(args)) {
        vscode.window.showErrorMessage("Cascade CLI: Command args must be a JSON array");
        return;
      }

      const data = {
        command: commandId,
        args,
        window: windowId,
        timestamp: new Date().toISOString(),
        source: "command-palette",
      };
      fs.writeFileSync(
        path.join(promptDir, PROMPT_FILE),
        JSON.stringify(data, null, 2)
      );
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("cascadeCli.openNewWindow", async (dirPath) => {
      if (!dirPath) {
        const input = await vscode.window.showInputBox({
          prompt: "Enter directory path for new window",
          placeHolder: "/path/to/project",
        });
        if (!input) return;
        dirPath = input;
      }
      await openNewWindow(dirPath);
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("cascadeCli.startWatching", () =>
      startWatching(context)
    )
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("cascadeCli.stopWatching", () =>
      stopWatching()
    )
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("cascadeCli.showStatus", () => {
      const statusPath = path.join(promptDir, STATUS_FILE);
      if (fs.existsSync(statusPath)) {
        const data = JSON.parse(fs.readFileSync(statusPath, "utf8"));
        vscode.window.showInformationMessage(
          `Cascade CLI [${windowId}]: ${data.status} — ${data.message}`
        );
      } else {
        vscode.window.showInformationMessage(
          `Cascade CLI [${windowId}]: No status available`
        );
      }
    })
  );

  // Write active-window on activation and whenever this window gains focus
  // so hooks (pre_user_prompt, post_cascade_response) know which window is active
  writeActiveWindow();
  context.subscriptions.push(
    vscode.window.onDidChangeWindowState((state) => {
      if (state.focused) {
        writeActiveWindow();
        _log("[focus] Window focused — updated active-window.json");
      }
    })
  );

  // Auto-start if configured
  const config = vscode.workspace.getConfiguration("cascadeCli");
  if (config.get("autoStart")) {
    startWatching(context);
  }

  // Discover commands for debugging
  discoverCascadeCommands();
}

async function discoverCascadeCommands() {
  try {
    const allCommands = await vscode.commands.getCommands(true);
    const cascadeCommands = allCommands.filter(
      (cmd) =>
        cmd.toLowerCase().includes("cascade") ||
        cmd.toLowerCase().includes("windsurf")
    );
    if (cascadeCommands.length > 0) {
      const commandsPath = path.join(promptDir, "available-commands.json");
      fs.writeFileSync(
        commandsPath,
        JSON.stringify({ commands: cascadeCommands }, null, 2)
      );
    }
  } catch {
    // Silent fail
  }
}

function deactivate() {
  // Unregister window
  try {
    const registryPath = path.join(promptDir, WINDOWS_FILE);
    if (fs.existsSync(registryPath)) {
      const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
      delete registry[windowId];
      fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2));
    }
  } catch {
    // Non-critical
  }
  stopWatching();
  if (statusBarItem) statusBarItem.dispose();
}

module.exports = { activate, deactivate };
