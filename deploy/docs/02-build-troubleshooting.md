# Troubleshooting — Build Continue Extension on Windows

> Các lỗi thường gặp và cách xử lý khi build Continue VSCode Extension trên Windows 11.

---

## 1. Lỗi npm

### 1.1. EBADENGINE warnings

**Hiện tượng**:
```
npm warn EBADENGINE Unsupported engine { package: 'continue@2.0.5', required: { node: '>=20.20.1' } ... }
```

**Nguyên nhân**: Node.js version thấp hơn yêu cầu (>= 20.20.1).
**Mức độ ảnh hưởng**: ⚠️ Warning — không gây lỗi build.
**Xử lý**:
- Bỏ qua nếu build thành công
- Hoặc nâng cấp Node.js: `nvm install 20.20.1 && nvm use 20.20.1`

### 1.2. EINTEGRITY / cache corrupt

**Hiện tượng**:
```
npm ERR! code EINTEGRITY
npm ERR! errno EINTEGRITY
```

**Xử lý**:
```powershell
npm cache clean --force
npm install
```

### 1.3. ERESOLVE peer dependency

**Hiện tượng**:
```
npm ERR! Could not resolve dependency:
npm ERR! peerOptional @types/node@"^18.0.0 || ^20.0.0 || >=22.0.0"
```

**Xử lý**:
```powershell
npm install --legacy-peer-deps
```

### 1.4. Network timeout / fetch failed

**Hiện tượng**:
```
npm ERR! network timeout
npm ERR! fetch failed
```

**Nguyên nhân**: Mạng chậm hoặc bị chặn (Nexus/firewall).
**Xử lý**:
```powershell
# Tăng timeout
npm config set fetch-timeout 120000
npm config set fetch-retries 5

# Hoặc dùng registry khác
npm install --registry https://registry.npmjs.org
```

---

## 2. Lỗi build

### 2.1. TypeScript compilation error

**Hiện tượng**:
```
src/file.ts:XX:YY - error TS2322: Type 'X' is not assignable to type 'Y'
```

**Nguyên nhân**: Code TypeScript không pass type check.
**Xử lý**:
- Kiểm tra file lỗi và sửa type
- Hoặc dùng `// @ts-ignore` (tạm thời)
- Hoặc set `"skipLibCheck": true` trong tsconfig.json

### 2.2. Cannot find module

**Hiện tượng**:
```
Error: Cannot find module '@continuedev/config-types'
```

**Nguyên nhân**: Build sai thứ tự — package dependency chưa được build.
**Xử lý**: Build lại theo đúng thứ tự (dùng `scripts/build-all.ps1`).

### 2.3. prepackage thất bại

**Hiện tượng**:
```
Error: gui build did not produce index.js
```

**Nguyên nhân**: GUI chưa được build hoặc build lỗi.
**Xử lý**:
```powershell
cd gui
npm install
npm run build
```

### 2.4. vsce package thất bại

**Hiện tượng**:
```
Error: Missing extension icon
Error: ENOENT: no such file or directory, open '...media/icon.png'
```

**Xử lý**:
```powershell
# Kiểm tra file icon
Test-Path extensions/vscode/media/icon.png

# Nếu thiếu, tạo file icon tối thiểu
# Hoặc comment dòng "icon" trong extensions/vscode/package.json
```

---

## 3. Lỗi runtime (sau khi install)

### 3.1. Extension không load / UI stuck

**Hiện tượng**: VSCode mở nhưng Continue panel không hiện hoặc hiện loading mãi.

**Nguyên nhân** (theo kinh nghiệm từ .patches/03-upstream-sync-strategy.md):
- Native modules sai platform (ví dụ: build trên Linux copy sang Windows)
- `onnxruntime-node` binary sai OS
- `@lancedb/vectordb` binary sai platform

**Xử lý**:
```powershell
# 1. Uninstall extension cũ
code --uninstall-extension continue

# 2. Build lại đúng trên Windows (không cross-platform)
.\scripts\build-all.ps1

# 3. Install lại
code --install-extension extensions\vscode\build\continue-win32-x64-2.0.5.vsix --force

# 4. Reload VSCode
# Ctrl+Shift+P → Developer: Reload Window
```

### 3.2. Lỗi "Cannot find module" khi chạy

**Hiện tượng**: Extension load được nhưng có lỗi trong Console.

**Xử lý**:
```powershell
# Mở VSCode Developer Console
# Ctrl+Shift+P → Developer: Toggle Developer Tools
# Xem tab Console để biết lỗi chi tiết
```

