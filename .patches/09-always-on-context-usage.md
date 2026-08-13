# Patch #5: Always-On Context Usage Display

> **PR:** [#13093](https://github.com/continuedev/continue/pull/13093)
> **Branch:** `feat/always-on-context-usage`
> **Status:** OPEN — chờ review từ maintainer
> **Files thay đổi:** 2 files GUI (purely additive UI enhancement)

---

## Vấn đề

Upstream Continue chỉ hiển thị context usage indicator khi:
- Conversation đã bị pruned (context exceeded), HOẶC
- Context usage >= 60%

Điều này nghĩa là user **không có visibility** vào mức tiêu thụ context trong
quá trình sử dụng bình thường. Họ chỉ phát hiện giới hạn context khi đã quá
muộn — sau khi pruning đã xảy ra và thông tin đã bị mất.

**Impact thực tế với ~300 developers:**
- User gửi conversation dài, đột ngột mất context → confused
- Không biết khi nào nên "Compact conversation" để giữ thông tin quan trọng
- Mất productivity do phải lặp lại context đã bị prune

---

## Giải pháp

Hiển thị context usage indicator **luôn luôn** khi có conversation history,
với enhanced precision và visual feedback theo mức sử dụng.

### Thiết kế UX

```
┌─────────────────────────────────────┐
│  [Chat messages...]                 │
│                                     │
│  ┌─ Response Actions ─────────────┐ │
│  │  0.3% · Compact    📋 ↻ 👍 👎 │ │  ← Luôn hiển thị % trước "Compact"
│  └────────────────────────────────┘ │
│                                     │
│  ┌─ Context Status Bar ───────────┐ │
│  │  [█░░░░░░░] 4.2%              │ │  ← Luôn hiển thị khi history > 0
│  └────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### Color-coded feedback

| Mức context | Color class | Visual |
|-------------|-------------|--------|
| < 60% | `bg-description-muted` | Subtle, không gây distraction |
| >= 60% | `bg-description` | Noticeable — bắt đầu chú ý |
| >= 80% | `bg-warning` | Warning — cần action sớm |
| Pruned | `bg-error` | Error — context đã bị cắt |

### Sub-1% precision

- `0.3%` thay vì round xuống `0%` (1 decimal khi < 1%)
- `4%`, `67%` khi >= 1% (integer)
- `—` khi chưa gửi message đầu tiên (contextPercentage undefined)

---

## Files thay đổi

### 1. `gui/src/components/mainInput/ContextStatus.tsx`

**Trước (upstream):**
```typescript
// Chỉ hiển thị khi pruned hoặc >= 60%
if (!isPruned && percent < 60) {
  return null;
}
```

**Sau (custom):**
```typescript
// Luôn hiển thị khi có history
// Previously: if (!isPruned && percent < 60) return null;
if (history.length === 0) {
  return null;
}
```

**Thay đổi chi tiết:**
- **Visibility:** Hiển thị khi `history.length > 0` (bỏ threshold 60%)
- **Precision:** Sub-1% formatting (`0.3%` thay vì `0%`)
- **Color coding:** 4 levels thay vì 2 (thêm `muted` và `warning`)
- **Percentage label:** Hiển thị số % bên cạnh battery bar
- **Layout:** Thêm `flex items-center gap-1` cho alignment
- **Bar minimum:** `Math.max(percent, 2)` để bar luôn visible khi có data
- **Graceful state:** Hiển thị `—` khi chưa có context data

### 2. `gui/src/components/StepContainer/ResponseActions.tsx`

**Trước (upstream):**
```typescript
const showLabel = isLast && (isPruned || percent >= 60);
// ...
<span>Compact conversation</span>
```

**Sau (custom):**
```typescript
// Always show label on last message when there's history
const showLabel = isLast && history.length > 0;
// ...
<span>{hasContextData ? `${percentFormatted}% · ` : ""}Compact</span>
```

**Thay đổi chi tiết:**
- **Always show** `Compact` label trên message cuối cùng
- **Percentage prefix:** `4.2% · Compact` thay vì chỉ "Compact conversation"
- **Shorter label:** "Compact" thay vì "Compact conversation" (tiết kiệm space)
- **Graceful:** Hide prefix khi chưa có context data

---

## Inspiration

Pattern UX này lấy cảm hứng từ **Kiro IDE**, nơi luôn hiển thị context usage
để user chủ động quản lý context budget thay vì bị surprise bởi pruning.

---

## Backward Compatibility

- ✅ Không breaking changes
- ✅ Không thêm dependencies mới
- ✅ Purely additive UI enhancement
- ✅ Behavior existing preserved khi `history.length === 0`
- ✅ Không thay đổi logic compute `contextPercentage` (chỉ thay đổi display)

---

## Trade-offs

| Aspect | Đánh giá |
|--------|----------|
| Visual noise | Minimal — muted color khi < 60%, không intrusive |
| Performance | Zero impact — chỉ thêm conditional rendering |
| UX familiarity | Có thể lạ với user quen upstream (luôn thấy indicator) |
| Information overload | Mitigated bằng color coding (subtle → warning → error) |

---

## Verify patch còn nguyên

```bash
# Check ContextStatus.tsx có always-on logic
grep -c "history.length === 0" gui/src/components/mainInput/ContextStatus.tsx
# Expected: 1

# Check ResponseActions.tsx có percentage display
grep -c "percentFormatted" gui/src/components/StepContainer/ResponseActions.tsx
# Expected: >= 2

# Check color coding levels
grep -c "bg-warning\|bg-description-muted\|bg-description\|bg-error" gui/src/components/mainInput/ContextStatus.tsx
# Expected: >= 4
```

---

## Tài liệu liên quan

- PR description: https://github.com/continuedev/continue/pull/13093
- Upstream ContextStatus component: `gui/src/components/mainInput/ContextStatus.tsx`
- Upstream ResponseActions component: `gui/src/components/StepContainer/ResponseActions.tsx`
- Context percentage computation: `core/llm/compileChatMessages.ts` (không thay đổi)
