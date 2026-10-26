#!/usr/bin/env bash

# ==============================================================================
# Script: git-report.sh
# Purpose: Link multiple Git repositories (local folders or remote URLs) and
#          generate commit message reports across selected repos, branches,
#          and date ranges (presets or custom dates).
#          Compatible with macOS, Linux, and Windows (Git Bash / PowerShell / CMD).
#
# Usage:
#   git report                              (Interactive wizard)
#   git report add [path_or_url]            (Link local repo or remote URL)
#   git report scan [workspace_dir]         (Auto-discover & link local repos)
#   git report list                         (List linked repositories)
#   git report remove [repo_name]           (Unlink repository)
#   git report -r repoA,repoB -b main -p last-7-days
# ==============================================================================

set -eo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Safety state variables in case of Ctrl+C during branch checkout/pull/stash
ACTIVE_REPO_NAME=""
ACTIVE_REPO_PATH=""
ACTIVE_ORIG_BRANCH=""
ACTIVE_STASH_TOKEN=""
ACTIVE_REPO_STASHED=0
ACTIVE_REPO_SWITCHED=0

cleanup_on_exit() {
  trap '' INT TERM
  printf "\033[?7h\033[?25h"

  if [ -n "$ACTIVE_REPO_PATH" ] && [ -d "$ACTIVE_REPO_PATH" ]; then
    local rpath="$ACTIVE_REPO_PATH"
    local rname="${ACTIVE_REPO_NAME:-repo}"
    local orig_b="$ACTIVE_ORIG_BRANCH"
    local stashed="$ACTIVE_REPO_STASHED"
    local stash_tok="$ACTIVE_STASH_TOKEN"

    # Clear state immediately so cleanup never runs twice
    ACTIVE_REPO_PATH=""
    ACTIVE_REPO_NAME=""
    ACTIVE_ORIG_BRANCH=""
    ACTIVE_STASH_TOKEN=""
    ACTIVE_REPO_STASHED=0
    ACTIVE_REPO_SWITCHED=0

    # Clean stale index.lock if an interrupted git subprocess left one behind
    local git_dir
    git_dir=$(git -C "$rpath" rev-parse --git-dir 2>/dev/null || true)
    if [ -n "$git_dir" ] && [ -f "$rpath/$git_dir/index.lock" ]; then
      rm -f "$rpath/$git_dir/index.lock" 2>/dev/null || true
    elif [ -n "$git_dir" ] && [ -f "$git_dir/index.lock" ]; then
      rm -f "$git_dir/index.lock" 2>/dev/null || true
    fi

    # 1. Switch back to original branch if currently on a different branch
    if [ -n "$orig_b" ] && [ "$orig_b" != "HEAD" ]; then
      local curr_b
      curr_b=$(git -C "$rpath" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
      if [ "$curr_b" != "$orig_b" ]; then
        echo -e "\n   ${CYAN}↩️  [${rname}] Interrupted — switching back to '${orig_b}'...${NC}"
        git -C "$rpath" checkout -f "$orig_b" --quiet 2>/dev/null || git -C "$rpath" checkout "$orig_b" --quiet 2>/dev/null || true
      fi
    fi

    # 2. Restore stashed code if stashed (or if top stash matches our token)
    local top_stash=""
    if [ -n "$stash_tok" ]; then
      top_stash=$(git -C "$rpath" stash list -n 1 2>/dev/null || true)
    fi
    if [ "$stashed" -eq 1 ] || { [ -n "$stash_tok" ] && [[ "$top_stash" == *"$stash_tok"* ]]; }; then
      echo -e "   ${YELLOW}📥 [${rname}] Restoring your stashed code changes...${NC}"
      if git -C "$rpath" stash pop --quiet 2>/dev/null; then
        echo -e "   ${GREEN}✅ [${rname}] Restored branch '${orig_b}' and your code changes!${NC}"
      else
        echo -e "   ${YELLOW}⚠️  [${rname}] Stash restored with conflicts; check 'git status'.${NC}"
      fi
    fi
  fi
}

handle_interrupt() {
  cleanup_on_exit
  echo -e "\n${YELLOW}⚠️  Session exited (Ctrl+C).${NC}"
  exit 130
}

trap cleanup_on_exit EXIT
trap handle_interrupt INT TERM

# Preserve exact directory where the user ran the command
# (When invoked as a `git report` alias inside a repo subdir, Git sets GIT_PREFIX)
if [ -n "${GIT_PREFIX:-}" ]; then
  CALLER_DIR="$(pwd)/${GIT_PREFIX%/}"
else
  CALLER_DIR="$(pwd)"
fi

# Configuration paths
CONFIG_DIR="${GIT_REPORT_CONFIG_DIR:-$HOME/.config/developer-toolkit}"
REPOS_FILE="$CONFIG_DIR/repos.conf"
TEMPLATES_FILE="$CONFIG_DIR/templates.conf"
REMOTES_DIR="$CONFIG_DIR/remotes"

mkdir -p "$CONFIG_DIR" 2>/dev/null || true
[ -f "$REPOS_FILE" ] || touch "$REPOS_FILE" 2>/dev/null || true
[ -f "$TEMPLATES_FILE" ] || touch "$TEMPLATES_FILE" 2>/dev/null || true

# Template arrays
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
# Helper Functions: Cross-Platform Path & Date Utilities
# ==============================================================================

normalize_input_path() {
  local raw_path="$1"
  # Expand leading ~
  if [[ "$raw_path" == "~"* ]]; then
    raw_path="${HOME}${raw_path#\~}"
  fi
  # Convert Windows backslashes to forward slashes
  raw_path="${raw_path//\\//}"
  # Resolve relative paths against CALLER_DIR
  if [[ "$raw_path" != /* ]] && [[ ! "$raw_path" =~ ^[A-Za-z]:/ ]]; then
    raw_path="${CALLER_DIR}/${raw_path}"
  fi
  echo "$raw_path"
}

is_remote_url() {
  local target="$1"
  if [[ "$target" =~ ^(https?|ssh|git|file):// ]] || [[ "$target" =~ ^git@ ]]; then
    return 0
  fi
  # If it ends in .git and does not exist as a local directory
  if [[ "$target" == *.git ]] && [ ! -d "$target" ] && [ ! -d "${CALLER_DIR}/${target}" ]; then
    return 0
  fi
  return 1
}

extract_repo_name_from_url() {
  local url="$1"
  url="${url%/}"
  local base="${url##*/}"
  base="${base##*:}"
  base="${base%.git}"
  echo "$base"
}

# Detect whether the system `date` is GNU date (Linux / Windows Git Bash) or BSD date (macOS)
is_gnu_date() {
  date -d "2026-01-01" "+%Y-%m-%d" >/dev/null 2>&1
}

# Return date string YYYY-MM-DD shifted by N days from today (e.g., -7)
date_shift_days() {
  local offset="$1"
  if is_gnu_date; then
    date -d "${offset} days" "+%Y-%m-%d"
  else
    if [ "$offset" -ge 0 ]; then
      date -v+"${offset}"d "+%Y-%m-%d"
    else
      date -v"${offset}"d "+%Y-%m-%d"
    fi
  fi
}

# Compute FROM_DATE and TO_DATE ("YYYY-MM-DD") from a named preset
compute_date_preset() {
  local preset="$1"
  local today
  today=$(date "+%Y-%m-%d")

  case "$preset" in
    today)
      FROM_DATE="$today"
      TO_DATE="$today"
      PRESET_LABEL="Today ($today)"
      ;;
    yesterday)
      FROM_DATE=$(date_shift_days -1)
      TO_DATE="$FROM_DATE"
      PRESET_LABEL="Yesterday ($FROM_DATE)"
      ;;
    last-7-days|7d)
      FROM_DATE=$(date_shift_days -6)
      TO_DATE="$today"
      PRESET_LABEL="Last 7 Days ($FROM_DATE -> $TO_DATE)"
      ;;
    last-14-days|14d)
      FROM_DATE=$(date_shift_days -13)
      TO_DATE="$today"
      PRESET_LABEL="Last 14 Days ($FROM_DATE -> $TO_DATE)"
      ;;
    last-30-days|30d)
      FROM_DATE=$(date_shift_days -29)
      TO_DATE="$today"
      PRESET_LABEL="Last 30 Days ($FROM_DATE -> $TO_DATE)"
      ;;
    this-week)
      # Day of week: 1=Mon .. 7=Sun
      local dow
      dow=$(date "+%u")
      local diff=$((1 - dow))
      FROM_DATE=$(date_shift_days "$diff")
      TO_DATE="$today"
      PRESET_LABEL="This Week ($FROM_DATE -> $TO_DATE)"
      ;;
    last-week)
      local dow
      dow=$(date "+%u")
      local prev_mon=$((1 - dow - 7))
      local prev_sun=$((prev_mon + 6))
      FROM_DATE=$(date_shift_days "$prev_mon")
      TO_DATE=$(date_shift_days "$prev_sun")
      PRESET_LABEL="Last Week ($FROM_DATE -> $TO_DATE)"
      ;;
    this-month)
      FROM_DATE="$(date "+%Y-%m")-01"
      TO_DATE="$today"
      PRESET_LABEL="This Month ($FROM_DATE -> $TO_DATE)"
      ;;
    last-month)
      if is_gnu_date; then
        FROM_DATE=$(date -d "$(date +%Y-%m-01) -1 month" "+%Y-%m-01")
        TO_DATE=$(date -d "$(date +%Y-%m-01) -1 day" "+%Y-%m-%d")
      else
        FROM_DATE=$(date -v1d -v-1m "+%Y-%m-01")
        TO_DATE=$(date -v1d -v-1d "+%Y-%m-%d")
      fi
      PRESET_LABEL="Last Month ($FROM_DATE -> $TO_DATE)"
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

