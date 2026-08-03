# Build Continue Extension — TLS Self-Signed Cert Fix (v2 - Bền vững)

## Giải pháp: `insecureSkipVerify` + Logic ưu tiên

Thay vì global `NODE_TLS_REJECT_UNAUTHORIZED=0` (quick-win) hay default `false` (v1),
fix này implement **logic ưu tiên thông minh**:

### Priority cho TLS verification

```
1. insecureSkipVerify: true  → rejectUnauthorized = false (explicitly insecure)
2. verifySsl: true/false     → user explicitly sets verification
3. NODE_TLS_REJECT_UNAUTHORIZED env var → fallback
4. Default: true (secure)    — chỉ false nếu user explicitly opt-in
```

### Files đã sửa

| File | Change |
|------|--------|
| `packages/config-types/src/index.ts` | Thêm `insecureSkipVerify?: boolean` vào `requestOptionsSchema` + `modelDescriptionSchema.requestOptions` |
| `packages/config-yaml/src/schemas/models.ts` | Thêm `insecureSkipVerify?: boolean` vào `requestOptionsSchema` |
| `packages/openai-adapters/src/types.ts` | Thêm `insecureSkipVerify?: boolean` vào `RequestOptionsSchema` |
| `core/index.d.ts` | Thêm `insecureSkipVerify?: boolean` vào `RequestOptions` interface |
| `packages/fetch/src/getAgentOptions.ts` | Logic ưu tiên mới (insecureSkipVerify > verifySsl > env var > default true) |
| `packages/fetch/dist/getAgentOptions.js` | Đồng bộ dist |
| `packages/openai-adapters/node_modules/@continuedev/fetch/src/getAgentOptions.ts` | Đồng bộ node_modules source |
| `packages/openai-adapters/node_modules/@continuedev/fetch/dist/getAgentOptions.js` | Đồng bộ node_modules dist |
| `core/context/mcp/MCPConnection.ts` | Thêm `shouldRejectUnauthorized()` helper cho SSE/HTTP transports |
| `core/dist/context/mcp/MCPConnection.js` | Đồng bộ dist |
| `extensions/cli/src/services/mcpTransports.ts` | Thêm `shouldRejectUnauthorized()` helper |

### Config (config.yaml)

```yaml
# Cách 1: Dùng verifySsl (recommended)
requestOptions:
  verifySsl: false  # Accept self-signed certs

# Cách 2: Dùng insecureSkipVerify (explicit)
requestOptions:
  insecureSkipVerify: true  # Skip TLS verification

# Cách 3: Kết hợp với CA bundle
requestOptions:
  verifySsl: false
  caBundlePath: /path/to/cert.crt
```

### Build Commands

```bash
cd ~/.continue/continue-src

# 1. Build packages (đúng thứ tự)
conda run -n node20 bash -c 'cd packages/config-types && npm run build'
conda run -n node20 bash -c 'cd packages/fetch && npm run build'
conda run -n node20 bash -c 'cd packages/openai-adapters && npm run build'

# 2. Build extension
cd extensions/vscode
conda run -n node20 npm run esbuild

# 3. Verify cả 2 instances đã patch
grep -c "insecureSkipVerify" out/extension.js
# Expected: 2 (hoặc 3 nếu có MCP)

# 4. Package & Install
conda run -n node20 npm run prepackage -- --target darwin-arm64
conda run -n node20 npm run package -- --target darwin-arm64
code --install-extension build/continue-darwin-arm64-*.vsix --force

# 5. Reload VS Code
```

### Lưu ý khi update source

Nếu `npm install` hoặc update source, các file trong:
- `packages/openai-adapters/node_modules/@continuedev/fetch/dist/`
- `packages/openai-adapters/node_modules/@continuedev/fetch/src/`

sẽ bị ghi đè. Cần re-patch bằng cách chạy lại build commands ở trên.

### Verification

```bash
# Kiểm tra trong bundle
grep -n "insecureSkipVerify\|shouldRejectUnauthorized" extensions/vscode/out/extension.js

# Test connection với model có verifySsl: false
# Mở Continue → chọn Gateway model → "Hello" → should respond
```
