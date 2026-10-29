# 🛠️ Developer Toolkit (`developer-toolkit`)

A modular collection of productivity scripts, Git extensions, and workflow utilities for everyday engineering.

---

## 📦 Tools Catalog

| Tool | Category | Command | Description | Documentation |
| :--- | :--- | :--- | :--- | :--- |
| **`git-toolkit` (`dtk`)** | Unified Hub | `dtk` / `git dtk --help` | Master entry point to launch any tool interactively or list all commands across all tools (`--help`). | [Docs](tools/git-toolkit/README.md) |
| **`git-gui` (`dtk gui`)** | Desktop App | `dtk gui` / `dtk app` | Standalone cross-platform Electron Desktop App (macOS, Windows, Linux) for repository management, multi-repo commit reports, templates, and smart rebase. | [Docs](tools/git-gui/README.md) |
| **`git-smart-rebase`** | Git Workflow | `git smart-rebase [target]` | Auto-stashes pending changes, updates target branch from remote, and rebases cleanly. | [Docs](tools/git-smart-rebase/README.md) |
| **`git-report`** | Git Reporting | `git report` | Links multiple local or remote repos and generates commit reports filtered by subset, branch, and date presets into `./report/`. | [Docs](tools/git-report/README.md) |
| **`git-template`** | Report Presets | `git template` / `dtk template` | Saves reusable report templates (pre-selected repos, per-repo branches, author filter & date preset). | [Docs](tools/git-template/README.md) |

---

## ⚡ 1-Minute Quick Start

### 🍏 macOS & 🐧 Linux

Open your terminal, navigate to this directory, and run the installer:

```bash
cd developer-toolkit
chmod +x install.sh
./install.sh
```

> [!TIP]
> The installer automatically registers Git aliases (`git smart-rebase`) and creates symlinks in `~/.local/bin`.

---

### 🪟 Windows

Open **PowerShell** in the `developer-toolkit` directory and run:

```powershell
.\install.ps1
```

*(If script execution is disabled on your machine, run `powershell -ExecutionPolicy Bypass -File .\install.ps1`)*

---

## 🚀 Usage

Once installed, you can use **`dtk`** (or **`git dtk`** / **`git toolkit`**) as a single command hub, or call each tool directly:

```bash
# 🛠️ 0. Unified Toolkit Hub & Desktop App
dtk gui                           # Launch the cross-platform Electron Desktop App
dtk app                           # Alias for dtk gui
dtk --help                        # List all tools and commands in one place
git dtk --help                    # Same via Git alias
dtk                               # Interactive menu to pick & run any tool

# 1. git-smart-rebase
git smart-rebase                  # Rebase onto default 'develop'
git smart-rebase main             # Rebase onto 'main'
git smart-rebase -b feature/auth  # Rebase onto a specific branch

# 2. git-report (Multi-Repo Commit Report Generator)
git report scan ~/Documents       # Auto-discover & link local repos (0 MB storage)
git report add                    # Link current repo
git report add <remote-git-url>   # Link remote URL (lightweight metadata clone)
git report                        # Launch interactive selector & report wizard
git report -r repoA,repoB -b develop -p this-week --me
```

---

## 🧩 Adding a New Tool (How to Scale)

To add a new script to this toolkit:

1. Create a new folder inside `tools/`:
   ```text
   developer-toolkit/tools/my-new-tool/
   ├── my-new-tool.sh         # Main bash script (or git-my-new-tool.sh for git commands)
   ├── my-new-tool.cmd        # Windows cmd wrapper (optional)
   └── README.md              # Documentation
   ```
2. Re-run `./install.sh` (or `.\install.ps1` on Windows).
3. The installer will auto-discover your new tool, configure aliases/symlinks, and make it immediately usable!

---

## 🗑️ Uninstall / Undo

To remove all registered aliases and symlinks across your system:

- **macOS & Linux**:
  ```bash
  ./uninstall.sh
  ```
- **Windows**:
  ```powershell
  .\uninstall.ps1
  ```
- **Manual Git Alias Cleanup (Any OS)**:
  ```bash
  git config --global --unset alias.smart-rebase
  ```
