#!/usr/bin/env bash

# ==============================================================================
# Script: git-template.sh
# Purpose: Create, edit, list, remove, and run saved report templates for
#          git-report (pre-selecting repositories, per-repo or shared branches,
#          author filter, and optional date range preset).
#          Compatible with macOS, Linux, and Windows (Git Bash / PowerShell / CMD).
#
# Usage:
#   git template                            (Interactive Template Manager menu)
#   git template create [name]              (Create a new template interactively)
#   git template run [name]                 (Run a template via git-report)
#   git template edit [name]                (Edit an existing template)
#   git template list                       (List all saved templates)
#   git template remove [name]              (Delete saved templates)
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

cleanup_on_exit() {
  printf "\033[?7h\033[?25h"
}

handle_interrupt() {
  cleanup_on_exit
  echo -e "\n${YELLOW}⚠️  Session exited (Ctrl+C).${NC}"
  exit 130
}

trap cleanup_on_exit EXIT
trap handle_interrupt INT TERM

# Resolve real script path so we can invoke git-report.sh reliably
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GIT_REPORT_SCRIPT="$TOOLKIT_ROOT/tools/git-report/git-report.sh"

# Preserve caller directory
if [ -n "${GIT_PREFIX:-}" ]; then
  CALLER_DIR="$(pwd)/${GIT_PREFIX%/}"
else
  CALLER_DIR="$(pwd)"
fi

CONFIG_DIR="${GIT_REPORT_CONFIG_DIR:-$HOME/.config/developer-toolkit}"
REPOS_FILE="$CONFIG_DIR/repos.conf"
TEMPLATES_FILE="$CONFIG_DIR/templates.conf"

mkdir -p "$CONFIG_DIR" 2>/dev/null || true
[ -f "$REPOS_FILE" ] || touch "$REPOS_FILE" 2>/dev/null || true
[ -f "$TEMPLATES_FILE" ] || touch "$TEMPLATES_FILE" 2>/dev/null || true

# ==============================================================================
# Help & Usage
# ==============================================================================

show_help() {
  echo -e "${CYAN}======================================================${NC}"
  echo -e "${CYAN}📋 Git Report Template Manager (git-template)${NC}"
  echo -e "${CYAN}======================================================${NC}"
  echo -e "Save and manage reusable report templates with pre-selected repositories,"
  echo -e "shared or per-repo branches, author filters, and optional date presets."
  echo -e ""
  echo -e "${BOLD}Usage:${NC}"
  echo -e "  git template                          Launch interactive Template Manager"
  echo -e "  git template create [template_name]   Create a new report template"
  echo -e "  git template run [template_name]      Run a saved template immediately"
  echo -e "  git template edit [template_name]     Edit an existing template"
  echo -e "  git template list                     List all saved templates"
  echo -e "  git template remove [template_name]   Delete one or more templates"
  echo -e ""
  echo -e "${BOLD}Examples:${NC}"
  echo -e "  git template                          # Open interactive menu"
  echo -e "  git template create core-weekly       # Create 'core-weekly' template"
  echo -e "  git template run core-weekly          # Generate report using 'core-weekly'"
  echo -e "  git report -t core-weekly             # Same via git report"
}

# ==============================================================================
# Load Linked Repositories & Saved Templates
# ==============================================================================

REPO_NAMES=()
REPO_TYPES=()
REPO_PATHS=()
REPO_SOURCES=()

