# Issue: Accept Button Clipped in PendingToolCallToolbar

> **Status:** 🔴 OPEN — chưa fix được
> **Branch:** `hotfix/pending-toolcall-button-clipped`
> **Phát hiện:** 2026-08-13
> **Ảnh hưởng:** Button "Accept" (xanh) cho Run Terminal Command bị ẩn/cắt ở cạnh phải panel
> **Mức độ:** UX bug — user phải kéo panel rộng >50% màn hình mới thấy button
> **Nguồn gốc:** Bug có sẵn từ upstream Continue (không do custom patches gây ra)

---

## Triệu chứng

Khi agent gọi `run_terminal_command` và chờ user approve:
- Toolbar hiển thị: `Run Terminal Command` ... `⌘⌫ Reject` `[⌘⏎ Accept]`
- Button **Accept** (xanh, primary) bị cắt/ẩn hoàn toàn ở cạnh phải
- Chỉ thấy khi kéo panel ra rất rộng (>50% màn hình)
- Bug tồn tại cả trên upstream marketplace extension (đã verify)

---

## Layout Chain (đã trace qua DevTools)

```
LayoutTopDiv (styled-component)
  → overflow-x: hidden          ← CLIPS everything horizontally
  → height: 100%

  GridDiv (styled-component)
    → display: grid; grid-template-rows: 1fr auto
    → height: 100vh
    → overflow-x: visible

    Chat.tsx return:
      <div className="relative shrink-0">        ← ContinueInputBox wrapper
        <ContinueInputBox>
          <div className="relative flex flex-col px-2">    ← px-2 = 16px total padding
            <Lump>
              <div className="bg-input rounded-t-default border-command-border mx-1 ...">
                <div className="px-1 py-0.5">
                  <LumpToolbar>
                    <PendingToolCallToolbar>
                      <div className="flex w-full min-w-0 flex-col pb-0.5">
                        <!-- PER TOOL CALL ROW: -->
                        <div className="... flex min-w-0 items-center gap-1 ...">
                          <span className="... min-w-0 shrink truncate ...">
                            Run Terminal Command
                          </span>
                          <div className="ml-auto flex shrink-0 items-center gap-1 pr-1">
                            <button>⌘⌫ Reject</button>
                            <button>⌘⏎ Accept</button>  ← BỊ CẮT
                          </div>
                        </div>
```

### Tổng horizontal overhead (mỗi bên):

| Level | Class | Pixels (mỗi bên) |
|-------|-------|-------------------|
| ContinueInputBox | `px-2` | 8px |
| Lump outer | `mx-1` | 4px |
| Lump border | `border-l border-r` | 1px |
| Lump inner | `px-1` | 4px |
| **Total mỗi bên** | | **~17px** |
| **Total cả 2 bên** | | **~34px** |

→ Toolbar row chỉ có `panel_width - 34px` để render content.

---

## Root Cause Analysis

1. **`LayoutTopDiv` có `overflow-x: hidden`** — bất kỳ content nào tràn ra phải đều bị invisible (không scrollable)

2. **Flex layout không constraint width đúng cách** — dù đã thêm `min-w-0` ở nhiều level, buttons container vẫn bị đẩy ra ngoài visible area

3. **Buttons container kích thước thực tế khá lớn:**
   - `⌘⌫ Reject` + `⌘⏎ Accept` = ~160-180px (bao gồm padding, gap, keyboard shortcut labels)
   - Trên sidebar hẹp (~300px), sau khi trừ 34px overhead, chỉ còn ~266px
   - Tool name "Run Terminal Command" dù truncate, vẫn cần minimum width
   - Kết quả: buttons bị đẩy ra ngoài 266px boundary

4. **Vấn đề cốt lõi:** CSS flexbox `shrink-0` trên buttons container = "KHÔNG BAO GIỜ co lại". Khi parent width < (tool_name_min + buttons_width), buttons overflow ra ngoài. `overflow-x: hidden` ở LayoutTopDiv clip chúng.

---

## Các Approach Đã Thử (chưa thành công)

### Attempt 1: Thêm `shrink-0` cho buttons, `min-w-0` cho tool name
- **Thay đổi:** `PendingToolCallToolbar.tsx` — buttons `shrink-0`, tool name `min-w-0 flex-1 truncate`
- **Kết quả:** Không fix. `flex-1` vẫn khiến tool name grow, đẩy buttons ra ngoài

### Attempt 2: Giảm margin/padding
- **Thay đổi:** Lump `mx-1.5` → `mx-1`, bỏ `xs:px-2`, giảm `gap-2` → `gap-1`
- **Kết quả:** Không đủ. Tiết kiệm ~4px mỗi bên, nhưng buttons vẫn overflow

### Attempt 3: Thêm `overflow-hidden` ở Lump container
- **Thay đổi:** Lump outer div thêm `overflow-hidden`
- **Kết quả:** Clip buttons thay vì tràn ra ngoài — vẫn không visible

### Attempt 4: Thêm `min-w-0` ở mọi flex level
- **Thay đổi:** `min-w-0` trên wrapper, row, tool name span
- **Kết quả:** Không fix. `min-w-0` cho phép shrink nhưng flex algorithm vẫn không force shrink tool name đủ

