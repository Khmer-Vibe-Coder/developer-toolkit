# 🛠️ Developer Toolkit (`developer-toolkit`)

A modular collection of productivity scripts, Git extensions, and workflow utilities for everyday engineering.

---

## 📦 Tools Catalog

| Tool | Category | Command | Description | Documentation |
| :--- | :--- | :--- | :--- | :--- |
| **`git-smart-rebase`** | Git Workflow | `git smart-rebase [target]` | Auto-stashes pending changes, updates target branch from remote, and rebases cleanly. | [Docs](tools/git-smart-rebase/README.md) |

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

Once installed, you can use the tools directly in any Git repository:

```bash
# Rebase onto default 'develop'
git smart-rebase

# Rebase onto 'main'
git smart-rebase main

# Rebase onto a specific branch
git smart-rebase -b feature/auth

# Show tool help
git smart-rebase -h
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
