# Troubleshooting — Build Extension

## Checklist đầu tiên

```bash
# Chạy check nhanh
bash deploy/01-build-extension/00-pre-install.sh --target linux-x64 --check-only

# Verify khác
conda run -n node20 node --version  # v20.x
git branch --show-current           # develop hoặc release/v2.1.x-onprem
```

---

## Lỗi quan trọng nhất — Platform binary mismatch

### Triệu chứng

```
Error: The following files were missing:
- node_modules/@vscode/ripgrep/bin/rg
- out/node_modules/@vscode/ripgrep/bin/rg
```

hoặc:

```
Could not find @vscode/ripgrep-linux-x64. Ensure optionalDependencies are installed
```

### Nguyên nhân

`node_modules` trong repo thường được install trên **Windows** → chỉ có `rg.exe`.
Build trên Linux/WSL cần `rg` (Linux ELF binary).

Tương tự với `@lancedb/vectordb`: cần `vectordb-linux-x64-gnu` thay vì `vectordb-win32-x64-msvc`.

### Fix

```bash
# Fix tự động tất cả platform dependencies
bash deploy/01-build-extension/00-pre-install.sh --target linux-x64
```

Script sẽ:

1. Install `@vscode/ripgrep-linux-x64` → tạo symlink vào `@vscode/ripgrep/bin/rg`
2. Install `@lancedb/vectordb-linux-x64-gnu`
3. Verify tất cả required files

---

## Các lỗi khác

### `prepackage.js` hangs trên macOS (hoặc bất kỳ platform)

**Triệu chứng:** `npm run prepackage` hoặc `npm run package` treo vô thời hạn.
Process ở trạng thái Sleep (S), CPU 0%.

**Nguyên nhân:** `npmInstall()` trong prepackage.js fork 2 child processes chạy
`npm install` trong gui/ và extensions/vscode/. Khi node_modules đã có đầy đủ,
npm vẫn chạy lifecycle scripts và lock files → deadlock.

Ngoài ra, `npm run package` tự động trigger `prepackage` (npm lifecycle convention
`pre<script>`) → chạy lại prepackage lần nữa.

**Fix:**

```bash
# Dùng SKIP_INSTALLS=true + gọi script trực tiếp
cd extensions/vscode
SKIP_INSTALLS=true node scripts/prepackage.js --target darwin-arm64
npx @vscode/vsce package --out ./build --no-dependencies --target darwin-arm64
```

Hoặc dùng `build-macos.sh` đã được fix sẵn:

```bash
bash deploy/01-build-extension/build-macos.sh --target darwin-arm64
```

### `conda: command not found`

```bash
source ~/miniconda3/etc/profile.d/conda.sh && conda init bash && source ~/.bashrc
```

### `EBADENGINE` warnings

Node v20.17.0 build vẫn thành công dù require >=20.20.1. Bỏ qua.

### `Cannot find module '@continuedev/config-types'`

Build sai thứ tự. Chạy lại không có `--skip-packages`.

### `gui build did not produce index.js`

```bash
conda run -n node20 bash -c "cd gui && npm install && npm run build"
```

### `npm install` timeout qua Nexus

```bash
conda run -n node20 npm config set fetch-timeout 120000
curl -s http://localhost:7081/service/rest/v1/status  # kiểm tra Nexus up
```

### Patch bị mất sau rebase

```bash
grep -c "retry\|without.*tools" packages/openai-adapters/src/apis/OpenAI.ts
# Nếu = 0: xem .patches/01-nim-empty-response-retry.md
```

---

## Khi nào cần chạy 00-pre-install.sh

| Tình huống                                      | Cần pre-install?                  |
| ----------------------------------------------- | --------------------------------- |
| Lần đầu build trên máy Linux/WSL                | ✅ Luôn cần                       |
| `node_modules` vừa install trên Windows         | ✅ Cần fix platform binaries      |
| Đã build thành công trước đó, chỉ thay đổi code | ❌ Không cần, dùng `--only-ext`   |
| Sau `git pull` có thay đổi package.json         | ✅ Nên chạy lại                   |
| Sau `npm install` thủ công trong WSL            | ❌ Không cần (đã đúng platform)   |
| Build trên macOS local (đã có node_modules)     | ❌ Không cần (native npm install) |

---

## Summary: Build flow chuẩn (tất cả platforms)

### Nguyên tắc chung

Tất cả scripts build đã được fix để:

1. **Không dùng `npm run prepackage`** — tránh `npmInstall()` fork child processes bị hang
2. **Không dùng `npm run package`** — tránh npm lifecycle auto-trigger prepackage
3. **Dùng `SKIP_INSTALLS=true` + `node scripts/prepackage.js`** — chỉ copy files
4. **Dùng `npx @vscode/vsce package`** — trigger `vscode:prepublish` (esbuild) đúng cách

### Prerequisite: node_modules phải có sẵn

Trước khi chạy build scripts, đảm bảo:

```bash
# macOS / Windows: npm install thông thường
cd extensions/vscode && npm install
cd gui && npm install
cd core && npm install

# Linux/WSL: dùng 00-pre-install.sh (fix platform binaries)
bash deploy/01-build-extension/00-pre-install.sh --target linux-x64
```

### Thời gian build tham chiếu

| Platform      | Full build | --skip-packages | --only-ext |
| ------------- | :--------: | :-------------: | :--------: |
| macOS arm64   |    ~50s    |      ~42s       |  ~12-14s   |
| Linux/WSL x64 |  ~60-90s   |      ~50s       |  ~15-20s   |
| Windows x64   |  ~60-90s   |      ~50s       |  ~15-20s   |
