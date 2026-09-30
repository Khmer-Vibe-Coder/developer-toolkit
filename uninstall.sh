#!/usr/bin/env bash

# ==============================================================================
# Script: uninstall.sh
# Purpose: One-command uninstaller to remove Developer Toolkit aliases and symlinks.
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}🗑️  Uninstalling Developer Toolkit...${NC}"
echo -e "${CYAN}======================================================${NC}\n"

REMOVED_COUNT=0

for tool_dir in "$TOOLKIT_ROOT"/tools/*; do
  if [ -d "$tool_dir" ]; then
    for script in "$tool_dir"/*.sh; do
      if [ -f "$script" ]; then
        script_filename="$(basename "$script")"
        cmd_name="${script_filename%.sh}"

        echo -e "${YELLOW}🧹 Removing: ${cmd_name}${NC}"

        # 1. If it's a git tool, remove global Git alias
        if [[ "$cmd_name" =~ ^git- ]]; then
          git_alias="${cmd_name#git-}"
          if git config --global --get alias."$git_alias" >/dev/null 2>&1; then
            git config --global --unset alias."$git_alias"
            echo -e "   ${GREEN}✔${NC} Removed Git alias: git ${git_alias}"
          fi
        fi

        # 2. Remove symlink from ~/.local/bin
        if [ -L "$BIN_DIR/$cmd_name" ] || [ -f "$BIN_DIR/$cmd_name" ]; then
          rm -f "$BIN_DIR/$cmd_name"
          echo -e "   ${GREEN}✔${NC} Removed symlink: ${BIN_DIR}/${cmd_name}"
        fi

        REMOVED_COUNT=$((REMOVED_COUNT + 1))
      fi
    done
  fi
done

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}✅ Successfully uninstalled ${REMOVED_COUNT} tool(s).${NC}"
echo -e "${GREEN}======================================================${NC}\n"
