#!/usr/bin/env bash

# ==============================================================================
# Script: git-toolkit.sh (also linked as `dtk`, `git dtk`, and `git toolkit`)
# Purpose: Unified command hub & cheatsheet for Developer Toolkit.
#          - Run `dtk --help` (or `git dtk --help`) to list all commands for every tool.
#          - Run `dtk` (or `git dtk`) interactively to pick and launch any tool.
#          - Run `dtk <tool> [args...]` to execute any tool from one entry point.
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Resolve real script path (follow symlinks so TOOLKIT_ROOT is always accurate)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN_DIR="$HOME/.local/bin"

# Check if a tool is installed on the system
is_installed_badge() {
  local cmd_name="$1"
  local git_alias="${cmd_name#git-}"
  if [ -L "$BIN_DIR/$cmd_name" ] || [ -f "$BIN_DIR/$cmd_name" ] || [ -f "$BIN_DIR/$cmd_name.cmd" ]; then
    echo -e "${GREEN}[✔ installed]${NC}"
    return 0
  fi
  if [[ "$cmd_name" =~ ^git- ]] && git config --global --get alias."$git_alias" >/dev/null 2>&1; then
    echo -e "${GREEN}[✔ installed]${NC}"
    return 0
  fi
  echo -e "${YELLOW}[not installed]${NC}"
}

