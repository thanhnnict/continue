# Custom Patches — Continue Extension (On-Prem / Self-Managed)

> **Cập nhật lần cuối:** 2026-08-09
> **Base upstream:** `continuedev/continue` @ `upstream/main` (5522c6f)
> **Custom version:** `2.1.1` (trên branch `develop`)
> **Fork:** [`thanhnnict/continue`](https://github.com/thanhnnict/continue)

---

## Overview

Fork cá nhân của [`continuedev/continue`](https://github.com/continuedev/continue),
được customize cho môi trường **on-premises** với các LLM server nội bộ (NIM, vLLM)
phục vụ ~300+ developer users qua dịch vụ Vibe coding.

**Models đang phục vụ:** Nemotron Ultra 253B, DeepSeek V4 Flash, Kimi K2.6, GLM-5.2-FP8

---

## Branch Structure

| PR | Branch | File | CLA | CI | Status |
|----|--------|------|-----|----|--------|
| [#13091](https://github.com/continuedev/continue/pull/13091) | `fix/empty-response-retry` | `OpenAI.ts` | ✅ | ⚠️ flaky | OPEN |
| [#13092](https://github.com/continuedev/continue/pull/13092) | `fix/sanitize-tool-arguments` | `openaiTypeConverters.ts` | ✅ | ⚠️ flaky | OPEN |
| [#13093](https://github.com/continuedev/continue/pull/13093) | `feat/always-on-context-usage` | GUI components | ✅ | ✅ | OPEN |
| [#13131](https://github.com/continuedev/continue/pull/13131) | `fix/pending-toolcall-button-overflow` | GUI components (6 files) | ✅ | ✅ | OPEN |

---

## Patch Index

| # | Patch | File(s) | Status | PR |
|---|-------|---------|--------|-----|
| 01 | **NIM/vLLM Empty Response Retry** | `packages/openai-adapters/src/apis/OpenAI.ts` | Active | #13091 |
| 02 | **Tool Arguments JSON Sanitize** | `core/llm/openaiTypeConverters.ts` | Active | #13092 |
| 03 | **Vision Proxy** | `core/llm/visionProxy.ts` (new), `core/llm/index.ts`, `core/index.d.ts`, `packages/config-yaml/src/schemas/models.ts` | Active | #13093 |
| 04 | **TLS Self-Signed Certificate Fix** | `packages/fetch/src/getAgentOptions.ts`, `extensions/vscode/src/extension.ts` | Active | — |
| 05 | **Performance Monitoring** | Research/Proposal | Planned | — |
| 06 | **Capacity Planning (300 Users)** | Research/Proposal | Planned | — |
| 07 | **Upstream Contribution Guide** | Documentation | Reference | — |
| 08 | **TLS Self-Signed Fix** (detailed) | Documentation | Reference | — |
| 09 | **Pending ToolCall Button Overflow Fix** | 6 GUI files | Active | #13131 |

### Quick Patch Summary

- **Patch 01 — Empty Response Retry:** When NIM/vLLM returns `content: null` with empty `tool_calls: []`, retry without tools so the model returns text instead of blank.
- **Patch 02 — JSON Sanitize:** Validates JSON in `tool_calls.function.arguments` before sending to server. Wraps malformed JSON in `{"_raw": "..."}` to prevent vLLM 400 errors.
- **Patch 03 — Vision Proxy:** Routes image messages through a VLM (Qwen2.5-VL-32B) for text description, enabling text-only LLMs (DeepSeek V4 Flash) to understand images. Configurable per-model via `visionProxy` in `config.yaml`.
- **Patch 04/08 — TLS Self-Signed:** Defaults `rejectUnauthorized` to `false` and sets `NODE_TLS_REJECT_UNAUTHORIZED=0` to allow self-signed certificates in on-prem environments.
- **Patch 09 — Button Overflow:** Fixes Accept/Reject buttons being clipped in narrow sidebar by switching to CSS Grid and using container-relative widths.

---

## Versioning

Scheme: `{upstream_major}.{upstream_minor}.{custom_patch}`

| Version | Meaning |
|---------|---------|
| `2.1.0` | Rebased on upstream v2.1.0 (no custom patches yet) |
| `2.1.1` | Current — custom build #1 after rebase |
| `2.2.1` | After syncing upstream v2.2.0 |

---

## Build

