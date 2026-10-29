# VS Code & Antigravity IDE Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `tools/git-gui` into a dual-target **VS Code & Antigravity IDE Extension** (supporting both an Activity Bar Sidebar View and a Full Editor Tab) that shares 100% of the existing Git backend (`lib/ipc-controller.mjs`, `lib/git-ops.mjs`, `lib/config-store.mjs`) and UI (`public/index.html`, `public/styles.css`, `public/app.mjs`) alongside the standalone Electron Desktop App.

**Architecture:**
1. **Universal Renderer RPC Bridge (`public/app.mjs`):** When running in Electron, `window.dtk` is provided by `preload.cjs`. When running inside a VS Code or Antigravity IDE Webview (`typeof acquireVsCodeApi === 'function'`), `createVsCodeDtkBridge()` creates an identical `window.dtk` interface backed by `postMessage` / `window.addEventListener('message')` with correlated `requestId` promises.
2. **VS Code / Antigravity Extension Host (`vscode-extension.cjs` & `lib/vscode-host.mjs`):**
   - Registers:
     - **Activity Bar Container (`dtk-workbench`)** with a crisp SVG icon (`public/icon-activitybar.svg`) and a `WebviewViewProvider` (`dtk.sidebarView`) so users can dock Developer Toolkit in the left or right IDE sidebar.
     - **Command Palette Commands:** `dtk.openWorkbench` ("Developer Toolkit: Open Workbench in Editor Tab") and `dtk.refreshState` ("Developer Toolkit: Refresh Repositories").
   - Wires Webview messages directly to `createIpcHandlers` from `./lib/ipc-controller.mjs`, injecting `vscode.window.showOpenDialog` as `dialogApi` and `vscode.commands.executeCommand('revealFileInOS', ...)` / `vscode.window.showTextDocument` as `shellApi`.
3. **One-Command Installer (`dtk install-ext`):**
   - Adds `dtk install-ext` to `tools/git-toolkit/git-toolkit.sh` and `tools/git-gui/scripts/install-ide-extension.mjs` to install the extension directly into Antigravity IDE (`~/.antigravity-ide/extensions/`) and VS Code (`~/.vscode/extensions/`).

**Tech Stack:** Node.js ES Modules + CommonJS VS Code Extension entry (`vscode-extension.cjs`), VS Code Webview API (`WebviewViewProvider` & `WebviewPanel`), `node:test`.

---

### Task 1: Universal Webview RPC Bridge & Testable VS Code Host Adapter (`lib/vscode-host.mjs` & `public/app.mjs`)

**Files:**
- Create: `tools/git-gui/lib/vscode-host.mjs`
- Modify: `tools/git-gui/public/app.mjs`
- Create: `tools/git-gui/test/vscode-extension.test.mjs`

