#!/usr/bin/env bash

# ==============================================================================
# Script: git-smart-rebase.sh
# Purpose: Safely update a target branch (default: develop), rebase the current
#          branch onto it, and preserve working changes via git stash.
#
# Usage:
#   git smart-rebase                    (defaults to branch 'develop')
#   git smart-rebase main               (rebases onto 'main')
#   git smart-rebase branch=develop     (rebases onto 'develop')
#   git smart-rebase -b feature/xyz     (rebases onto 'feature/xyz')
# ==============================================================================

set -eo pipefail

# ANSI color codes for clear visual output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 1. Quick help check (allows viewing help outside of git repos)
for arg in "$@"; do
  if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}🚀 Git Smart Rebase Utility${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "Safely syncs your branch with a target branch without losing changes:"
    echo -e "  1. Auto-stashes pending changes (including untracked files)"
    echo -e "  2. Switches to target branch and pulls latest remote updates"
    echo -e "  3. Switches back to your working branch"
    echo -e "  4. Rebases your branch onto the updated target branch"
    echo -e "  5. Automatically restores your stashed changes"
    echo -e ""
    echo -e "Usage:"
    echo -e "  git smart-rebase [target_branch]"
    echo -e "  git smart-rebase -b <target_branch>"
    echo -e "  git smart-rebase --branch=<target_branch>"
    echo -e ""
    echo -e "Options:"
    echo -e "  -b, --branch <branch>   Specify target branch (default: develop)"
    echo -e "  -h, --help              Show this help message"
    echo -e ""
    echo -e "Examples:"
    echo -e "  git smart-rebase"
    echo -e "  git smart-rebase main"
    echo -e "  git smart-rebase -b staging"
    echo -e "  git smart-rebase branch=develop"
    exit 0
  fi
done

# 2. Verify we are inside a Git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo -e "${RED}❌ Error: Not inside a valid git repository.${NC}"
  echo -e "Please run this command from within a Git project directory."
  exit 1
fi

# 3. Parse target branch argument
TARGET_BRANCH="develop" # Default target branch

while [ $# -gt 0 ]; do
  case "$1" in
    branch=*)
      TARGET_BRANCH="${1#branch=}"
      shift
      ;;
    -b=*|--branch=*)
      TARGET_BRANCH="${1#*=}"
      shift
      ;;
    -b|--branch)
      shift
      if [ -z "$1" ]; then
        echo -e "${RED}❌ Error: Missing branch name after $1.${NC}"
        exit 1
      fi
      TARGET_BRANCH="$1"
      shift
      ;;
    -*)
      echo -e "${RED}❌ Unknown option: $1${NC}"
      echo -e "Usage: git smart-rebase [target_branch | branch=target_branch | -b target_branch]"
      exit 1
      ;;
    *)
      TARGET_BRANCH="$1"
      shift
      ;;
  esac
done

# 4. Detect current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}🚀 Git Smart Rebase Utility${NC}"
echo -e "${CYAN}   Current Branch: ${YELLOW}${CURRENT_BRANCH}${NC}"
echo -e "${CYAN}   Target Branch:  ${YELLOW}${TARGET_BRANCH}${NC}"
echo -e "${CYAN}======================================================${NC}"

# Check if already on the target branch
if [ "$CURRENT_BRANCH" = "$TARGET_BRANCH" ]; then
  echo -e "${YELLOW}ℹ️  You are already on '${TARGET_BRANCH}'. Pulling latest changes directly...${NC}"
  git pull origin "$TARGET_BRANCH"
  echo -e "${GREEN}✅ '${TARGET_BRANCH}' is up to date!${NC}"
  exit 0
fi

# 5. Check for pending changes (unstaged, staged, or untracked)
STASHED=0
HAS_PENDING_CHANGES=0

if [ -n "$(git status --porcelain)" ]; then
  HAS_PENDING_CHANGES=1
fi

if [ "$HAS_PENDING_CHANGES" -eq 1 ]; then
  echo -e "\n${YELLOW}📦 Pending changes detected. Staging all files and creating stash...${NC}"
  
  # Stage everything across the repository so all untracked files are included in the stash
  git add -A
  
  STASH_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  git stash push -u -m "auto-rebase-stash [${CURRENT_BRANCH}] at ${STASH_TIMESTAMP}"
  STASHED=1
  echo -e "${GREEN}✅ Changes successfully stashed.${NC}"
else
  echo -e "\n${BLUE}✨ Working directory is clean. No stash needed.${NC}"
fi

# 6. Checkout target branch and pull latest changes
echo -e "\n${YELLOW}🔄 Switching to '${TARGET_BRANCH}' and pulling latest changes...${NC}"
if ! git checkout "$TARGET_BRANCH"; then
  echo -e "${RED}❌ Failed to checkout '${TARGET_BRANCH}'. Restoring workspace...${NC}"
  if [ "$STASHED" -eq 1 ]; then
    git stash pop
  fi
  exit 1
fi

if ! git pull origin "$TARGET_BRANCH"; then
  echo -e "${RED}❌ Failed to pull latest changes for '${TARGET_BRANCH}'. Returning to '${CURRENT_BRANCH}'...${NC}"
  git checkout "$CURRENT_BRANCH"
  if [ "$STASHED" -eq 1 ]; then
    git stash pop
  fi
  exit 1
fi

# 7. Switch back to working branch
echo -e "\n${YELLOW}↩️  Switching back to '${CURRENT_BRANCH}'...${NC}"
git checkout "$CURRENT_BRANCH"

# 8. Perform git rebase
echo -e "\n${YELLOW}⚡ Rebasing '${CURRENT_BRANCH}' onto '${TARGET_BRANCH}'...${NC}"
if git rebase "$TARGET_BRANCH"; then
  echo -e "${GREEN}✅ Rebase completed successfully!${NC}"
  
  # 9. Restore stash if previously created
  if [ "$STASHED" -eq 1 ]; then
    echo -e "\n${YELLOW}📥 Restoring stashed changes with 'git stash pop'...${NC}"
    if git stash pop; then
      echo -e "${GREEN}✅ Stashed changes restored successfully.${NC}"
    else
      echo -e "${YELLOW}⚠️  Stash applied with potential conflict. Please review with 'git status'.${NC}"
    fi
  fi

  echo -e "\n${GREEN}🎉 All done! '${CURRENT_BRANCH}' is successfully rebased onto '${TARGET_BRANCH}'.${NC}\n"
else
  echo -e "\n${RED}⚠️  Rebase conflict detected!${NC}"
  echo -e "${YELLOW}------------------------------------------------------${NC}"
  echo -e "1. Resolve conflicts in your code editor."
  echo -e "2. Run ${CYAN}git add <resolved-files>${NC}"
  echo -e "3. Run ${CYAN}git rebase --continue${NC}"
  echo -e "   (Or run ${RED}git rebase --abort${NC} to cancel)"
  if [ "$STASHED" -eq 1 ]; then
    echo -e "4. After finishing rebase, restore your stash with: ${CYAN}git stash pop${NC}"
  fi
  echo -e "${YELLOW}------------------------------------------------------${NC}\n"
  exit 1
fi
