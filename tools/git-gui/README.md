# 🖥️ `git-gui` (`dtk gui` / `dtk app`) — Cross-Platform Electron Desktop App

A clean, minimalist, standalone **Electron Desktop Application** for `developer-toolkit` that runs natively on **macOS, Windows, and Linux** (zero web server, zero browser tabs).

## Features

- **Native OS Integration & Pure Electron IPC:** Communicates directly between the UI and Node.js Git backend over `contextBridge` + `ipcRenderer.invoke` (`window.dtk.*`), with native OS Folder Pickers (`Browse...`) and one-click **Reveal in Finder / Explorer**.
- **Live Repository Rail:** Scan workspace folders via native folder dialog, link local or remote (`--filter=blob:none`) repositories, and inspect real-time working-tree status (`clean` vs `uncommitted`) and current branch.
- **Automatic Workspace Detection & Real-Time Sync:** When working in Antigravity IDE or VS Code, Developer Toolkit automatically resolves the nearest Git repository root for your active project folder or open file (even if opened in a subfolder), auto-links it to your repository list with a `📍 workspace` badge, and automatically selects it as the active Local Repository in Smart Rebase.
- **Multi-Repo Commit Report Builder:** Select repositories, shared or per-repo target branches, date presets or custom date ranges, and author filters. Auto-saves generated reports (`commit-report-<timestamp>.md`) to your configured Output Folder (`./report/` when launched from a project terminal, or `~/Documents/DeveloperToolkit-Reports/` when launched from OS Applications) with a live preview, **Copy Markdown**, and **Reveal in Folder**.
- **Saved Report Templates:** Create, run, load, and delete reusable templates shared directly with `git template` (`~/.config/developer-toolkit/templates.conf`).
- **Safe Smart Rebase:** Run the 5-stage `git-smart-rebase` workflow visually on any linked local repository, with quick-select **Favorite Base Branch Pills** (`⭐ develop`, `⭐ main`, plus custom pinned favorites with 1-click star toggle), live pull & rebase route preview, and a one-click **Abort Rebase & Restore Stash** rescue action if a conflict occurs.

## Launch Desktop App

```bash
dtk gui                   # Launch the Electron Desktop App from anywhere
dtk app                   # Alias for dtk gui
```

## Install as Antigravity IDE & VS Code Extension

```bash
dtk install-ext           # Installs Sidebar + Editor Tab extension into Antigravity IDE & VS Code
```
After running `dtk install-ext`:
1. In **Antigravity IDE** or **VS Code**, press `⌘⇧P` (`Ctrl+Shift+P`) → **`Developer: Reload Window`**.
2. Click the **`dtk`** icon in the Activity Bar (left sidebar) to use the docked responsive panel, or run **`Developer Toolkit: Open Workbench in Editor Tab`**.

## Build Standalone OS Installers (macOS / Windows / Linux)

```bash
cd tools/git-gui
npm install
npm run dist:mac          # Builds macOS .app / .dmg / .zip in tools/git-gui/dist/
npm run dist:win          # Builds Windows NSIS .exe + portable .exe in tools/git-gui/dist/
npm run dist:linux        # Builds Linux .AppImage + .deb in tools/git-gui/dist/
```