# Print the unified cheatsheet of all tools and their commands
show_all_tools_help() {
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "${CYAN}🛠️  Developer Toolkit — Unified Command Reference (${BOLD}dtk${NC}${CYAN} / ${BOLD}git dtk${NC}${CYAN})${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "You can run tools directly (e.g. ${BOLD}git report${NC}) or through ${BOLD}dtk${NC} (e.g. ${BOLD}dtk report${NC})."
  echo -e ""
  echo -e "${BOLD}Unified Hub Commands:${NC}"
  echo -e "  ${CYAN}dtk${NC} / ${CYAN}git dtk${NC}                       Launch interactive tool picker menu"
  echo -e "  ${CYAN}dtk --help${NC} / ${CYAN}dtk list${NC} / ${CYAN}git dtk -h${NC}  List all tools and their commands"
  echo -e "  ${CYAN}dtk <tool> --help${NC} / ${CYAN}git dtk help <tool>${NC} Show detailed help for a specific tool"
  echo -e "  ${CYAN}dtk install${NC} / ${CYAN}dtk uninstall${NC}         Manage installed tools interactively"
  echo -e ""
  echo -e "${CYAN}----------------------------------------------------------------------${NC}"
  echo -e "${BOLD}# 1. git-smart-rebase${NC} (Safe Branch Sync & Auto-Stash Rebase) $(is_installed_badge "git-smart-rebase")"
  echo -e "${CYAN}----------------------------------------------------------------------${NC}"
  echo -e "  ${GREEN}git smart-rebase${NC}                    ${DIM}# Rebase onto default 'develop'${NC}"
  echo -e "  ${GREEN}git smart-rebase main${NC}               ${DIM}# Rebase onto 'main'${NC}"
  echo -e "  ${GREEN}git smart-rebase -b feature/auth${NC}    ${DIM}# Rebase onto a specific branch${NC}"
  echo -e "  ${GREEN}git smart-rebase -h${NC}                 ${DIM}# Show detailed rebase options${NC}"
  echo -e "  ${DIM}(Shortcut via hub: ${CYAN}dtk rebase [branch]${NC}${DIM} or ${CYAN}dtk smart-rebase [branch]${NC}${DIM})${NC}"
  echo -e ""
  echo -e "${CYAN}----------------------------------------------------------------------${NC}"
  echo -e "${BOLD}# 2. git-report${NC} (Multi-Repo Commit Report Generator) $(is_installed_badge "git-report")"
  echo -e "${CYAN}----------------------------------------------------------------------${NC}"
  echo -e "  ${GREEN}git report scan ~/Documents${NC}         ${DIM}# Auto-discover & link local repos (0 MB storage)${NC}"
  echo -e "  ${GREEN}git report add${NC}                      ${DIM}# Link current repo (0 MB storage)${NC}"
  echo -e "  ${GREEN}git report add <remote-git-url>${NC}     ${DIM}# Link remote URL (lightweight metadata clone)${NC}"
  echo -e "  ${GREEN}git report list${NC}                     ${DIM}# List all linked repositories & status${NC}"
  echo -e "  ${GREEN}git report remove [repo-name]${NC}       ${DIM}# Unlink repositories (interactive if no name)${NC}"
  echo -e "  ${GREEN}git report${NC}                          ${DIM}# Launch interactive selector & report wizard${NC}"
  echo -e "  ${GREEN}git report -t <template_name>${NC}       ${DIM}# Generate report using a saved template${NC}"
  echo -e "  ${GREEN}git report -r repoA,repoB -b develop -p this-week --me${NC}"
  echo -e "  ${GREEN}git report --all -b main --from 2026-10-01 --to 2026-10-26${NC}"
  echo -e "  ${GREEN}git report -h${NC}                       ${DIM}# Show all flags & date presets${NC}"
  echo -e "  ${DIM}(Shortcut via hub: ${CYAN}dtk report [args...]${NC}${DIM})${NC}"
  echo -e ""
  echo -e "${CYAN}----------------------------------------------------------------------${NC}"
  echo -e "${BOLD}# 3. git-template${NC} (Saved Report Template Manager) $(is_installed_badge "git-template")"
  echo -e "${CYAN}----------------------------------------------------------------------${NC}"
  echo -e "  ${GREEN}git template${NC}                        ${DIM}# Launch interactive Template Manager menu${NC}"
  echo -e "  ${GREEN}git template create [name]${NC}          ${DIM}# Pre-select repos, per-repo branches & author${NC}"
  echo -e "  ${GREEN}git template run [name]${NC}             ${DIM}# Run a saved template immediately${NC}"
  echo -e "  ${GREEN}git template edit [name]${NC}            ${DIM}# Edit an existing template${NC}"
  echo -e "  ${GREEN}git template list${NC}                   ${DIM}# List all saved templates${NC}"
  echo -e "  ${GREEN}git template remove [name]${NC}          ${DIM}# Delete saved templates${NC}"
  echo -e "  ${DIM}(Shortcut via hub: ${CYAN}dtk template [args...]${NC}${DIM})${NC}"

  # Dynamically list any additional custom tools added in ./tools/ in the future
  local extra_num=4
  for tool_dir in "$TOOLKIT_ROOT"/tools/*; do
    if [ -d "$tool_dir" ]; then
      for script in "$tool_dir"/*.sh; do
        if [ -f "$script" ]; then
          local fname
          fname="$(basename "$script")"
          local cname="${fname%.sh}"
          if [ "$cname" != "git-smart-rebase" ] && [ "$cname" != "git-report" ] && [ "$cname" != "git-template" ] && [ "$cname" != "git-toolkit" ]; then
            echo -e ""
            echo -e "${CYAN}----------------------------------------------------------------------${NC}"
            echo -e "${BOLD}# ${extra_num}. ${cname}${NC} $(is_installed_badge "$cname")"
            echo -e "${CYAN}----------------------------------------------------------------------${NC}"
            echo -e "  ${GREEN}${cname} --help${NC}                    ${DIM}# Show help for ${cname}${NC}"
            echo -e "  ${DIM}(Shortcut via hub: ${CYAN}dtk ${cname#git-} [args...]${NC}${DIM})${NC}"
            extra_num=$((extra_num + 1))
          fi
        fi
      done
    fi
  done

  echo -e "${CYAN}======================================================================${NC}"
}

# Interactive launcher menu when running `dtk` / `git dtk` with no arguments
interactive_hub_menu() {
  local options=(
    "git-report         — Generate multi-repo commit report (Wizard / Templates)"
    "git-template       — Create, edit, or run saved report templates"
    "git-report scan    — Scan a folder to link local Git repositories"
    "git-report list    — View all linked repositories"
    "git-smart-rebase   — Sync & rebase current branch (default: develop)"
    "Show All Commands  — Display full command cheatsheet (--help)"
    "Manage Toolkit     — Install / select tools (./install.sh)"
    "Exit"
  )
  local total="${#options[@]}"
  local cursor=0

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    show_all_tools_help
    exit 0
  fi

  echo -e "${CYAN}======================================================${NC}"
  echo -e "${CYAN}🛠️  Developer Toolkit Hub (${BOLD}dtk${NC}${CYAN})${NC}"
  echo -e "${CYAN}======================================================${NC}"
  echo -e "${DIM}Controls: [↑/↓ or j/k] Move  [Enter] Run  [h] Help Cheatsheet  [q] Quit${NC}\n"

  trap 'printf "\033[?7h\033[?25h"' EXIT
  trap 'printf "\033[?7h\033[?25h\n"; echo -e "${YELLOW}⚠️  Session exited (Ctrl+C).${NC}"; exit 130' INT TERM

  draw_menu() {
    printf "\033[?25l\033[?7l"
    local i
    for ((i = 0; i < total; i++)); do
      if [ "$i" -eq "$cursor" ]; then
        printf "\r\033[2K  ${CYAN}❯${NC} (${GREEN}◉${NC}) ${BOLD}%d) %s${NC}\n" "$((i + 1))" "${options[$i]}"
      else
        printf "\r\033[2K    ( ) %d) %s\n" "$((i + 1))" "${options[$i]}"
      fi
    done
    printf "\033[?7h\033[?25h"
  }

  draw_menu

  while true; do
    IFS= read -rsn1 key || true
    if [[ "$key" == $'\x03' ]]; then
      printf "\033[?7h\033[?25h\n"
      echo -e "${YELLOW}⚠️  Session exited (Ctrl+C).${NC}"
      exit 130
    elif [[ "$key" == $'\x1b' ]]; then
      IFS= read -rsn2 rest || true
      case "$rest" in
        "[A"|"OA") cursor=$(((cursor - 1 + total) % total)) ;;
        "[B"|"OB") cursor=$(((cursor + 1) % total)) ;;
      esac
    elif [ "$key" = "k" ] || [ "$key" = "K" ]; then
      cursor=$(((cursor - 1 + total) % total))
    elif [ "$key" = "j" ] || [ "$key" = "J" ]; then
      cursor=$(((cursor + 1) % total))
    elif [ "$key" = "h" ] || [ "$key" = "H" ]; then
      echo ""
      show_all_tools_help
      exit 0
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      echo ""
      exit 0
    elif [[ "$key" =~ ^[1-8]$ ]]; then
      cursor=$((key - 1))
      break
    elif [ "$key" = "" ] || [ "$key" = " " ]; then
      break
    fi

    printf "\033[%dA" "$total"
    draw_menu
  done

  echo ""
  case "$cursor" in
    0) exec bash "$TOOLKIT_ROOT/tools/git-report/git-report.sh" ;;
    1) exec bash "$TOOLKIT_ROOT/tools/git-template/git-template.sh" ;;
    2) exec bash "$TOOLKIT_ROOT/tools/git-report/git-report.sh" scan ;;
    3) exec bash "$TOOLKIT_ROOT/tools/git-report/git-report.sh" list ;;
    4) exec bash "$TOOLKIT_ROOT/tools/git-smart-rebase/git-smart-rebase.sh" ;;
    5) show_all_tools_help ;;
    6) exec bash "$TOOLKIT_ROOT/install.sh" ;;
    *) exit 0 ;;
  esac
}

# ==============================================================================
# Entry Point & Command Routing
# ==============================================================================

if [ $# -eq 0 ]; then
  interactive_hub_menu
  exit 0
fi

case "$1" in
  -h|--help|help|commands|cheatsheet|list)
    shift
    if [ $# -gt 0 ]; then
      # e.g. `dtk help report` or `dtk help smart-rebase`
      target_tool="$1"
      target_tool="${target_tool#git-}"
      if [ -f "$TOOLKIT_ROOT/tools/git-${target_tool}/git-${target_tool}.sh" ]; then
        exec bash "$TOOLKIT_ROOT/tools/git-${target_tool}/git-${target_tool}.sh" --help
      elif [ -f "$TOOLKIT_ROOT/tools/${target_tool}/${target_tool}.sh" ]; then
        exec bash "$TOOLKIT_ROOT/tools/${target_tool}/${target_tool}.sh" --help
      fi
    fi
    show_all_tools_help
    exit 0
    ;;
  rebase|smart-rebase|git-smart-rebase)
    shift
    exec bash "$TOOLKIT_ROOT/tools/git-smart-rebase/git-smart-rebase.sh" "$@"
    ;;
  report|git-report)
    shift
    exec bash "$TOOLKIT_ROOT/tools/git-report/git-report.sh" "$@"
    ;;
  template|templates|git-template)
    shift
    exec bash "$TOOLKIT_ROOT/tools/git-template/git-template.sh" "$@"
    ;;
  install|setup)
    shift
    exec bash "$TOOLKIT_ROOT/install.sh" "$@"
    ;;
  uninstall)
    shift
    exec bash "$TOOLKIT_ROOT/uninstall.sh" "$@"
    ;;
  *)
    # Try matching any tool in ./tools/
    sub="$1"
    sub_stripped="${sub#git-}"
    shift
    if [ -f "$TOOLKIT_ROOT/tools/git-${sub_stripped}/git-${sub_stripped}.sh" ]; then
      exec bash "$TOOLKIT_ROOT/tools/git-${sub_stripped}/git-${sub_stripped}.sh" "$@"
    elif [ -f "$TOOLKIT_ROOT/tools/${sub}/${sub}.sh" ]; then
      exec bash "$TOOLKIT_ROOT/tools/${sub}/${sub}.sh" "$@"
    else
      echo -e "${RED}❌ Unknown toolkit command: '${sub}'${NC}\n"
      show_all_tools_help
      exit 1
    fi
    ;;
esac
