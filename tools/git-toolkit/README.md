# 🛠️ `dtk` / `git dtk` / `git toolkit` — Unified Toolkit Hub & Command Reference

Instead of remembering multiple separate tool commands (`git smart-rebase`, `git report`, etc.), use **`dtk`** (or **`git dtk`** / **`git toolkit`**) as a single entry point for the entire Developer Toolkit.

---

## 🚀 Usage

### 1. List All Commands Across Every Tool (`--help`)

```bash
dtk --help
# or
git dtk --help
# or
git toolkit --help
```

Outputs the complete cheatsheet for every tool in the repository along with its installation status (`[✔ installed]` / `[not installed]`):
- **# 1. `git-smart-rebase`** commands & examples
- **# 2. `git-report`** commands & examples
- Any future tools added to `./tools/`

### 2. Interactive Launcher Menu

Run with no arguments to pick and launch any tool using `↑`/`↓` arrow keys:

```bash
dtk
# or
git dtk
```

### 3. Run Any Tool via `dtk`

```bash
# Run git-smart-rebase
dtk rebase
dtk rebase main
dtk smart-rebase -b feature/auth

# Run git-report
dtk report
dtk report scan ~/Documents
dtk report add
dtk report -r repoA,repoB -b develop -p this-week --me

# Show detailed help for a specific tool
dtk report --help
dtk rebase --help

# Manage installed tools interactively
dtk install
dtk uninstall
```
