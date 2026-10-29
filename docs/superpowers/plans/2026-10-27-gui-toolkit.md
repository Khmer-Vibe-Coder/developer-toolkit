# Developer Toolkit Electron Desktop App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the Developer Toolkit GUI from a local web server into a standalone cross-platform **Electron Desktop App** for macOS, Windows, and Linux with pure Electron IPC, native OS folder pickers, "Reveal in Finder/Explorer" integration, and `electron-builder` packaging.

**Architecture:** The desktop app lives in `tools/git-gui/` with an Electron main process (`main.mjs`), a secure `contextBridge` preload script (`preload.cjs`), a testable IPC controller (`lib/ipc-controller.mjs`), shared Git/config modules (`lib/config-store.mjs`, `lib/date-presets.mjs`, `lib/git-ops.mjs`), and the 3-column Swiss Precision Workbench renderer (`public/`). It launches as a native desktop window via `dtk gui` / `dtk app` or as a packaged `.app` / `.exe` / `.AppImage`.

**Tech Stack:** Electron, `electron-builder` (macOS/Windows/Linux targets), Node.js >= 18 built-ins (`node:child_process`, `node:fs/promises`, `node:path`, `node:test`), Vanilla HTML5/CSS3/ESM.

**Spec:** [docs/superpowers/specs/2026-10-27-gui-toolkit-design.md](file:///Users/rithyhong/developer-toolkit/docs/superpowers/specs/2026-10-27-gui-toolkit-design.md)

## Global Constraints

- **No Web Server / Browser Tabs:** Remove `server.mjs`; all communication between UI and backend must use Electron IPC (`window.dtk.*` ↔ `ipcMain.handle`).
- **Electron Security:** `contextIsolation: true`, `nodeIntegration: false`, and strict `execFile` argument arrays for all `git` invocations.
- **Smart Report Output Directory:** Default to `<callerDir>/report` when launched via CLI inside a project workspace, or `~/Documents/DeveloperToolkit-Reports` when launched from OS Applications (`/` or `$HOME`), with user overrides persisted in `~/.config/developer-toolkit/gui-settings.json`.

## Review Focus

- **Fallback report output directory when launched from OS Dock/Start Menu (`cwd === '/'` or `$HOME`):** Launching a packaged `.app`/`.exe` sets `process.cwd()` to `/` or `$HOME`; the IPC controller must resolve a writable default (`~/Documents/DeveloperToolkit-Reports` or `<callerDir>/report`) and persist user-selected output directories in `gui-settings.json`.
- **Canceled native OS folder picker dialogs (`dialog.showOpenDialog` returns `{ canceled: true }`):** Canceling a folder picker must return `{ canceled: true }` cleanly without throwing or mutating state.
- **Unescaped HTML characters in repository/template metadata (`Name <email@example.com>`):** All dynamic strings rendered in `app.mjs` must pass through `escapeHtml`.
- **Smart rebase failure recovery & conflict abort:** Failed target checkout/pull must restore the original branch and pop the auto-stash; conflicts must expose the 1-click Abort Rebase & Restore Stash IPC action.
- **Cross-platform launch & packaging configuration (`macOS`, `Windows`, `Linux`):** `package.json` and `git-gui.sh` / `git-gui.cmd` must support launching via `electron` across macOS, Windows, and Linux and building OS packages via `electron-builder`.

---

### Task 1: GUI Settings Persistence & Pure Electron IPC Controller (`config-store.mjs` & `ipc-controller.mjs`)

**Files:**
- Modify: `tools/git-gui/lib/config-store.mjs`
- Create: `tools/git-gui/lib/ipc-controller.mjs`
- Delete: `tools/git-gui/server.mjs`
- Delete: `tools/git-gui/test/server.test.mjs`
- Test: `tools/git-gui/test/ipc-controller.test.mjs`

**Interfaces:**
- Consumes: `config-store.mjs`, `date-presets.mjs`, `git-ops.mjs`
- Produces:
  - `loadGuiSettings(configDir: string, callerDir?: string): Promise<{ reportOutputDir: string }>`
  - `saveGuiSettings(configDir: string, settings: { reportOutputDir?: string }): Promise<{ reportOutputDir: string }>`
  - `createIpcHandlers(options: { configDir?: string, callerDir?: string, dialogApi?: object, shellApi?: object }): Record<string, Function>`

- [ ] **Step 1: Write the failing test in `tools/git-gui/test/ipc-controller.test.mjs`**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement `loadGuiSettings`/`saveGuiSettings` in `config-store.mjs` and `createIpcHandlers` in `ipc-controller.mjs`, and remove `server.mjs`**
- [ ] **Step 4: Run test to verify it passes**

---

### Task 2: Electron Main Process, Preload Bridge & Cross-Platform Package Config (`package.json`, `main.mjs`, `preload.cjs`)

**Files:**
- Create: `tools/git-gui/package.json`
- Create: `tools/git-gui/main.mjs`
- Create: `tools/git-gui/preload.cjs`
- Modify: `tools/git-gui/test/ipc-controller.test.mjs`

**Interfaces:**
- Consumes: `createIpcHandlers` from `tools/git-gui/lib/ipc-controller.mjs`
- Produces:
  - `window.dtk` preload bridge (`getState`, `addRepo`, `scanWorkspace`, `linkBatchRepos`, `removeRepos`, `saveTemplate`, `removeTemplates`, `generateReport`, `runRebase`, `abortRebase`, `pickFolder`, `pickReportOutputDir`, `revealInFolder`, `openPath`)
  - `package.json` with `start`, `test`, `dist:mac`, `dist:win`, `dist:linux` scripts

- [ ] **Step 1: Write failing test verifying preload & package configuration**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement `package.json`, `main.mjs`, and `preload.cjs`, and install `electron`**
- [ ] **Step 4: Run test to verify it passes**

---

### Task 3: Desktop Renderer Workbench (`public/index.html`, `styles.css`, `app.mjs`) & CLI Launcher Update (`git-gui.sh`, `git-gui.cmd`)

**Files:**
- Modify: `tools/git-gui/public/index.html`
- Modify: `tools/git-gui/public/styles.css`
- Modify: `tools/git-gui/public/app.mjs`
- Modify: `tools/git-gui/git-gui.sh`
- Modify: `tools/git-gui/git-gui.cmd`
- Modify: `tools/git-gui/README.md`
- Modify: `tools/git-toolkit/git-toolkit.sh`
- Modify: `tools/git-gui/test/cli-integration.test.mjs`

- [ ] **Step 1: Update tests in `tools/git-gui/test/ipc-controller.test.mjs` and `cli-integration.test.mjs` for Desktop IPC UI & Electron launcher**
- [ ] **Step 2: Run tests to verify they fail**
- [ ] **Step 3: Update `index.html`, `styles.css`, `app.mjs` to use `window.dtk` IPC, native Folder Picker buttons, Output Folder selector, Reveal in Finder/Explorer buttons, and macOS titlebar drag bar; update `git-gui.sh` and `git-gui.cmd` to launch Electron**
- [ ] **Step 4: Run full test suite (`node --test tools/git-gui/test/*.test.mjs`) to verify all pass**
