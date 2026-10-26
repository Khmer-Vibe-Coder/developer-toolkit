# 📊 `git-report` — Multi-Repository Commit Report Generator

Link multiple local or remote Git repositories and generate clean Markdown (`.md`) or text (`.txt`) commit reports across selected repositories, branches, and date presets. Works seamlessly on **macOS, Linux, and Windows**.

---

## ✨ Features

- **Hybrid Repository Linking (Zero Storage Overhead)**:
  - **Local Folders (`0 MB` extra storage):** Link existing repositories directly (`git report add`) or auto-discover an entire workspace folder (`git report scan`).
  - **Remote Git URLs (`--filter=blob:none`):** Link remote GitHub/GitLab/Bitbucket URLs (`https://...` or `git@...`) using lightweight metadata-only bare clones that download **only commit history** without source code files.
- **Subset Selection:** Pick 4–5 repositories out of 10+ linked repositories via an interactive checkbox menu (`↑`/`↓`, `Space` to toggle, `a` for all, `Enter` to confirm) or CLI flags (`-r repoA,repoB`).
- **Smart Branch Resolution:** Pick `develop`, `main`, `master`, `staging`, `CURRENT` (each repo's checked-out branch), or any custom branch without switching branches or disturbing dirty working trees.
- **Rich Date Range Presets & Custom Dates:**
  - `today`, `yesterday`, `last-7-days`, `this-week`, `last-week`, `this-month`, `last-month`, `last-14-days`, `last-30-days`, or custom `YYYY-MM-DD -> YYYY-MM-DD`.
- **Clean Report File Output:** Saves directly to `./report/commit-report-<timestamp>.md` in the terminal directory where you ran the command.

---

## 🔗 1. Linking & Managing Repositories

```bash
# Option A: Auto-scan a workspace folder and check which repos to link (0 MB extra storage)
git report scan ~/Documents

# Option B: Link the repository you are currently inside (0 MB extra storage)
git report add

# Option C: Link a specific local folder path (Mac/Linux/Windows paths supported)
git report add /path/to/my-repo
git report add "C:\Users\name\Projects\my-repo"

# Option D: Link a remote Git URL (lightweight metadata-only clone)
git report add https://github.com/org/service-a.git
git report add git@github.com:org/service-b.git

# List all linked repositories and their status
git report list

# Unlink / remove repositories (interactive checklist if no name passed)
git report remove
git report remove service-a
```

---

## 🚀 2. Generating a Report

### Interactive Mode (Recommended)

Simply run:

```bash
git report
```

The interactive wizard will walk you through:
1. **Selecting repositories** (use `↑`/`↓` + `Space` to check/uncheck 4–5 repos, `a` to toggle all, or `n` to type numbers like `1,3,5`).
2. **Choosing the target branch** (`develop`, `main`, `master`, `staging`, `CURRENT`, or custom).
3. **Choosing the date range** (9 presets or custom `YYYY-MM-DD` -> `YYYY-MM-DD`).
4. **Choosing the author filter** (All authors, My commits only, or specific author).

---

### Fast CLI Mode (Flags)

```bash
# Pick specific repos, branch 'develop', preset 'this-week', only your own commits
git report -r repo-a,repo-b,repo-c -b develop -p this-week --me

# Custom date range across all linked repos on 'main'
git report --all -b main --from 2026-10-01 --to 2026-10-26

# Fetch latest remote commits before generating and output as .txt
git report -r 1,2,4 -b develop -p last-7-days --fetch --format txt

# Include short commit hash, date, and author in each line
git report -r repo-a,repo-b -b main -p this-month --detailed
```

---

## 📄 Output Format

Running `git report` creates `report/commit-report-<YYYYMMDD-HHMMSS>.md` in your current working directory:

```markdown
- repo name A
   - feat: add multi-repo report generator
   - fix: handle custom date range validation
- repo name B
   - (No commits in this period)
```