load_repos() {
  REPO_NAMES=()
  REPO_TYPES=()
  REPO_PATHS=()
  REPO_SOURCES=()

  [ ! -f "$REPOS_FILE" ] && return 0

  while IFS='|' read -r r_name r_type r_path r_source || [ -n "$r_name" ]; do
    [ -z "$r_name" ] && continue
    [[ "$r_name" =~ ^# ]] && continue
    if [ -z "$r_path" ] && [ -n "$r_type" ]; then
      r_path="$r_type"
      r_type="local"
      r_source="$r_path"
    fi
    [ -z "$r_source" ] && r_source="$r_path"
    REPO_NAMES+=("$r_name")
    REPO_TYPES+=("$r_type")
    REPO_PATHS+=("$r_path")
    REPO_SOURCES+=("$r_source")
  done < "$REPOS_FILE"
}

# Template format: name|repos_csv|branch_spec|author_mode|author_pattern|date_preset
TPL_NAMES=()
TPL_REPOS=()
TPL_BRANCHES=()
TPL_AUTHOR_MODES=()
TPL_AUTHOR_PATTERNS=()
TPL_DATE_PRESETS=()

load_templates() {
  TPL_NAMES=()
  TPL_REPOS=()
  TPL_BRANCHES=()
  TPL_AUTHOR_MODES=()
  TPL_AUTHOR_PATTERNS=()
  TPL_DATE_PRESETS=()

  [ ! -f "$TEMPLATES_FILE" ] && return 0

  while IFS='|' read -r t_name t_repos t_branch t_amode t_apat t_date || [ -n "$t_name" ]; do
    [ -z "$t_name" ] && continue
    [[ "$t_name" =~ ^# ]] && continue
    TPL_NAMES+=("$t_name")
    TPL_REPOS+=("$t_repos")
    TPL_BRANCHES+=("${t_branch:-develop}")
    TPL_AUTHOR_MODES+=("${t_amode:-all}")
    TPL_AUTHOR_PATTERNS+=("${t_apat:-}")
    TPL_DATE_PRESETS+=("${t_date:-ask}")
  done < "$TEMPLATES_FILE"
}

save_template_entry() {
  local name="$1"
  local repos_csv="$2"
  local branch_spec="$3"
  local author_mode="$4"
  local author_pattern="$5"
  local date_preset="$6"

  load_templates
  local tmp_file="${TEMPLATES_FILE}.tmp"
  : > "$tmp_file"

  local updated=0
  local i
  for ((i = 0; i < ${#TPL_NAMES[@]}; i++)); do
    if [ "${TPL_NAMES[$i]}" = "$name" ]; then
      echo "${name}|${repos_csv}|${branch_spec}|${author_mode}|${author_pattern}|${date_preset}" >> "$tmp_file"
      updated=1
    else
      echo "${TPL_NAMES[$i]}|${TPL_REPOS[$i]}|${TPL_BRANCHES[$i]}|${TPL_AUTHOR_MODES[$i]}|${TPL_AUTHOR_PATTERNS[$i]}|${TPL_DATE_PRESETS[$i]}" >> "$tmp_file"
    fi
  done

  if [ "$updated" -eq 0 ]; then
    echo "${name}|${repos_csv}|${branch_spec}|${author_mode}|${author_pattern}|${date_preset}" >> "$tmp_file"
  fi

  mv "$tmp_file" "$TEMPLATES_FILE"
}

# ==============================================================================
# Interactive Checkbox & Radio UI Helpers
# ==============================================================================

ITEMS_LABELS=()
ITEMS_HINTS=()
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

interactive_multi_select() {
  local title="$1"
  local prechecked_csv="${2:-}"
  local total="${#ITEMS_LABELS[@]}"
  SELECTED_INDICES=()

  [ "$total" -eq 0 ] && return 1

  local checked=()
  local i
  for ((i = 0; i < total; i++)); do
    local is_pre=0
    if [ -n "$prechecked_csv" ]; then
      IFS=',' read -r -a pre_arr <<< "$prechecked_csv"
      local p
      for p in "${pre_arr[@]}"; do
        if [ "$p" = "${ITEMS_LABELS[$i]}" ]; then
          is_pre=1
          break
        fi
      done
    fi
    checked+=("$is_pre")
  done

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    for ((i = 0; i < total; i++)); do
      SELECTED_INDICES+=("$i")
    done
    return 0
  fi

  local cursor=0
  local use_number_mode=0

  echo -e "\n${CYAN}${BOLD}${title}${NC}"
  echo -e "${DIM}Controls: [↑/↓ or j/k] Move  [Space] Toggle  [a] Toggle All  [n] Type Numbers  [Enter] Confirm  [Ctrl+C/q] Exit${NC}"

  draw_checklist() {
    printf "\033[?25l\033[?7l"
    local idx
    for ((idx = 0; idx < total; idx++)); do
      local mark=" "
      [ "${checked[$idx]}" -eq 1 ] && mark="${GREEN}✔${NC}"
      local pointer="  "
      local label_style="${NC}"
      if [ "$idx" -eq "$cursor" ]; then
        pointer="${CYAN}❯ ${NC}"
        label_style="${BOLD}"
      fi
      local num=$((idx + 1))
      local hint=""
      [ -n "${ITEMS_HINTS[$idx]:-}" ] && hint=" ${DIM}${ITEMS_HINTS[$idx]}${NC}"
      printf "\r\033[2K%b[%b] %d) %b%s%b%b\n" "$pointer" "$mark" "$num" "$label_style" "${ITEMS_LABELS[$idx]}" "${NC}" "$hint"
    done
    printf "\033[?7h\033[?25h"
  }

  draw_checklist

  while true; do
    IFS= read -rsn1 key || true

    if [[ "$key" == $'\x03' ]] || [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      handle_interrupt
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
    elif [ "$key" = " " ]; then
      if [ "${checked[$cursor]}" -eq 1 ]; then
        checked[$cursor]=0
      else
        checked[$cursor]=1
      fi
    elif [ "$key" = "a" ] || [ "$key" = "A" ]; then
      local all_on=1
      for ((i = 0; i < total; i++)); do
        if [ "${checked[$i]}" -eq 0 ]; then
          all_on=0
          break
        fi
      done
      local new_val=$((1 - all_on))
      for ((i = 0; i < total; i++)); do
        checked[$i]="$new_val"
      done
    elif [ "$key" = "n" ] || [ "$key" = "N" ]; then
      use_number_mode=1
      break
    elif [ "$key" = "" ]; then
      SELECTED_INDICES=()
      for ((i = 0; i < total; i++)); do
        if [ "${checked[$i]}" -eq 1 ]; then
          SELECTED_INDICES+=("$i")
        fi
      done
      if [ "${#SELECTED_INDICES[@]}" -gt 0 ]; then
        break
      fi
    fi

    printf "\033[%dA" "$total"
    draw_checklist
  done

  if [ "$use_number_mode" -eq 1 ]; then
    while true; do
      echo -ne "\n${YELLOW}Enter numbers (e.g. 1,3,5 or 1-4 or 'all'): ${NC}"
      read -r num_input
      if parse_number_selection "$num_input" "$total"; then
        break
      fi
      echo -e "${RED}⚠️  Please enter valid item numbers between 1 and ${total}.${NC}"
    done
  fi

  return 0
}

RADIO_LABELS=()
RADIO_HINTS=()
RADIO_SELECTED_INDEX=0

interactive_radio_select() {
  local title="$1"
  local default_idx="${2:-0}"
  local total="${#RADIO_LABELS[@]}"
  RADIO_SELECTED_INDEX="$default_idx"

  [ "$total" -eq 0 ] && return 1
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    return 0
  fi

  local cursor="$default_idx"
  if [ "$cursor" -lt 0 ] || [ "$cursor" -ge "$total" ]; then
    cursor=0
  fi

  echo -e "\n${CYAN}${BOLD}${title}${NC}"
  echo -e "${DIM}Controls: [↑/↓ or j/k] Move  [Enter/Space] Select  [Ctrl+C/q] Exit${NC}"

  draw_radio_list() {
    printf "\033[?25l\033[?7l"
    local idx
    for ((idx = 0; idx < total; idx++)); do
      local radio="( )"
      local pointer="  "
      local label_style="${NC}"
      if [ "$idx" -eq "$cursor" ]; then
        radio="(${GREEN}◉${NC})"
        pointer="${CYAN}❯ ${NC}"
        label_style="${BOLD}"
      fi
      local num=$((idx + 1))
      local hint=""
      [ -n "${RADIO_HINTS[$idx]:-}" ] && hint=" ${DIM}${RADIO_HINTS[$idx]}${NC}"
      printf "\r\033[2K%b%b %d) %b%s%b%b\n" "$pointer" "$radio" "$num" "$label_style" "${RADIO_LABELS[$idx]}" "${NC}" "$hint"
    done
    printf "\033[?7h\033[?25h"
  }

  draw_radio_list

  while true; do
    IFS= read -rsn1 key || true

    if [[ "$key" == $'\x03' ]] || [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      handle_interrupt
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
    elif [ "$key" = "" ] || [ "$key" = " " ]; then
      RADIO_SELECTED_INDEX="$cursor"
      break
    elif [[ "$key" =~ ^[1-9]$ ]] && [ "$key" -le "$total" ]; then
      cursor=$((key - 1))
      printf "\033[%dA" "$total"
      draw_radio_list
      RADIO_SELECTED_INDEX="$cursor"
      break
    fi

    printf "\033[%dA" "$total"
    draw_radio_list
  done

  return 0
}

# ==============================================================================
# Remote Branch Discovery & Per-Repo Branch Selector
# ==============================================================================

get_repo_branches() {
  local repo_path="$1"
  local curr_branch
  curr_branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

  local ref_scope="refs/heads"
  if git -C "$repo_path" remote get-url origin >/dev/null 2>&1; then
    git -C "$repo_path" fetch origin --prune --quiet 2>/dev/null || true
    if [ -n "$(git -C "$repo_path" for-each-ref --count=1 refs/remotes/origin 2>/dev/null)" ]; then
      ref_scope="refs/remotes/origin"
    fi
  fi

  local raw_branches=()
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    b="${b#origin/}"
    [ "$b" = "HEAD" ] || [ "$b" = "origin" ] && continue
    raw_branches+=("$b")
  done < <(
    git -C "$repo_path" for-each-ref --format='%(refname:short)' "$ref_scope" 2>/dev/null
  )

  local ordered=()
  local priority=("$curr_branch" "develop" "main" "master" "staging")
  local p b existing already

  for p in "${priority[@]}"; do
    [ -z "$p" ] || [ "$p" = "HEAD" ] && continue
    for b in "${raw_branches[@]}"; do
      if [ "$b" = "$p" ]; then
        already=0
        for existing in "${ordered[@]}"; do
          [ "$existing" = "$p" ] && already=1 && break
        done
        [ "$already" -eq 0 ] && ordered+=("$p")
        break
      fi
    done
  done

  for b in "${raw_branches[@]}"; do
    already=0
    for existing in "${ordered[@]}"; do
      [ "$existing" = "$b" ] && already=1 && break
    done
    [ "$already" -eq 0 ] && ordered+=("$b")
  done

  for b in "${ordered[@]}"; do
    echo "$b"
  done
}

PICKED_BRANCH=""
prompt_branch_for_repo() {
  local r_name="$1"
  local r_path="$2"
  local curr_branch
  curr_branch=$(git -C "$r_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

  local branches=()
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    branches+=("$b")
  done < <(get_repo_branches "$r_path")

  if [ "${#branches[@]}" -eq 0 ]; then
    echo -ne "${YELLOW}Enter branch name for ${BOLD}${r_name}${NC}${YELLOW} (default: develop): ${NC}"
    read -r custom_b
    PICKED_BRANCH="${custom_b:-develop}"
    return 0
  fi

  RADIO_LABELS=()
  RADIO_HINTS=()
  local max_show=12
  local i
  for ((i = 0; i < ${#branches[@]} && i < max_show; i++)); do
    RADIO_LABELS+=("${branches[$i]}")
    if [ "${branches[$i]}" = "$curr_branch" ]; then
      RADIO_HINTS+=("(current)")
    else
      RADIO_HINTS+=("")
    fi
  done
  local custom_idx="${#RADIO_LABELS[@]}"
  RADIO_LABELS+=("Custom branch name...")
  RADIO_HINTS+=("(type any branch)")

  interactive_radio_select "🌿 Select branch for ${r_name} (current: ${curr_branch:-none}):" 0

  if [ "$RADIO_SELECTED_INDEX" -eq "$custom_idx" ]; then
    echo -ne "\n${YELLOW}Enter custom branch name for ${BOLD}${r_name}${NC}${YELLOW}: ${NC}"
    read -r custom_b
    PICKED_BRANCH="${custom_b:-${branches[0]}}"
  else
    PICKED_BRANCH="${RADIO_LABELS[$RADIO_SELECTED_INDEX]}"
  fi
}

# ==============================================================================
# Template Operations: List, Create/Edit, Run, Remove
# ==============================================================================

cmd_list_templates() {
  load_templates
  echo -e "${CYAN}======================================================${NC}"
  echo -e "${CYAN}📋 Saved Report Templates (${#TPL_NAMES[@]})${NC}"
  echo -e "${CYAN}======================================================${NC}"

  if [ "${#TPL_NAMES[@]}" -eq 0 ]; then
    echo -e "${YELLOW}No report templates saved yet.${NC}"
    echo -e "Run ${CYAN}git template create${NC} (or ${CYAN}git template${NC}) to build your first template!"
    echo ""
    return 0
  fi

  local i
  for ((i = 0; i < ${#TPL_NAMES[@]}; i++)); do
    local idx=$((i + 1))
    local t_name="${TPL_NAMES[$i]}"
    local t_repos="${TPL_REPOS[$i]}"
    local t_branch="${TPL_BRANCHES[$i]}"
    local t_amode="${TPL_AUTHOR_MODES[$i]}"
    local t_apat="${TPL_AUTHOR_PATTERNS[$i]}"
    local t_date="${TPL_DATE_PRESETS[$i]}"

    local author_desc="$t_amode"
    [ "$t_amode" = "me" ] && author_desc="My commits only"
    [ "$t_amode" = "all" ] && author_desc="All authors"
    [ "$t_amode" = "custom" ] && author_desc="Author: ${t_apat}"

    local date_desc="$t_date"
    [ "$t_date" = "ask" ] && date_desc="Ask each time"

    echo -e "  ${BOLD}${idx}.${NC} ${GREEN}📋 ${BOLD}${t_name}${NC}"
    echo -e "     • Repos:    ${BLUE}${t_repos}${NC}"
    echo -e "     • Branches: ${YELLOW}${t_branch}${NC}"
    echo -e "     • Author:   ${CYAN}${author_desc}${NC}  |  Date: ${CYAN}${date_desc}${NC}"
  done
  echo ""
}

cmd_create_or_edit_template() {
  local preset_name="${1:-}"
  local existing_repos=""
  local i

  load_repos
  if [ "${#REPO_NAMES[@]}" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No repositories are linked yet! Let's link your repositories first.${NC}"
    bash "$GIT_REPORT_SCRIPT" scan "$CALLER_DIR"
    load_repos
    [ "${#REPO_NAMES[@]}" -eq 0 ] && exit 1
  fi

  load_templates
  if [ -z "$preset_name" ]; then
    echo -ne "\n${YELLOW}Enter a name for this template (e.g. core-weekly, my-standup): ${NC}"
    read -r preset_name
    preset_name="${preset_name// /_}"
    preset_name="${preset_name//|/}"
    if [ -z "$preset_name" ]; then
      echo -e "${RED}❌ Error: Template name cannot be empty.${NC}"
      exit 1
    fi
  fi

  for ((i = 0; i < ${#TPL_NAMES[@]}; i++)); do
    if [ "${TPL_NAMES[$i]}" = "$preset_name" ]; then
      existing_repos="${TPL_REPOS[$i]}"
      break
    fi
  done

  # Step 1: Select repositories for the template
  ITEMS_LABELS=()
  ITEMS_HINTS=()
  for ((i = 0; i < ${#REPO_NAMES[@]}; i++)); do
    ITEMS_LABELS+=("${REPO_NAMES[$i]}")
    ITEMS_HINTS+=("[${REPO_TYPES[$i]}]")
  done
  interactive_multi_select "Template '${preset_name}' — Step 1: Select Repositories:" "$existing_repos"

  local chosen_indices=("${SELECTED_INDICES[@]}")
  local chosen_names=()
  for idx in "${chosen_indices[@]}"; do
    chosen_names+=("${REPO_NAMES[$idx]}")
  done
  local repos_csv
  IFS=',' eval 'repos_csv="${chosen_names[*]}"'

  # Step 2: Select Target Branch (shared or per-repo)
  RADIO_LABELS=(
    "develop"
    "main"
    "master"
    "staging"
    "Select branch individually per repo"
    "CURRENT"
    "Custom branch name..."
  )
  RADIO_HINTS=(
    "(all selected repos)"
    "(all selected repos)"
    "(all selected repos)"
    "(all selected repos)"
    "(pick different branch for each repo)"
    "(each repo's currently checked-out branch)"
    "(type a custom branch name)"
  )
  interactive_radio_select "Template '${preset_name}' — Step 2: Select Target Branch:" 0

  local branch_spec="develop"
  case "$RADIO_SELECTED_INDEX" in
    0) branch_spec="develop" ;;
    1) branch_spec="main" ;;
    2) branch_spec="master" ;;
    3) branch_spec="staging" ;;
    4)
      local mappings=()
      for idx in "${chosen_indices[@]}"; do
        local r_name="${REPO_NAMES[$idx]}"
        local r_path="${REPO_PATHS[$idx]}"
        prompt_branch_for_repo "$r_name" "$r_path"
        mappings+=("${r_name}:${PICKED_BRANCH}")
      done
      IFS=',' eval 'branch_spec="${mappings[*]}"'
      ;;
    5) branch_spec="CURRENT" ;;
    6)
      echo -ne "\n${YELLOW}Enter custom branch name: ${NC}"
      read -r branch_spec
      branch_spec="${branch_spec:-develop}"
      ;;
  esac

  # Step 3: Select Author Filter
  RADIO_LABELS=(
    "All authors"
    "My commits only"
    "Specific author name or email..."
  )
  RADIO_HINTS=(
    "(default)"
    "(git config user.email / user.name)"
    ""
  )
  interactive_radio_select "Template '${preset_name}' — Step 3: Select Commit Author Filter:" 0

  local author_mode="all"
  local author_pattern=""
  case "$RADIO_SELECTED_INDEX" in
    1) author_mode="me" ;;
    2)
      author_mode="custom"
      echo -ne "\n${YELLOW}Enter author name or email: ${NC}"
      read -r author_pattern
      author_pattern="${author_pattern//|/}"
      ;;
    *) author_mode="all" ;;
  esac

  # Step 4: Select Default Date Behavior
  RADIO_LABELS=(
    "Ask me for the date range each time"
    "Today"
    "Yesterday"
    "Last 7 days"
    "This week (Mon -> Today)"
    "Last week (Prev Mon -> Prev Sun)"
    "This month (1st -> Today)"
    "Last month"
    "Last 14 days"
    "Last 30 days"
  )
  RADIO_HINTS=(
    "(recommended — prompts only for date range when run)"
    "(fixed 1-click preset)"
    "(fixed 1-click preset)"
    "(fixed 1-click preset)"
    "(fixed 1-click preset)"
    "(fixed 1-click preset)"
    "(fixed 1-click preset)"
    "(fixed 1-click preset)"
    "(fixed 1-click preset)"
    "(fixed 1-click preset)"
  )
  interactive_radio_select "Template '${preset_name}' — Step 4: Default Date Range:" 0

  local date_preset="ask"
  case "$RADIO_SELECTED_INDEX" in
    0) date_preset="ask" ;;
    1) date_preset="today" ;;
    2) date_preset="yesterday" ;;
    3) date_preset="last-7-days" ;;
    4) date_preset="this-week" ;;
    5) date_preset="last-week" ;;
    6) date_preset="this-month" ;;
    7) date_preset="last-month" ;;
    8) date_preset="last-14-days" ;;
    9) date_preset="last-30-days" ;;
  esac

  save_template_entry "$preset_name" "$repos_csv" "$branch_spec" "$author_mode" "$author_pattern" "$date_preset"

  echo -e "\n${GREEN}======================================================${NC}"
  echo -e "${GREEN}✅ Saved template '${BOLD}${preset_name}${NC}${GREEN}'!${NC}"
  echo -e "   • Repos:    ${BLUE}${repos_csv}${NC}"
  echo -e "   • Branches: ${YELLOW}${branch_spec}${NC}"
  echo -e "   • Author:   ${CYAN}${author_mode}${author_pattern:+ ($author_pattern)}${NC}"
  echo -e "   • Date:     ${CYAN}${date_preset}${NC}"
  echo -e "${GREEN}======================================================${NC}"
  echo -e "💡 Run it anytime with: ${CYAN}${BOLD}git report -t ${preset_name}${NC} (or ${CYAN}${BOLD}git report${NC})\n"
}

cmd_edit_template() {
  local target_name="${1:-}"
  load_templates
  if [ "${#TPL_NAMES[@]}" -eq 0 ]; then
    echo -e "${YELLOW}No templates saved yet. Creating a new template...${NC}"
    cmd_create_or_edit_template
    return 0
  fi

  if [ -z "$target_name" ]; then
    RADIO_LABELS=()
    RADIO_HINTS=()
    local i
    for ((i = 0; i < ${#TPL_NAMES[@]}; i++)); do
      RADIO_LABELS+=("${TPL_NAMES[$i]}")
      RADIO_HINTS+=("(${TPL_REPOS[$i]} | ${TPL_BRANCHES[$i]})")
    done
    interactive_radio_select "Select a template to edit:" 0
    target_name="${TPL_NAMES[$RADIO_SELECTED_INDEX]}"
  fi

  cmd_create_or_edit_template "$target_name"
}

cmd_run_template() {
  local target_name="${1:-}"
  shift || true

  load_templates
  if [ "${#TPL_NAMES[@]}" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No templates saved yet. Let's create one first!${NC}"
    cmd_create_or_edit_template
    load_templates
    [ "${#TPL_NAMES[@]}" -eq 0 ] && exit 0
    target_name="${TPL_NAMES[0]}"
  fi

  if [ -z "$target_name" ]; then
    RADIO_LABELS=()
    RADIO_HINTS=()
    local i
    for ((i = 0; i < ${#TPL_NAMES[@]}; i++)); do
      RADIO_LABELS+=("${TPL_NAMES[$i]}")
      RADIO_HINTS+=("(${TPL_REPOS[$i]} | ${TPL_BRANCHES[$i]})")
    done
    interactive_radio_select "Select a template to run:" 0
    target_name="${TPL_NAMES[$RADIO_SELECTED_INDEX]}"
  fi

  exec bash "$GIT_REPORT_SCRIPT" -t "$target_name" "$@"
}

cmd_remove_template() {
  load_templates
  if [ "${#TPL_NAMES[@]}" -eq 0 ]; then
    echo -e "${YELLOW}No templates are currently saved.${NC}"
    return 0
  fi

  local to_remove=()
  if [ $# -gt 0 ]; then
    for arg in "$@"; do
      to_remove+=("$arg")
    done
  else
    ITEMS_LABELS=()
    ITEMS_HINTS=()
    local i
    for ((i = 0; i < ${#TPL_NAMES[@]}; i++)); do
      ITEMS_LABELS+=("${TPL_NAMES[$i]}")
      ITEMS_HINTS+=("(${TPL_REPOS[$i]} | ${TPL_BRANCHES[$i]})")
    done
    interactive_multi_select "Select template(s) to delete:" ""
    for idx in "${SELECTED_INDICES[@]}"; do
      to_remove+=("${TPL_NAMES[$idx]}")
    done
  fi

  local tmp_file="${TEMPLATES_FILE}.tmp"
  : > "$tmp_file"
  local removed=0
  local i r match
  for ((i = 0; i < ${#TPL_NAMES[@]}; i++)); do
    match=0
    for r in "${to_remove[@]}"; do
      if [ "$r" = "${TPL_NAMES[$i]}" ]; then
        match=1
        break
      fi
    done
    if [ "$match" -eq 1 ]; then
      echo -e "   ${GREEN}✔${NC} Deleted template: ${BOLD}${TPL_NAMES[$i]}${NC}"
      removed=$((removed + 1))
    else
      echo "${TPL_NAMES[$i]}|${TPL_REPOS[$i]}|${TPL_BRANCHES[$i]}|${TPL_AUTHOR_MODES[$i]}|${TPL_AUTHOR_PATTERNS[$i]}|${TPL_DATE_PRESETS[$i]}" >> "$tmp_file"
    fi
  done

  mv "$tmp_file" "$TEMPLATES_FILE"
  echo -e "${GREEN}✅ Deleted ${removed} template(s).${NC}"
}

# ==============================================================================
# Main Interactive Menu & CLI Routing
# ==============================================================================

for arg in "$@"; do
  if [ "$arg" = "-h" ] || [ "$arg" = "--help" ] || [ "$arg" = "help" ]; then
    show_help
    exit 0
  elif [ "$arg" = "-v" ] || [ "$arg" = "-V" ] || [ "$arg" = "--version" ] || [ "$arg" = "version" ]; then
    TOOLKIT_VERSION="2.0.0"
    [ -f "$TOOLKIT_ROOT/VERSION" ] && read -r TOOLKIT_VERSION < "$TOOLKIT_ROOT/VERSION" || true
    echo "git-template (Developer Toolkit) ${TOOLKIT_VERSION:-2.0.0}"
    exit 0
  fi
done

if [ $# -gt 0 ]; then
  case "$1" in
    create|add|new)
      shift
      cmd_create_or_edit_template "$@"
      exit 0
      ;;
    edit|update)
      shift
      cmd_edit_template "$@"
      exit 0
      ;;
    run|use)
      shift
      cmd_run_template "$@"
      exit 0
      ;;
    list|ls)
      shift
      cmd_list_templates
      exit 0
      ;;
    remove|rm|delete)
      shift
      cmd_remove_template "$@"
      exit 0
      ;;
    *)
      # If they passed a template name directly (e.g. `git template core-weekly`), run it!
      cmd_run_template "$@"
      exit 0
      ;;
  esac
fi

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}📋 Git Report Template Manager${NC}"
echo -e "${CYAN}======================================================${NC}"

load_templates
RADIO_LABELS=(
  "Run a saved template"
  "Create a new template"
  "Edit an existing template"
  "List all saved templates"
  "Delete template(s)"
  "Exit"
)
RADIO_HINTS=(
  "(${#TPL_NAMES[@]} saved)"
  "(pre-select repos, branches & author)"
  "(modify saved template settings)"
  "(view details)"
  ""
  ""
)

default_menu_idx=0
[ "${#TPL_NAMES[@]}" -eq 0 ] && default_menu_idx=1

interactive_radio_select "What would you like to do?" "$default_menu_idx"

case "$RADIO_SELECTED_INDEX" in
  0) cmd_run_template ;;
  1) cmd_create_or_edit_template ;;
  2) cmd_edit_template ;;
  3)
    echo ""
    cmd_list_templates
    ;;
  4) cmd_remove_template ;;
  *) exit 0 ;;
esac
