#!/usr/bin/env bash
# =============================================================================
# 00-pre-install.sh — Pre-install native dependencies cho build Linux/WSL
#
# Vấn đề: node_modules trong repo thường được install trên Windows (rg.exe),
# nhưng build linux-x64 cần Linux binaries (rg, .so files).
# Script này fix tất cả platform-specific dependencies trước khi build.
#
# Những gì script làm:
#   1. Kiểm tra / cài conda env node20
#   2. npm install trong extensions/vscode (lấy đúng platform packages)
#   3. Fix @vscode/ripgrep → install linux-x64 binary + symlink
#   4. Fix @lancedb → install linux-x64-gnu binary
#   5. Verify tất cả required files có mặt
#
# Usage:
#   bash deploy/01-build-extension/00-pre-install.sh [--target linux-x64|win32-x64]
#   bash deploy/01-build-extension/00-pre-install.sh --check-only
# =============================================================================
set -euo pipefail

TARGET="${TARGET:-linux-x64}"
CHECK_ONLY=false
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NPM_REGISTRY="http://localhost:7081/repository/npm-group/"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)     TARGET="$2"; shift 2 ;;
    --check-only) CHECK_ONLY=true; shift ;;
    *) shift ;;
  esac
done

# --- Colors ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Derive platform info from target
case "$TARGET" in
  linux-x64)    OS=linux; ARCH=x64; EXE="";     LANCEDB_SUFFIX="-gnu" ;;
  win32-x64)    OS=win32; ARCH=x64; EXE=".exe";  LANCEDB_SUFFIX="-msvc" ;;
  darwin-arm64) OS=darwin; ARCH=arm64; EXE="";   LANCEDB_SUFFIX="" ;;
  darwin-x64)   OS=darwin; ARCH=x64; EXE="";     LANCEDB_SUFFIX="" ;;
  *) error "Unknown target: $TARGET" ;;
esac

LANCEDB_PKG="@lancedb/vectordb-${TARGET}${LANCEDB_SUFFIX}"
RIPGREP_PKG="@vscode/ripgrep-${OS}-${ARCH}"

echo ""
echo "=============================================="
echo "  Continue Pre-install — $TARGET"
echo "  Repo: $REPO_ROOT"
echo "  npm:  $NPM_REGISTRY"
echo "=============================================="
echo ""

EXT_DIR="${REPO_ROOT}/extensions/vscode"
FAILED=0

# =============================================================================
# STEP 0: Verify conda env node20
# =============================================================================
info "Checking conda env 'node20'..."
if ! conda env list 2>/dev/null | grep -q "^node20"; then
  if [[ "$CHECK_ONLY" == "true" ]]; then
    echo -e "  ${RED}[FAIL]${NC} conda env 'node20' not found"
    FAILED=$((FAILED+1))
  else
    info "Creating conda env 'node20'..."
    conda create -n node20 -y nodejs=20
  fi
fi
NODE_VER=$(conda run -n node20 node --version 2>/dev/null || echo "N/A")
success "Node: $NODE_VER"

# =============================================================================
# Helper: check_or_install
# =============================================================================
check_file() {
  local file="$1"
  local desc="$2"
  if [[ -e "$file" ]]; then
    echo -e "  ${GREEN}[OK]${NC}    $desc"
    return 0
  else
    echo -e "  ${RED}[MISSING]${NC} $desc"
    echo -e "            → $file"
    FAILED=$((FAILED+1))
    return 1
  fi
}

# =============================================================================
# STEP 1: npm install trong extensions/vscode
# =============================================================================
if [[ "$CHECK_ONLY" == "false" ]]; then
  info "Running npm install in extensions/vscode..."
  conda run -n node20 bash -c "
    cd '${EXT_DIR}'
    npm install --registry ${NPM_REGISTRY} 2>&1 | tail -4
  "
  success "npm install done"
fi

# =============================================================================
# STEP 2: Fix @vscode/ripgrep — install platform binary
# =============================================================================
RIPGREP_BIN="${EXT_DIR}/node_modules/${RIPGREP_PKG}/bin/rg${EXE}"
RIPGREP_SYMLINK="${EXT_DIR}/node_modules/@vscode/ripgrep/bin/rg${EXE}"

echo ""
info "[@vscode/ripgrep] target: $RIPGREP_PKG"

