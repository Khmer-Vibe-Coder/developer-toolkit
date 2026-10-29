#!/usr/bin/env bash

# ==============================================================================
# Script: git-gui.sh
# Purpose: Launch the Developer Toolkit Cross-Platform Electron Desktop App
#          (dtk gui / dtk app). Uses pure Electron IPC and native OS dialogs
#          on macOS, Windows, and Linux (zero web server / browser tabs).
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

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TOOLKIT_VERSION="2.0.0"
[ -f "$TOOLKIT_ROOT/VERSION" ] && read -r TOOLKIT_VERSION < "$TOOLKIT_ROOT/VERSION" || true

for arg in "$@"; do
  if [ "$arg" = "-v" ] || [ "$arg" = "-V" ] || [ "$arg" = "--version" ] || [ "$arg" = "version" ]; then
    echo "git-gui (Developer Toolkit) ${TOOLKIT_VERSION:-2.0.0}"
    exit 0
  elif [ "$arg" = "-h" ] || [ "$arg" = "--help" ] || [ "$arg" = "help" ]; then
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}🖥️  Developer Toolkit GUI — Electron Desktop App (dtk gui)${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "Launches the standalone cross-platform Electron Desktop App"
    echo -e "(macOS, Windows, Linux) with native OS dialogs & pure IPC:"
    echo -e "  • Linking & scanning local/remote Git repositories"
    echo -e "  • Generating multi-repo commit reports & auto-saving Markdown"
    echo -e "  • Managing reusable report templates"
    echo -e "  • Running safe 5-stage git-smart-rebase with conflict rescue"
    echo -e ""
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  dtk gui"
    echo -e "  dtk app"
    echo -e ""
    echo -e "${BOLD}Build Standalone OS Installers (.dmg / .exe / .AppImage):${NC}"
    echo -e "  cd \"$SCRIPT_DIR\" && npm install"
    echo -e "  npm run dist:mac     # macOS .dmg + .zip"
    echo -e "  npm run dist:win     # Windows NSIS .exe + portable"
    echo -e "  npm run dist:linux   # Linux .AppImage + .deb"
    echo -e ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  -h, --help      Show this help message"
    echo -e "  -v, --version   Show version"
    exit 0
  fi
done

if [ -n "${GIT_PREFIX:-}" ]; then
  CALLER_DIR="$(pwd)/${GIT_PREFIX%/}"
else
  CALLER_DIR="$(pwd)"
fi

if [ ! -x "$SCRIPT_DIR/node_modules/.bin/electron" ]; then
  if command -v electron >/dev/null 2>&1; then
    exec electron "$SCRIPT_DIR" --caller-dir "$CALLER_DIR" "$@"
  fi
  echo -e "${YELLOW}📦 Installing Electron desktop runtime in $SCRIPT_DIR (first-time setup)...${NC}"
  npm install --prefix "$SCRIPT_DIR"
fi

# Ensure Electron platform binary is extracted and ready (handles Node >= 24 allowScripts & yauzl stream bug)
if [ ! -f "$SCRIPT_DIR/node_modules/electron/path.txt" ]; then
  node "$SCRIPT_DIR/scripts/ensure-electron.mjs"
fi

exec "$SCRIPT_DIR/node_modules/.bin/electron" "$SCRIPT_DIR" --caller-dir "$CALLER_DIR" "$@"
