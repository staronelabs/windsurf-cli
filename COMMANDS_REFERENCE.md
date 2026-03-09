# Cascade and Windsurf Command Reference

This document describes the following command IDs as they relate to this repository and the installed Windsurf environment:

- `cascadeCli.sendPrompt`
- `cascadeCli.executeCommand`
- `cascadeCli.startWatching`
- `cascadeCli.stopWatching`
- `cascadeCli.openNewWindow`
- `cascadeCli.showStatus`
- `windsurf.sendTextToChat`
- `windsurf.triggerCascade`
- `windsurf.openCascade`
- `windsurf.cascadePanel.open`
- `windsurf.addCurrentFileToChat`
- `windsurf.cascadePanel.focus`
- `windsurf.prioritized.chat.open`
- `windsurf.cascade.resetCurrentConversation`
- `windsurf.cascade.openAgentPicker`
- `windsurf.cascade.toggleModelSelector`

## Scope and Verification Status

This repo contains a custom extension and CLI bridge that interacts with built-in Windsurf commands.

For accuracy, each command below is classified as one of:

- **Implemented here**
  The command is registered by this repo and its behavior is directly visible in source.

- **Observed and invoked here**
  The command is not implemented in this repo, but this repo calls it via `vscode.commands.executeCommand(...)`, so its practical role is known from real integration usage.

- **Discovered but not implemented here**
  The command ID belongs to Windsurf. This repo may know it exists, but does not define its internals.

- **Not verified in this repo**
  The command was requested for documentation, but there is no implementation or call site for it in this codebase. Any description is therefore limited to naming-based inference and integration guidance.

## System Architecture Context

These commands are used in a three-part flow:

- **`wsc` CLI**
  Writes requests into `~/.windsurf-cli/prompt.json`.

- **Cascade CLI Bridge extension**
  Watches that directory, reads requests, and either:
  - sends prompts to Cascade, or
  - executes arbitrary Windsurf/VS Code commands by ID.

- **Cascade hooks**
  Capture prompts, responses, and transcripts into `~/.windsurf-cli/`.

Relevant files in this repo:

- `cascade-cli-extension/src/extension.js`
- `cascade-cli-extension/bin/wsc`
- `cascade-cli-extension/package.json`
- `cascade-cli-extension/README.md`

## Command Reference

---

## `cascadeCli.openNewWindow`

- **Status**
  Implemented here.

- **Registered by**
  `cascade-cli-extension/package.json`

- **Implemented in**
  `cascade-cli-extension/src/extension.js`

- **Purpose**
  Opens a new Windsurf window at a specified directory, using `vscode.openFolder` with `forceNewWindow: true`.

- **How it works**
  When executed, the command:

  - prompts for a directory path if not provided as an argument
  - calls `vscode.commands.executeCommand('vscode.openFolder', uri, { forceNewWindow: true })`
  - the new window registers itself in `windows.json` on activation

- **Arguments**
  Optional `dirPath` (string). If omitted, an input box is shown.

- **CLI usage**

  ```bash
  wsc -N ~/projects/myapp           # open new window at directory
  wsc -N ~/projects/myapp "fix bug" # open + send prompt
  ```

- **Side effects**
  Opens a new Windsurf window. The new window's extension instance registers itself in `windows.json`.

---

## `cascadeCli.executeCommand`

- **Status**
  Implemented here.

- **Registered by**
  `cascade-cli-extension/package.json`

- **Implemented in**
  `cascade-cli-extension/src/extension.js`

- **Purpose**
  Executes any arbitrary Windsurf/VS Code command by ID, with optional JSON arguments.

- **How it works**
  When executed, the command:

  - prompts for a command ID
  - prompts for optional JSON array of arguments
  - writes a JSON payload to `prompt.json` with `command` and `args` fields
  - the watcher picks it up and runs `vscode.commands.executeCommand(commandId, ...args)`

- **CLI usage**

  ```bash
  wsc --exec windsurf.cascadePanel.focus
  wsc --exec windsurf.openGenericUrl --args '["https://docs.windsurf.com"]'
  ```

---

## `cascadeCli.startWatching` / `cascadeCli.stopWatching`

- **Status**
  Implemented here.

- **Purpose**
  Start or stop the file watcher that monitors `prompt.json` for incoming CLI requests.

