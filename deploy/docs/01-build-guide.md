# Build Continue VSCode Extension — Windows 11

> **Target**: win32-x64 (Windows 11 64-bit)  
> **Cập nhật**: 2026-08-09 (moved from docs/build/ to deploy/docs/)  
> **Node.js**: >= 20.x (tested with v20.14.0)  
> **npm**: >= 10.x (tested with 10.7.0)  
> **Version**: v2.1.1 (custom on-prem build, base upstream/main)

---

## Mục lục

- [1. Yêu cầu hệ thống](#1-yêu-cầu-hệ-thống)
- [2. Chuẩn bị môi trường](#2-chuẩn-bị-môi-trường)
- [3. Cấu trúc thư mục](#3-cấu-trúc-thư-mục)
- [4. Build tự động (recommended)](#4-build-tự-động-recommended)
- [5. Build thủ công từng bước](#5-build-thủ-công-từng-bước)
- [6. Install extension](#6-install-extension)
- [7. Verify kết quả](#7-verify-kết-quả)
- [8. Troubleshooting](#8-troubleshooting)
- [9. Các patches đã áp dụng](#9-các-patches-đã-áp-dụng)

---

## 1. Yêu cầu hệ thống

### Phần mềm

| Phần mềm | Phiên bản tối thiểu | Kiểm tra |
|----------|:-------------------:|----------|
| Windows | 10 / 11 | \winver\ |
| Node.js | >= 20.20.1 | \
ode --version\ |
| npm | >= 10.x | \
pm --version\ |
| Git | >= 2.x | \git --version\ |
| VSCode | >= 1.70.0 | \code --version\ |

### Kiểm tra nhanh

\\\powershell
node --version
npm --version
git --version
code --version
\\\

### Lưu ý Node.js version

Extension yêu cầu \
ode >= 20.20.1\. Nếu bạn dùng Node.js 20.14.0 (như môi trường hiện tại), build vẫn hoạt động nhưng sẽ có cảnh báo \EBADENGINE\ — không ảnh hưởng đến kết quả.

Để nâng cấp Node.js:

\\\powershell
# Kiểm tra phiên bản hiện tại
node --version

# Download Node.js 20.20.1+ từ: https://nodejs.org/
# Hoặc dùng nvm-windows
nvm install 20.20.1
nvm use 20.20.1
\\\

---

## 2. Chuẩn bị môi trường

### 2.1. Clone repository

\\\powershell
# Ví dụ: clone vào E:\08-Sources\1.AI\continue
git clone https://github.com/continuedev/continue.git
cd continue
\\\

### 2.2. Kiểm tra branch và patches

\\\powershell
# Kiểm tra branch hiện tại
git branch

# Kiểm tra các patches đã áp dụng
Select-String -Path packages/openai-adapters/src/apis/OpenAI.ts -Pattern "Retry without tools"
Select-String -Path core/llm/openaiTypeConverters.ts -Pattern "Sanitize arguments"
Test-Path core/llm/visionProxy.ts
Select-String -Path extensions/vscode/src/extension.ts -Pattern "NODE_TLS_REJECT_UNAUTHORIZED"
\\\

---

## 3. Cấu trúc thư mục

\\\
continue/
├── docs/
│   └── build/
│       ├── README.md              # Hướng dẫn build (file này)
│       └── troubleshooting.md     # Xử lý lỗi thường gặp
├── scripts/
│   ├── build-all.ps1              # Build script tự động (Windows)
│   ├── build-packages.js          # Build script cho packages
│   └── util/
│       └── index.js               # Utilities cho build
├── packages/
│   ├── config-types/              # [1] Build đầu tiên
│   ├── llm-info/                  # [2]
│   ├── fetch/                     # [3]
│   ├── openai-adapters/           # [4]
│   ├── config-yaml/               # [5]
│   └── terminal-security/         # [6]
├── core/                          # [7]
├── gui/                           # [8]
├── extensions/
│   └── vscode/                    # [9] Prepackage + Package → VSIX
│       ├── build/                 # Output: *.vsix files
│       └── scripts/               # Build scripts của extension
├── .patches/                      # Tài liệu các custom patches
└── .vscode/
    └── tasks.json                 # VSCode tasks cho build
\\\

### Thứ tự build (dependency chain)

\\\mermaid
flowchart LR
    A[config-types] --> B[llm-info]
    A --> C[fetch]
    B --> D[openai-adapters]
    C --> D
    D --> E[config-yaml]
    D --> F[terminal-security]
    E --> G[core]
    F --> G
    G --> H[gui]
    G --> I[vscode extension]
    H --> I
    I --> J[VSIX output]
\\\

---

## 4. Build tự động (recommended)

### 4.1. Chạy build script

\\\powershell
cd E:\08-Sources\1.AI\continue

# Build với target mặc định (win32-x64)
.\scripts\build-all.ps1

# Hoặc chỉ định target cụ thể
.\scripts\build-all.ps1 -Target win32-x64
\\\

### 4.2. Tiến trình build

Script sẽ tự động chạy theo thứ tự:

| Step | Package | Command | Thời gian |
|:----:|---------|---------|:---------:|
| 1 | \config-types\ | \
pm install && npm run build\ | ~15s |
| 2 | \llm-info\ | \
pm install && npm run build\ | ~25s |
| 3 | \etch\ | \
pm install && npm run build\ | ~20s |
| 4 | \openai-adapters\ | \
pm install && npm run build\ | ~30s |
| 5 | \config-yaml\ | \
pm install && npm run build\ | ~25s |
| 6 | \	erminal-security\ | \
pm install && npm run build\ | ~20s |
| 7 | \core\ | \
pm install && npm run build\ | ~30s |
| 8 | \gui\ | \
pm install && npm run build\ | ~60s |
| 9 | \scode\ | \
pm install && prepackage && package\ | ~120s |
| | **Tổng** | | **~5-6 phút** |

### 4.3. Kết quả

Sau khi build thành công:

\\\
========================================
  BUILD COMPLETE!
  Total time: 7.8 min
========================================

  VSIX: continue-win32-x64-2.1.1.vsix (71.01 MB)

Install with:
  code --install-extension extensions\vscode\build\continue-*.vsix --force
\\\

---

## 5. Build thủ công từng bước

### Step 1-6: Build packages

\\\powershell
# Từ root project directory
 = "E:\08-Sources\1.AI\continue"

# 1. config-types
cd "\packages\config-types"
npm install && npm run build

# 2. llm-info
cd "\packages\llm-info"
npm install && npm run build

# 3. fetch
cd "\packages\fetch"
npm install && npm run build

# 4. openai-adapters
cd "\packages\openai-adapters"
npm install && npm run build

# 5. config-yaml
cd "\packages\config-yaml"
npm install && npm run build

# 6. terminal-security
cd "\packages\terminal-security"
npm install && npm run build
\\\

### Step 7: Build core

\\\powershell
cd "\core"
npm install && npm run build
\\\

### Step 8: Build GUI

\\\powershell
cd "\gui"
npm install && npm run build
\\\

### Step 9: Build VSCode extension

\\\powershell
cd "\extensions\vscode"
npm install
npm run prepackage -- --target win32-x64
npm run package -- --target win32-x64
\\\

### Kiểm tra output

\\\powershell
Get-ChildItem "\extensions\vscode\build\*.vsix"
\\\

---

## 6. Install extension

### 6.1. Install bằng command line

\\\powershell
cd E:\08-Sources\1.AI\continue

# Install VSIX vào VSCode
code --install-extension extensions\vscode\build\continue-win32-x64-2.1.1.vsix --force
\\\

### 6.2. Install bằng VSCode UI

1. Mở VSCode
2. Mở Extensions panel (\Ctrl+Shift+X\)
3. Click \...\ (More Actions) → \Install from VSIX...\
4. Chọn file \extensions\vscode\build\continue-win32-x64-2.1.1.vsix\

### 6.3. Verify installation

\\\powershell
# Kiểm tra extension đã install
code --list-extensions | Select-String "continue"
\\\"

Hoặc trong VSCode: \Extensions\ panel → tìm \Continue OnPrem\

---

## 7. Verify kết quả

### 7.1. Kiểm tra VSIX file

\\\powershell
Get-ChildItem extensions\vscode\build\*.vsix | ForEach-Object {
    Write-Host "File: "
    Write-Host "Size: 0 MB"
    Write-Host "Modified: "
}
\\\

Kỳ vọng:
- File: \continue-win32-x64-2.1.1.vsix\
- Size: ~71 MB
- Ngày: mới nhất

### 7.2. Kiểm tra patches trong build

\\\powershell
Write-Host "=== Verify Patches ==="

Write-Host "1. NIM Empty Response Retry:"
Select-String -Path packages/openai-adapters/src/apis/OpenAI.ts -Pattern "Retry without tools"

Write-Host "2. JSON Sanitize:"
Select-String -Path core/llm/openaiTypeConverters.ts -Pattern "Sanitize arguments"

Write-Host "3. Vision Proxy:"
if (Test-Path core/llm/visionProxy.ts) { Write-Host "   visionProxy.ts exists" }
Select-String -Path core/llm/index.ts -Pattern "Vision Proxy"

Write-Host "4. TLS Self-Signed Cert:"
Select-String -Path extensions/vscode/src/extension.ts -Pattern "NODE_TLS_REJECT_UNAUTHORIZED"
\\\

### 7.3. Kiểm tra extension trong VSCode

1. Mở VSCode
2. \Ctrl+Shift+P\ → \Continue: Open config file\ — kiểm tra config
3. Thử chat với model — kiểm tra response không bị blank

---

## 8. Troubleshooting

### 8.1. Lỗi \EBADENGINE\ warnings

\\\
npm warn EBADENGINE Unsupported engine { package: 'continue@2.0.5', required: { node: '>=20.20.1' } ... }
\\\

**Nguyên nhân**: Node.js version < 20.20.1  
**Giải pháp**: Nâng cấp Node.js lên >= 20.20.1, hoặc bỏ qua (không ảnh hưởng build).

### 8.2. Lỗi \
pm install\ thất bại

\\\
npm ERR! code EINTEGRITY
npm ERR! errno EINTEGRITY
\\\

**Nguyên nhân**: Cache npm bị corrupt  
**Giải pháp**:

\\\powershell
npm cache clean --force
npm install
\\\

### 8.3. Lỗi \prepackage\ thất bại

\\\
Error: Cannot find module '...'
\\\

**Nguyên nhân**: Thiếu dependencies ở các bước trước  
**Giải pháp**: Build lại từ đầu với script tự động

### 8.4. Lỗi \sce package\ thất bại

\\\
Error: Missing extension icon
\\\

**Nguyên nhân**: Thiếu file \media/icon.png\  
**Giải pháp**: Kiểm tra file tồn tại:

\\\powershell
Test-Path extensions/vscode/media/icon.png
\\\

### 8.5. Extension install nhưng không hoạt động

**Nguyên nhân**: Có thể do:
- Xung đột với Continue version cũ
- Native modules không đúng platform

**Giải pháp**:

\\\powershell
# Uninstall version cũ
code --uninstall-extension continue

# Install lại
code --install-extension extensions\vscode\build\continue-win32-x64-2.1.1.vsix --force

# Reload VSCode window
# Ctrl+Shift+P → Developer: Reload Window
\\\

---

## 9. Các patches đã áp dụng

Extension này bao gồm 4 custom patches cho on-prem deployment:

| # | Patch | File | Mô tả |
|:-:|-------|------|-------|
| 1 | NIM Empty Response Retry | \packages/openai-adapters/src/apis/OpenAI.ts\ | Retry without tools khi server trả về \content: null\ + \	ool_calls: []\ |
| 2 | JSON Sanitize | \core/llm/openaiTypeConverters.ts\ | Validate JSON arguments trong tool_calls trước khi gửi lại server |
| 3 | Vision Proxy | \core/llm/visionProxy.ts\ | Route images qua VLM (Qwen2.5-VL) cho text-only LLMs |
| 4 | TLS Self-Signed Cert | \extensions/vscode/src/extension.ts\ | Cho phép self-signed certificates |

Chi tiết: [.patches/README.md](../../.patches/README.md)

---

## Appendix

### A. So sánh build Windows vs macOS

| Hạng mục | Windows 11 | macOS (Apple Silicon) |
|----------|:----------:|:---------------------:|
| Target | \win32-x64\ | \darwin-arm64\ |
| Native modules | \onnxruntime.dll\, \
ode_sqlite3.node\ | \libonnxruntime.dylib\, \
ode_sqlite3.node\ |
| LanceDB | \ectordb-win32-x64-msvc\ | \ectordb-darwin-arm64\ |
| ripgrep | \
g.exe\ | \
g\ |
| Thời gian build | ~5-8 phút | ~5-8 phút |
| VSIX size | ~71 MB | ~70 MB |

### B. File tham chiếu

| File | Mô tả |
|------|-------|
| \scripts/build-all.ps1\ | Build script tự động cho Windows |
| \extensions/vscode/scripts/prepackage.js\ | Prepackage script (copy native modules) |
| \extensions/vscode/scripts/package.js\ | Package script (gọi vsce) |
| \extensions/vscode/scripts/download-copy-sqlite.js\ | Download sqlite3 binary |
| \extensions/vscode/scripts/install-copy-nodemodule.js\ | Copy lancedb binary |
| \.patches/README.md\ | Danh sách và mô tả patches |
