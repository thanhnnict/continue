#!/usr/bin/env bash
# =============================================================================
# 02-install-continue.sh
# Install Continue VSIX (linux-x64) vào VSCode portable Linux WSL
# + Setup ~/.continue-wsl/ config riêng cho WSL context
#
# Usage:
#   bash 02-install-continue.sh [--vsix <path>]
# =============================================================================
set -euo pipefail

INSTALL_DIR="${HOME}/.apps/vscode-linux"
CONTINUE_CONFIG="${HOME}/.continue-wsl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Parse args ---
VSIX_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vsix) VSIX_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# --- Auto-detect VSIX ---
if [[ -z "$VSIX_FILE" ]]; then
  # Tìm trong cùng folder
  VSIX_FILE=$(ls "${SCRIPT_DIR}/continue-linux-x64-"*.vsix 2>/dev/null | sort -r | head -1 || true)
  # Fallback: build output
  if [[ -z "$VSIX_FILE" ]]; then
    VSIX_FILE=$(ls "${REPO_ROOT}/extensions/vscode/build/continue-linux-x64-"*.vsix 2>/dev/null | sort -r | head -1 || true)
  fi
fi

if [[ -z "$VSIX_FILE" ]]; then
  error "No linux-x64 VSIX found. Build first:
  bash deploy/01-build-extension/build-linux.sh --target linux-x64"
fi

echo ""
echo "=============================================="
echo "  Continue Extension Install — Linux/WSL"
echo "  VSIX:    $(basename "$VSIX_FILE")"
echo "  VSCode:  $INSTALL_DIR"
echo "=============================================="
echo ""

# --- Check VSCode portable installed ---
[[ -f "${INSTALL_DIR}/code" ]] || \
  error "VSCode portable not found at $INSTALL_DIR. Run 01-setup-vscode-portable.sh first."

# --- Install extension ---
info "Installing Continue extension..."
"${INSTALL_DIR}/code" \
  --extensions-dir "${INSTALL_DIR}/data/extensions" \
  --user-data-dir  "${INSTALL_DIR}/data/user-data" \
  --install-extension "$VSIX_FILE" \
  --force \
  --no-sandbox

success "Continue extension installed"

# --- Setup ~/.continue-wsl/ config riêng ---
info "Setting up ~/.continue-wsl/ (WSL-specific config)..."
mkdir -p "${CONTINUE_CONFIG}"

# Tạo config.yaml mặc định nếu chưa có
CONFIG_FILE="${CONTINUE_CONFIG}/config.yaml"
if [[ ! -f "$CONFIG_FILE" ]]; then
  cat > "$CONFIG_FILE" << 'CONFIG_EOF'
# Continue config cho VSCode Linux/WSL
# File này riêng biệt với config Windows (~/.continue/config.yaml)
# để có thể cấu hình terminal và shell path phù hợp với WSL

name: WSL OnPrem

models:
  - name: "NIM — Nemotron Ultra"
    provider: openai
    model: nemotron-ultra-253b-v1
    apiBase: https://nim.internal.company.com/v1
    requestOptions:
      verifySsl: false

# WSL-specific: terminal chạy bash trực tiếp (không qua Windows shell)
# Không cần cấu hình thêm — VSCode Linux tự dùng WSL bash
CONFIG_EOF
  success "Config created: $CONFIG_FILE"
else
  warn "Config already exists: $CONFIG_FILE (not overwritten)"
fi

# --- Configure VSCode portable để dùng ~/.continue-wsl/ ---
USER_SETTINGS="${INSTALL_DIR}/data/user-data/User/settings.json"
mkdir -p "$(dirname "$USER_SETTINGS")"

if [[ ! -f "$USER_SETTINGS" ]]; then
  cat > "$USER_SETTINGS" << SETTINGS_EOF
{
  "continue.configFile": "${CONTINUE_CONFIG}/config.yaml",
  "terminal.integrated.defaultProfile.linux": "bash",
  "terminal.integrated.profiles.linux": {
    "bash": {
      "path": "/bin/bash",
      "args": ["-l"]
    }
  }
}
SETTINGS_EOF
  success "VSCode settings created"
else
  warn "VSCode settings already exist: $USER_SETTINGS"
  info "Add manually if needed:"
  echo "  \"continue.configFile\": \"${CONTINUE_CONFIG}/config.yaml\""
fi

# --- Verify ---
EXT_DIR="${INSTALL_DIR}/data/extensions"
INSTALLED=$(ls "$EXT_DIR" 2>/dev/null | grep -i "continue" || true)
if [[ -n "$INSTALLED" ]]; then
  success "Verified: $INSTALLED"
else
  warn "Could not verify extension — check $EXT_DIR manually"
fi

echo ""
echo "=============================================="
echo -e "${GREEN}  Install complete!${NC}"
echo "=============================================="
echo ""
echo "  Config:   $CONFIG_FILE"
echo "  Settings: $USER_SETTINGS"
echo ""
echo "  Launch:"
echo "  source ~/.bashrc && code-wsl /mnt/e/08-Sources/1.AI/continue"
echo ""
echo "  Next: bash deploy/03-vscode-portable-linux-wsl/03-verify.sh"
echo ""
