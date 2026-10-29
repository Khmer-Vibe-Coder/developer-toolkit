# Workspace Repository Auto-Detection & Real-Time Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically detect the active workspace git repository in Antigravity IDE and VS Code (resolving nearest git root even from subfolders), auto-link it in `repos.conf` if not present, and dynamically sync it in real time to both Smart Rebase and the Report Builder with a `📍 workspace` badge.

**Tech Stack:** Node.js, Electron IPC, VS Code Extension API (`workspaceFolders`, `activeTextEditor`, Webview RPC), `node:test`.

**Spec:** `docs/superpowers/specs/2026-10-28-workspace-repo-auto-sync-design.md`

---

### Task 1: Git Root Resolution & Auto-Link in IPC Controller

**Files:**
- Modify: `tools/git-gui/lib/git-ops.mjs`
- Modify: `tools/git-gui/lib/ipc-controller.mjs`
- Modify: `tools/git-gui/test/git-ops.test.mjs`
- Modify: `tools/git-gui/test/ipc-controller.test.mjs`

- [ ] **Step 1: Write failing tests in `test/git-ops.test.mjs` and `test/ipc-controller.test.mjs`**
  - Verify `resolveGitRoot(nestedSubfolder)` returns the root repository path containing `.git`.
  - Verify `resolveGitRoot(nonGitFolder)` returns `null`.
  - Verify `ipc.syncWorkspaceRepo({ callerDir })` auto-links the repo into `repos.conf` and sets `isCurrentWorkspace: true` and `currentRepoName`.
  - Verify `ipc.getState()` exposes `isCurrentWorkspace: true` on the active repo.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/git-ops.test.mjs tools/git-gui/test/ipc-controller.test.mjs`
  Expected: FAIL

- [ ] **Step 3: Implement `resolveGitRoot` and `syncWorkspaceRepo`**
  - In `lib/git-ops.mjs`, implement `resolveGitRoot(startDir)` using `git rev-parse --show-toplevel` or upward traversal.
  - In `lib/ipc-controller.mjs`, update `getState` and implement `syncWorkspaceRepo(payload)` to auto-link the resolved git root if not present and mark `isCurrentWorkspace: true`.

- [ ] **Step 4: Run test to verify it passes**
  Run: `node --test tools/git-gui/test/git-ops.test.mjs tools/git-gui/test/ipc-controller.test.mjs`
  Expected: PASS

---

### Task 2: Real-Time IDE Extension Event Listeners & Webview Sync

**Files:**
- Modify: `tools/git-gui/vscode-extension.cjs`
- Modify: `tools/git-gui/public/app.mjs`
- Modify: `tools/git-gui/public/styles.css`
- Modify: `tools/git-gui/test/vscode-host.test.mjs`
- Modify: `tools/git-gui/test/ipc-controller.test.mjs`

- [ ] **Step 1: Write failing tests for extension event listeners and webview sync**
  - In `test/vscode-host.test.mjs`, assert `resolveActiveWorkspaceDir(vscode)` detects active editor file folder or workspace folder.
  - In `test/ipc-controller.test.mjs`, assert `app.mjs` listens for `dtk:activeRepoChanged` or syncs `currentRepoName` and renders `.pill-workspace`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/vscode-host.test.mjs tools/git-gui/test/ipc-controller.test.mjs`
  Expected: FAIL

- [ ] **Step 3: Implement extension listeners and UI sync**
  - In `vscode-extension.cjs`, attach listeners for `onDidChangeWorkspaceFolders` and `onDidChangeActiveTextEditor` (debounced). Send `dtk:activeRepoChanged` event to active webview(s).
  - In `public/app.mjs`, handle `dtk:activeRepoChanged` event, auto-check the workspace repo in `state.selectedRepos`, set `#rebase-repo-select` to it, and re-render.
  - In `public/styles.css`, style `.pill-workspace` with clean Swiss accent styling.

- [ ] **Step 4: Run test to verify it passes**
  Run: `node --test tools/git-gui/test/*.test.mjs`
  Expected: PASS

---

### Task 3: Stage to IDE Extensions & End-to-End Verification

**Files:**
- Modify: `tools/git-gui/scripts/install-ide-extension.mjs`
- Modify: `tools/git-gui/README.md`

- [ ] **Step 1: Run full test suite**
  Run: `node --test tools/git-gui/test/*.test.mjs`
  Expected: 100% pass

- [ ] **Step 2: Re-stage IDE extension bundle**
  Run: `node tools/git-gui/scripts/install-ide-extension.mjs` (with `BypassSandbox: true`)
  Expected: Updated in `~/.antigravity-ide/extensions` and `~/.vscode/extensions`.
