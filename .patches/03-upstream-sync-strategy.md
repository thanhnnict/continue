# Upstream Sync Strategy — Keeping Custom Continue Updated

## Overview

Strategy để maintain custom Continue extension fork khi upstream `continuedev/continue` release updates, phục vụ ~300+ developer users.

---

## 1. Git Workflow

### Repository Setup

```bash
cd ~/.continue/continue-src

# Current state
git remote -v
# origin → (your fork or local)

# Add upstream remote
git remote add upstream https://github.com/continuedev/continue.git

# Verify
git remote -v
# origin   → your-org/continue (push/fetch)
# upstream → continuedev/continue (fetch only)
```

### Branch Strategy

```
main (or release-v2.x.x)     ← production branch, deployed to users
├── patches/nim-empty-retry   ← patch #1 as isolated branch
├── patches/json-sanitize     ← patch #2 as isolated branch
└── upstream/main             ← tracking upstream
```

---

## 2. Sync Process (khi upstream release mới)

### Step 1: Fetch upstream changes

```bash
git fetch upstream
git log --oneline upstream/main -10  # Review what's new
```

### Step 2: Check if our patches conflict

```bash
# Create temp branch from upstream
git checkout -b temp-merge upstream/main

# Try applying our patches
git cherry-pick <patch-1-commit-hash>
git cherry-pick <patch-2-commit-hash>

# If conflicts → resolve manually
# If clean → good to go
```

### Step 3: Merge or Rebase

**Option A: Rebase (cleaner history)**
```bash
git checkout main
git rebase upstream/main
# Resolve conflicts in patch files if any
```

**Option B: Merge (safer, preserves history)**
```bash
git checkout main
git merge upstream/main
# Resolve conflicts
```

### Step 4: Verify patches still work

```bash
# Check patch 1
grep -c "Retry without tools" packages/openai-adapters/src/apis/OpenAI.ts
# Expected: 1

# Check patch 2
grep -c "Sanitize arguments" core/llm/openaiTypeConverters.ts
# Expected: 1

# Build test
conda run -n node20 bash -c 'cd packages/openai-adapters && npm run build'
conda run -n node20 bash -c 'cd core && npm run build'
```

### Step 5: Rebuild & Deploy

```bash
cd extensions/vscode
conda run -n node20 npm run prepackage -- --target darwin-arm64
conda run -n node20 npm run package -- --target darwin-arm64
# Install & test
```

---

## 3. When Patches Become Unnecessary

### Patch 01 (Empty Response Retry)

**Remove when ANY of:**
- Continue adds built-in handling for `content:null` + `tool_calls:[]`
- NIM/vLLM servers fix their behavior (return content when no tool needed)
- PR #12591 or equivalent is merged upstream

**How to check:**
```bash
# If upstream has similar logic
grep -r "tool_calls.*length.*0\|retry.*without.*tools" packages/openai-adapters/src/
```

### Patch 02 (JSON Sanitize)

