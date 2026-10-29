# Favorite Base Branches for Smart Rebase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a favorite base branches system to Smart Rebase with quick-select pills, a 1-click star toggle button, and persistent settings across both the Electron Desktop App and VS Code / Antigravity IDE extension.

**Architecture:** Extend `config-store.mjs` and `ipc-controller.mjs` to persist `favoriteBranches` in `gui-settings.json` (and `window.dtk.saveGuiSettings`), update `public/index.html` with favorite branch pills and star toggle button, update `public/app.mjs` to render and synchronize favorite branches with the target select dropdown and route summary, and stage the updated extension bundle.

**Tech Stack:** Node.js, Electron IPC, VS Code Webview RPC bridge, CSS custom properties, `node:test`.

**Spec:** `docs/superpowers/specs/2026-10-28-rebase-favorite-branches-design.md`

## Global Constraints
- Must work identically in both the Electron standalone desktop app and the VS Code / Antigravity IDE extension.
- Preserve 100% test pass rate across all existing test suites.
- Follow Swiss Precision aesthetic: clean pills, no layout shifts, responsive down to `minWidth: 360`.

## Review Focus
- Default favorite branches (`develop`, `main`) should be present even on fresh install.
- Adding a custom branch (e.g. `release/v2`) and clicking Star should add it to pills and select it.
- Clicking the active favorite pill should switch the base branch target immediately.
- Removing a favorite should update the pills and dropdown without breaking the active selection.
- Works cleanly in both Electron Desktop and IDE extension webview environments.

---

### Task 1: Settings Persistence & IPC Support for Favorite Branches

**Files:**
- Modify: `tools/git-gui/lib/config-store.mjs`
- Modify: `tools/git-gui/lib/ipc-controller.mjs`
- Modify: `tools/git-gui/main.mjs`
- Modify: `tools/git-gui/preload.cjs`
- Modify: `tools/git-gui/test/config-store.test.mjs`
- Modify: `tools/git-gui/test/ipc-controller.test.mjs`

- [ ] **Step 1: Write failing tests for `favoriteBranches` in `test/config-store.test.mjs` and `test/ipc-controller.test.mjs`**
  - Verify `loadGuiSettings` defaults `favoriteBranches` to `['develop', 'main']`.
  - Verify `saveGuiSettings` persists custom array of `favoriteBranches` (deduplicated and trimmed).
  - Verify `ipc.saveGuiSettings` updates settings via IPC and exposes `favoriteBranches` in `ipc.getState()`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/config-store.test.mjs tools/git-gui/test/ipc-controller.test.mjs`
  Expected: FAIL

- [ ] **Step 3: Implement `favoriteBranches` in `config-store.mjs`, `ipc-controller.mjs`, `main.mjs`, and `preload.cjs`**
  - Update `loadGuiSettings` and `saveGuiSettings` in `config-store.mjs` to handle `favoriteBranches`.
  - Add `saveGuiSettings` method to `createIpcHandlers` in `ipc-controller.mjs`.
  - Register `dtk:saveGuiSettings` in `main.mjs` and expose in `preload.cjs`.

- [ ] **Step 4: Run test to verify it passes**
  Run: `node --test tools/git-gui/test/config-store.test.mjs tools/git-gui/test/ipc-controller.test.mjs`
  Expected: PASS

---

### Task 2: Favorite Branch Pills & Star Toggle in Smart Rebase UI

**Files:**
- Modify: `tools/git-gui/public/index.html`
- Modify: `tools/git-gui/public/styles.css`
- Modify: `tools/git-gui/public/app.mjs`
- Modify: `tools/git-gui/test/ipc-controller.test.mjs`

- [ ] **Step 1: Write failing tests in `test/ipc-controller.test.mjs`**
  - Assert `index.html` contains `#rebase-favorite-pills` and `#btn-star-target-branch`.
  - Assert `styles.css` contains styles for favorite pills and star button (`.favorite-pill`, `.star-btn`).
  - Assert `app.mjs` contains `renderFavoriteBranchPills` and `toggleFavoriteBranch`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/ipc-controller.test.mjs`
  Expected: FAIL

- [ ] **Step 3: Implement UI elements and handlers**
  - In `index.html`, add `<div id="rebase-favorite-pills" class="pill-grid"></div>` below the base branch label, and add `<button type="button" id="btn-star-target-branch" class="btn btn-secondary btn-icon" title="Toggle favorite branch">⭐</button>` next to custom target input.
  - In `styles.css`, style favorite pills with active states and hover delete tags.
  - In `app.mjs`, maintain `state.favoriteBranches` (defaulting to `['develop', 'main']`), render pills, handle clicking a pill to select the branch, handle star toggle to add/remove favorites, and update `#rebase-target-select` to group favorites with `⭐`.

- [ ] **Step 4: Run test to verify it passes**
  Run: `node --test tools/git-gui/test/*.test.mjs`
  Expected: PASS

---

### Task 3: Stage to IDE Extension & End-to-End Verification

**Files:**
- Modify: `tools/git-gui/README.md`

- [ ] **Step 1: Run full test suite**
  Run: `node --test tools/git-gui/test/*.test.mjs`
  Expected: 100% pass

- [ ] **Step 2: Stage updated extension bundle**
  Run: `node tools/git-gui/scripts/install-ide-extension.mjs`
  Expected: Extension updated in `~/.antigravity-ide/extensions` and `~/.vscode/extensions`.
