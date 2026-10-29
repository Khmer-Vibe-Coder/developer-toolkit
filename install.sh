#!/usr/bin/env bash

# ==============================================================================
# Script: install.sh
# Purpose: Interactive installer for Developer Toolkit on macOS, Linux & Git Bash.
#          Allows selecting which tools to install via interactive checklist
#          (Up/Down arrows, Space, 'a' for all) and prevents duplicate installs.
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
# On Apple Silicon macOS, /opt/homebrew/bin is in PATH by default and user-writable
EXTRA_BIN_DIR=""
if [ -d "/opt/homebrew/bin" ] && [ -w "/opt/homebrew/bin" ] && [ "$HOME" = "/Users/$(whoami)" ]; then
  EXTRA_BIN_DIR="/opt/homebrew/bin"
fi

mkdir -p "$BIN_DIR"

AUTO_ALL=0
FORCE_INSTALL=0

for arg in "$@"; do
  case "$arg" in
    -a|--all|-y|--yes)
      AUTO_ALL=1
      ;;
    -f|--force)
      FORCE_INSTALL=1
      ;;
    -h|--help)
      echo -e "${CYAN}Usage:${NC} ./install.sh [options]"
      echo -e "  (no args)     Interactive checklist to select tools to install"
      echo -e "  -a, --all     Install all non-installed tools without prompting"
      echo -e "  -f, --force   Re-register aliases and symlinks even if already installed"
      echo -e "  -h, --help    Show this help message"
      exit 0
      ;;
  esac
done

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}🛠️  Developer Toolkit Installer${NC}"
echo -e "${CYAN}   Path: ${TOOLKIT_ROOT}${NC}"
echo -e "${CYAN}======================================================${NC}"

# Check if a tool script is already fully installed
is_tool_installed() {
  local script_path="$1"
  local cmd_name="$2"

  # 1. Check symlink in ~/.local/bin
  if [ ! -L "$BIN_DIR/$cmd_name" ] && [ ! -f "$BIN_DIR/$cmd_name" ]; then
    return 1
  fi
  if [ -L "$BIN_DIR/$cmd_name" ]; then
    local link_target
    link_target="$(readlink "$BIN_DIR/$cmd_name" 2>/dev/null || true)"
    if [ "$link_target" != "$script_path" ]; then
      return 1
    fi
  fi

  # 2. If /opt/homebrew/bin is writable, verify symlink exists there too for instant PATH access
  if [ -n "$EXTRA_BIN_DIR" ]; then
    if [ "$cmd_name" != "git-gui" ] && [ ! -L "$EXTRA_BIN_DIR/$cmd_name" ]; then
      return 1
    fi
    if [ "$cmd_name" = "git-toolkit" ] && [ ! -L "$EXTRA_BIN_DIR/dtk" ]; then
      return 1
    fi
  fi

  # 3. For git-toolkit, ensure `dtk` symlink and `git dtk` alias exist
  if [ "$cmd_name" = "git-toolkit" ]; then
    if [ ! -L "$BIN_DIR/dtk" ]; then
      return 1
    fi
    local dtk_alias
    dtk_alias="$(git config --global --get alias.dtk 2>/dev/null || true)"
    if [ "$dtk_alias" != "!bash \"$script_path\"" ]; then
      return 1
    fi
  fi

  # 4. If git-* tool, check global git alias
  if [[ "$cmd_name" =~ ^git- ]]; then
    local git_alias="${cmd_name#git-}"
    local expected_alias="!bash \"$script_path\""
    local current_alias
    current_alias="$(git config --global --get alias."$git_alias" 2>/dev/null || true)"
    if [ "$current_alias" != "$expected_alias" ]; then
      return 1
    fi
  fi

  return 0
}

# Discover all available tools in ./tools/
TOOL_SCRIPTS=()
TOOL_NAMES=()
TOOL_INSTALLED=()
TOOL_HINTS=()

