# Troubleshooting — Build Continue Extension

> Tham khảo: [`01-build-guide.md`](./01-build-guide.md)

---

## 0. Checklist đầu tiên

Trước khi troubleshoot, kiểm tra nhanh:

```bash
# 1. Đúng branch chưa?
git branch
# Expected: develop hoặc release/v2.1.x-onprem

# 2. Đúng Node.js version chưa?
conda run -n node20 node --version
# Expected: v20.17.0

# 3. conda env node20 đã có chưa?
conda env list | grep node20
# Nếu chưa: conda create -n node20 -y nodejs=20

# 4. Working directory đúng chưa?
pwd
# Expected: /mnt/e/08-Sources/1.AI/continue
```

---

## 1. Lỗi liên quan Node.js / conda

### 1.1. `conda: command not found`

**Nguyên nhân:** conda chưa được thêm vào PATH trong shell hiện tại.

**Fix:**
```bash
# Thêm conda vào PATH
source ~/miniconda3/etc/profile.d/conda.sh

# Hoặc init cho bash
conda init bash
source ~/.bashrc
```

### 1.2. conda env `node20` chưa có

**Triệu chứng:** `conda run -n node20 node --version` báo lỗi.

**Fix:**
```bash
conda create -n node20 -y nodejs=20
conda run -n node20 node --version   # verify
```

### 1.3. Node.js version sai — dùng system Node thay vì conda

**Triệu chứng:** Build chạy được nhưng native modules lỗi khi runtime, hoặc
`EBADENGINE` warnings với wrong version.

**Kiểm tra:**
```bash
# System Node (KHÔNG dùng để build)
node --version       # có thể là v18, v22, hay bất kỳ

# Conda Node (PHẢI dùng)
conda run -n node20 node --version   # phải là v20.x
```

**Fix:** Luôn prefix commands với `conda run -n node20`:
```bash
# ĐÚNG
conda run -n node20 npm install
conda run -n node20 npm run build

# SAI — dùng system Node
npm install
npm run build
```

### 1.4. `EBADENGINE` warnings khi build

```
npm warn EBADENGINE Unsupported engine { required: { node: '>=20.20.1' }, current: { node: 'v20.17.0' } }
```

**Đánh giá:** Warning này **không gây lỗi build** — conda `node20` cài v20.17.0, project
yêu cầu >=20.20.1. Bỏ qua warning này là được, build vẫn thành công.

---

## 2. Lỗi npm install

### 2.1. `EINTEGRITY` — cache corrupt

```
npm ERR! code EINTEGRITY
npm ERR! Verification failed while extracting ...
```

**Fix:**
```bash
conda run -n node20 npm cache clean --force
conda run -n node20 npm install
```

### 2.2. `ERESOLVE` — peer dependency conflict

```
npm ERR! Could not resolve dependency: peerOptional @types/node@"^18||^20||>=22"
```

**Fix:**
```bash
conda run -n node20 npm install --legacy-peer-deps
```

### 2.3. Network timeout / fetch failed (qua Nexus)

```
npm ERR! network timeout at: http://localhost:7081/repository/npm-group/...
```

**Fix:**
```bash
# Kiểm tra Nexus accessible
curl -s http://localhost:7081/service/rest/v1/status | python3 -c "import sys,json; print(json.load(sys.stdin))"

# Tăng timeout
conda run -n node20 npm config set fetch-timeout 120000
conda run -n node20 npm config set fetch-retries 5

# .npmrc phải trỏ đúng Nexus
cat ~/.npmrc
# registry=http://localhost:7081/repository/npm-group/
```

### 2.4. `Cannot find module` sau npm install

```
Error: Cannot find module '@continuedev/config-types'
```

**Nguyên nhân:** Build sai thứ tự — package dependency chưa build.

**Fix:** Build đúng thứ tự dependency chain (xem `01-build-guide.md` section 3):
```bash
# Build packages trước, theo thứ tự
conda run -n node20 bash -c "cd packages/config-types && npm run build"
conda run -n node20 bash -c "cd packages/fetch && npm run build"
# ... tiếp theo
```

---

## 3. Lỗi build (compile)

### 3.1. TypeScript error

```
src/file.ts:XX:YY - error TS2322: Type 'X' is not assignable to type 'Y'
```

**Đánh giá trước:** Kiểm tra có phải do conflict với upstream change không:
```bash
git diff upstream/main -- <file>
```

**Fix:**
- Nếu do patch conflict: resolve thủ công, giữ custom logic
- Nếu do type mismatch: thêm type assertion hoặc `// @ts-ignore`
- Nếu không rõ nguyên nhân: `"skipLibCheck": true` trong tsconfig.json (tạm thời)

### 3.2. `prepackage` thất bại — GUI chưa build

```
Error: gui build did not produce index.js
```

**Fix:**
```bash
conda run -n node20 bash -c "cd gui && npm install && npm run build"
```

### 3.3. `vsce package` thất bại — thiếu icon

```
Error: Missing extension icon
```

**Fix:**
```bash
ls extensions/vscode/media/icon.png
# Nếu thiếu, tạm thời comment dòng "icon" trong extensions/vscode/package.json
```

---

## 4. Lỗi runtime sau install

### 4.1. Extension không load / UI stuck loading mãi

**Nguyên nhân phổ biến:** Native modules sai platform.

