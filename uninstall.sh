#!/usr/bin/env bash

# ==============================================================================
# Script: uninstall.sh
# Purpose: Interactive uninstaller for Developer Toolkit on macOS, Linux & Git Bash.
#          Detects which tools are currently installed on the system and lets
#          the user select which ones to uninstall via interactive checklist.
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
EXTRA_BIN_DIR=""
if [ -d "/opt/homebrew/bin" ] && [ -w "/opt/homebrew/bin" ] && [ "${HOME}" = "/Users/$(whoami)" ]; then
  EXTRA_BIN_DIR="/opt/homebrew/bin"
fi

AUTO_ALL=0
PURGE_DATA=0
CONFIG_DIR="${GIT_REPORT_CONFIG_DIR:-$HOME/.config/developer-toolkit}"

for arg in "$@"; do
  case "$arg" in
    -a|--all|-y|--yes)
      AUTO_ALL=1
      ;;
    --purge)
      PURGE_DATA=1
      ;;
    -h|--help)
      echo -e "${CYAN}Usage:${NC} ./uninstall.sh [options]"
      echo -e "  (no args)     Interactive checklist of currently installed tools to remove"
      echo -e "  -a, --all     Uninstall all installed tools without prompting"
      echo -e "  --purge       Also delete saved repos, templates & remote caches (~/.config/developer-toolkit)"
      echo -e "  -h, --help    Show this help message"
      exit 0
      ;;
  esac
done

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}🗑️  Developer Toolkit Uninstaller${NC}"
echo -e "${CYAN}======================================================${NC}"

# Detect which tools from ./tools/ are currently installed on the system
INSTALLED_SCRIPTS=()
INSTALLED_NAMES=()
INSTALLED_HINTS=()

