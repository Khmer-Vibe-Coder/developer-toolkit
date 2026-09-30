#!/usr/bin/env bash

# ==============================================================================
# Script: install.sh
# Purpose: One-command installer for Developer Toolkit on macOS & Linux.
#          Auto-discovers tools in ./tools/ and configures Git aliases and symlinks.
# ==============================================================================

set -eo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$BIN_DIR"

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}🛠️  Installing Developer Toolkit...${NC}"
echo -e "${CYAN}   Path: ${TOOLKIT_ROOT}${NC}"
echo -e "${CYAN}======================================================${NC}\n"

INSTALLED_COUNT=0

# Loop through all tool folders
for tool_dir in "$TOOLKIT_ROOT"/tools/*; do
  if [ -d "$tool_dir" ]; then
    tool_name="$(basename "$tool_dir")"
    
    # Look for shell scripts in this tool directory
    for script in "$tool_dir"/*.sh; do
      if [ -f "$script" ]; then
        chmod +x "$script"
        script_filename="$(basename "$script")"
        cmd_name="${script_filename%.sh}"

        echo -e "${YELLOW}📦 Setting up: ${cmd_name}${NC}"

        # 1. If it's a git tool (starts with git-), configure global Git alias
        if [[ "$cmd_name" =~ ^git- ]]; then
          git_alias="${cmd_name#git-}"
          git config --global alias."$git_alias" "!bash \"$script\""
          echo -e "   ${GREEN}✔${NC} Git Alias registered: ${BLUE}git ${git_alias}${NC}"
        fi

        # 2. Symlink into ~/.local/bin for global CLI access
        ln -sf "$script" "$BIN_DIR/$cmd_name"
        echo -e "   ${GREEN}✔${NC} Symlink created: ${BIN_DIR}/${cmd_name}"

        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
      fi
    done
  fi
done

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}✅ Successfully installed ${INSTALLED_COUNT} tool(s)!${NC}"
echo -e "${GREEN}======================================================${NC}"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo -e "\n${YELLOW}💡 Tip: Add ~/.local/bin to your PATH to run tools directly:${NC}"
  echo -e "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc   ${BLUE}# for Zsh (macOS default)${NC}"
  echo -e "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc  ${BLUE}# for Bash (Linux)${NC}\n"
fi