### Attempt 5: Bỏ `flex-1`, dùng `shrink` + `ml-auto`
- **Thay đổi:** Tool name: bỏ `flex-1`, thêm `shrink`. Buttons: thêm `ml-auto`
- **Kết quả:** Không fix. `ml-auto` push buttons sang phải nhưng chúng vẫn overflow vì total content > container width

---

## Suggested Next Steps (chưa thử)

### Option A: Hide keyboard shortcut labels khi panel hẹp
```tsx
// Dùng responsive class để hide shortcut labels
{index === 0 && (
  <span className="text-2xs mr-1 hidden sm:inline">⌘⌫</span>
)}
```
→ Giảm buttons width ~40px, có thể đủ fit

### Option B: Đặt buttons container width cố định bằng CSS
```tsx
// Force buttons container max-width và cho phép wrap
<div className="flex shrink-0 items-center gap-0.5" style={{ maxWidth: '40%' }}>
```

### Option C: Dùng CSS Grid thay vì Flexbox
```tsx
// Grid với 2 columns: auto (buttons cố định) + 1fr (tool name)
<div className="grid grid-cols-[1fr_auto] items-center gap-1">
  <span className="truncate ...">Tool name</span>
  <div className="flex ...">buttons</div>
</div>
```
→ Grid `1fr` + `auto` đảm bảo column 2 (buttons) LUÔN có đủ width, column 1 nhận phần còn lại

### Option D: Bỏ `overflow-x: hidden` ở LayoutTopDiv
```tsx
// Layout.tsx - LayoutTopDiv styled-component
const LayoutTopDiv = styled(CustomScrollbarDiv)`
  height: 100%;
  position: relative;
  overflow-x: hidden;  ← BỎ DÒNG NÀY hoặc đổi thành overflow-x: clip
`;
```
→ Risky — có thể gây horizontal scroll ở các chỗ khác

### Option E: Đặt max-width % cho tool name span
```tsx
<span className="... max-w-[45%] truncate ...">
  {toolCall.tool?.displayTitle ?? toolCall.toolCall.function.name}
</span>
```
→ Đơn giản nhất, force tool name không bao giờ chiếm quá 45% width

### Option F (Recommended): Grid layout + responsive shortcut labels
```tsx
<div className="grid grid-cols-[1fr_auto] items-center rounded border">
  <span className="truncate px-1 text-xs italic">
    {toolCall.tool?.displayTitle}
  </span>
  <div className="flex items-center gap-0.5 pr-1">
    <Button size="sm">
      <span className="hidden xs:inline text-2xs mr-0.5">⌘⌫</span>
      Reject
    </Button>
    <Button variant="primary" size="sm">
      <span className="hidden xs:inline text-2xs mr-0.5">⌘⏎</span>
      Accept
    </Button>
  </div>
</div>
```

---

## DevTools Debug Guide

1. `Cmd+Shift+P` → "Developer: Open Webview Developer Tools"
2. Elements tab → Select element tool (🔍) → click vào area bị lỗi
3. Check **Computed** tab → box model xem actual rendered width
4. Trace parent chain tìm element có width constraint
5. Test fix: uncheck `overflow-hidden` hoặc edit styles trực tiếp

### Quick test trong DevTools Console:
```js
// Tìm tất cả elements có overflow hidden
document.querySelectorAll('*').forEach(el => {
  const style = getComputedStyle(el);
  if (style.overflowX === 'hidden' || style.overflow === 'hidden') {
    console.log(el.className.substring(0, 60), el.getBoundingClientRect().width);
  }
});
```

---

## Files Đã Thay Đổi (trên branch hotfix)

| File | Changes |
|------|---------|
| `gui/src/components/mainInput/Lump/index.tsx` | `mx-1.5`→`mx-1`, thêm `min-w-0 overflow-hidden` |
| `gui/src/components/mainInput/Lump/LumpToolbar/PendingToolCallToolbar.tsx` | Nhiều attempts: `min-w-0`, bỏ `flex-1`, thêm `shrink`, `ml-auto`, `shrink-0` |
| `extensions/vscode/package.json` | version bump `2.1.1` → `2.1.2` |
| `deploy/01-build-extension/build-macos.sh` | `ls` → `ls -t` fix output filename |

---

## Git Log (branch: hotfix/pending-toolcall-button-clipped)

```
8c3cf7b fix(gui): prevent Accept button overflow in PendingToolCallToolbar
8ab6d2d fix(build): use ls -t to pick latest VSIX in build output display
2202517 chore: bump version to 2.1.2 for hotfix build
832f94e fix(gui): prevent accept/reject buttons from being clipped in PendingToolCallToolbar
```

---

## Khi Tiếp Tục

1. Checkout branch: `git checkout hotfix/pending-toolcall-button-clipped`
2. Mở DevTools: `Cmd+Shift+P` → "Developer: Open Webview Developer Tools"
3. Thử **Option C (Grid)** hoặc **Option F (Grid + responsive labels)** — approach mới hoàn toàn
4. Build test: `bash deploy/01-build-extension/build-macos.sh --skip-packages`
5. Install: `code --install-extension extensions/vscode/build/continue-darwin-arm64-2.1.2.vsix --force`
