# Workspace Repository Auto-Detection & Real-Time Sync — Design Spec

## 1. Intent & Problem Statement
When a developer opens or switches between projects in Antigravity IDE or VS Code (e.g. `POS Inventory Management UI` vs `developer-toolkit`), the Developer Toolkit's "Local Repository" dropdown in Smart Rebase and the linked repositories list currently remain static on whatever was previously configured. The user has to manually link and select the project repository every time they switch workspaces.

## 2. Decided Architecture & Requirements (via `/grill-me`)

### 1. Nearest Git Root Upward Traversal:
- When a workspace or file is active, resolve the nearest git repository root (`git rev-parse --show-toplevel` or upward traversal for `.git`).
- If the user opens a nested subfolder (e.g. `tools/git-gui`), properly resolve the parent repository root (`developer-toolkit`).
- If the folder is not inside a git repository, gracefully retain previously linked repositories.

### 2. Auto-Detection & Auto-Link:
- Check if the resolved git root path already exists in `repos.conf`.
- If not present, automatically link it using the folder's base name as the project name and persist to `repos.conf`.
- Expose `isCurrentWorkspace: true` on the repository object returned by `ipc.getState()`.

### 3. Real-Time Workspace Sync:
- In `vscode-extension.cjs`:
  - Listen to `vscode.workspace.onDidChangeWorkspaceFolders` and `vscode.window.onDidChangeActiveTextEditor`.
  - Debounce triggers to prevent redundant calls.
  - When the active repository root changes, notify the webview with `dtk:activeRepoChanged`.
  - Also re-evaluate on manual click of "Refresh" (`btn-refresh-state`).

### 4. Coordinated UI Adaptation:
- **Smart Rebase:**
  - Auto-selects this active workspace repository in `#rebase-repo-select`.
  - Re-evaluates working branch, telemetry, and base branch favorite pills.
- **Report Builder (Left Rail):**
  - Displays a clean `📍 workspace` badge next to the active project name.
  - Automatically selects/checks this repository in `state.selectedRepos` without unchecking previously selected repositories.
- **Desktop Electron App Compatibility:**
  - When launched from terminal with a directory argument or `DTK_CALLER_DIR`, the same auto-detection applies seamlessly.

## 3. Scope & Non-Goals
- **In-Scope:** Git root resolution, auto-linking in `repos.conf`, real-time IDE event listeners, webview push notifications, UI synchronization.
- **Non-Goals:** Tracking git repositories outside the active IDE window or filesystem watcher overhead on entire disk drives.
