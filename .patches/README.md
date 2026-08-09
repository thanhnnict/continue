# Custom Patches — Continue Extension (On-Prem / Self-Managed)

> **Cập nhật lần cuối:** 2026-08-09
> **Base upstream:** `continuedev/continue` @ `upstream/main` (5522c6f)
> **Custom version:** `2.1.1` (trên branch `develop`)

---

## Overview

Fork cá nhân của [`continuedev/continue`](https://github.com/continuedev/continue),
được customize cho môi trường **on-premises** với các LLM server nội bộ (NIM, vLLM)
phục vụ ~300+ developer users qua dịch vụ Vibe coding.

**Models đang phục vụ:** Nemotron Ultra 253B, DeepSeek V4 Flash, Kimi K2.6, GLM-5.2-FP8

**Fork:** [`thanhnnict/continue`](https://github.com/thanhnnict/continue)

---

## Branch Structure

```
upstream/main  (continuedev/continue — read-only)
      │
      ▼
  develop  ←── làm việc hàng ngày, phát triển features
      │         upstream/main + 16 custom commits
      │         version: 2.1.1
      ▼
release/v2.1.x-onprem  ←── stable snapshot, build VSIX deploy
      │                     merge từ develop khi stable
      ▼
   [VSIX build → deploy ~300 developers]
```

### Tất cả branches trên origin (`thanhnnict/continue`)

| Branch | Base | Mục đích | Trạng thái |
|--------|------|---------|------------|
| `main` | `release/v2.0.0-vscode` (upstream cũ) | Archive custom build v2.0.x | 🗄️ Archive — không phát triển thêm |
| `develop` | `upstream/main` (5522c6f) | Working branch chính — tích hợp tất cả custom patches + features khách hàng | ✅ Active |
| `release/v2.1.x-onprem` | `develop` HEAD | Stable snapshot để build VSIX deploy on-prem | ✅ Active |
| `fix/empty-response-retry` | `upstream/main` | PR #13091 — fix NIM/vLLM empty response | 🔄 OPEN PR |
| `fix/sanitize-tool-arguments` | `upstream/main` | PR #13092 — fix malformed JSON tool args | 🔄 OPEN PR |
| `feat/always-on-context-usage` | `upstream/main` | PR #13093 — context usage display | 🔄 OPEN PR |

> **Lưu ý:** Branch `main` có warning `refname 'main' is ambiguous` do trùng với tag upstream.
> Dùng `git push origin refs/heads/main:refs/heads/main` khi cần thao tác với nó.

---

## Custom Patches

### Code changes (so với upstream/main)

| # | Patch doc | File thay đổi | Vấn đề | Mô tả |
|---|-----------|--------------|--------|-------|
| 1 | `01-nim-empty-response-retry.md` | `packages/openai-adapters/src/apis/OpenAI.ts` | Empty response | Retry without tools khi server trả `content:null` + `tool_calls:[]` — NIM/vLLM compatibility |
| 2 | `02-tool-arguments-json-sanitize.md` | `core/llm/openaiTypeConverters.ts` | Malformed JSON | Sanitize tool_calls arguments trước khi gửi lại trong conversation history — tránh vLLM 400 |
| 3 | `04-vision-proxy.md` | `core/llm/visionProxy.ts`, `core/llm/index.ts`, `core/index.d.ts` | Image support | Vision proxy — route images qua VLM cho text-only LLMs |
| 4 | — | `extensions/vscode/src/extension.ts`, `packages/fetch/src/getAgentOptions.ts` | TLS self-signed | Cho phép self-signed certs trong môi trường on-prem (internal CA) |
| 5 | — | `gui/src/components/StepContainer/ResponseActions.tsx`, `gui/src/components/mainInput/ContextStatus.tsx` | UX | Always-on context usage display với sub-1% precision |
| 6 | — | `core/llm/toolSupport.ts` | Tool support | Cải thiện tool support compatibility |
| 7 | — | `packages/config-yaml/src/schemas/models.ts` | Config | Model schema adjustments |
| 8 | `08-tls-self-signed-fix.md` | `packages/fetch/src/getAgentOptions.ts`, `extensions/vscode/src/extension.ts` | TLS self-signed | Default `rejectUnauthorized: false` + `NODE_TLS_REJECT_UNAUTHORIZED=0` cho on-prem |

### Documentation only (no code change)

| File | Nội dung |
|------|---------|
| `03-upstream-sync-strategy.md` | Chiến lược sync với upstream, git-flow, versioning |
| `05-performance-monitoring.md` | Performance monitoring setup cho 300+ users |
| `06-capacity-planning-300-users.md` | Capacity planning — infrastructure sizing |
| `07-huong-dan-dong-gop-pr-cong-dong.md` | Hướng dẫn đóng góp PR lên upstream, tooling setup |

### Build & Deploy documentation (in `deploy/docs/`)

| File | Nội dung |
|------|---------|
| `deploy/docs/01-build-guide.md` | Hướng dẫn build VSIX cho Windows/WSL |
| `deploy/docs/02-build-troubleshooting.md` | Troubleshooting build issues |

---

## Open PRs lên upstream

| PR | Branch | File | CLA | CI | Status |
|----|--------|------|-----|----|--------|
| [#13091](https://github.com/continuedev/continue/pull/13091) | `fix/empty-response-retry` | `OpenAI.ts` | ✅ | ⚠️ flaky | OPEN |
| [#13092](https://github.com/continuedev/continue/pull/13092) | `fix/sanitize-tool-arguments` | `openaiTypeConverters.ts` | ✅ | ⚠️ flaky | OPEN |
| [#13093](https://github.com/continuedev/continue/pull/13093) | `feat/always-on-context-usage` | GUI components | ✅ | ✅ | OPEN |

> CI failures trên #13091 và #13092 là flaky tests upstream (`jetbrains-tests`, `llm-pre-fetch.vitest.ts`) — không liên quan đến code thay đổi. Đã comment maintainers.

---

## Quick Reference

### Build VSIX (WSL/Linux)

```bash
cd /mnt/e/08-Sources/1.AI/continue

# Checkout branch stable
git checkout release/v2.1.x-onprem

# Build
conda run -n node20 bash -c '
  cd packages/openai-adapters && npm run build && cd ../.. &&
  cd core && npm run build && cd .. &&
  cd gui && npm run build && cd .. &&
  cd extensions/vscode &&
    npm run prepackage -- --target linux-x64 &&
    npm run package -- --target linux-x64
'

# Output
ls extensions/vscode/build/continue-linux-x64-2.1.1.vsix

# Install
code --install-extension extensions/vscode/build/continue-linux-x64-2.1.1.vsix --force
```

### Verify patches còn nguyên sau git operations

```bash
# Patch 1 — NIM empty response retry
grep -c "retry\|without.*tools" packages/openai-adapters/src/apis/OpenAI.ts
# Expected: >= 1

# Patch 2 — JSON sanitize
grep -c "sanitize\|JSON\.parse.*arguments" core/llm/openaiTypeConverters.ts
# Expected: >= 1

# Patch 3 — Vision proxy
test -f core/llm/visionProxy.ts && echo "✅ visionProxy.ts exists" || echo "❌ MISSING"

# Patch 4 — TLS
grep -c "rejectUnauthorized\|NODE_TLS" packages/fetch/src/getAgentOptions.ts
# Expected: >= 1
```

### Sync upstream mới nhất

```bash
git fetch upstream refs/heads/main:refs/remotes/upstream/main
git log --oneline develop..upstream/main  # xem có gì mới

git checkout develop
git rebase upstream/main
# Resolve conflicts nếu có → git rebase --continue
git push origin develop --force-with-lease

# Merge vào release khi stable
git checkout release/v2.1.x-onprem
git merge develop
git push origin release/v2.1.x-onprem
```

### Tạo PR mới lên upstream

```bash
# Luôn tạo từ upstream/main — KHÔNG từ develop
git fetch upstream refs/heads/main:refs/remotes/upstream/main
git checkout -b fix/ten-van-de upstream/main

# ... code, commit ...

git push -u origin fix/ten-van-de
gh pr create --repo continuedev/continue --title "fix: ..." --base main
```

---

## Versioning

Scheme: `{upstream_major}.{upstream_minor}.{custom_patch}`

| Version | Trạng thái |
|---------|-----------|
| `2.0.5` | Branch `main` (archive) — base `release/v2.0.0-vscode` |
| `2.1.1` | Branch `develop` / `release/v2.1.x-onprem` — base `upstream/main` hiện tại |
| `2.1.2` | Custom build tiếp theo sau khi thêm feature |

Tăng PATCH +1 mỗi lần build có thay đổi code. Reset về `.1` khi sync upstream major/minor mới.

---

## Tài liệu chi tiết

**Patch documentation (`.patches/`):**
- [`01-nim-empty-response-retry.md`](./01-nim-empty-response-retry.md) — Patch #1: NIM/vLLM empty response
- [`02-tool-arguments-json-sanitize.md`](./02-tool-arguments-json-sanitize.md) — Patch #2: JSON sanitize
- [`03-upstream-sync-strategy.md`](./03-upstream-sync-strategy.md) — Git workflow, sync, versioning
- [`04-vision-proxy.md`](./04-vision-proxy.md) — Patch #3: Vision proxy
- [`05-performance-monitoring.md`](./05-performance-monitoring.md) — Performance monitoring
- [`06-capacity-planning-300-users.md`](./06-capacity-planning-300-users.md) — Capacity planning
- [`07-huong-dan-dong-gop-pr-cong-dong.md`](./07-huong-dan-dong-gop-pr-cong-dong.md) — PR contribution guide
- [`08-tls-self-signed-fix.md`](./08-tls-self-signed-fix.md) — Patch #4: TLS self-signed cert fix

**Build & Deploy documentation (`deploy/`):**
- [`deploy/README.md`](../deploy/README.md) — Air-gap deployment guide
- [`deploy/docs/01-build-guide.md`](../deploy/docs/01-build-guide.md) — Hướng dẫn build VSIX
- [`deploy/docs/02-build-troubleshooting.md`](../deploy/docs/02-build-troubleshooting.md) — Troubleshooting build
