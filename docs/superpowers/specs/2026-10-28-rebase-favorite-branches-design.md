# Favorite Base Branches for Smart Rebase — Design Spec

## 1. Intent & Problem Statement
When developers rebase active feature branches, they frequently pull from and rebase onto recurring target branches (e.g., `develop`, `main`, or sprint/release integration branches like `release/v2.1`).
Currently, users must pick from a standard branch dropdown or type a custom branch into a text box. There is no quick 1-click access to recurring favorite base branches, nor a way to bookmark/pin custom branch names.

## 2. Recommended Approach: Quick-Select Favorite Branch Pills & Star Toggle

### Visual & Interactive Model:
1. **Interactive Favorite Pills Bar:**
   - Positioned cleanly right below the **Base Branch to Pull & Rebase From** label.
   - Shows active favorite pills: default favorites `⭐ develop` and `⭐ main`, plus any user-added favorite branches.
   - Clicking a pill immediately sets both the dropdown and active base branch target.
   - The currently selected base branch pill is highlighted (`.choice-pill.active`).
   - Custom-added favorite pills include an inline remove icon (`✕`) on hover/focus to unpin.

2. **1-Click "Star as Favorite" Action:**
   - A bookmark/star button (`#btn-star-target-branch`, `⭐`) positioned next to the custom branch input.
   - Clicking it adds the currently selected/typed branch into the user's favorites list and auto-activates it.
   - If the branch is already a favorite, clicking it toggles it off.

3. **Dropdown Mirroring:**
   - In `#rebase-target-select`, favorite branches appear at the very top of the `<select>` labeled with `⭐ <branch> (favorite)`.

4. **Persistence:**
   - Favorites are stored in `favoriteBranches` in `gui-settings.json` via `ipcMain.handle('dtk:saveGuiSettings')` / `window.dtk.saveGuiSettings` (with synchronized `localStorage` fallback).
   - Can support both global favorites (default: `['develop', 'main']`) and custom additions.

## 3. Scope & Non-Goals
- **In-Scope:** Adding/removing favorite branches via UI, persisting in settings, rendering quick pills, updating the dropdown and route summary.
- **Non-Goals:** Modifying git history or altering the underlying git rebase safety pipeline.