- **Notes**
  If `cascadeCli.autoStart` is `true` (default), watching begins automatically on extension activation. These commands provide manual control.

---

## `cascadeCli.showStatus`

- **Status**
  Implemented here.

- **Purpose**
  Displays the current extension status (from `status.json`) in a Windsurf notification.

- **Notes**
  Also accessible from the status bar item (`wsc: {windowId}`).

---

## `cascadeCli.sendPrompt`

- **Status**
  Implemented here.

- **Registered by**
  `cascade-cli-extension/package.json`

- **Implemented in**
  `cascade-cli-extension/src/extension.js`

- **Purpose**
  Opens an input box inside Windsurf, captures a freeform prompt from the user, and writes that request to the bridge request file so the watcher can send it to Cascade.

- **How it works**
  When executed, the command:

  - shows an input box with the prompt `Enter prompt for Cascade`
  - uses the placeholder `What would you like Cascade to do?`
  - if the user enters text, writes a JSON payload to `prompt.json`

  The payload contains:

  - `prompt`
  - `window`
  - `timestamp`
  - `source: "command-palette"`

- **Execution flow after write**
  The watcher later picks up that file and routes it through `processPromptFile()`, which eventually calls `focusCascadeAndSend(...)`.

- **Arguments**
  None.

- **Side effects**
  Writes to `~/.windsurf-cli/prompt.json` or the configured `cascadeCli.promptDir`.

- **Failure modes**
  There is no direct validation beyond checking whether a prompt was entered.
  If the prompt is empty or canceled, nothing is written.
  Any later failure happens in the asynchronous watcher/send pipeline.

- **When to use**
  Use this when you want a native command-palette entry point for sending a prompt without using the terminal CLI.

- **Notes**
  This command does not directly send text to Cascade itself.
  It enqueues a request for the watcher.

---

## `windsurf.sendTextToChat`

- **Status**
  Discovered but not implemented here.

- **Verification level**
  Mentioned in project context and prior integration knowledge, but not called by the current source tree.

- **Purpose**
  Intended to send plain text into a Windsurf chat surface, likely Cascade or a related chat UI.

- **Known repository evidence**
  There is no active call site for this command in `src/extension.js`.
  The bridge currently does not rely on it.

- **Practical interpretation**
  Based on the command name, this is likely a direct programmatic text-send API.
  However, because this repo does not use it, its exact argument shape and runtime behavior are not verified here.

- **Integration guidance**
  If you want to try it through this bridge, use:

  ```bash
  wsc --exec windsurf.sendTextToChat --args '[...]'
  ```

  You will need to determine the correct argument shape experimentally.

- **Caution**
  Prior observed behavior associated with this project indicates this command was not a reliable integration path for the bridge workflow.
  For this repo, the more reliable approach became:

  - `windsurf.cascadePanel.focus`
  - `windsurf.prioritized.chat.open`
  - clipboard paste
  - Enter submit

- **Recommended documentation stance**
  Treat this as a potentially available built-in Windsurf command, but not as a verified or stable transport in this codebase.

---

## `windsurf.triggerCascade`

- **Status**
  Not verified in this repo.

- **Purpose**
  By name, this likely triggers Cascade to open, start, or become active.

- **Known repository evidence**
  No implementation.
  No direct invocation in the current source tree.

- **What this means**
  This repository cannot authoritatively document:

  - required arguments
  - whether it opens the panel, focuses input, or submits a request
  - whether it starts a new conversation or reuses the current one

- **Integration guidance**
  If experimentation is desired, it can be invoked through:

  ```bash
  wsc --exec windsurf.triggerCascade
  ```

  Then inspect:

  - `wsc -w`
  - `wsc -L`
  - `~/.windsurf-cli/status.json`
  - `~/.windsurf-cli/extension.log`

- **Recommended interpretation in this repo**
  Do not depend on this command for production bridge behavior unless you verify it in your Windsurf build.

---

## `windsurf.openCascade`

- **Status**
  Not verified in this repo.

- **Purpose**
  By name, this likely opens the Cascade UI.

- **Known repository evidence**
  No implementation.
  No direct invocation in the bridge code.

