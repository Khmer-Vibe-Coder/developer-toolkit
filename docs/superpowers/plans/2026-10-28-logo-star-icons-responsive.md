# DTK Logo, Vector Star Icons & Narrow Sidebar Responsiveness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace cartoon emoji stars with sleek SVG vector star icons, polish responsiveness for narrow sidebar widths (< 360px) to eliminate text collisions/clipping, and use the user's uploaded illustrated mascot as the official DTK logo.

**Tech Stack:** HTML5, CSS3, SVG, Electron, VS Code Webview API, `node:test`.

---

### Task 1: DTK Mascot Logo Integration

**Files:**
- Modify: `tools/git-gui/public/index.html`
- Modify: `tools/git-gui/public/styles.css`
- Modify: `tools/git-gui/lib/vscode-host.mjs`
- Modify: `tools/git-gui/vscode-extension.cjs`
- Modify: `tools/git-gui/test/vscode-extension.test.mjs`
- Modify: `tools/git-gui/test/ipc-controller.test.mjs`

- [ ] **Step 1: Write failing tests for logo integration**
  - Verify `index.html` contains `class="brand-logo"` and references `./logo.png`.
  - Verify `transformHtmlForWebview` replaces `./logo.png` with webview `logoUri`.
  - Verify `styles.css` defines `.brand-logo` with rounded border and dimensions.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/vscode-extension.test.mjs`
  Expected: FAIL

- [ ] **Step 3: Implement logo in HTML, CSS, vscode-host, and extension**
  - Update `index.html`: replace `<div class="brand-mark">` with `<img src="./logo.png" alt="Developer Toolkit" class="brand-logo" width="32" height="32">`.
  - In `styles.css`, style `.brand-logo`.
  - In `vscode-host.mjs`, support `logoUri` option and replacement.
  - In `vscode-extension.cjs`, generate `logoUri` and pass to `transformHtmlForWebview`.

- [ ] **Step 4: Run test to verify it passes**
  Run: `node --test tools/git-gui/test/vscode-extension.test.mjs`
  Expected: PASS

---

### Task 2: Vector SVG Star Icons (No Emojis)

**Files:**
- Modify: `tools/git-gui/public/index.html`
- Modify: `tools/git-gui/public/styles.css`
- Modify: `tools/git-gui/public/app.mjs`
- Modify: `tools/git-gui/test/ipc-controller.test.mjs`

- [ ] **Step 1: Write failing tests in `test/ipc-controller.test.mjs`**
  - Verify `#btn-star-target-branch` contains an inline SVG star icon (not emoji `⭐`).
  - Verify `renderFavoriteBranchPills` in `app.mjs` renders vector SVG `<polygon` star.
  - Verify `styles.css` defines `.star-icon` with proper fill/stroke states for active/starred.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/ipc-controller.test.mjs`
  Expected: FAIL

- [ ] **Step 3: Implement vector SVG stars**
  - In `index.html`: update `#btn-star-target-branch` to hold vector SVG `<svg class="star-icon star-icon-btn"...>`. Remove emoji from field hint.
  - In `app.mjs`: render crisp SVG star in `renderFavoriteBranchPills`. Update `btn-star-target-branch` title and `.starred` state. In `<select>`, use clean text without cartoon emojis.
  - In `styles.css`: style `.star-icon`, `.star-icon-btn`, `.starred .star-icon-btn`.

- [ ] **Step 4: Run test to verify it passes**
  Run: `node --test tools/git-gui/test/ipc-controller.test.mjs`
  Expected: PASS

---

### Task 3: Narrow Sidebar Responsive Layout Polish

**Files:**
- Modify: `tools/git-gui/public/index.html`
- Modify: `tools/git-gui/public/styles.css`
- Modify: `tools/git-gui/test/ipc-controller.test.mjs`

- [ ] **Step 1: Write failing tests in `test/ipc-controller.test.mjs`**
  - Verify responsive compact tab text classes (`.tab-text-full`, `.tab-text-compact`).
  - Verify `.field-header` wrapping and companion width responsive rules.

- [ ] **Step 2: Run test to verify it fails**
  Run: `node --test tools/git-gui/test/ipc-controller.test.mjs`
  Expected: FAIL

- [ ] **Step 3: Implement responsive improvements**
  - In `index.html`: wrap tab labels in `<span class="tab-text-full">` and `<span class="tab-text-compact">`. Use compact button text spans.
  - In `styles.css`: on `@media (max-width: 480px)` and `.platform-vscode`, switch to compact tab text (`Report` · `Templates` · `Rebase`), stack `.field-header` to prevent collisions, allow custom input to shrink gracefully.

- [ ] **Step 4: Run test to verify it passes**
  Run: `node --test tools/git-gui/test/ipc-controller.test.mjs`
  Expected: PASS

---

### Task 4: Full Suite Verification & Extension Re-Staging

- [ ] **Step 1: Run complete test suite**
  Run: `node --test tools/git-gui/test/*.test.mjs`
  Expected: 100% pass

- [ ] **Step 2: Re-stage IDE extension bundle**
  Run: `node tools/git-gui/scripts/install-ide-extension.mjs`
  Expected: Staged to Antigravity IDE and VS Code extensions.
