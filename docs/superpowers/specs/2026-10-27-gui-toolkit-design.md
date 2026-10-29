# Developer Toolkit Desktop App (`dtk gui`) — Design Specification

## 1. Intent & Why

`developer-toolkit` (`dtk`) provides four Bash/PowerShell CLI utilities (`git-toolkit`, `git-report`, `git-template`, `git-smart-rebase`) backed by plain pipe-delimited config files in `~/.config/developer-toolkit/` (`repos.conf` and `templates.conf`).

This specification defines the **cross-platform Native Desktop Application** (macOS `.app`/`.dmg`, Windows `.exe`, Linux `.AppImage`) built with **Electron**, giving engineers a standalone desktop workbench (not a browser tab or web server) where they can:
1. Visually manage linked local and remote repositories using native OS folder pickers (`dialog.showOpenDialog`), workspace auto-scanning, live working-tree telemetry (`clean` vs `uncommitted`), and one-click "Reveal in Finder / Explorer".
2. Configure and generate multi-repository commit reports with shared or per-repo branch selection, date presets or custom date ranges, and author filters—auto-saving each report to disk (`<callerDir>/report/` when launched from terminal or `~/Documents/DeveloperToolkit-Reports/` when launched as a desktop app, with a native folder picker to customize) and displaying a live preview with one-click Copy Markdown and Reveal in Finder/Explorer.
3. Create, edit, run, and delete reusable report templates (`templates.conf`).
4. Execute `git-smart-rebase` on any linked local repository with a 5-stage visual pipeline and a one-click **Abort Rebase & Restore Stash** rescue button if a conflict occurs.

## 2. Goals, Non-Goals & Anti-Goals

### Goals
- **True Cross-Platform Desktop App (No Web Browser):** Runs in a standalone Electron desktop window on macOS, Windows, and Linux, communicating strictly via Electron IPC (`ipcMain.handle` ↔ `contextBridge.exposeInMainWorld('dtk', ...)`), with zero HTTP ports opened.
- **100% CLI Config Compatibility:** Reads and writes `~/.config/developer-toolkit/repos.conf` and `templates.conf` so CLI commands (`dtk`, `git report`, `git template`, `git smart-rebase`) and the Desktop App share all linked repositories and templates.
- **Native OS Integrations:**
  - Native OS Folder Picker (`dialog.showOpenDialog`) for scanning workspace folders, linking local repositories, and choosing the report output directory.
  - Native OS File Manager integration (`shell.showItemInFolder` / `shell.openPath`) to reveal saved report files or open repository directories in Finder / Explorer / File Manager.
  - Native macOS window integration (`titleBarStyle: 'hiddenInset'` with traffic-light inset padding and `-webkit-app-region: drag` header) and clean window chrome on Windows and Linux.
- **Cross-Platform Packaging:** Configured with `electron-builder` to produce redistributable desktop bundles for macOS (`dmg`, `dir`), Windows (`nsis`, `portable`), and Linux (`AppImage`, `deb`), plus instant launch via `dtk gui` / `dtk app`.

### Non-Goals
- Running an HTTP web server or opening browser tabs in Chrome/Safari.
- Cloud account sync or multi-user remote servers.

## 3. Security & Runtime Constraints

- **Electron Security Best Practices:**
  - `contextIsolation: true`
  - `nodeIntegration: false`
  - `sandbox: true` on renderer preload bridge (`preload.cjs` exposes only explicit `window.dtk` IPC methods).
- **Safe Git Subprocess Execution:** All `git` commands execute in the main process via `execFile('git', args, ...)` with argument arrays—never shell string interpolation.
- **Working-Tree Safety:** Report generation never checks out branches or modifies working trees. Smart rebase auto-stashes uncommitted/untracked files before switching branches and rolls back automatically if target checkout or pull fails.

## 4. Architecture & File Structure

```text
tools/git-gui/
├── package.json               # Electron & electron-builder configuration (mac, win, linux)
├── main.mjs                   # Electron Main process (BrowserWindow, native dialogs, IPC registration)
├── preload.cjs                # Secure contextBridge exposing window.dtk desktop API
├── lib/
│   ├── config-store.mjs       # Reads/writes repos.conf, templates.conf, and gui-settings.json
│   ├── date-presets.mjs       # Computes 9 date presets & validates custom YYYY-MM-DD ranges
│   ├── git-ops.mjs            # Safe execFile git inspection, workspace scan, report, and smart-rebase
│   └── ipc-controller.mjs     # Testable desktop IPC handler functions wired to ipcMain
├── public/
│   ├── index.html             # Desktop Workbench UI (draggable titlebar, native folder picker triggers)
│   ├── styles.css             # Adaptive Light/Dark Swiss Precision Workbench styles
│   └── app.mjs                # Renderer controller using window.dtk IPC bridge
├── test/
│   ├── config-store.test.mjs
│   ├── date-presets.test.mjs
│   ├── git-ops.test.mjs
│   ├── ipc-controller.test.mjs
│   └── cli-integration.test.mjs
├── git-gui.sh                 # Launches Electron Desktop App from dtk / CLI on macOS & Linux
└── git-gui.cmd                # Launches Electron Desktop App on Windows
```