- **Contrast with commands actually used here**
  The bridge does not use `windsurf.openCascade`.
  Instead it uses:

  - `windsurf.cascadePanel.focus` to ensure the panel is visible
  - `windsurf.prioritized.chat.open` to focus the input
  - AppleScript `Cmd+Shift+L` as a reliable new-conversation fallback on macOS

- **Implication**
  Even if `windsurf.openCascade` exists, the bridge authors did not rely on it for the working automation path.

- **Suggested use**
  Experimental only unless verified in your Windsurf version.

---

## `windsurf.cascadePanel.open`

- **Status**
  Not verified in this repo.

- **Purpose**
  Likely opens the Cascade panel explicitly.

- **Known repository evidence**
  No implementation.
  No call site in the current repo.

- **Contrast with verified behavior**
  The verified command used by this repo is `windsurf.cascadePanel.focus`, not `windsurf.cascadePanel.open`.

- **Likely semantic difference**
  If this command exists, it may focus less aggressively than `...focus`, or simply make the panel visible.
  That distinction matters for automation because visibility and input focus are not the same thing.

- **Recommended caution**
  For automation, do not assume `open` implies the text box is ready to type into.

---

## `windsurf.addCurrentFileToChat`

- **Status**
  Not verified in this repo.

- **Purpose**
  By name, likely attaches the currently active editor file to the current chat/Cascade context.

- **Known repository evidence**
  No implementation.
  No usage found in this repo.

- **Probable behavior**
  This likely depends on:

  - an active editor
  - an existing chat or Cascade session
  - UI state that can accept file context

- **Potential use case**
  Could be useful before sending a prompt if you want Cascade to consider the active file as context.

- **Unknowns**
  This repo does not verify:

  - whether it targets the current editor tab
  - whether it requires the Cascade panel to be open first
  - whether it appends content, metadata, or a file reference

---

## `windsurf.cascadePanel.focus`

- **Status**
  Observed and invoked here.

- **Implemented in Windsurf, used by this repo**
  Called from `focusExistingCascade()` in `src/extension.js`.

- **Purpose**
  Makes the Cascade panel visible as the first step in focusing an existing conversation.

- **How this repo uses it**
  The flow is:

  - execute `windsurf.cascadePanel.focus`
  - wait briefly
  - execute `windsurf.prioritized.chat.open`
  - then paste and submit the prompt

- **Observed semantics in this integration**
  In this project, `windsurf.cascadePanel.focus` is treated as:

  - sufficient to bring the panel forward or make it visible
  - not sufficient by itself to guarantee the text input is focused

- **Why it matters**
  This distinction is central to reliable automation.
  Opening or focusing the panel does not always place the text caret in the input field.
  That is why the bridge follows it with `windsurf.prioritized.chat.open`.

- **Arguments**
  None are used here.

- **Failure handling**
  Failures are caught and logged.
  The bridge still attempts later steps when appropriate, and has a fallback path via AppleScript.

- **CLI example**

  ```bash
  wsc --exec windsurf.cascadePanel.focus
  ```

- **Recommended use**
  Use this when you need the Cascade UI visible in the current Windsurf window.
  If you need the user input focused, pair it with `windsurf.prioritized.chat.open`.

---

## `windsurf.cascade.resetCurrentConversation`

- **Status**
  Not verified in this repo.

- **Purpose**
  By name, likely clears or resets the current Cascade conversation state.

- **Known repository evidence**
  No implementation.
  No direct invocation in the bridge code.

- **Potential meaning**
  It may do one of the following:

  - clear the current thread contents
  - start a fresh conversation in the same panel
  - reset internal agent/conversation state without creating a new visible tab

- **Important distinction**
  The bridge handles new conversations differently.
  On macOS it uses `Cmd+Shift+L` to create a new conversation because that path reliably focuses the input.
  Therefore, this repo does not depend on `resetCurrentConversation` for new-thread behavior.

- **Guidance**
  Treat this as potentially useful for session hygiene, but unverified for automation.

---

## `windsurf.cascade.openAgentPicker`

- **Status**
  Not verified in this repo.

- **Purpose**
  By name, likely opens the agent selector for Cascade.

- **Known repository evidence**
  No implementation.
  No call site in this codebase.

- **Possible use**
  This may expose a UI for selecting specialized agents or modes before submitting a prompt.