if [[ ! -f "$RIPGREP_BIN" ]]; then
  if [[ "$CHECK_ONLY" == "true" ]]; then
    echo -e "  ${RED}[MISSING]${NC} $RIPGREP_PKG binary"
    FAILED=$((FAILED+1))
  else
    info "Installing $RIPGREP_PKG..."
    conda run -n node20 bash -c "
      cd '${EXT_DIR}'
      npm install '${RIPGREP_PKG}' --registry ${NPM_REGISTRY} --no-save 2>&1 | tail -3
    "
    success "$RIPGREP_PKG installed"
  fi
else
  success "$RIPGREP_PKG binary exists"
fi

# Create symlink nếu chưa có
if [[ ! -e "$RIPGREP_SYMLINK" ]] && [[ -f "$RIPGREP_BIN" ]]; then
  if [[ "$CHECK_ONLY" == "true" ]]; then
    echo -e "  ${RED}[MISSING]${NC} ripgrep symlink: $RIPGREP_SYMLINK"
    FAILED=$((FAILED+1))
  else
    info "Creating ripgrep symlink..."
    mkdir -p "$(dirname "$RIPGREP_SYMLINK")"
    ln -sf "$RIPGREP_BIN" "$RIPGREP_SYMLINK"
    success "Symlink: @vscode/ripgrep/bin/rg${EXE} → ${RIPGREP_PKG}/bin/rg${EXE}"
  fi
elif [[ -e "$RIPGREP_SYMLINK" ]]; then
  success "ripgrep symlink exists"
fi

# =============================================================================
# STEP 3: Fix @lancedb — install platform binary
# =============================================================================
LANCEDB_NODE="${EXT_DIR}/node_modules/${LANCEDB_PKG}/index.node"

echo ""
info "[@lancedb] target: $LANCEDB_PKG"

if [[ ! -f "$LANCEDB_NODE" ]]; then
  if [[ "$CHECK_ONLY" == "true" ]]; then
    echo -e "  ${RED}[MISSING]${NC} $LANCEDB_PKG"
    FAILED=$((FAILED+1))
  else
    info "Installing $LANCEDB_PKG..."
    conda run -n node20 bash -c "
      cd '${EXT_DIR}'
      npm install '${LANCEDB_PKG}' --registry ${NPM_REGISTRY} --no-save 2>&1 | tail -3
    "
    success "$LANCEDB_PKG installed"
  fi
else
  success "$LANCEDB_PKG binary exists"
fi

# =============================================================================
# STEP 4: Verify tất cả required files
# =============================================================================
echo ""
info "Verifying required files for prepackage ($TARGET)..."

cd "$EXT_DIR"

# Core required files
check_file "node_modules/@vscode/ripgrep/bin/rg${EXE}"          "ripgrep binary (node_modules)"

# onnxruntime — luôn có sau npm install core
check_file "${REPO_ROOT}/core/node_modules/onnxruntime-node/bin/napi-v3/${OS}/${ARCH}/onnxruntime_binding.node" \
           "onnxruntime binding (${OS}/${ARCH})"

# lancedb
check_file "node_modules/${LANCEDB_PKG}/index.node" \
           "lancedb binary (${LANCEDB_PKG})"

# GUI build output — prepackage.js expects gui/assets/ symlinked or copied
# Kiểm tra cả 2 locations có thể có
if [[ -f "gui/assets/index.js" ]] || [[ -f "../../gui/out/assets/index.js" ]]; then
  echo -e "  ${GREEN}[OK]${NC}    gui assets (gui/assets/index.js)"
else
  echo -e "  ${YELLOW}[WARN]${NC}  gui/assets not built yet — OK if running full build"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}  Pre-install complete — ready to build!${NC}"
  if [[ "$CHECK_ONLY" == "true" ]]; then
    echo -e "${GREEN}  All checks passed${NC}"
  fi
  echo ""
  echo "  Next:"
  echo "  bash deploy/01-build-extension/build-linux.sh --target $TARGET"
else
  if [[ "$CHECK_ONLY" == "true" ]]; then
    echo -e "${RED}  $FAILED check(s) failed${NC}"
    echo ""
    echo "  Fix with:"
    echo "  bash deploy/01-build-extension/00-pre-install.sh --target $TARGET"
  else
    echo -e "${YELLOW}  $FAILED item(s) may still be missing${NC}"
    echo "  Re-run with --check-only to verify"
  fi
fi
echo "=============================================="
echo ""
