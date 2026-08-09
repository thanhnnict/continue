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

| Tình huống | Cần pre-install? |
|---|---|
| Lần đầu build trên máy Linux/WSL | ✅ Luôn cần |
| `node_modules` vừa install trên Windows | ✅ Cần fix platform binaries |
| Đã build thành công trước đó, chỉ thay đổi code | ❌ Không cần, dùng `--only-ext` |
| Sau `git pull` có thay đổi package.json | ✅ Nên chạy lại |
| Sau `npm install` thủ công trong WSL | ❌ Không cần (đã đúng platform) |
