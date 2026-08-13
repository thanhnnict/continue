#!/usr/bin/env bash
# =============================================================================
# build-linux.sh — Build Continue VSIX on Linux/WSL
#
# Requirements:
#   - Miniconda with env 'node20' (Node.js v20.17.0)
#   - conda create -n node20 -y nodejs=20
#
# Usage:
#   bash build-linux.sh [--target linux-x64|win32-x64|darwin-arm64|darwin-x64]
#                       [--skip-packages] [--only-ext]
# =============================================================================
set -euo pipefail

# --- Defaults ---
TARGET="${1:-linux-x64}"
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
echo "  Continue Extension Build — Linux/WSL"
echo "  Target:  $TARGET"
echo "  Repo:    $REPO_ROOT"
echo "================================================"
echo ""

cd "$REPO_ROOT"

# --- Run pre-install if ripgrep not ready ---
RIPGREP_CHECK="extensions/vscode/node_modules/@vscode/ripgrep/bin/rg"
if [[ "$TARGET" == "win32-x64" ]]; then RIPGREP_CHECK="${RIPGREP_CHECK}.exe"; fi
if [[ ! -e "$RIPGREP_CHECK" ]]; then
  warn "ripgrep binary missing — running pre-install first..."
  bash "$(dirname "${BASH_SOURCE[0]}")/00-pre-install.sh" --target "$TARGET"
fi

# --- Verify conda node20 ---
info "Checking conda env 'node20'..."
if ! conda env list 2>/dev/null | grep -q "^node20"; then
  error "conda env 'node20' not found. Run: conda create -n node20 -y nodejs=20"
fi
NODE_VER=$(conda run -n node20 node --version 2>/dev/null)
NPM_VER=$(conda run -n node20 npm --version 2>/dev/null)
success "Node: $NODE_VER | npm: $NPM_VER"

# --- Verify branch ---
BRANCH=$(git branch --show-current)
info "Branch: $BRANCH"
if [[ "$BRANCH" != "develop" && "$BRANCH" != release/* ]]; then
  warn "Not on develop/release branch. Continuing anyway..."
fi

# --- Verify critical dependencies ---
info "Checking critical build dependencies..."
MISSING=0

EXE=""
if [[ "$TARGET" == "win32-x64" ]]; then EXE=".exe"; fi

# node_modules
if [[ ! -d "$REPO_ROOT/extensions/vscode/node_modules" ]]; then
  warn "Missing: extensions/vscode/node_modules/"
  MISSING=$((MISSING+1))
fi

# ripgrep
if [[ ! -f "$REPO_ROOT/extensions/vscode/node_modules/@vscode/ripgrep/bin/rg${EXE}" ]]; then
  warn "Missing: @vscode/ripgrep binary (rg${EXE})"
  MISSING=$((MISSING+1))
fi

# lancedb
LANCEDB_SUFFIX=""
if [[ "$TARGET" == linux-* ]]; then LANCEDB_SUFFIX="-gnu"; fi
if [[ "$TARGET" == win32-* ]]; then LANCEDB_SUFFIX="-msvc"; fi
if [[ ! -f "$REPO_ROOT/extensions/vscode/node_modules/@lancedb/vectordb-${TARGET}${LANCEDB_SUFFIX}/index.node" ]]; then
  warn "Missing: @lancedb/vectordb-${TARGET}${LANCEDB_SUFFIX}"
  MISSING=$((MISSING+1))
fi

if [[ $MISSING -gt 0 ]]; then
  error "Missing $MISSING critical dependencies. Run:\n" \
        "  bash deploy/01-build-extension/00-pre-install.sh --target $TARGET"
fi
success "All critical dependencies present"

# --- Build packages (unless skipped) ---
if [[ "$SKIP_PACKAGES" == "false" ]]; then
  timer "Building packages..."
  PACKAGES=(config-types llm-info fetch openai-adapters config-yaml terminal-security)
  for pkg in "${PACKAGES[@]}"; do
    timer "  packages/$pkg"
    conda run -n node20 bash -c "cd packages/$pkg && npm run build 2>&1 | tail -2"
  done
  success "Packages built"
fi

# --- Build core (unless only-ext) ---
if [[ "$ONLY_EXT" == "false" ]]; then
  timer "Building core..."
  conda run -n node20 bash -c "cd core && npm run build 2>&1 | tail -3"
  success "Core built"

  timer "Building gui..."
  conda run -n node20 bash -c "cd gui && npm run build 2>&1 | tail -3"
  success "GUI built"
fi

# --- Build VSCode extension ---
# NOTE: We avoid `npm run prepackage` and `npm run package` because:
#   1. npmInstall() in prepackage.js forks child processes that run `npm install`
#      which can hang indefinitely when node_modules already exist
#   2. npm lifecycle auto-runs "prepackage" before "package" (naming convention)
#   3. package.js calls vsce directly without vscode:prepublish → missing esbuild
#
# Instead: SKIP_INSTALLS=true + npx @vscode/vsce (triggers vscode:prepublish)

timer "Prepackage (target: $TARGET)..."
conda run -n node20 bash -c "
  cd extensions/vscode &&
  SKIP_INSTALLS=true node scripts/prepackage.js --target $TARGET 2>&1 | tail -10
"
success "Prepackage done"

timer "Packaging VSIX (target: $TARGET)..."
conda run -n node20 bash -c "
  cd extensions/vscode &&
  npx @vscode/vsce package --out ./build --no-dependencies --target $TARGET 2>&1 | tail -10
"

# --- Result ---
VSIX=$(ls "$REPO_ROOT/extensions/vscode/build/continue-${TARGET}-"*.vsix 2>/dev/null | head -1)
if [[ -z "$VSIX" ]]; then
  error "Build failed — no VSIX found"
fi

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