validate_date_format() {
  local d="$1"
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# ==============================================================================
# Help & Usage
# ==============================================================================

show_help() {
  echo -e "${CYAN}======================================================${NC}"
  echo -e "${CYAN}📊 Git Multi-Repo Commit Report Utility (git-report)${NC}"
  echo -e "${CYAN}======================================================${NC}"
  echo -e "Link multiple local or remote Git repositories and generate clean"
  echo -e "Markdown/Text commit reports filtered by branch, date range, and author."
  echo -e ""
  echo -e "${BOLD}Repository Management:${NC}"
  echo -e "  git report add [path_or_url] [--name <alias>]  Link local folder (0 MB) or remote Git URL"
  echo -e "  git report scan [workspace_dir] [--all]        Auto-discover & link Git repos in a folder"
  echo -e "  git report list                                List all linked repositories"
  echo -e "  git report remove [repo_name...]               Unlink repositories (interactive if no name)"
  echo -e ""
  echo -e "${BOLD}Generate Report (Interactive or CLI):${NC}"
  echo -e "  git report                                     Launch interactive step-by-step wizard"
  echo -e "  git report [options]"
  echo -e ""
  echo -e "${BOLD}Options:${NC}"
  echo -e "  -r, --repos <r1,r2>     Comma-separated repo names or indices (e.g. repoA,repoB or 1,3)"
  echo -e "  -a, --all               Select all linked repositories"
  echo -e "  -b, --branch <branch>   Target branch name (e.g. develop, main, CURRENT)"
  echo -e "  -p, --preset <preset>   Date preset:"
  echo -e "                            today, yesterday, last-7-days, this-week, last-week,"
  echo -e "                            this-month, last-month, last-14-days, last-30-days"
  echo -e "      --from <YYYY-MM-DD> Start date for custom range"
  echo -e "      --to <YYYY-MM-DD>   End date for custom range (defaults to today)"
  echo -e "      --me                Filter to only your commits (git config user.email/name)"
  echo -e "      --all-authors       Include commits from all authors"
  echo -e "      --author <pattern>  Filter commits by specific author name or email"
  echo -e "      --fetch             Fetch latest remote updates before querying logs"
  echo -e "      --include-merges    Include merge commits (excluded by default)"
  echo -e "      --detailed          Include short commit hash, date, and author in output"
  echo -e "      --format <md|txt>   Output file extension (default: md)"
  echo -e "  -o, --output <file>     Custom output filename inside ./report/ (or full path)"
  echo -e "  -h, --help              Show this help message"
  echo -e ""
  echo -e "${BOLD}Examples:${NC}"
  echo -e "  git report add                                 # Link current repo"
  echo -e "  git report add https://github.com/org/api.git  # Link remote repo (metadata only)"
  echo -e "  git report scan ~/Documents                    # Scan & pick repos from workspace"
  echo -e "  git report                                     # Run interactive report wizard"
  echo -e "  git report -r api,web -b develop -p this-week --me"
  echo -e "  git report --all -b main --from 2026-10-01 --to 2026-10-26"
}

# ==============================================================================
# Repository Registry Operations
# ==============================================================================

# Global arrays populated by load_repos
REPO_NAMES=()
REPO_TYPES=()
REPO_PATHS=()
REPO_SOURCES=()

load_repos() {
  REPO_NAMES=()
  REPO_TYPES=()
  REPO_PATHS=()
  REPO_SOURCES=()

  if [ ! -f "$REPOS_FILE" ]; then
    return 0
  fi

  while IFS='|' read -r r_name r_type r_path r_source || [ -n "$r_name" ]; do
    # Skip empty lines or comments
    [ -z "$r_name" ] && continue
    [[ "$r_name" =~ ^# ]] && continue

    # Backward compatibility for 2-column format: name|path
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

save_repo_entry() {
  local new_name="$1"
  local new_type="$2"
  local new_path="$3"
  local new_source="$4"

  load_repos
  local tmp_file="${REPOS_FILE}.tmp"
  : > "$tmp_file"

  local updated=0
  local i
  for ((i = 0; i < ${#REPO_NAMES[@]}; i++)); do
    if [ "${REPO_NAMES[$i]}" = "$new_name" ] || [ "${REPO_PATHS[$i]}" = "$new_path" ]; then
      if [ "$updated" -eq 0 ]; then
        echo "${new_name}|${new_type}|${new_path}|${new_source}" >> "$tmp_file"
        updated=1
      fi
    else
      echo "${REPO_NAMES[$i]}|${REPO_TYPES[$i]}|${REPO_PATHS[$i]}|${REPO_SOURCES[$i]}" >> "$tmp_file"
    fi
  done

  if [ "$updated" -eq 0 ]; then
    echo "${new_name}|${new_type}|${new_path}|${new_source}" >> "$tmp_file"
  fi

  mv "$tmp_file" "$REPOS_FILE"
}

cmd_add_repo() {
  local target=""
  local custom_name=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--name)
        shift
        custom_name="${1:-}"
        shift || true
        ;;
      --name=*)
        custom_name="${1#*=}"
        shift
        ;;
      *)
        target="$1"
        shift
        ;;
    esac
  done

  if [ -z "$target" ]; then
    target="$CALLER_DIR"
  fi

  if is_remote_url "$target"; then
    local repo_name="${custom_name:-$(extract_repo_name_from_url "$target")}"
    if [ -z "$repo_name" ]; then
      echo -e "${RED}❌ Error: Could not determine repository name from URL. Use --name <alias>.${NC}"
      exit 1
    fi

    mkdir -p "$REMOTES_DIR"
    local cache_dir="$REMOTES_DIR/${repo_name}.git"

    echo -e "${CYAN}🌐 Linking remote repository: ${BOLD}${repo_name}${NC}"
    echo -e "   Source: ${BLUE}${target}${NC}"
    echo -e "   Mode:   Lightweight metadata-only clone (--filter=blob:none)"

    if [ -d "$cache_dir" ]; then
      echo -e "${YELLOW}🔄 Updating existing metadata cache...${NC}"
      git -C "$cache_dir" remote set-url origin "$target" >/dev/null 2>&1 || true
      git -C "$cache_dir" config remote.origin.fetch "+refs/heads/*:refs/heads/*"
      git -C "$cache_dir" fetch origin --prune --filter=blob:none --quiet
    else
      git clone --bare --filter=blob:none "$target" "$cache_dir" --quiet
      git -C "$cache_dir" config remote.origin.fetch "+refs/heads/*:refs/heads/*"
      git -C "$cache_dir" fetch origin --prune --filter=blob:none --quiet || true
    fi

    save_repo_entry "$repo_name" "remote" "$cache_dir" "$target"
    echo -e "${GREEN}✅ Linked remote repo '${repo_name}'!${NC}"
  else
    local norm_path
    norm_path=$(normalize_input_path "$target")

    if [ ! -d "$norm_path" ]; then
      echo -e "${RED}❌ Error: Directory not found: ${norm_path}${NC}"
      exit 1
    fi

    local repo_root=""
    if repo_root=$(git -C "$norm_path" rev-parse --show-toplevel 2>/dev/null) && [ -n "$repo_root" ]; then
      :
    elif [ "$(git -C "$norm_path" rev-parse --is-bare-repository 2>/dev/null)" = "true" ]; then
      repo_root="$(cd "$norm_path" && pwd)"
    else
      echo -e "${RED}❌ Error: '${norm_path}' is not a valid Git repository.${NC}"
      exit 1
    fi

    # Normalize Windows slashes
    repo_root="${repo_root//\\//}"
    local repo_name="${custom_name:-$(basename "$repo_root")}"

    save_repo_entry "$repo_name" "local" "$repo_root" "$repo_root"
    echo -e "${GREEN}✅ Linked local repo '${BOLD}${repo_name}${NC}${GREEN}' -> ${BLUE}${repo_root}${NC} ${DIM}(0 MB extra storage)${NC}"
  fi
}

cmd_list_repos() {
  load_repos
  echo -e "${CYAN}======================================================${NC}"
  echo -e "${CYAN}📂 Linked Repositories (${#REPO_NAMES[@]})${NC}"
  echo -e "${CYAN}======================================================${NC}"

  if [ "${#REPO_NAMES[@]}" -eq 0 ]; then
    echo -e "${YELLOW}No repositories linked yet.${NC}"
    echo -e "Run ${CYAN}git report add${NC} inside a repo, ${CYAN}git report scan <dir>${NC}, or ${CYAN}git report add <url>${NC}."
    return 0
  fi

  local i
  for ((i = 0; i < ${#REPO_NAMES[@]}; i++)); do
    local idx=$((i + 1))
    local name="${REPO_NAMES[$i]}"
    local type="${REPO_TYPES[$i]}"
    local path="${REPO_PATHS[$i]}"
    local source="${REPO_SOURCES[$i]}"
    local badge="${BLUE}[local]${NC} "
    [ "$type" = "remote" ] && badge="${YELLOW}[remote]${NC}"

    if [ -d "$path" ] && git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
      echo -e "  ${BOLD}${idx}.${NC} ${GREEN}✔${NC} ${BOLD}${name}${NC} ${badge} ${DIM}-> ${source}${NC}"
    else
      echo -e "  ${BOLD}${idx}.${NC} ${RED}⚠${NC} ${BOLD}${name}${NC} ${badge} ${RED}(Missing: ${source})${NC}"
    fi
  done
  echo ""
}

# ==============================================================================
# Interactive Multi-Select Checklist TUI (with Number Input Fallback)
# ==============================================================================

# Populates SELECTED_INDICES=() from given ITEMS_LABELS=() and ITEMS_HINTS=()
# Args: $1 = Prompt Title, $2 = Default select all (0 or 1)
SELECTED_INDICES=()

parse_number_selection() {
  local input="$1"
  local total="$2"
  SELECTED_INDICES=()

  # Lowercase check for "all" or "*"
  if [ "$input" = "all" ] || [ "$input" = "ALL" ] || [ "$input" = "*" ] || [ "$input" = "a" ] || [ "$input" = "A" ]; then
    local i
    for ((i = 0; i < total; i++)); do
      SELECTED_INDICES+=("$i")
    done
    return 0
  fi

  # Replace commas with spaces
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
  local default_all="${2:-0}"
  local total="${#ITEMS_LABELS[@]}"
  SELECTED_INDICES=()

  if [ "$total" -eq 0 ]; then
    return 1
  fi

  local checked=()
  local i
  for ((i = 0; i < total; i++)); do
    checked+=("$default_all")
  done

  # Check if interactive TTY is available
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

  # Draw menu lines (with line-wrap disabled so each item is strictly 1 row)
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
        "[A"|"OA") # Up arrow
          cursor=$(((cursor - 1 + total) % total))
          ;;
        "[B"|"OB") # Down arrow
          cursor=$(((cursor + 1) % total))
          ;;
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
      # Enter pressed
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

    # Move cursor up `total` lines and redraw in-place
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

# ==============================================================================
# Interactive Radio-Select TUI (Single-Choice with (◉) / ( ))
# ==============================================================================

# Populates RADIO_SELECTED_INDEX (0-based) from RADIO_LABELS=() and RADIO_HINTS=()
# Args: $1 = Prompt Title, $2 = Default 0-based index (optional, default 0)
RADIO_LABELS=()
RADIO_HINTS=()
RADIO_SELECTED_INDEX=0

interactive_radio_select() {
  local title="$1"
  local default_idx="${2:-0}"
  local total="${#RADIO_LABELS[@]}"
  RADIO_SELECTED_INDEX="$default_idx"

  if [ "$total" -eq 0 ]; then
    return 1
  fi

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
        "[A"|"OA")
          cursor=$(((cursor - 1 + total) % total))
          ;;
        "[B"|"OB")
          cursor=$(((cursor + 1) % total))
          ;;
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
# Scan & Remove Commands
# ==============================================================================

cmd_scan_repos() {
  local scan_dir=""
  local auto_all=0

  while [ $# -gt 0 ]; do
    case "$1" in
      -a|--all|-y|--yes)
        auto_all=1
        shift
        ;;
      *)
        scan_dir="$1"
        shift
        ;;
    esac
  done

  if [ -z "$scan_dir" ]; then
    scan_dir="$CALLER_DIR"
  fi
  scan_dir=$(normalize_input_path "$scan_dir")

  if [ ! -d "$scan_dir" ]; then
    echo -e "${RED}❌ Error: Directory not found: ${scan_dir}${NC}"
    exit 1
  fi

  echo -e "${CYAN}🔍 Scanning for Git repositories in: ${BLUE}${scan_dir}${NC} ..."

  local found_paths=()
  while IFS= read -r git_entry; do
    [ -z "$git_entry" ] && continue
    local repo_dir
    repo_dir=$(dirname "$git_entry")
    repo_dir=$(cd "$repo_dir" && pwd)
    repo_dir="${repo_dir//\\//}"
    found_paths+=("$repo_dir")
  done < <(find "$scan_dir" -maxdepth 4 -name ".git" 2>/dev/null | sort)

  if [ "${#found_paths[@]}" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No Git repositories found inside '${scan_dir}'.${NC}"
    return 0
  fi

  load_repos
  ITEMS_LABELS=()
  ITEMS_HINTS=()

  local p
  for p in "${found_paths[@]}"; do
    local rname
    rname=$(basename "$p")
    local already=0
    local j
    for ((j = 0; j < ${#REPO_PATHS[@]}; j++)); do
      if [ "${REPO_PATHS[$j]}" = "$p" ]; then
        already=1
        break
      fi
    done
    ITEMS_LABELS+=("$rname")
    if [ "$already" -eq 1 ]; then
      ITEMS_HINTS+=("[already linked]")
    else
      ITEMS_HINTS+=("[local]")
    fi
  done

  if [ "$auto_all" -eq 1 ]; then
    SELECTED_INDICES=()
    local k
    for ((k = 0; k < ${#found_paths[@]}; k++)); do
      SELECTED_INDICES+=("$k")
    done
  else
    interactive_multi_select "Select repositories to link (${#found_paths[@]} found):" 1
  fi

  local linked_count=0
  local idx
  for idx in "${SELECTED_INDICES[@]}"; do
    local chosen_path="${found_paths[$idx]}"
    local chosen_name="${ITEMS_LABELS[$idx]}"
    save_repo_entry "$chosen_name" "local" "$chosen_path" "$chosen_path"
    echo -e "   ${GREEN}✔${NC} Linked: ${BOLD}${chosen_name}${NC} -> ${DIM}${chosen_path}${NC}"
    linked_count=$((linked_count + 1))
  done

  echo -e "\n${GREEN}✅ Successfully linked ${linked_count} repository(s)!${NC}"
}

cmd_remove_repo() {
  load_repos
  if [ "${#REPO_NAMES[@]}" -eq 0 ]; then
    echo -e "${YELLOW}No repositories are currently linked.${NC}"
    return 0
  fi

  local to_remove_names=()
  if [ $# -gt 0 ]; then
    for arg in "$@"; do
      to_remove_names+=("$arg")
    done
  else
    ITEMS_LABELS=()
    ITEMS_HINTS=()
    local i
    for ((i = 0; i < ${#REPO_NAMES[@]}; i++)); do
      ITEMS_LABELS+=("${REPO_NAMES[$i]}")
      ITEMS_HINTS+=("[${REPO_TYPES[$i]}]")
    done
    interactive_multi_select "Select repositories to unlink/remove:" 0
    for idx in "${SELECTED_INDICES[@]}"; do
      to_remove_names+=("${REPO_NAMES[$idx]}")
    done
  fi

  local tmp_file="${REPOS_FILE}.tmp"
  : > "$tmp_file"
  local removed=0

  local i
  for ((i = 0; i < ${#REPO_NAMES[@]}; i++)); do
    local name="${REPO_NAMES[$i]}"
    local type="${REPO_TYPES[$i]}"
    local path="${REPO_PATHS[$i]}"
    local source="${REPO_SOURCES[$i]}"

    local match=0
    local r
    for r in "${to_remove_names[@]}"; do
      if [ "$r" = "$name" ]; then
        match=1
        break
      fi
    done

    if [ "$match" -eq 1 ]; then
      if [ "$type" = "remote" ] && [ -d "$path" ] && [[ "$path" == "$REMOTES_DIR"/* ]]; then
        rm -rf "$path"
      fi
      echo -e "   ${GREEN}✔${NC} Unlinked: ${BOLD}${name}${NC}"
      removed=$((removed + 1))
    else
      echo "${name}|${type}|${path}|${source}" >> "$tmp_file"
    fi
  done

  mv "$tmp_file" "$REPOS_FILE"
  echo -e "${GREEN}✅ Removed ${removed} repository(s).${NC}"
}

# ==============================================================================
# Branch Discovery, Interactive Per-Repo Branch Picker & Resolution
# ==============================================================================

# Lists available remote branch names from origin (prioritizing current, develop, main, master, staging)
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

# Interactive single-select branch picker for a specific repository
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

  # Limit displayed list to top 12 branches + custom option so it stays compact
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

resolve_repo_branch_ref() {
  local repo_path="$1"
  local repo_type="$2"
  local requested_branch="$3"

  if [ "$requested_branch" = "CURRENT" ] || [ "$requested_branch" = "HEAD" ]; then
    requested_branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
  fi

  # 1. Always prefer origin/<branch> (from GitHub/remote) so we never depend on or override local branches
  if git -C "$repo_path" show-ref --verify --quiet "refs/remotes/origin/${requested_branch}"; then
    echo "refs/remotes/origin/${requested_branch}"
    return 0
  fi

  # 2. For bare remote caches or repos without an 'origin' remote, check refs/heads/<branch>
  if git -C "$repo_path" show-ref --verify --quiet "refs/heads/${requested_branch}"; then
    echo "refs/heads/${requested_branch}"
    return 0
  fi

  if [ "$requested_branch" = "HEAD" ] && git -C "$repo_path" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "HEAD"
    return 0
  fi

  return 1
}

# ==============================================================================
# Main Report Execution & Argument Parsing
# ==============================================================================

# Quick help & version check
for arg in "$@"; do
  if [ "$arg" = "-h" ] || [ "$arg" = "--help" ] || [ "$arg" = "help" ]; then
    show_help
    exit 0
  elif [ "$arg" = "-v" ] || [ "$arg" = "-V" ] || [ "$arg" = "--version" ] || [ "$arg" = "version" ]; then
    SOURCE="${BASH_SOURCE[0]}"
    while [ -L "$SOURCE" ]; do
      DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
      SOURCE="$(readlink "$SOURCE")"
      [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    TOOLKIT_ROOT="$(cd -P "$(dirname "$SOURCE")/../.." && pwd)"
    TOOLKIT_VERSION="2.0.0"
    [ -f "$TOOLKIT_ROOT/VERSION" ] && read -r TOOLKIT_VERSION < "$TOOLKIT_ROOT/VERSION" || true
    echo "git-report (Developer Toolkit) ${TOOLKIT_VERSION:-2.0.0}"
    exit 0
  fi
done

# Dispatch subcommands
if [ $# -gt 0 ]; then
  case "$1" in
    add)
      shift
      cmd_add_repo "$@"
      exit 0
      ;;
    scan)
      shift
      cmd_scan_repos "$@"
      exit 0
      ;;
    list|ls)
      shift
      cmd_list_repos
      exit 0
      ;;
    remove|rm|unlink)
      shift
      cmd_remove_repo "$@"
      exit 0
      ;;
    template|templates)
      shift
      SOURCE="${BASH_SOURCE[0]}"
      while [ -L "$SOURCE" ]; do
        DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
        SOURCE="$(readlink "$SOURCE")"
        [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
      done
      SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
      exec bash "$SCRIPT_DIR/../git-template/git-template.sh" "$@"
      ;;
  esac
fi

# Parse CLI flags for report generation
CLI_TEMPLATE=""
CLI_REPOS=""
CLI_ALL_REPOS=0
TARGET_BRANCH=""
DATE_PRESET=""
FROM_DATE=""
TO_DATE=""
PRESET_LABEL=""
AUTHOR_MODE=""      # "me", "all", "custom"
AUTHOR_PATTERN=""
DO_FETCH=0
INCLUDE_MERGES=0
DETAILED_FORMAT=0
OUTPUT_EXT="md"
CUSTOM_OUTPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--template)
      shift
      CLI_TEMPLATE="${1:-}"
      shift || true
      ;;
    --template=*|template=*)
      CLI_TEMPLATE="${1#*=}"
      shift
      ;;
    -r|--repos)
      shift
      CLI_REPOS="${1:-}"
      shift || true
      ;;
    --repos=*)
      CLI_REPOS="${1#*=}"
      shift
      ;;
    -a|--all)
      CLI_ALL_REPOS=1
      shift
      ;;
    -b|--branch)
      shift
      TARGET_BRANCH="${1:-}"
      shift || true
      ;;
    --branch=*|branch=*)
      TARGET_BRANCH="${1#*=}"
      shift
      ;;
    -p|--preset)
      shift
      DATE_PRESET="${1:-}"
      shift || true
      ;;
    --preset=*)
      DATE_PRESET="${1#*=}"
      shift
      ;;
    --from)
      shift
      FROM_DATE="${1:-}"
      shift || true
      ;;
    --from=*)
      FROM_DATE="${1#*=}"
      shift
      ;;
    --to)
      shift
      TO_DATE="${1:-}"
      shift || true
      ;;
    --to=*)
      TO_DATE="${1#*=}"
      shift
      ;;
    --me)
      AUTHOR_MODE="me"
      shift
      ;;
    --all-authors)
      AUTHOR_MODE="all"
      shift
      ;;
    --author)
      shift
      AUTHOR_MODE="custom"
      AUTHOR_PATTERN="${1:-}"
      shift || true
      ;;
    --author=*)
      AUTHOR_MODE="custom"
      AUTHOR_PATTERN="${1#*=}"
      shift
      ;;
    --fetch)
      DO_FETCH=1
      shift
      ;;
    --include-merges)
      INCLUDE_MERGES=1
      shift
      ;;
    --detailed)
      DETAILED_FORMAT=1
      shift
      ;;
    --format)
      shift
      OUTPUT_EXT="${1:-md}"
      shift || true
      ;;
    --format=*)
      OUTPUT_EXT="${1#*=}"
      shift
      ;;
    -o|--output)
      shift
      CUSTOM_OUTPUT="${1:-}"
      shift || true
      ;;
    --output=*)
      CUSTOM_OUTPUT="${1#*=}"
      shift
      ;;
    *)
      echo -e "${RED}❌ Unknown option or command: $1${NC}"
      echo -e "Run ${CYAN}git report --help${NC} for usage."
      exit 1
      ;;
  esac
done

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}📊 Git Multi-Repo Commit Report Generator${NC}"
echo -e "${CYAN}======================================================${NC}"

# 1. Load linked repositories (if none exist, offer interactive onboarding)
load_repos

if [ "${#REPO_NAMES[@]}" -eq 0 ]; then
  echo -e "\n${YELLOW}⚠️  No repositories are linked yet!${NC}"
  if [ ! -t 0 ]; then
    echo -e "Link repositories first using: ${CYAN}git report add <path_or_url>${NC} or ${CYAN}git report scan <dir>${NC}"
    exit 1
  fi

  RADIO_LABELS=(
    "Scan a workspace folder for local Git repos"
    "Link current folder"
    "Link a remote Git URL"
    "Exit"
  )
  RADIO_HINTS=(
    "(0 MB storage)"
    "(${CALLER_DIR})"
    "(lightweight metadata clone)"
    ""
  )
  interactive_radio_select "How would you like to link your repositories right now?" 0

  case "$RADIO_SELECTED_INDEX" in
    0)
      echo -ne "\n${YELLOW}Enter workspace folder to scan (default: ${CALLER_DIR}): ${NC}"
      read -r scan_input
      cmd_scan_repos "${scan_input:-$CALLER_DIR}"
      ;;
    1)
      cmd_add_repo "$CALLER_DIR"
      ;;
    2)
      echo -ne "\n${YELLOW}Enter remote Git URL (https://... or git@...): ${NC}"
      read -r url_input
      cmd_add_repo "$url_input"
      ;;
    *)
      exit 0
      ;;
  esac

  load_repos
  if [ "${#REPO_NAMES[@]}" -eq 0 ]; then
    exit 0
  fi
fi

# 1b. Template Selection (CLI -t <name> or Interactive Mode when templates exist)
USED_TEMPLATE=0
load_templates

apply_template_by_index() {
  local tidx="$1"
  USED_TEMPLATE=1
  CLI_REPOS="${TPL_REPOS[$tidx]}"
  [ -z "$TARGET_BRANCH" ] && TARGET_BRANCH="${TPL_BRANCHES[$tidx]}"
  if [ -z "$AUTHOR_MODE" ]; then
    AUTHOR_MODE="${TPL_AUTHOR_MODES[$tidx]}"
    AUTHOR_PATTERN="${TPL_AUTHOR_PATTERNS[$tidx]}"
  fi
  local t_date="${TPL_DATE_PRESETS[$tidx]}"
  if [ -z "$DATE_PRESET" ] && [ -z "$FROM_DATE" ] && [ -n "$t_date" ] && [ "$t_date" != "ask" ]; then
    DATE_PRESET="$t_date"
  fi
  echo -e "\n${GREEN}📋 Loaded template '${BOLD}${TPL_NAMES[$tidx]}${NC}${GREEN}'${NC} ${DIM}(Repos: ${CLI_REPOS} | Branch: ${TARGET_BRANCH})${NC}"
}

if [ -n "$CLI_TEMPLATE" ]; then
  found_tpl=-1
  for ((i = 0; i < ${#TPL_NAMES[@]}; i++)); do
    if [ "${TPL_NAMES[$i]}" = "$CLI_TEMPLATE" ]; then
      found_tpl="$i"
      break
    fi
  done
  if [ "$found_tpl" -lt 0 ]; then
    echo -e "${RED}❌ Error: Saved template '${CLI_TEMPLATE}' not found.${NC}"
    echo -e "Run ${CYAN}git template list${NC} to view saved templates."
    exit 1
  fi
  apply_template_by_index "$found_tpl"
elif [ "$CLI_ALL_REPOS" -eq 0 ] && [ -z "$CLI_REPOS" ] && [ "${#TPL_NAMES[@]}" -gt 0 ] && [ -t 0 ] && [ -t 1 ]; then
  RADIO_LABELS=()
  RADIO_HINTS=()
  for ((i = 0; i < ${#TPL_NAMES[@]}; i++)); do
    RADIO_LABELS+=("📋 Template: ${TPL_NAMES[$i]}")
    RADIO_HINTS+=("(${TPL_REPOS[$i]} | ${TPL_BRANCHES[$i]} | author:${TPL_AUTHOR_MODES[$i]})")
  done
  custom_mode_idx="${#RADIO_LABELS[@]}"
  RADIO_LABELS+=("🛠️  Custom Report")
  RADIO_HINTS+=("(Select repositories, branches & filters manually)")
  manage_tpl_idx="${#RADIO_LABELS[@]}"
  RADIO_LABELS+=("➕ Manage Templates")
  RADIO_HINTS+=("(Create, edit, or delete templates)")

  interactive_radio_select "Select Report Mode (${#TPL_NAMES[@]} template(s) available):" 0

  if [ "$RADIO_SELECTED_INDEX" -lt "$custom_mode_idx" ]; then
    apply_template_by_index "$RADIO_SELECTED_INDEX"
  elif [ "$RADIO_SELECTED_INDEX" -eq "$manage_tpl_idx" ]; then
    SOURCE="${BASH_SOURCE[0]}"
    while [ -L "$SOURCE" ]; do
      DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
      SOURCE="$(readlink "$SOURCE")"
      [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    exec bash "$SCRIPT_DIR/../git-template/git-template.sh"
  fi
fi

# 2. Select subset of repositories
CHOSEN_REPO_INDICES=()

if [ "$CLI_ALL_REPOS" -eq 1 ]; then
  for ((i = 0; i < ${#REPO_NAMES[@]}; i++)); do
    CHOSEN_REPO_INDICES+=("$i")
  done
elif [ -n "$CLI_REPOS" ]; then
  IFS=',' read -r -a requested_tokens <<< "$CLI_REPOS"
  for tok in "${requested_tokens[@]}"; do
    matched=0
    # Match by repo name first
    for ((i = 0; i < ${#REPO_NAMES[@]}; i++)); do
      if [ "${REPO_NAMES[$i]}" = "$tok" ]; then
        CHOSEN_REPO_INDICES+=("$i")
        matched=1
        break
      fi
    done
    # Match by 1-based index if numeric
    if [ "$matched" -eq 0 ] && [[ "$tok" =~ ^[0-9]+$ ]]; then
      if [ "$tok" -ge 1 ] && [ "$tok" -le "${#REPO_NAMES[@]}" ]; then
        CHOSEN_REPO_INDICES+=("$((tok - 1))")
        matched=1
      fi
    fi
    if [ "$matched" -eq 0 ]; then
      echo -e "${YELLOW}⚠️  Warning: Linked repository '${tok}' not found (skipping).${NC}"
    fi
  done
else
  ITEMS_LABELS=()
  ITEMS_HINTS=()
  for ((i = 0; i < ${#REPO_NAMES[@]}; i++)); do
    ITEMS_LABELS+=("${REPO_NAMES[$i]}")
    ITEMS_HINTS+=("[${REPO_TYPES[$i]}]")
  done
  interactive_multi_select "Step 1: Select repositories to include in the report (${#REPO_NAMES[@]} linked):" 0
  CHOSEN_REPO_INDICES=("${SELECTED_INDICES[@]}")
fi

if [ "${#CHOSEN_REPO_INDICES[@]}" -eq 0 ]; then
  echo -e "${RED}❌ Error: No repositories selected.${NC}"
  exit 1
fi

# 3. Select Target Branch (shared or per-repository)
PER_REPO_BRANCH_MODE=0
CHOSEN_REPO_BRANCHES=()

if [ -z "$TARGET_BRANCH" ]; then
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
  interactive_radio_select "Step 2: Select Target Branch" 0

  case "$RADIO_SELECTED_INDEX" in
    0) TARGET_BRANCH="develop" ;;
    1) TARGET_BRANCH="main" ;;
    2) TARGET_BRANCH="master" ;;
    3) TARGET_BRANCH="staging" ;;
    4)
      PER_REPO_BRANCH_MODE=1
      TARGET_BRANCH="PER-REPO"
      ;;
    5) TARGET_BRANCH="CURRENT" ;;
    6)
      echo -ne "\n${YELLOW}Enter custom branch name: ${NC}"
      read -r TARGET_BRANCH
      TARGET_BRANCH="${TARGET_BRANCH:-develop}"
      ;;
  esac
fi

# Populate CHOSEN_REPO_BRANCHES for each selected repository
if [ "$PER_REPO_BRANCH_MODE" -eq 1 ]; then
  for idx in "${CHOSEN_REPO_INDICES[@]}"; do
    r_name="${REPO_NAMES[$idx]}"
    r_path="${REPO_PATHS[$idx]}"
    prompt_branch_for_repo "$r_name" "$r_path"
    CHOSEN_REPO_BRANCHES+=("$PICKED_BRANCH")
  done
elif [[ "$TARGET_BRANCH" == *:* ]]; then
  # Support CLI per-repo mapping: -b repoA:develop,repoB:main
  IFS=',' read -r -a branch_mappings <<< "$TARGET_BRANCH"
  for idx in "${CHOSEN_REPO_INDICES[@]}"; do
    r_name="${REPO_NAMES[$idx]}"
    mapped_b="develop"
    for pair in "${branch_mappings[@]}"; do
      if [[ "$pair" == "${r_name}:"* ]]; then
        mapped_b="${pair#*:}"
        break
      fi
    done
    CHOSEN_REPO_BRANCHES+=("$mapped_b")
  done
else
  for idx in "${CHOSEN_REPO_INDICES[@]}"; do
    r_name="${REPO_NAMES[$idx]}"
    r_type="${REPO_TYPES[$idx]}"
    r_path="${REPO_PATHS[$idx]}"
    if [ "$TARGET_BRANCH" != "CURRENT" ] && [ -t 0 ] && [ -t 1 ]; then
      if ! resolve_repo_branch_ref "$r_path" "$r_type" "$TARGET_BRANCH" >/dev/null 2>&1; then
        echo -e "\n${YELLOW}⚠️  Branch '${TARGET_BRANCH}' not found in '${BOLD}${r_name}${NC}${YELLOW}'. Please choose a branch for this repo:${NC}"
        prompt_branch_for_repo "$r_name" "$r_path"
        CHOSEN_REPO_BRANCHES+=("$PICKED_BRANCH")
        continue
      fi
    fi
    CHOSEN_REPO_BRANCHES+=("$TARGET_BRANCH")
  done
fi

# 4. Select Date Preset or Custom Date Range
if [ -n "$DATE_PRESET" ]; then
  if ! compute_date_preset "$DATE_PRESET"; then
    echo -e "${RED}❌ Error: Unknown date preset '${DATE_PRESET}'.${NC}"
    exit 1
  fi
elif [ -n "$FROM_DATE" ]; then
  [ -z "$TO_DATE" ] && TO_DATE=$(date "+%Y-%m-%d")
  if ! validate_date_format "$FROM_DATE" || ! validate_date_format "$TO_DATE"; then
    echo -e "${RED}❌ Error: Dates must be in YYYY-MM-DD format.${NC}"
    exit 1
  fi
  PRESET_LABEL="Custom ($FROM_DATE -> $TO_DATE)"
else
  RADIO_LABELS=(
    "Today"
    "Yesterday"
    "Last 7 days"
    "This week"
    "Last week"
    "This month"
    "Last month"
    "Last 14 days"
    "Last 30 days"
    "Custom date range"
  )
  RADIO_HINTS=(
    ""
    ""
    "(default)"
    "(Mon -> Today)"
    "(Prev Mon -> Prev Sun)"
    "(1st -> Today)"
    "(Prev month)"
    ""
    ""
    "(YYYY-MM-DD -> YYYY-MM-DD)"
  )
  interactive_radio_select "Step 3: Select Date Range" 2

  case "$RADIO_SELECTED_INDEX" in
    0) compute_date_preset "today" ;;
    1) compute_date_preset "yesterday" ;;
    2) compute_date_preset "last-7-days" ;;
    3) compute_date_preset "this-week" ;;
    4) compute_date_preset "last-week" ;;
    5) compute_date_preset "this-month" ;;
    6) compute_date_preset "last-month" ;;
    7) compute_date_preset "last-14-days" ;;
    8) compute_date_preset "last-30-days" ;;
    9)
      echo ""
      while true; do
        echo -ne "${YELLOW}Enter FROM date (YYYY-MM-DD): ${NC}"
        read -r FROM_DATE
        if validate_date_format "$FROM_DATE"; then
          break
        fi
        echo -e "${RED}⚠️  Invalid date format. Please use YYYY-MM-DD (e.g. 2026-10-01).${NC}"
      done
      while true; do
        local_today=$(date "+%Y-%m-%d")
        echo -ne "${YELLOW}Enter TO date (YYYY-MM-DD, default: ${local_today}): ${NC}"
        read -r TO_DATE
        TO_DATE="${TO_DATE:-$local_today}"
        if validate_date_format "$TO_DATE"; then
          break
        fi
        echo -e "${RED}⚠️  Invalid date format. Please use YYYY-MM-DD (e.g. ${local_today}).${NC}"
      done
      PRESET_LABEL="Custom ($FROM_DATE -> $TO_DATE)"
      ;;
  esac
fi

# 5. Select Author Filter & Remote Fetch (if not specified via CLI flags)
if [ -z "$AUTHOR_MODE" ]; then
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
  interactive_radio_select "Step 4: Select Commit Author Filter" 0

  case "$RADIO_SELECTED_INDEX" in
    1) AUTHOR_MODE="me" ;;
    2)
      AUTHOR_MODE="custom"
      echo -ne "\n${YELLOW}Enter author name or email: ${NC}"
      read -r AUTHOR_PATTERN
      ;;
    *) AUTHOR_MODE="all" ;;
  esac

  # Offer to save this manual setup as a reusable template for next time
  if [ "$USED_TEMPLATE" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    RADIO_LABELS=(
      "No — Generate report now"
      "Yes — Save this setup as a template & generate report"
    )
    RADIO_HINTS=(
      "(default)"
      "(re-use these repos, branches & author next time)"
    )
    interactive_radio_select "Save this selection as a template for future reports?" 0
    if [ "$RADIO_SELECTED_INDEX" -eq 1 ]; then
      echo -ne "\n${YELLOW}Enter a name for this template (e.g. core-weekly): ${NC}"
      read -r new_tpl_name
      new_tpl_name="${new_tpl_name// /_}"
      new_tpl_name="${new_tpl_name//|/}"
      if [ -n "$new_tpl_name" ]; then
        chosen_names_list=()
        branch_pairs_list=()
        for ((pos = 0; pos < ${#CHOSEN_REPO_INDICES[@]}; pos++)); do
          idx="${CHOSEN_REPO_INDICES[$pos]}"
          rn="${REPO_NAMES[$idx]}"
          rb="${CHOSEN_REPO_BRANCHES[$pos]:-$TARGET_BRANCH}"
          chosen_names_list+=("$rn")
          branch_pairs_list+=("${rn}:${rb}")
        done
        IFS=',' eval 'saved_repos_csv="${chosen_names_list[*]}"'
        if [ "$PER_REPO_BRANCH_MODE" -eq 1 ]; then
          IFS=',' eval 'saved_branch_spec="${branch_pairs_list[*]}"'
        else
          saved_branch_spec="$TARGET_BRANCH"
        fi
        save_template_entry "$new_tpl_name" "$saved_repos_csv" "$saved_branch_spec" "$AUTHOR_MODE" "$AUTHOR_PATTERN" "ask"
        echo -e "${GREEN}✅ Saved template '${BOLD}${new_tpl_name}${NC}${GREEN}'!${NC}"
      fi
    fi
  fi
fi

# ==============================================================================
# Collect Commits & Write Report
# ==============================================================================

REPORT_DIR="${CALLER_DIR}/report"
mkdir -p "$REPORT_DIR"

TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
if [ -n "$CUSTOM_OUTPUT" ]; then
  if [[ "$CUSTOM_OUTPUT" == */* ]]; then
    OUTPUT_FILE="$CUSTOM_OUTPUT"
  else
    OUTPUT_FILE="${REPORT_DIR}/${CUSTOM_OUTPUT}"
  fi
else
  OUTPUT_FILE="${REPORT_DIR}/commit-report-${TIMESTAMP}.${OUTPUT_EXT}"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
: > "$OUTPUT_FILE"

echo -e "\n${CYAN}======================================================${NC}"
echo -e "${CYAN}⚡ Generating Report...${NC}"
echo -e "   Repositories: ${YELLOW}${#CHOSEN_REPO_INDICES[@]} selected${NC}"
echo -e "   Branch:       ${YELLOW}${TARGET_BRANCH}${NC}"
echo -e "   Date Range:   ${YELLOW}${PRESET_LABEL}${NC}"
echo -e "   Author Mode:  ${YELLOW}${AUTHOR_MODE}${AUTHOR_PATTERN:+ ($AUTHOR_PATTERN)}${NC}"
echo -e "${CYAN}======================================================${NC}\n"

TOTAL_COMMITS=0

for ((pos = 0; pos < ${#CHOSEN_REPO_INDICES[@]}; pos++)); do
  idx="${CHOSEN_REPO_INDICES[$pos]}"
  r_name="${REPO_NAMES[$idx]}"
  r_type="${REPO_TYPES[$idx]}"
  r_path="${REPO_PATHS[$idx]}"
  repo_branch="${CHOSEN_REPO_BRANCHES[$pos]:-$TARGET_BRANCH}"

  echo "- ${r_name}" >> "$OUTPUT_FILE"

  if [ ! -d "$r_path" ] || ! git -C "$r_path" rev-parse --git-dir >/dev/null 2>&1; then
    echo "   - (Repository path not found: ${r_path})" >> "$OUTPUT_FILE"
    continue
  fi

  if [ "$repo_branch" = "CURRENT" ] || [ "$repo_branch" = "HEAD" ]; then
    repo_branch=$(git -C "$r_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
  fi

  # Always fetch the target branch directly from origin (GitHub/remote)
  # without touching, checking out, or overriding any local branches or working files!
  if git -C "$r_path" remote get-url origin >/dev/null 2>&1; then
    echo -e "${DIM}🔄 [${r_name}] Fetching latest 'origin/${repo_branch}' from remote...${NC}"
    if [ "$r_type" = "remote" ]; then
      git -C "$r_path" fetch origin "+refs/heads/${repo_branch}:refs/heads/${repo_branch}" --filter=blob:none --quiet 2>/dev/null \
        || git -C "$r_path" fetch origin --prune --filter=blob:none --quiet 2>/dev/null || true
    else
      git -C "$r_path" fetch origin "${repo_branch}:refs/remotes/origin/${repo_branch}" --quiet 2>/dev/null \
        || git -C "$r_path" fetch origin "$repo_branch" --quiet 2>/dev/null || true
    fi
  fi

  # Resolve target branch ref (strictly prefers refs/remotes/origin/<branch>)
  resolved_ref=""
  if ! resolved_ref=$(resolve_repo_branch_ref "$r_path" "$r_type" "$repo_branch"); then
    echo "   - (Branch 'origin/${repo_branch}' not found in this repository)" >> "$OUTPUT_FILE"
    continue
  fi

  # Build git log arguments
  log_args=()
  log_args+=("$resolved_ref")
  log_args+=("--since=${FROM_DATE} 00:00:00")
  log_args+=("--until=${TO_DATE} 23:59:59")

  if [ "$INCLUDE_MERGES" -eq 0 ]; then
    log_args+=("--no-merges")
  fi

  if [ "$AUTHOR_MODE" = "me" ]; then
    my_email=$(git -C "$r_path" config user.email 2>/dev/null || git config --global user.email 2>/dev/null || true)
    my_name=$(git -C "$r_path" config user.name 2>/dev/null || git config --global user.name 2>/dev/null || true)
    if [ -n "$my_email" ]; then
      log_args+=("--author=${my_email}")
    elif [ -n "$my_name" ]; then
      log_args+=("--author=${my_name}")
    fi
  elif [ "$AUTHOR_MODE" = "custom" ] && [ -n "$AUTHOR_PATTERN" ]; then
    log_args+=("--author=${AUTHOR_PATTERN}")
  fi

  if [ "$DETAILED_FORMAT" -eq 1 ]; then
    log_args+=("--date=short" "--pretty=format:@@COMMIT_START@@[%h] %s (%ad - %an)%n%b")
  else
    log_args+=("--pretty=format:@@COMMIT_START@@%s%n%b")
  fi

  commits_output=$(git -C "$r_path" log "${log_args[@]}" 2>/dev/null || true)

  if [ -z "$commits_output" ]; then
    echo "   - (No commits in this period)" >> "$OUTPUT_FILE"
  else
    while IFS= read -r commit_line || [ -n "$commit_line" ]; do
      if [[ "$commit_line" == "@@COMMIT_START@@"* ]]; then
        subject_text="${commit_line#@@COMMIT_START@@}"
        [ -z "$subject_text" ] && continue
        echo "   - ${subject_text}" >> "$OUTPUT_FILE"
        TOTAL_COMMITS=$((TOTAL_COMMITS + 1))
      else
        # Trim leading/trailing whitespace from commit body lines
        trimmed_body="${commit_line#"${commit_line%%[![:space:]]*}"}"
        trimmed_body="${trimmed_body%"${trimmed_body##*[![:space:]]}"}"
        [ -z "$trimmed_body" ] && continue
        # Strip leading '- ' or '* ' if the commit body line already has a bullet prefix
        if [[ "$trimmed_body" == "- "* ]] || [[ "$trimmed_body" == "* "* ]]; then
          trimmed_body="${trimmed_body#[-*] }"
        fi
        echo "      - ${trimmed_body}" >> "$OUTPUT_FILE"
      fi
    done <<< "$commits_output"
  fi
done

# Print report preview to terminal
cat "$OUTPUT_FILE"

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}✅ Report generated (${TOTAL_COMMITS} commit(s) across ${#CHOSEN_REPO_INDICES[@]} repo(s))!${NC}"
echo -e "${GREEN}📄 Saved to: ${BOLD}${OUTPUT_FILE}${NC}"
echo -e "${GREEN}======================================================${NC}\n"