for tool_dir in "$TOOLKIT_ROOT"/tools/*; do
  if [ -d "$tool_dir" ]; then
    for script in "$tool_dir"/*.sh; do
      if [ -f "$script" ]; then
        script_filename="$(basename "$script")"
        cmd_name="${script_filename%.sh}"
        TOOL_SCRIPTS+=("$script")
        TOOL_NAMES+=("$cmd_name")

        if is_tool_installed "$script" "$cmd_name"; then
          TOOL_INSTALLED+=(1)
          if [ "$cmd_name" = "git-toolkit" ]; then
            TOOL_HINTS+=("${GREEN}[already installed -> dtk / git dtk]${NC}")
          else
            TOOL_HINTS+=("${GREEN}[already installed -> git ${cmd_name#git-}]${NC}")
          fi
        else
          TOOL_INSTALLED+=(0)
          if [ "$cmd_name" = "git-toolkit" ]; then
            TOOL_HINTS+=("${YELLOW}[not installed -> dtk / git dtk]${NC}")
          elif [[ "$cmd_name" =~ ^git- ]]; then
            TOOL_HINTS+=("${YELLOW}[not installed -> git ${cmd_name#git-}]${NC}")
          else
            TOOL_HINTS+=("${YELLOW}[not installed]${NC}")
          fi
        fi
      fi
    done
  fi
done

TOTAL_TOOLS="${#TOOL_NAMES[@]}"

if [ "$TOTAL_TOOLS" -eq 0 ]; then
  echo -e "\n${YELLOW}⚠️  No tools found in ${TOOLKIT_ROOT}/tools/${NC}"
  exit 0
fi

# Interactive multi-select checklist
SELECTED_INDICES=()

parse_number_selection() {
  local input="$1"
  local total="$2"
  SELECTED_INDICES=()

  if [ "$input" = "all" ] || [ "$input" = "ALL" ] || [ "$input" = "*" ] || [ "$input" = "a" ] || [ "$input" = "A" ]; then
    local i
    for ((i = 0; i < total; i++)); do
      SELECTED_INDICES+=("$i")
    done
    return 0
  fi

  input="${input//,/ }"
  local token
  for token in $input; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local start="${BASH_REMATCH[1]}"
      local end="${BASH_REMATCH[2]}"
      local n
      for ((n = start; n <= end; n++)); do
        if [ "$n" -ge 1 ] && [ "$n" -le "$total" ]; then
          SELECTED_INDICES+=("$((n - 1))")
        fi
      done
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      if [ "$token" -ge 1 ] && [ "$token" -le "$total" ]; then
        SELECTED_INDICES+=("$((token - 1))")
      fi
    fi
  done

  [ "${#SELECTED_INDICES[@]}" -gt 0 ]
}

select_tools_interactively() {
  local checked=()
  local i
  for ((i = 0; i < TOTAL_TOOLS; i++)); do
    if [ "${TOOL_INSTALLED[$i]}" -eq 0 ]; then
      checked+=(1)
    else
      checked+=(0)
    fi
  done

  if [ "$AUTO_ALL" -eq 1 ] || [ ! -t 0 ] || [ ! -t 1 ]; then
    for ((i = 0; i < TOTAL_TOOLS; i++)); do
      SELECTED_INDICES+=("$i")
    done
    return 0
  fi

  local cursor=0
  local use_number_mode=0

  echo -e "\n${CYAN}${BOLD}Select tools to install (${TOTAL_TOOLS} available):${NC}"
  echo -e "${DIM}Controls: [↑/↓ or j/k] Move  [Space] Toggle  [a] Toggle All  [n] Type Numbers  [Enter] Confirm${NC}"

  trap 'printf "\033[?7h\033[?25h"' EXIT
  trap 'printf "\033[?7h\033[?25h\n"; echo -e "${YELLOW}⚠️  Installer exited (Ctrl+C).${NC}"; exit 130' INT TERM

  draw_checklist() {
    printf "\033[?25l\033[?7l"
    local idx
    for ((idx = 0; idx < TOTAL_TOOLS; idx++)); do
      local mark=" "
      [ "${checked[$idx]}" -eq 1 ] && mark="${GREEN}✔${NC}"
      local pointer="  "
      local label_style="${NC}"
      if [ "$idx" -eq "$cursor" ]; then
        pointer="${CYAN}❯ ${NC}"
        label_style="${BOLD}"
      fi
      local num=$((idx + 1))
      printf "\r\033[2K%b[%b] %d) %b%s%b %b\n" "$pointer" "$mark" "$num" "$label_style" "${TOOL_NAMES[$idx]}" "${NC}" "${TOOL_HINTS[$idx]}"
    done
    printf "\033[?7h\033[?25h"
  }

  draw_checklist

  while true; do
    IFS= read -rsn1 key || true

    if [[ "$key" == $'\x03' ]] || [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      printf "\033[?7h\033[?25h\n"
      echo -e "${YELLOW}⚠️  Installer exited (Ctrl+C).${NC}"
      exit 130
    elif [[ "$key" == $'\x1b' ]]; then
      IFS= read -rsn2 rest || true
      case "$rest" in
        "[A"|"OA") cursor=$(((cursor - 1 + TOTAL_TOOLS) % TOTAL_TOOLS)) ;;
        "[B"|"OB") cursor=$(((cursor + 1) % TOTAL_TOOLS)) ;;
      esac
    elif [ "$key" = "k" ] || [ "$key" = "K" ]; then
      cursor=$(((cursor - 1 + TOTAL_TOOLS) % TOTAL_TOOLS))
    elif [ "$key" = "j" ] || [ "$key" = "J" ]; then
      cursor=$(((cursor + 1) % TOTAL_TOOLS))
    elif [ "$key" = " " ]; then
      if [ "${checked[$cursor]}" -eq 1 ]; then
        checked[$cursor]=0
      else
        checked[$cursor]=1
      fi
    elif [ "$key" = "a" ] || [ "$key" = "A" ]; then
      local all_on=1
      for ((i = 0; i < TOTAL_TOOLS; i++)); do
        if [ "${checked[$i]}" -eq 0 ]; then
          all_on=0
          break
        fi
      done
      local new_val=$((1 - all_on))
      for ((i = 0; i < TOTAL_TOOLS; i++)); do
        checked[$i]="$new_val"
      done
    elif [ "$key" = "n" ] || [ "$key" = "N" ]; then
      use_number_mode=1
      break
    elif [ "$key" = "" ]; then
      SELECTED_INDICES=()
      for ((i = 0; i < TOTAL_TOOLS; i++)); do
        if [ "${checked[$i]}" -eq 1 ]; then
          SELECTED_INDICES+=("$i")
        fi
      done
      break
    fi

    printf "\033[%dA" "$TOTAL_TOOLS"
    draw_checklist
  done

  if [ "$use_number_mode" -eq 1 ]; then
    while true; do
      echo -ne "\n${YELLOW}Enter tool numbers (e.g. 1,2 or 'all'): ${NC}"
      read -r num_input
      if parse_number_selection "$num_input" "$TOTAL_TOOLS"; then
        break
      fi
      echo -e "${RED}⚠️  Please enter valid numbers between 1 and ${TOTAL_TOOLS}.${NC}"
    done
  fi
}

select_tools_interactively

if [ "${#SELECTED_INDICES[@]}" -eq 0 ]; then
  echo -e "\n${YELLOW}ℹ️  No tools selected for installation. Exiting.${NC}\n"
  exit 0
fi

echo ""
INSTALLED_COUNT=0
SKIPPED_COUNT=0

for idx in "${SELECTED_INDICES[@]}"; do
  script="${TOOL_SCRIPTS[$idx]}"
  cmd_name="${TOOL_NAMES[$idx]}"
  already_installed="${TOOL_INSTALLED[$idx]}"

  chmod +x "$script"

  # Prevent duplicate installation unless --force is passed
  if [ "$already_installed" -eq 1 ] && [ "$FORCE_INSTALL" -eq 0 ]; then
    echo -e "${BLUE}⏭️  Skipping ${BOLD}${cmd_name}${NC}${BLUE}: Already installed (use --force to reinstall)${NC}"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  echo -e "${YELLOW}📦 Installing: ${BOLD}${cmd_name}${NC}"

  # 1. If it's a git tool (starts with git-), configure global Git alias without duplicates
  if [[ "$cmd_name" =~ ^git- ]]; then
    git_alias="${cmd_name#git-}"
    expected_alias="!bash \"$script\""
    current_alias="$(git config --global --get alias."$git_alias" 2>/dev/null || true)"

    if [ "$current_alias" = "$expected_alias" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
      echo -e "   ${GREEN}✔${NC} Git Alias already set: ${BLUE}git ${git_alias}${NC}"
    else
      git config --global --replace-all alias."$git_alias" "$expected_alias"
      echo -e "   ${GREEN}✔${NC} Git Alias registered: ${BLUE}git ${git_alias}${NC}"
    fi
  fi

  # 2. Symlink into ~/.local/bin (and /opt/homebrew/bin if available on macOS so it works immediately)
  ln -sf "$script" "$BIN_DIR/$cmd_name"
  echo -e "   ${GREEN}✔${NC} Symlink created: ${BIN_DIR}/${cmd_name}"
  if [ -n "$EXTRA_BIN_DIR" ] && [ "$cmd_name" != "git-gui" ]; then
    ln -sf "$script" "$EXTRA_BIN_DIR/$cmd_name"
  fi

  # 3. If this is git-toolkit, also register the short `dtk` CLI & `git dtk` alias
  if [ "$cmd_name" = "git-toolkit" ]; then
    ln -sf "$script" "$BIN_DIR/dtk"
    if [ -n "$EXTRA_BIN_DIR" ]; then
      ln -sf "$script" "$EXTRA_BIN_DIR/dtk"
    fi
    git config --global --replace-all alias.dtk "!bash \"$script\""
    echo -e "   ${GREEN}✔${NC} Unified Hub registered: ${BLUE}dtk${NC} / ${BLUE}git dtk${NC} / ${BLUE}git toolkit${NC}"
  fi

  # 4. If this is git-gui, also register `dtk-gui` and `git app` alias
  if [ "$cmd_name" = "git-gui" ]; then
    ln -sf "$script" "$BIN_DIR/dtk-gui"
    if [ -n "$EXTRA_BIN_DIR" ]; then
      ln -sf "$script" "$EXTRA_BIN_DIR/dtk-gui"
    fi
    git config --global --replace-all alias.app "!bash \"$script\""
    echo -e "   ${GREEN}✔${NC} Desktop App registered: ${BLUE}dtk app${NC} / ${BLUE}dtk gui${NC} / ${BLUE}git app${NC}"
  fi

  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
done

# Automatically ensure ~/.local/bin is in the user's shell RC file (~/.zshrc or ~/.bashrc)
ensure_path_in_rc() {
  local rc_file="$1"
  local create_if_missing="${2:-0}"
  local path_line='export PATH="$HOME/.local/bin:$PATH"'
  if [ -f "$rc_file" ] || [ "$create_if_missing" -eq 1 ]; then
    if ! grep -Fq ".local/bin" "$rc_file" 2>/dev/null; then
      printf "\n# Developer Toolkit CLI PATH\n%s\n" "$path_line" >> "$rc_file"
      echo -e "${GREEN}✔${NC} Added ${BLUE}~/.local/bin${NC} to ${BOLD}${rc_file}${NC}"
    fi
  fi
}

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  ensure_path_in_rc "$HOME/.zshrc" 1
  ensure_path_in_rc "$HOME/.bashrc" 0
fi

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}✅ Installed: ${INSTALLED_COUNT} tool(s) | Skipped (already installed): ${SKIPPED_COUNT}${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "💡 Run ${CYAN}${BOLD}dtk --help${NC} (or ${CYAN}${BOLD}git dtk -h${NC}) to see all commands!\n"