**Nguyên lý:** `onnxruntime-node`, `@lancedb/vectordb` được copy từ `node_modules` của
host lúc build → nếu build trên Linux nhưng install trên Windows → crash silently.

**Kiểm tra:**
```bash
# Xem VSIX được build trên platform nào
ls extensions/vscode/build/
# continue-linux-x64-2.1.1.vsix → chỉ chạy trên Linux
# continue-win32-x64-2.1.1.vsix → chỉ chạy trên Windows
```

**Fix:** Build lại đúng trên target platform:
```bash
# Trên WSL → dùng cho Linux
conda run -n node20 bash -c "cd extensions/vscode && npm run prepackage -- --target linux-x64 && npm run package -- --target linux-x64"

# Trên Windows → dùng cho Windows  
# (phải chạy PowerShell trên Windows host, không phải WSL)
npm run prepackage -- --target win32-x64
npm run package -- --target win32-x64
```

### 4.2. Extension load nhưng không kết nối model

**Kiểm tra theo thứ tự:**
```bash
# 1. Model server running?
curl http://your-nim-server/v1/models

# 2. TLS cert issue?
curl -k https://your-nim-server/v1/models   # -k = skip verify

# 3. Config file đúng chưa?
# Ctrl+Shift+P → Continue: Open config file
# Kiểm tra apiBase, apiKey

# 4. Patch TLS còn không?
grep "rejectUnauthorized\|verifySsl" packages/fetch/src/getAgentOptions.ts
```

### 4.3. Response blank / empty (NIM/vLLM)

**Nguyên nhân:** Patch #1 (NIM empty response retry) bị mất sau sync upstream.

**Kiểm tra:**
```bash
grep -c "retry\|without.*tools" packages/openai-adapters/src/apis/OpenAI.ts
# Expected: >= 1, nếu 0 → patch bị mất
```

**Fix:** Xem `.patches/01-nim-empty-response-retry.md` để re-apply patch.

---

## 5. Lỗi môi trường

### 5.1. PowerShell execution policy (Windows)

```
.\scripts\build-all.ps1 cannot be loaded because running scripts is disabled
```

**Fix:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Hoặc chạy với bypass:
powershell -ExecutionPolicy Bypass -File .\scripts\build-all.ps1
```

### 5.2. Path quá dài — MAX_PATH (Windows)

**Triệu chứng:** Lỗi khi tạo file/folder do path > 260 ký tự trong `node_modules`.

**Fix:**
```powershell
# Enable long path support (Admin)
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
  -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
```

Hoặc clone repo vào path ngắn hơn: `C:\dev\continue`.

### 5.3. File permission issues (WSL ↔ Windows)

**Triệu chứng:** `git status` hiển thị hàng trăm files "modified" dù không sửa gì.

**Fix:**
```bash
git config core.fileMode false
```

### 5.4. Build chậm bất thường trên `/mnt/e/` (WSL)

**Nguyên nhân:** Cross-filesystem I/O (WSL ↔ Windows NTFS) chậm hơn Linux native ~5-10x.

**Fix:** Copy repo sang Linux filesystem để build nhanh hơn:
```bash
cp -r /mnt/e/08-Sources/1.AI/continue ~/continue-src
cd ~/continue-src
conda run -n node20 bash -c '...'
# Copy VSIX về sau khi build
cp extensions/vscode/build/*.vsix /mnt/e/08-Sources/1.AI/continue/extensions/vscode/build/
```

---

## 6. Patch bị mất sau git operations

### 6.1. Kiểm tra tất cả patches

```bash
cd /mnt/e/08-Sources/1.AI/continue

echo "=== Patch verification ==="

echo "1. NIM empty response retry:"
grep -c "retry\|without.*tools" packages/openai-adapters/src/apis/OpenAI.ts
# Expected: >= 1

echo "2. JSON sanitize:"
grep -c "sanitize\|JSON.parse" core/llm/openaiTypeConverters.ts
# Expected: >= 1

echo "3. Vision proxy:"
test -f core/llm/visionProxy.ts && echo "OK" || echo "MISSING"

echo "4. TLS fix:"
grep -c "rejectUnauthorized\|verifySsl" packages/fetch/src/getAgentOptions.ts
# Expected: >= 1

echo "5. Context usage:"
grep -c "contextUsage\|ContextStatus" gui/src/components/mainInput/ContextStatus.tsx
# Expected: >= 1
```

### 6.2. Nếu patch bị mất sau rebase

```bash
# Xem commit nào chứa patch
git log --oneline develop | head -20

# Cherry-pick lại nếu cần
git cherry-pick <patch-commit-hash>

# Hoặc xem diff để re-apply thủ công
git show <patch-commit-hash> -- packages/openai-adapters/src/apis/OpenAI.ts
```

---

## 7. Quick diagnostics

```bash
# Full environment check
echo "=== Node.js (conda) ===" && conda run -n node20 node --version
echo "=== npm (conda) ===" && conda run -n node20 npm --version
echo "=== Git ===" && git --version
echo "=== Branch ===" && git branch --show-current
echo "=== Last commit ===" && git log --oneline -1
echo "=== VSIX files ===" && ls -lh extensions/vscode/build/*.vsix 2>/dev/null || echo "No VSIX built yet"
echo "=== Extension installed ===" && code --list-extensions 2>/dev/null | grep -i continue || echo "Not installed"
```
