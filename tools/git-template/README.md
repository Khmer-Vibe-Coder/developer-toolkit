# 📋 `git-template` — Report Template Manager

Save and manage reusable report presets for **`git-report`** so you don't have to re-select your repositories, per-repo branches, and author filter every time!

---

## ✨ Features

- **Pre-select Repositories & Per-Repo Branches:** Save a subset of repositories (e.g. `platform-api`, `tenant-admin-web`, `invita-admin-api`) and their exact target branches (`platform-api:develop,invita-admin-api:main`).
- **Pre-select Author Filter:** Save `All authors`, `My commits only`, or a specific author name/email.
- **Flexible Date Mode:** Choose either **"Ask me for the date range each time"** (so running the template only asks for the date range!) or lock in a **fixed date preset** (like `this-week` or `today`) for 1-click zero-prompt reports.
- **Seamless `git report` Integration:** Saved templates appear right at the top when you run `git report`, or can be run directly via `git report -t <name>` or `git template run <name>`.

---

## 🚀 Usage

```bash
# Open interactive Template Manager (Run, Create, Edit, List, Delete)
git template
# or
dtk template

# Create a new template directly
git template create core-weekly

# Run a saved template
git template run core-weekly
# or via git report:
git report -t core-weekly

# Override date preset when running a template
git report -t core-weekly -p last-month

# List all saved templates
git template list

# Edit or delete templates
git template edit
git template remove
```