- **Automation implication**
  If this command opens a transient picker UI, any automation that runs after it would need to account for:

  - focus movement
  - keyboard selection
  - timing delays
  - interaction with other pickers such as the model selector

- **Repository stance**
  No authoritative behavior is available from this codebase.

---

## `windsurf.cascade.toggleModelSelector`

- **Status**
  Observed and invoked here.

- **Implemented in Windsurf, used by this repo**
  Called from `selectModel(model)` in `src/extension.js`.

- **Purpose**
  Opens the Windsurf model selector so the bridge can choose a specific LLM before sending a prompt.

- **How this repo uses it**
  The sequence is:

  - open or focus Cascade first
  - call `windsurf.cascade.toggleModelSelector`
  - wait for the dropdown to appear
  - use AppleScript to type the model name
  - arrow down to the first filtered result
  - press Enter to confirm

- **Critical behavior note**
  In this integration, model selection must happen **after** the Cascade panel is already open and focused.
  Otherwise the keystrokes intended for the model picker may go to the wrong target.

- **Arguments**
  None are used here.

- **Failure handling**
  If the command throws, the bridge logs the failure and continues using the currently selected model.
  Model selection is treated as optional enhancement, not a hard blocker.

- **CLI examples**

  ```bash
  wsc --exec windsurf.cascade.toggleModelSelector
  wsc -V --exec windsurf.cascade.toggleModelSelector -w
  ```

- **Model-only mode in this repo**
  The CLI also supports model-only requests.
  In that mode the extension:

  - opens or focuses Cascade
  - runs `windsurf.cascade.toggleModelSelector`
  - selects the requested model
  - stops without submitting a prompt

- **Recommended use**
  Use this command when you want the Windsurf UI to expose the model picker.
  For full automation, pair it with a follow-up keyboard selection strategy.

---

## Behavior Comparison Summary

### Commands directly defined by this repo

- `cascadeCli.sendPrompt`
- `cascadeCli.executeCommand`
- `cascadeCli.startWatching`
- `cascadeCli.stopWatching`
- `cascadeCli.openNewWindow`
- `cascadeCli.showStatus`

### Commands actively used by the bridge and therefore integration-verified

- `windsurf.cascadePanel.focus`
- `windsurf.prioritized.chat.open`
- `windsurf.cascade.toggleModelSelector`

### Commands requested here but not verified by current source

- `windsurf.sendTextToChat`
- `windsurf.triggerCascade`
- `windsurf.openCascade`
- `windsurf.cascadePanel.open`
- `windsurf.addCurrentFileToChat`
- `windsurf.cascade.resetCurrentConversation`
- `windsurf.cascade.openAgentPicker`

## Recommended Automation Patterns

### For opening or reusing Cascade reliably

Use the workflow validated by this bridge:

- **Existing conversation**
  - `windsurf.cascadePanel.focus`
  - `windsurf.prioritized.chat.open`
  - paste text
  - Enter

- **New conversation on macOS**
  - `Cmd+Shift+L`
  - wait for UI readiness
  - optionally select model
  - paste text
  - Enter

### For model changes

Use:

- `windsurf.cascade.toggleModelSelector`

But only after Cascade is already open and in the foreground.

### For arbitrary command experimentation

This bridge supports command execution by ID:

```bash
wsc --exec <command-id>
wsc --exec <command-id> --args '[...]'
wsc -w --exec <command-id>
```

This is the safest way to test uncertain built-in Windsurf commands while preserving watcher/status logging.

## Source References

Primary sources used for this document:

- `cascade-cli-extension/src/extension.js`
- `cascade-cli-extension/package.json`
- `cascade-cli-extension/bin/wsc`
- `cascade-cli-extension/README.md`

## Bottom Line

If you are working specifically with this repository, the commands you can rely on most strongly are:

- `cascadeCli.sendPrompt`
- `cascadeCli.executeCommand`
- `cascadeCli.openNewWindow`
- `cascadeCli.startWatching` / `cascadeCli.stopWatching`
- `cascadeCli.showStatus`
- `windsurf.cascadePanel.focus`
- `windsurf.prioritized.chat.open`
- `windsurf.cascade.toggleModelSelector`

The remaining Windsurf command IDs in this document should be treated as candidate built-ins whose exact behavior must be validated against the user's installed Windsurf build before depending on them in automation.
