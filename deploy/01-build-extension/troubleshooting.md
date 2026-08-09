# Troubleshooting — Build Extension

## Checklist đầu tiên

```bash
conda run -n node20 node --version  # v20.x
git branch --show-current           # develop hoặc release/v2.1.x-onprem
ls extensions/vscode/build/*.vsix   # output có không
```

---

## Lỗi thường gặp

### `conda: command not found`
```bash
source ~/miniconda3/etc/profile.d/conda.sh && conda init bash && source ~/.bashrc
```

### `EBADENGINE` warnings
Node v20.17.0 build vẫn thành công dù require >=20.20.1. Bỏ qua warning này.

### `Cannot find module '@continuedev/config-types'`
Build sai thứ tự. Chạy lại từ đầu không có `--skip-packages`.

### `gui build did not produce index.js`
```bash
conda run -n node20 bash -c "cd gui && npm install && npm run build"
```

### VSIX không chạy được trên Windows (UI stuck)
Native modules sai platform — xem note cross-compile trong README.md.
Build lại đúng trên Windows host.

### Patch bị mất sau rebase
```bash
grep -c "retry\|without.*tools" packages/openai-adapters/src/apis/OpenAI.ts
# Nếu = 0: xem .patches/01-nim-empty-response-retry.md để re-apply
```

### `npm install` timeout qua Nexus
```bash
conda run -n node20 npm config set fetch-timeout 120000
# Kiểm tra Nexus: curl -s http://localhost:7081/service/rest/v1/status
```
