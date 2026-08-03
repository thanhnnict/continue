# Custom Patches — Continue Extension (On-Prem / Self-Managed)

## Overview

This directory documents all custom patches applied to the Continue extension source code for compatibility with on-premises LLM servers (NIM, vLLM) serving models like Nemotron Ultra 253B, DeepSeek V4 Flash, Kimi K2.6, GLM-5.2-FP8.

These patches are required for production deployment serving ~300+ developer users via Vibe coding service.

---

## Patches Applied

| #   | File                                            | Issue          | Description                                                               |
| --- | ----------------------------------------------- | -------------- | ------------------------------------------------------------------------- |
| 1   | `packages/openai-adapters/src/apis/OpenAI.ts`   | Empty response | Retry without tools when server returns `content:null` + `tool_calls:[]`  |
| 2   | `core/llm/openaiTypeConverters.ts`              | Malformed JSON | Sanitize tool_calls arguments before sending back in conversation history |
| 3   | —                                               | Upstream sync  | Strategy document (no code change)                                        |
| 4   | `core/llm/visionProxy.ts` + `core/llm/index.ts` | Image support  | Vision proxy — route images through VLM for text-only LLMs                |

---

## Quick Reference

### Rebuild after modifying patches

```bash
cd ~/.continue/continue-src

# Build affected packages
conda run -n node20 bash -c '
  cd packages/openai-adapters && npm run build && cd ../.. &&
  cd core && npm run build && cd .. &&
  cd gui && npm run build && cd .. &&
  cd extensions/vscode && npm run prepackage -- --target darwin-arm64 && npm run package -- --target darwin-arm64
'

# Install
code --install-extension extensions/vscode/build/continue-darwin-arm64-2.0.0.vsix --force
```

### Verify patches still present after git operations

```bash
# Check patch 1
grep -c "Retry without tools" packages/openai-adapters/src/apis/OpenAI.ts
# Expected: 1

# Check patch 2
grep -c "Sanitize arguments" core/llm/openaiTypeConverters.ts
# Expected: 1

# Check patch 4
grep -c "Vision Proxy" core/llm/index.ts
# Expected: 1
test -f core/llm/visionProxy.ts && echo "visionProxy.ts exists"
```

---

## Detailed Documentation

- `01-nim-empty-response-retry.md` — Full details on patch #1
- `02-tool-arguments-json-sanitize.md` — Full details on patch #2
- `03-upstream-sync-strategy.md` — How to keep in sync with upstream
- `04-vision-proxy.md` — Full details on patch #4