- [ ] **Step 1: Write failing unit tests in `tools/git-gui/test/vscode-extension.test.mjs`**
  Test:
  1. `transformHtmlForWebview(html, { cssUri, jsUri, cspSource })` rewrites `./styles.css` and `./app.mjs` to Webview URIs, injects a strict Content-Security-Policy meta tag for `cspSource`, and adds `.platform-vscode` class so macOS traffic-light padding is disabled inside IDE tabs/sidebars.
  2. `handleWebviewMessage(msg, ipcHandlers, postMessage)` routes `{ type: 'dtk:invoke', requestId, method, payload }` to `ipcHandlers[method](payload)` and replies with `{ type: 'dtk:response', requestId, ok: true, result }` (or `{ ok: false, error }` on failure).
  3. `createDtkClientBridge(vscodeApi, win)` in `public/app.mjs` translates `dtk.getState()` / `dtk.generateReport(...)` calls into `vscodeApi.postMessage({ type: 'dtk:invoke', ... })` and resolves when the matching `dtk:response` message arrives.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/vscode-extension.test.mjs`
  Expected: FAIL (`Cannot find module '../lib/vscode-host.mjs'`)

- [ ] **Step 3: Implement `tools/git-gui/lib/vscode-host.mjs` and `createDtkClientBridge` in `tools/git-gui/public/app.mjs`**
  - Implement `transformHtmlForWebview`, `createVsCodeDialogAdapter`, `createVsCodeShellAdapter`, and `handleWebviewMessage` in `tools/git-gui/lib/vscode-host.mjs`.
  - Update `tools/git-gui/public/app.mjs` to export `createDtkClientBridge(vscodeApi, eventTarget)` and auto-initialize `window.dtk` when `typeof acquireVsCodeApi === 'function'` and `!window.dtk`.
  - Ensure `.platform-vscode .topbar` in `tools/git-gui/public/styles.css` uses normal `padding-left: 14px` (no macOS traffic light inset inside IDE panels).

- [ ] **Step 4: Run test to verify it passes**
  Run: `node --test tools/git-gui/test/vscode-extension.test.mjs`
  Expected: PASS

---

### Task 2: VS Code / Antigravity IDE Extension Entry Point, Activity Bar Icon & Manifest (`vscode-extension.cjs`, `public/icon-activitybar.svg`, `package.json`)

**Files:**
- Create: `tools/git-gui/vscode-extension.cjs`
- Create: `tools/git-gui/public/icon-activitybar.svg`
- Modify: `tools/git-gui/package.json`
- Modify: `tools/git-gui/test/vscode-extension.test.mjs`

- [ ] **Step 1: Add failing manifest & entry-point tests in `tools/git-gui/test/vscode-extension.test.mjs`**
  Verify `package.json` declares `engines.vscode`, `activationEvents`, `contributes.viewsContainers.activitybar`, `contributes.views`, and `contributes.commands` (`dtk.openWorkbench`, `dtk.refreshState`), and `vscode-extension.cjs` exports `activate` and `deactivate`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/vscode-extension.test.mjs`
  Expected: FAIL

- [ ] **Step 3: Implement `public/icon-activitybar.svg`, `vscode-extension.cjs`, and update `package.json`**
  - Create `tools/git-gui/public/icon-activitybar.svg` (`currentColor` monochrome vector badge for VS Code / Antigravity Activity Bar).
  - Create `tools/git-gui/vscode-extension.cjs` implementing both `WebviewViewProvider` (`dtk.sidebarView` with `retainContextWhenHidden: true`) and `vscode.commands.registerCommand('dtk.openWorkbench', ...)` (`WebviewPanel` in editor tab).
  - Update `tools/git-gui/package.json` with `publisher: "developer-toolkit"`, `engines.vscode: "^1.85.0"`, `contributes` (Activity Bar container, sidebar view, commands, view title action button to open in full editor tab).

- [ ] **Step 4: Run test to verify it passes**
  Run: `node --test tools/git-gui/test/vscode-extension.test.mjs`
  Expected: PASS

---

### Task 3: One-Command IDE Extension Installer (`scripts/install-ide-extension.mjs` & `dtk install-ext`)

**Files:**
- Create: `tools/git-gui/scripts/install-ide-extension.mjs`
- Modify: `tools/git-toolkit/git-toolkit.sh`
- Modify: `tools/git-gui/README.md`
- Modify: `tools/git-gui/test/cli-integration.test.mjs`

- [ ] **Step 1: Add failing test for `install-ide-extension.mjs` and `dtk --help` advertising `dtk install-ext`**
  Verify `installExtensionToDir(guiRoot, targetExtensionsDir)` copies/installs the extension files (`package.json`, `vscode-extension.cjs`, `lib/`, `public/`) cleanly without `node_modules` bloat (~50 KB total!) and registers the entry in `extensions.json`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/vscode-extension.test.mjs tools/git-gui/test/cli-integration.test.mjs`
  Expected: FAIL

- [ ] **Step 3: Implement `scripts/install-ide-extension.mjs` and wire `dtk install-ext` in `git-toolkit.sh`**
  - `install-ide-extension.mjs` installs the lightweight extension bundle (~50 KB, zero `node_modules` needed!) into `~/.antigravity-ide/extensions/developer-toolkit.developer-toolkit-desktop-2.0.0` and `~/.vscode/extensions/developer-toolkit.developer-toolkit-desktop-2.0.0` (plus updates `extensions.json` if present).
  - Add `dtk install-ext` / `dtk ext` command routing in `tools/git-toolkit/git-toolkit.sh`.

- [ ] **Step 4: Run full test suite and install into Antigravity IDE & VS Code**
  Run: `node --test tools/git-gui/test/*.test.mjs`
  Expected: 100% PASS with 0 failures.
