#!/usr/bin/env bash
# =============================================================================
# build-macos.sh — Build Continue VSIX on macOS
#
# Requirements:
#   - Node.js 20.x via nvm: nvm install 20 && nvm use 20
#   - OR Homebrew: brew install node@20
#
# Usage:
#   bash build-macos.sh [--target darwin-arm64|darwin-x64]
#                       [--skip-packages] [--only-ext]
# =============================================================================
set -euo pipefail

# --- Defaults ---
# Auto-detect arch
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
  DEFAULT_TARGET="darwin-arm64"
else
  DEFAULT_TARGET="darwin-x64"
fi

TARGET="$DEFAULT_TARGET"
SKIP_PACKAGES=false
ONLY_EXT=false
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)        TARGET="$2"; shift 2 ;;
    --skip-packages) SKIP_PACKAGES=true; shift ;;
    --only-ext)      ONLY_EXT=true; SKIP_PACKAGES=true; shift ;;
    *) shift ;;
  esac
done

# --- Colors ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
timer()   { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }

START_TIME=$(date +%s)

echo ""
echo "================================================"
echo "  Continue Extension Build — macOS"
echo "  Arch:    $ARCH"
echo "  Target:  $TARGET"
echo "  Repo:    $REPO_ROOT"
echo "================================================"
echo ""

cd "$REPO_ROOT"

# --- Verify Node.js ---
info "Checking Node.js version..."
if ! command -v node &>/dev/null; then
  error "Node.js not found. Install via: nvm install 20 or brew install node@20"
fi
NODE_VER=$(node --version)
NPM_VER=$(npm --version)
NODE_MAJOR=$(echo "$NODE_VER" | grep -oE '\d+' | head -1)
if [[ "$NODE_MAJOR" != "20" ]]; then
  warn "Node.js version is $NODE_VER — expected v20.x"
  warn "Switch with: nvm use 20"
fi
success "Node: $NODE_VER | npm: $NPM_VER"

# --- Verify branch ---
BRANCH=$(git branch --show-current)
info "Branch: $BRANCH"

# --- Build packages ---
if [[ "$SKIP_PACKAGES" == "false" ]]; then
  timer "Building packages..."
  for pkg in config-types llm-info fetch openai-adapters config-yaml terminal-security; do
    timer "  packages/$pkg"
    bash -c "cd packages/$pkg && npm run build 2>&1 | tail -2"
  done
  success "Packages built"
fi

# --- Build core & gui ---
if [[ "$ONLY_EXT" == "false" ]]; then
  timer "Building core..."
  bash -c "cd core && npm run build 2>&1 | tail -3"
  success "Core built"

  timer "Building gui..."
  bash -c "cd gui && npm run build 2>&1 | tail -3"
  success "GUI built"
fi

# --- Build extension ---
timer "Packaging extension (target: $TARGET)..."
bash -c "
  cd extensions/vscode &&
  npm run prepackage -- --target $TARGET 2>&1 | tail -5 &&
  npm run package -- --target $TARGET 2>&1 | tail -5
"

# --- Result ---
VSIX=$(ls "$REPO_ROOT/extensions/vscode/build/continue-${TARGET}-"*.vsix 2>/dev/null | head -1)
[[ -z "$VSIX" ]] && error "Build failed — no VSIX found"

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

echo ""
echo "================================================"
echo -e "${GREEN}  BUILD COMPLETE${NC}"
printf "  Time:    %dm %ds\n" $((ELAPSED/60)) $((ELAPSED%60))
echo "  Output:  $(basename "$VSIX")"
echo "  Size:    $(du -sh "$VSIX" | cut -f1)"
echo "================================================"
echo ""
echo "  Install:"
echo "  code --install-extension $VSIX --force"
echo ""