for tool_dir in "$TOOLKIT_ROOT"/tools/*; do
  if [ -d "$tool_dir" ]; then
    for script in "$tool_dir"/*.sh; do
      if [ -f "$script" ]; then
        script_filename="$(basename "$script")"
        cmd_name="${script_filename%.sh}"

        has_symlink=0
        has_alias=0
        details=()

        if [ -L "$BIN_DIR/$cmd_name" ] || [ -f "$BIN_DIR/$cmd_name" ] || { [ -n "$EXTRA_BIN_DIR" ] && [ -L "$EXTRA_BIN_DIR/$cmd_name" ]; }; then
          has_symlink=1
          details+=("CLI: ${cmd_name}")
        fi

        if [ "$cmd_name" = "git-toolkit" ]; then
          if [ -L "$BIN_DIR/dtk" ] || { [ -n "$EXTRA_BIN_DIR" ] && [ -L "$EXTRA_BIN_DIR/dtk" ]; }; then
            has_symlink=1
            details+=("CLI: dtk")
          fi
        fi

        if [[ "$cmd_name" =~ ^git- ]]; then
          git_alias="${cmd_name#git-}"
          if git config --global --get alias."$git_alias" >/dev/null 2>&1; then
            has_alias=1
            details+=("git ${git_alias}")
          fi
        fi

        if [ "$has_symlink" -eq 1 ] || [ "$has_alias" -eq 1 ]; then
          INSTALLED_SCRIPTS+=("$script")
          INSTALLED_NAMES+=("$cmd_name")
          IFS=', ' eval 'joined_details="${details[*]}"'
          INSTALLED_HINTS+=("${DIM}(${joined_details})${NC}")
        fi
      fi
    done
  fi
done

TOTAL_INSTALLED="${#INSTALLED_NAMES[@]}"

if [ "$TOTAL_INSTALLED" -eq 0 ]; then
  echo -e "\n${YELLOW}ℹ️  No Developer Toolkit tools are currently installed on this system.${NC}\n"
  exit 0
fi

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

select_installed_tools_interactively() {
  local checked=()
  local i
  for ((i = 0; i < TOTAL_INSTALLED; i++)); do
    checked+=(0)
  done

  if [ "$AUTO_ALL" -eq 1 ] || [ ! -t 0 ] || [ ! -t 1 ]; then
    for ((i = 0; i < TOTAL_INSTALLED; i++)); do
      SELECTED_INDICES+=("$i")
    done
    return 0
  fi

  local cursor=0
  local use_number_mode=0

  echo -e "\n${CYAN}${BOLD}Select installed tools to uninstall (${TOTAL_INSTALLED} detected):${NC}"
  echo -e "${DIM}Controls: [↑/↓ or j/k] Move  [Space] Toggle  [a] Toggle All  [n] Type Numbers  [Enter] Confirm${NC}"

  trap 'printf "\033[?7h\033[?25h"' EXIT
  trap 'printf "\033[?7h\033[?25h\n"; echo -e "${YELLOW}⚠️  Uninstaller exited (Ctrl+C).${NC}"; exit 130' INT TERM

  draw_checklist() {
    printf "\033[?25l\033[?7l"
    local idx
    for ((idx = 0; idx < TOTAL_INSTALLED; idx++)); do
      local mark=" "
      [ "${checked[$idx]}" -eq 1 ] && mark="${RED}✖${NC}"
      local pointer="  "
      local label_style="${NC}"
      if [ "$idx" -eq "$cursor" ]; then
        pointer="${CYAN}❯ ${NC}"
        label_style="${BOLD}"
      fi
      local num=$((idx + 1))
      printf "\r\033[2K%b[%b] %d) %b%s%b %b\n" "$pointer" "$mark" "$num" "$label_style" "${INSTALLED_NAMES[$idx]}" "${NC}" "${INSTALLED_HINTS[$idx]}"
    done
    printf "\033[?7h\033[?25h"
  }

  draw_checklist

  while true; do
    IFS= read -rsn1 key || true

    if [[ "$key" == $'\x03' ]] || [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      printf "\033[?7h\033[?25h\n"
      echo -e "${YELLOW}⚠️  Uninstaller exited (Ctrl+C).${NC}"
      exit 130
    elif [[ "$key" == $'\x1b' ]]; then
      IFS= read -rsn2 rest || true
      case "$rest" in
        "[A"|"OA") cursor=$(((cursor - 1 + TOTAL_INSTALLED) % TOTAL_INSTALLED)) ;;
        "[B"|"OB") cursor=$(((cursor + 1) % TOTAL_INSTALLED)) ;;
      esac
    elif [ "$key" = "k" ] || [ "$key" = "K" ]; then
      cursor=$(((cursor - 1 + TOTAL_INSTALLED) % TOTAL_INSTALLED))
    elif [ "$key" = "j" ] || [ "$key" = "J" ]; then
      cursor=$(((cursor + 1) % TOTAL_INSTALLED))
    elif [ "$key" = " " ]; then
      if [ "${checked[$cursor]}" -eq 1 ]; then
        checked[$cursor]=0
      else
        checked[$cursor]=1
      fi
    elif [ "$key" = "a" ] || [ "$key" = "A" ]; then
      local all_on=1
      for ((i = 0; i < TOTAL_INSTALLED; i++)); do
        if [ "${checked[$i]}" -eq 0 ]; then
          all_on=0
          break
        fi
      done
      local new_val=$((1 - all_on))
      for ((i = 0; i < TOTAL_INSTALLED; i++)); do
        checked[$i]="$new_val"
      done
    elif [ "$key" = "n" ] || [ "$key" = "N" ]; then
      use_number_mode=1
      break
    elif [ "$key" = "" ]; then
      SELECTED_INDICES=()
      for ((i = 0; i < TOTAL_INSTALLED; i++)); do
        if [ "${checked[$i]}" -eq 1 ]; then
          SELECTED_INDICES+=("$i")
        fi
      done
      break
    fi

    printf "\033[%dA" "$TOTAL_INSTALLED"
    draw_checklist
  done

  if [ "$use_number_mode" -eq 1 ]; then
    while true; do
      echo -ne "\n${YELLOW}Enter tool numbers to uninstall (e.g. 1,2 or 'all'): ${NC}"
      read -r num_input
      if parse_number_selection "$num_input" "$TOTAL_INSTALLED"; then
        break
      fi
      echo -e "${RED}⚠️  Please enter valid numbers between 1 and ${TOTAL_INSTALLED}.${NC}"
    done
  fi
}

select_installed_tools_interactively

if [ "${#SELECTED_INDICES[@]}" -eq 0 ]; then
  echo -e "\n${YELLOW}ℹ️  No tools selected for removal. Nothing changed.${NC}\n"
  exit 0
fi

echo ""
REMOVED_COUNT=0

for idx in "${SELECTED_INDICES[@]}"; do
  cmd_name="${INSTALLED_NAMES[$idx]}"
  echo -e "${YELLOW}🧹 Removing: ${BOLD}${cmd_name}${NC}"

  # 1. If it's a git tool, remove global Git alias (all occurrences if duplicated)
  if [[ "$cmd_name" =~ ^git- ]]; then
    git_alias="${cmd_name#git-}"
    if git config --global --get alias."$git_alias" >/dev/null 2>&1; then
      git config --global --unset-all alias."$git_alias"
      echo -e "   ${GREEN}✔${NC} Removed Git alias: ${BLUE}git ${git_alias}${NC}"
    fi
  fi

  # 2. Remove symlink from ~/.local/bin and /opt/homebrew/bin
  if [ -L "$BIN_DIR/$cmd_name" ] || [ -f "$BIN_DIR/$cmd_name" ]; then
    rm -f "$BIN_DIR/$cmd_name"
    echo -e "   ${GREEN}✔${NC} Removed symlink: ${BIN_DIR}/${cmd_name}"
  fi
  if [ -n "$EXTRA_BIN_DIR" ] && [ -L "$EXTRA_BIN_DIR/$cmd_name" ]; then
    rm -f "$EXTRA_BIN_DIR/$cmd_name"
  fi

  # 3. If git-toolkit, also remove short `dtk` symlink & `git dtk` alias
  if [ "$cmd_name" = "git-toolkit" ]; then
    if git config --global --get alias.dtk >/dev/null 2>&1; then
      git config --global --unset-all alias.dtk
      echo -e "   ${GREEN}✔${NC} Removed Git alias: ${BLUE}git dtk${NC}"
    fi
    if [ -L "$BIN_DIR/dtk" ] || [ -f "$BIN_DIR/dtk" ]; then
      rm -f "$BIN_DIR/dtk"
      echo -e "   ${GREEN}✔${NC} Removed symlink: ${BIN_DIR}/dtk"
    fi
    if [ -n "$EXTRA_BIN_DIR" ] && [ -L "$EXTRA_BIN_DIR/dtk" ]; then
      rm -f "$EXTRA_BIN_DIR/dtk"
    fi
  fi

  REMOVED_COUNT=$((REMOVED_COUNT + 1))
done

# Check if git-report or git-template was uninstalled and saved config exists
REMOVED_REPORT_OR_TEMPLATE=0
for idx in "${SELECTED_INDICES[@]}"; do
  if [ "${INSTALLED_NAMES[$idx]}" = "git-report" ] || [ "${INSTALLED_NAMES[$idx]}" = "git-template" ]; then
    REMOVED_REPORT_OR_TEMPLATE=1
    break
  fi
done

if [ -d "$CONFIG_DIR" ] && { [ "$REMOVED_REPORT_OR_TEMPLATE" -eq 1 ] || [ "$PURGE_DATA" -eq 1 ]; }; then
  should_delete_config=0
  if [ "$PURGE_DATA" -eq 1 ]; then
    should_delete_config=1
  elif [ "$AUTO_ALL" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    echo -e "\n${CYAN}${BOLD}Saved data found in ${CONFIG_DIR} (repos.conf / templates.conf / remotes):${NC}"
    echo -e "${DIM}Controls: [↑/↓ or j/k] Move  [Space/Enter] Select  [Ctrl+C/q] Exit${NC}"
    data_cursor=0
    data_opts=(
      "Keep saved repositories & templates (safe if reinstalling later - default)"
      "Delete all saved repositories, templates & cached remotes (${CONFIG_DIR})"
    )
    draw_data_radio() {
      printf "\033[?25l\033[?7l"
      local i
      for ((i = 0; i < 2; i++)); do
        local pointer="  "
        local radio="( )"
        local style="${NC}"
        if [ "$i" -eq "$data_cursor" ]; then
          pointer="${CYAN}❯ ${NC}"
          radio="(${GREEN}◉${NC})"
          style="${BOLD}"
        fi
        printf "\r\033[2K%b%b %d) %b%s%b\n" "$pointer" "$radio" "$((i + 1))" "$style" "${data_opts[$i]}" "${NC}"
      done
      printf "\033[?7h\033[?25h"
    }
    draw_data_radio
    while true; do
      IFS= read -rsn1 key || true
      if [[ "$key" == $'\x03' ]] || [ "$key" = "q" ] || [ "$key" = "Q" ]; then
        break
      elif [[ "$key" == $'\x1b' ]]; then
        IFS= read -rsn2 rest || true
        case "$rest" in
          "[A"|"OA"|"[B"|"OB") data_cursor=$((1 - data_cursor)) ;;
        esac
      elif [ "$key" = "k" ] || [ "$key" = "K" ] || [ "$key" = "j" ] || [ "$key" = "J" ]; then
        data_cursor=$((1 - data_cursor))
      elif [ "$key" = "1" ]; then
        data_cursor=0
        printf "\033[2A"
        draw_data_radio
        break
      elif [ "$key" = "2" ]; then
        data_cursor=1
        printf "\033[2A"
        draw_data_radio
        break
      elif [ "$key" = "" ] || [ "$key" = " " ]; then
        break
      fi
      printf "\033[2A"
      draw_data_radio
    done
    [ "$data_cursor" -eq 1 ] && should_delete_config=1
  fi

  if [ "$should_delete_config" -eq 1 ]; then
    rm -rf "$CONFIG_DIR"
    echo -e "   ${GREEN}✔${NC} Deleted saved configuration & templates: ${CONFIG_DIR}"
  else
    echo -e "   ${BLUE}ℹ️${NC} Kept saved configuration & templates in: ${CONFIG_DIR}"
  fi
fi

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}✅ Successfully uninstalled ${REMOVED_COUNT} tool(s).${NC}"
echo -e "${GREEN}======================================================${NC}\n"