**Remove when ANY of:**
- vLLM stops validating tool_calls arguments in history messages (vllm#43995 fixed)
- Continue adds argument validation upstream
- All models reliably generate valid JSON (unlikely near-term)

**How to check:**
```bash
# If upstream validates arguments
grep -r "JSON.parse.*arguments\|sanitize.*args" core/llm/
```

---

## 4. Automated Sync Check (CI/CD suggestion)

### Weekly check script

```bash
#!/bin/bash
# .patches/scripts/check-upstream.sh

cd ~/.continue/continue-src
git fetch upstream 2>/dev/null

LOCAL=$(git rev-parse HEAD)
UPSTREAM=$(git rev-parse upstream/main)

if [ "$LOCAL" != "$UPSTREAM" ]; then
  BEHIND=$(git rev-list HEAD..upstream/main --count)
  echo "⚠️  Behind upstream by $BEHIND commits"
  echo "Latest upstream: $(git log upstream/main -1 --oneline)"
  echo ""
  echo "Run: git merge upstream/main"
else
  echo "✅ Up to date with upstream"
fi
```

### Conflict detection

```bash
#!/bin/bash
# .patches/scripts/test-merge.sh

cd ~/.continue/continue-src
git fetch upstream

# Test merge without committing
git merge --no-commit --no-ff upstream/main 2>&1 | head -20

# Check for conflicts in our patched files
CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)
if echo "$CONFLICTS" | grep -q "OpenAI.ts\|openaiTypeConverters.ts"; then
  echo "⚠️  CONFLICT in patched files — manual resolution needed"
  echo "$CONFLICTS"
else
  echo "✅ No conflicts in patched files"
fi

# Abort test merge
git merge --abort
```

---

## 5. Multi-Platform Build

### Thực tế đã gặp: Docker build (Linux) → macOS = FAIL

Trước đó đã thử build VSIX trong Docker container (Linux x86_64) trên server ViettelCloud rồi copy về macOS → **extension không chạy được** (UI stuck loading).

**Nguyên nhân đã xác định:**

Native modules trong Continue được **compile hoặc copy từ host OS** tại build time:

| Module | Cách lấy binary | Platform-bound |
|--------|-----------------|:-:|
| `onnxruntime-node` | Copy từ `core/node_modules/onnxruntime-node/bin/` | ✅ Binary build lúc `npm install` trên host |
| `better-sqlite3` | Download prebuild theo target flag | ⚠️ Download đúng nếu `--target` đúng |
| `@lancedb/vectordb` | npm optional dep theo platform | ✅ Install lúc `npm install` trên host |
| `@vscode/ripgrep` | npm postinstall download theo platform | ✅ Download lúc `npm install` trên host |

**Vấn đề cốt lõi**: `onnxruntime-node` và `@lancedb/vectordb` được **copy trực tiếp** từ `node_modules` (đã install trên host) vào output package. Nếu host là Linux → binary là Linux ELF → macOS không load được → extension crash silently (UI stuck).

Script `prepackage.js` flow:
```
1. npm install (trên host) → install native modules cho HOST platform
2. Copy onnxruntime binary từ core/node_modules/ → out/bin/     ← PLATFORM BOUND
3. Download sqlite3 prebuild theo --target flag                  ← CÓ THỂ CROSS
4. Copy lancedb từ node_modules/@lancedb/vectordb-{platform}/   ← PLATFORM BOUND
5. Copy ripgrep binary                                           ← PLATFORM BOUND
6. esbuild bundle JS code                                        ← PLATFORM INDEPENDENT
```

Steps 2, 4, 5 copy binary **từ host `node_modules`** — nên phải build **trên đúng target OS**.

### Kết luận: Cross-platform build KHÔNG đáng tin cậy

| Build host | Target | Result |
|-----------|--------|--------|
| macOS arm64 | `darwin-arm64` | ✅ Works |
| macOS arm64 | `win32-x64` | ⚠️ sqlite3 OK (downloaded), nhưng onnxruntime/lancedb = macOS binary → **FAIL** |
| Linux x64 (Docker) | `darwin-arm64` | ❌ FAIL — native modules are Linux |
| Windows x64 | `win32-x64` | ✅ Works |

### Recommended: Build trên mỗi platform hoặc CI matrix

**Option A: CI/CD Matrix (recommended cho 300+ users)**

```yaml
# GitHub Actions example
jobs:
  build:
    strategy:
      matrix:
        include:
          - os: macos-14        # Apple Silicon runner
            target: darwin-arm64
          - os: macos-13        # Intel runner
            target: darwin-x64
          - os: windows-latest
            target: win32-x64
          - os: ubuntu-latest
            target: linux-x64
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm install --ignore-scripts
      - run: |
          cd packages/config-types && npm install && npm run build && cd ../..
          cd packages/llm-info && npm install && npm run build && cd ../..
          cd packages/fetch && npm install && npm run build && cd ../..
          cd packages/openai-adapters && npm install && npm run build && cd ../..
          cd packages/config-yaml && npm install && npm run build && cd ../..
          cd packages/terminal-security && npm install && npm run build && cd ../..
      - run: cd core && npm install && cd ..
      - run: cd gui && npm install && npm run build && cd ..
      - run: |
          cd extensions/vscode
          npm install
          npm run prepackage -- --target ${{ matrix.target }}
          npm run package -- --target ${{ matrix.target }}
      - uses: actions/upload-artifact@v4
        with:
          name: vsix-${{ matrix.target }}
          path: extensions/vscode/build/*.vsix
```

**Option B: Máy vật lý/VM per platform**

- macOS (MacBook hiện tại) → build `darwin-arm64`
- Windows VM/machine → build `win32-x64`
- Linux server → build `linux-x64`

**Option C: Hybrid — JS từ anywhere, native modules per-platform**

1. Build JS bundle + GUI trên bất kỳ máy nào
2. Trên mỗi target platform: `npm install` → lấy correct native modules
3. Copy native modules vào package
4. `vsce package`

Phức tạp hơn nhưng giảm build time nếu JS changes nhiều hơn native changes.

---

## 6. Versioning

### Custom version scheme

```
v2.0.0-custom.1  → first custom build based on upstream v2.0.0
v2.0.0-custom.2  → second custom build (added patches)
v2.1.0-custom.1  → rebased on upstream v2.1.0
```

Trong `extensions/vscode/package.json`:
```json
{
  "version": "2.0.0",
  "customVersion": "2.0.0-custom.2",
  "patchLevel": 2
}
```

---

## 7. Decision Matrix: When to Sync

| Upstream Change | Action | Priority |
|---|---|---|
| Security fix | Sync immediately | 🔴 High |
| Bug fix in core LLM logic | Sync soon, test patches | 🟡 Medium |
| New feature (model support) | Sync when needed | 🟢 Low |
| UI/UX changes | Sync at convenience | 🟢 Low |
| Breaking refactor in patched files | Plan migration, test thoroughly | 🔴 High |

---

## 8. Contribution Back to Upstream

Cả 2 patches đều có thể benefit community. Để submit PR:

### PR #1: Empty Response Retry

- Title: `fix(openai-adapters): retry without tools when server returns empty response`
- Target: `continuedev/continue` main branch
- Description: NIM/vLLM compatibility fix
- Tests: Add unit test in `packages/openai-adapters/src/test/`

### PR #2: JSON Sanitize

- Title: `fix(core): sanitize malformed tool arguments in conversation history`
- Target: `continuedev/continue` main branch  
- Description: Prevents 400 errors when LLM generates invalid JSON arguments
- Reference: vLLM issue #43995

### Process

```bash
# 1. Fork continuedev/continue on GitHub
# 2. Create branch per fix
git checkout -b fix/empty-response-retry
# 3. Cherry-pick patch commit
# 4. Push and create PR via GitHub UI or gh CLI
gh pr create --title "fix(openai-adapters): retry without tools on empty response" \
  --body "..." --base main
```

