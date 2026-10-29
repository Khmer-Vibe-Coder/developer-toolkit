# Smart Rebase Telemetry Clarity & Run Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide unmistakable visual clarity and tracking for consecutive Smart Rebase runs by instantly resetting output on execution, formatting each run with completion timestamps, durations, and prominent outcome banners, and adding an inspector Clear action.

**Architecture:** Pure vanilla JavaScript frontend in Electron / VS Code webview environment. Triggering rebase immediately clears previous output and displays an active execution placeholder with start timestamp. On completion or abort, a structured telemetry banner is formatted with timestamp, duration, repository, and outcome details. A "Clear" button is added to the inspector action bar for manual reset.

**Tech Stack:** Vanilla JavaScript (ES modules), HTML5 Popover/Dialog, CSS3, Node.js test runner (`node --test`).

**Spec:** Option 1 selected by user in brainstorming: Live Reset + Timestamped Execution Header + Clear Button.

## Global Constraints
- Zero external runtime dependencies.
- Maintain compatibility with Electron IPC (`window.dtk`) and VS Code / Antigravity IDE webview RPC bridge.
- Preserve all existing tests and features.

## Review Focus
- Consecutive rebase runs: Running rebase twice on the same repository with no changes must produce distinct timestamps and durations.
- Conflict detection: Merge conflicts must prominently indicate conflict status and timestamp in both badge and output box.
- Inspector Clear: Clearing output restores placeholder text, resets badge to "Ready" or "Cleared", and disables the copy button.
- Copy Output: Copies the entire active telemetry or report buffer cleanly.

---

### Task 1: Inspector UI Actions & Clear Button
- [x] Add `#btn-clear-output` to `#live-inspector .inspector-actions` in `tools/git-gui/public/index.html`.
- [x] Rename `#btn-copy-output` label text from "Copy Markdown" to "Copy Output" (while keeping ID intact) for semantic clarity between reports and rebase telemetry.
- [x] Ensure CSS styles in `tools/git-gui/public/styles.css` accommodate the new action button cleanly across full desktop and narrow sidebar viewports.

### Task 2: Live Telemetry Reset, Run Header & Duration Formatting
- [x] In `tools/git-gui/public/app.mjs`:
  - [x] On `rebase-form` submit:
    - [x] Record `startTime = Date.now()`
    - [x] Immediately clear `inspector-output` and display live running indicator:
      `[HH:MM:SS AM/PM] ⏳ Initiating Smart Rebase...\nRepository: <repo>\nBase Branch: <target>\n\nExecuting 5-stage safety pipeline... Please wait.`
    - [x] Set `inspector-stats` to `Running (HH:MM:SS)...`
    - [x] Enable copy button and inspector container `.has-output`.
  - [x] On `runRebase` promise resolution:
    - [x] Compute `durationMs = Date.now() - startTime` and `timeStr = new Date().toLocaleTimeString()`
    - [x] Format prominent completion banner:
      ```text
      ════════════════════════════════════════════════════════════════
      SMART REBASE TELEMETRY · ✔ COMPLETED
      Timestamp   : 10:25:02 PM (duration: 340ms)
      Repository  : developer-toolkit
      Base Branch : origin/develop
      Outcome     : Clean (up to date / fast-forward)
      ════════════════════════════════════════════════════════════════
      ```
    - [x] Set `inspector-stats` to `✔ Completed (HH:MM:SS)` or `⚠ Conflict (HH:MM:SS)` or `✖ Failed (HH:MM:SS)`.
  - [x] On `btn-abort-rebase` click:
    - [x] Compute duration and timestamp.
    - [x] Format aborted telemetry banner and update badge.
  - [x] Wire up `btn-clear-output`:
    - [x] Reset `inspector-output` text to friendly default instructions.
    - [x] Remove `.has-output` class from `#live-inspector`.
    - [x] Reset `inspector-stats` to `Ready`.
    - [x] Disable `#btn-copy-output`.

### Task 3: Unit Tests for Rebase Telemetry Clarity & Clear Button
- [x] Update `tools/git-gui/test/ipc-controller.test.mjs` to assert:
  - `index.html` contains `#btn-clear-output` and `Copy Output`.
  - `styles.css` contains status pill classes and actions bar.
  - `app.mjs` contains live rebase reset, timestamp formatting, duration tracking, and clear action handler.
- [x] Run test suite (`node --test tools/git-gui/test/*.test.mjs`) and verify all tests pass (23/23 passing).

### Task 4: Stage to Antigravity IDE and VS Code Extensions
- [x] Run `node tools/git-gui/scripts/install-ide-extension.mjs` (with bypass sandbox) to stage the updated bundle to `~/.antigravity-ide/extensions` and `~/.vscode/extensions`.
- [x] Confirm clean workspace and inform user.