### 3.3. Config không load được

**Hiện tượng**: Extension mở được nhưng không kết nối được model.

**Xử lý**:
1. Kiểm tra file config: `Ctrl+Shift+P` → `Continue: Open config file`
2. Kiểm tra `apiBase` có đúng URL server không
3. Kiểm tra network: `curl http://your-server:port/v1/models`

---

## 4. Lỗi liên quan đến Git

### 4.1. Patches bị mất sau khi merge/pull

**Hiện tượng**: Sau khi `git pull` hoặc `git merge`, các custom patches biến mất.

**Xử lý**:
```powershell
# Kiểm tra patches
Select-String -Path packages/openai-adapters/src/apis/OpenAI.ts -Pattern "Retry without tools"
Select-String -Path core/llm/openaiTypeConverters.ts -Pattern "Sanitize arguments"

# Nếu mất, apply lại từ .patches/
# Xem hướng dẫn trong .patches/03-upstream-sync-strategy.md
```

### 4.2. Conflict khi rebase

**Hiện tượng**: `git rebase` báo conflict ở các file đã patch.

**Xử lý**:
```powershell
# Xem file conflict
git diff --name-only --diff-filter=U

# Resolve thủ công, sau đó
git add <file>
git rebase --continue
```

---

## 5. Lỗi môi trường

### 5.1. PowerShell execution policy

**Hiện tượng**:
```
.\scripts\build-all.ps1 : File cannot be loaded because running scripts is disabled on this system.
```

**Xử lý**:
```powershell
# Kiểm tra policy hiện tại
Get-ExecutionPolicy

# Cho phép chạy script (Admin required)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Hoặc chạy với bypass
powershell -ExecutionPolicy Bypass -File .\scripts\build-all.ps1
```

### 5.2. Path quá dài (MAX_PATH)

**Hiện tượng**: Lỗi không tạo được file/folder do path > 260 ký tự.

**Xử lý**:
```powershell
# Kiểm tra và enable long path support
# Hoặc clone ở thư mục ngắn hơn, ví dụ: C:\dev\continue
```

### 5.3. Anti-virus chặn npm

**Hiện tượng**: npm install chậm hoặc thất bại do anti-virus scan.

**Xử lý**: Thêm exclusion cho thư mục project trong Windows Defender / anti-virus.

---

## 6. Diagnostic commands

### 6.1. Kiểm tra môi trường

```powershell
# Node
node --version
npm --version

# Git
git --version

# VSCode
code --version

# PowerShell
$PSVersionTable.PSVersion

# System
[System.Environment]::OSVersion.VersionString
```

### 6.2. Kiểm tra build output

```powershell
# VSIX file
Get-ChildItem extensions\vscode\build\*.vsix

# Native modules
Get-ChildItem extensions\vscode\bin\napi-v3\win32-x64\

# Extension install
code --list-extensions | Select-String "continue"
```

### 6.3. Kiểm tra patches

```powershell
Write-Host "Patch 1 (NIM retry):"
Select-String -Path packages/openai-adapters/src/apis/OpenAI.ts -Pattern "Retry without tools" -SimpleMatch | ForEach-Object { "  Found at line $($_.LineNumber)" }

Write-Host "Patch 2 (JSON sanitize):"
Select-String -Path core/llm/openaiTypeConverters.ts -Pattern "Sanitize arguments" -SimpleMatch | ForEach-Object { "  Found at line $($_.LineNumber)" }

Write-Host "Patch 3 (Vision Proxy):"
if (Test-Path core/llm/visionProxy.ts) { "  visionProxy.ts: EXISTS" } else { "  visionProxy.ts: MISSING" }

Write-Host "Patch 4 (TLS):"
Select-String -Path extensions/vscode/src/extension.ts -Pattern "NODE_TLS_REJECT_UNAUTHORIZED" -SimpleMatch | ForEach-Object { "  Found at line $($_.LineNumber)" }
```

---

## 7. Khi nào cần build lại từ đầu

Build lại từ đầu nếu:
- Thay đổi code trong packages/core/gui
- Update upstream (sync với continuedev/continue)
- Chuyển sang máy tính khác / OS khác
- Native modules bị corrupt
- Extension không hoạt động sau install

```powershell
# Clean toàn bộ node_modules
Get-ChildItem -Path . -Directory -Recurse -Filter node_modules | Remove-Item -Recurse -Force

# Build lại
.\scripts\build-all.ps1
```
