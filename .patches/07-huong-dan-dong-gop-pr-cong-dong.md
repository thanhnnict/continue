# Hướng dẫn đóng góp PR cho dự án Open Source

> Tài liệu này được viết từ kinh nghiệm thực tế đóng góp 3 PR cho
> [continuedev/continue](https://github.com/continuedev/continue), bao gồm
> toàn bộ quy trình từ chuẩn bị đến khi PR được review.

---

## Mục lục

1. [Tổng quan quy trình](#1-tổng-quan-quy-trình)
2. [Chuẩn bị repo local](#2-chuẩn-bị-repo-local)
3. [Viết patch đúng cách](#3-viết-patch-đúng-cách)
4. [Tạo PR trên GitHub](#4-tạo-pr-trên-github)
5. [Xử lý CI checks và CLA](#5-xử-lý-ci-checks-và-cla)
6. [Làm việc với maintainer](#6-làm-việc-với-maintainer)
7. [Các lỗi thường gặp và cách tránh](#7-các-lỗi-thường-gặp-và-cách-tránh)
8. [Quick Reference](#8-quick-reference)
9. [Tooling Setup — gh CLI và prettier](#9-tooling-setup--gh-cli-và-prettier)

---

## 1. Tổng quan quy trình

```
Fork repo       Tạo branch     Viết code      Push & tạo PR     Review
upstream   →    fix/feat-*  →  (focused)   →  lên fork      →  & merge
   │                │               │              │               │
Clone về       Từ upstream     1 PR = 1        Ký CLA        Phản hồi
local          main (mới)      vấn đề          bot           maintainer
```

### Các khái niệm quan trọng

| Thuật ngữ | Nghĩa |
|-----------|-------|
| **upstream** | Repo gốc của cộng đồng (vd: `continuedev/continue`) |
| **origin** | Fork cá nhân của bạn (vd: `thanhnnict/continue`) |
| **base branch** | Branch bạn tạo PR vào (thường là `upstream/main`) |
| **head branch** | Branch chứa code của bạn (vd: `fix/empty-response-retry`) |
| **CLA** | Contributor License Agreement — bạn trao quyền cho project dùng code bạn |

---

## 2. Chuẩn bị repo local

### 2.1. Fork và clone

```bash
# 1. Fork trên GitHub UI: upstream repo → nút "Fork"
# 2. Clone fork về local
git clone git@github.com:thanhnnict/continue.git
cd continue

# 3. Thêm upstream remote để sync
git remote add upstream https://github.com/continuedev/continue.git

# Kiểm tra
git remote -v
# origin   git@github.com:thanhnnict/continue.git (fetch/push)
# upstream https://github.com/continuedev/continue.git (fetch/push)
```

### 2.2. Cấu hình git cơ bản

```bash
# Tắt fileMode tracking — quan trọng trên Windows
# (Windows không có executable bit như Linux)
git config core.fileMode false

# Xác nhận
git config core.fileMode
# false
```

> **⚠️ QUAN TRỌNG — Email commit phải khớp với GitHub account:**
> CLA bot verify email của committer. Nếu email commit ≠ email GitHub account → CLA fail dù đã comment ký.
>
> ```bash
> git config user.email "thanhnn.ict@gmail.com"
> git config user.name "Nam Thanh Nguyen"
>
> # Fix commits đã sai email (trước khi push)
> git rebase upstream/main --exec 'git commit --amend --reset-author --no-edit'
> git push origin <branch> --force-with-lease
> ```

### 2.3. Fetch upstream để có code mới nhất

```bash
# Fetch branch main từ upstream
# Lưu ý: dùng refs/heads/ để tránh nhầm với tag cùng tên
git fetch upstream refs/heads/main:refs/remotes/upstream/main

# Kiểm tra upstream/main HEAD
git log upstream/main --oneline -5
```

---

## 3. Viết patch đúng cách

### 3.1. Nguyên tắc "1 PR = 1 vấn đề"

Đây là nguyên tắc quan trọng nhất. Mỗi PR chỉ nên giải quyết **một vấn đề cụ thể**.

```
✅ ĐÚNG: fix/empty-response-retry     ← chỉ fix retry logic
✅ ĐÚNG: fix/sanitize-tool-arguments  ← chỉ fix sanitize JSON
✅ ĐÚNG: feat/always-on-context-usage ← chỉ thêm 1 feature

❌ SAI: fix/various-improvements ← gộp nhiều thứ vào 1 PR
```

### 3.2. Tạo branch từ upstream/main (không từ branch custom của bạn)

```bash
# ❌ SAI — tạo branch từ main local của bạn (đã có custom patches)
git checkout main
git checkout -b fix/empty-response-retry

# ✅ ĐÚNG — tạo branch trực tiếp từ upstream/main
git fetch upstream refs/heads/main:refs/remotes/upstream/main
git checkout -b fix/empty-response-retry upstream/main
```

> **Tại sao quan trọng?**
> Nếu `main` local của bạn chứa nhiều custom patches không liên quan đến PR,
> tất cả sẽ bị đưa vào PR và gây conflict, khó review, dễ bị reject.

### 3.3. Ví dụ thực tế — PR #13091

**Vấn đề phát hiện:** NIM/vLLM trả về `content: null` + `tool_calls: []` khi
model không muốn call tool → GUI render blank.

**File thay đổi:** chỉ `packages/openai-adapters/src/apis/OpenAI.ts`

```typescript
// Trước — không xử lý empty response
const response = await this.openai.chat.completions.create(
  this.modifyChatBody(body),
  { signal },
);
return response;

// Sau — retry without tools khi response trống
let response = await this.openai.chat.completions.create(
  this.modifyChatBody(body),
  { signal },
);

// Some OpenAI-compatible servers (e.g. NIM, vLLM) return content: null
// with an empty tool_calls array when tools are provided but the model
// decides not to call any. Retry without tools so the model responds
// with text content instead.
const msg = response.choices?.[0]?.message;
if (msg && !msg.content && (!msg.tool_calls || msg.tool_calls.length === 0) && body.tools?.length) {
  const { tools, tool_choice, ...bodyWithoutTools } = body;
  response = await this.openai.chat.completions.create(
    this.modifyChatBody(bodyWithoutTools as ChatCompletionCreateParamsNonStreaming),
    { signal },
  );
}
return response;
```

**Commit message** theo convention:
```
fix: retry without tools when OpenAI-compatible server returns empty response
```

### 3.4. Commit message convention

Continue project dùng [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <mô tả ngắn gọn, không quá 72 ký tự>

[body tùy chọn — giải thích chi tiết WHY, không phải WHAT]
```

| Type | Dùng khi |
|------|----------|
| `fix` | Sửa bug |
| `feat` | Thêm tính năng mới |
| `docs` | Cập nhật documentation |
| `chore` | Công việc maintenance (build, deps...) |
| `test` | Thêm/sửa tests |
| `refactor` | Refactor không thêm/sửa feature |

### 3.5. Push lên origin (fork của bạn)

```bash
git push origin fix/empty-response-retry
```

---

## 4. Tạo PR trên GitHub

### 4.1. Chọn đúng base branch

Khi tạo PR trên GitHub:
- **base repository**: `continuedev/continue`
- **base branch**: `main` (upstream main — không phải main fork của bạn)
- **head repository**: `thanhnnict/continue`
- **head branch**: `fix/empty-response-retry`

```
thanhnnict:fix/empty-response-retry  →  continuedev:main
```

### 4.2. Điền PR description theo template

Continue có PR template tại `.github/pull_request_template.md`. Điền đầy đủ:

```markdown
## Description

Fix blank response when OpenAI-compatible servers (NIM/vLLM) return
`content: null` with empty `tool_calls[]` array. This happens when
tools are provided in the request but the model decides not to call any.

The fix retries the request without tools in this specific case,
so the model returns text content instead of an empty response.

**Affected servers:** NVIDIA NIM, vLLM with tool-use enabled

## Checklist

- [x] I've read the contributing guide
- [x] The relevant docs, if any, have been updated or created
- [x] The relevant tests, if any, have been updated or created

## Screen recording or screenshot

[Attached: screen recording showing before/after behavior]

## Tests

No new tests added — the fix is defensive and doesn't change
public API contract. Existing tests continue to pass.
```

### 4.3. Đặt title PR

```
fix: retry without tools when OpenAI-compatible server returns empty response
```

Cùng format với commit message — ngắn gọn, rõ ràng, dùng type prefix.

---

## 5. Xử lý CI checks và CLA

### 5.1. Hiểu các checks trong PR

Sau khi tạo PR, GitHub Actions tự động chạy các checks:

```
✅ / ❌  CLA Assistant                    ← Required — phải pass
✅ / ❌  PR Checks / require-all-checks   ← Required — aggregate
⚪       PR Build / build-and-upload-vsix ← Build artifact
⚪       CLI PR Checks / test             ← Unit/integration tests
⚪       PR Checks / jetbrains-tests      ← JetBrains plugin tests
```

### 5.2. Cài gh CLI (nếu chưa có)

**Trong WSL qua Nexus (Nexus repo `github-cli-apt` đã tạo sẵn):**

```bash
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /tmp/githubcli-keyring.gpg
sudo cp /tmp/githubcli-keyring.gpg /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg trusted=yes] \
  http://localhost:7081/repository/github-cli-apt stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/github-cli.list" \
  -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
sudo apt-get install -y gh
```

**Auth với Classic PAT:**

```bash
# Classic PAT scope cần: repo, write:discussion
gh auth login --with-token <<< "ghp_YOUR_TOKEN"
gh auth status  # kiểm tra scopes
```

> **Lưu ý:** Fine-grained PAT không có `X-OAuth-Scopes` header và có thể thiếu permission `Pull requests: Write` → dùng **Classic PAT**.

### 5.3. Ký CLA — bắt buộc, làm ngay

CLA (Contributor License Agreement) là thỏa thuận bạn trao quyền cho project
sử dụng code bạn đóng góp. **Phải ký trước khi PR có thể merge**.

Bot sẽ tự động comment vào PR khi phát hiện bạn chưa ký. Để ký:

**Bước 1:** Vào PR trên GitHub

**Bước 2:** Tìm comment của `cla-assistant-lite[bot]`, nội dung tương tự:
> *"Thank you for your submission. Before we can merge this PR, we need you to sign our CLA..."*

**Bước 3:** Comment vào PR (không phải reply, mà comment mới hoặc reply trực tiếp):

```
I have read the CLA Document and I hereby sign the CLA
```

**Bước 4:** Sau vài giây, check CLA sẽ chuyển sang ✅. Nếu chưa tự động re-run:

```
recheck
```

> **Lưu ý:** CLA chỉ cần ký **một lần** cho toàn bộ repo. Các PR sau sẽ tự pass.
> Nếu đã ký rồi mà check vẫn fail, comment `recheck` là đủ.

**Ký CLA hàng loạt bằng gh CLI:**

```bash
CLA="I have read the CLA Document and I hereby sign the CLA"
for pr in 13091 13092 13093; do
  gh pr comment $pr --repo continuedev/continue --body "$CLA"
done
```

> **Nếu CLA fail sau khi push commit mới:** Bot re-run và cần ký lại — comment thêm lần nữa là đủ. Chữ ký cũ vẫn giữ trong branch `cla-signatures`.

### 5.4. Fix prettier-check fail

Continue enforce prettier formatting. Check sẽ fail nếu code không đúng format.

```bash
# Cài prettier vào /tmp (không cần full npm install workspace)
mkdir -p /tmp/prettier-tools && cd /tmp/prettier-tools
conda run -n node20 npm install \
  --registry http://localhost:7081/repository/npm-group/ \
  prettier@3.3.3 prettier-plugin-tailwindcss@0.6.8

# Check
conda run -n node20 node_modules/.bin/prettier --check /path/to/file.tsx

# Fix
conda run -n node20 node_modules/.bin/prettier --write /path/to/file.tsx
```

> Cần cài cả `prettier-plugin-tailwindcss` vì `.prettierrc` require plugin này.

### 5.5. Phân tích CI failure — cái nào liên quan code bạn?

Khi CI fail, cần phân biệt 2 trường hợp:

**Trường hợp 1 — Fail do code bạn** (phải fix):
- Test liên quan trực tiếp đến file bạn sửa
- Build error sau khi thêm code mới
- Type error, lint error

**Trường hợp 2 — Fail không liên quan** (chờ maintainer):
- Test ở module hoàn toàn khác (vd: bạn sửa `OpenAI.ts` nhưng `jetbrains-tests` fail)
- Flaky tests (fail ngẫu nhiên, không stable)
- CI infrastructure issues

**Cách xác định nhanh:**

```bash
# Xem code bạn thay đổi những file nào
git diff upstream/main...HEAD --name-only

# Nếu các file changed KHÔNG liên quan đến test đang fail
# → CI failure không phải do bạn
```

**Ví dụ thực tế từ 3 PR:**
- Code thay đổi: `OpenAI.ts`, `openaiTypeConverters.ts` (packages/core)
- Tests failing: `jetbrains-tests`, `CLI macos tests`
- **Kết luận:** Không liên quan → flaky CI upstream

### 5.6. Comment hỏi maintainer khi CI fail không liên quan

```
Hi @continuedev/maintainers,

The failing checks (`jetbrains-tests`, `CLI PR Checks / test macos-latest`)
appear unrelated to this change — this PR only modifies `OpenAI.ts` in the
openai-adapters package.

Could you confirm if these are pre-existing flaky tests or re-run the CI?
Thanks!
```

---

## 6. Làm việc với maintainer

### 6.1. Quy trình review của Continue project

Theo CONTRIBUTING.md:
1. **Initial Review** — maintainer được assign là primary reviewer
2. **Feedback Loop** — reviewer có thể request changes
3. **Approval & Merge** — sau khi approve, merge vào `main`

### 6.2. Thời gian chờ thực tế

Đây là open source project — maintainer không có SLA cố định. Thông thường:
- Bug fix nhỏ, focused: 2–7 ngày
- Feature mới: có thể vài tuần, cần discussion
- Nếu quá 2 tuần không có response: ping nhẹ nhàng trong PR comment

### 6.3. Khi maintainer request changes

```bash
# Trên branch hiện tại, sửa code theo feedback
git add <files>
git commit -m "fix: address review feedback — <mô tả ngắn>"

# Push lại — PR tự động cập nhật
git push origin fix/empty-response-retry
```

Không tạo PR mới. Sửa trên cùng branch, push lại là PR tự update.

### 6.4. Khi cần rebase lên upstream/main mới hơn

Nếu upstream/main có commit mới làm conflict với PR của bạn:

```bash
# Fetch latest upstream
git fetch upstream refs/heads/main:refs/remotes/upstream/main

# Rebase branch của bạn
git checkout fix/empty-response-retry
git rebase upstream/main

# Giải quyết conflict nếu có, sau đó
git push origin fix/empty-response-retry --force-with-lease
```

> Dùng `--force-with-lease` thay vì `--force` — an toàn hơn, chỉ force push
> nếu không có ai khác push vào branch này trong lúc đó.

---

## 7. Các lỗi thường gặp và cách tránh

### Lỗi 1: Branch chứa quá nhiều commits không liên quan

**Triệu chứng:** Maintainer thấy PR diff lớn, nhiều file thay đổi không liên quan.

**Nguyên nhân:** Tạo branch từ `main` local đã có nhiều custom patches.

**Fix:**
```bash
# Xem diff so với upstream/main
git diff upstream/main...HEAD --name-only

# Nếu quá nhiều file không liên quan → cherry-pick commit của bạn
git checkout -b fix/empty-response-retry-v2 upstream/main
git cherry-pick <commit-hash-của-fix>
git push origin fix/empty-response-retry-v2

# Đóng PR cũ, tạo PR mới từ branch v2
```

### Lỗi 2: CLA check fail mãi không pass

**Nguyên nhân:** Comment chưa đúng format, hoặc bot chưa nhận.

**Fix:**
```
# Comment chính xác câu này (copy-paste, không sửa)
I have read the CLA Document and I hereby sign the CLA

# Nếu vẫn không pass sau 1 phút
recheck
```

### Lỗi 3: fileMode changes làm bẩn git status trên Windows

**Triệu chứng:** Hàng chục file `.sh`, `.mjs` hiện là "modified" dù không sửa gì.

**Fix vĩnh viễn:**
```bash
git config core.fileMode false
```

### Lỗi 4: Remote origin bị lấp đầy bởi dependabot/snyk branches

**Triệu chứng:** `git branch -r` hiển thị 100+ branches không liên quan.

**Nguyên nhân:** Fork cá nhân nhận branches từ upstream sync (dependabot, snyk).

**Fix:**
```bash
# Xóa hàng loạt, giữ lại chỉ branches của bạn
$keep = @("main", "fix/my-fix", "feat/my-feat", ...)
$all = git branch -r | Where-Object { $_ -match "origin/" } |
       ForEach-Object { $_.Trim() -replace "^origin/", "" }
$toDelete = $all | Where-Object { $_ -notin $keep }
foreach ($b in $toDelete) { git push origin --delete $b }
```

**Ngăn tái phát:** Vào GitHub → Settings → Code security and analysis → tắt
Dependabot và Snyk integration.

### Lỗi 5: Email commit không khớp GitHub account → CLA fail mãi

**Triệu chứng:** CLA bot báo `Committers of Pull Request number XXXXX have to sign the CLA` dù đã comment ký nhiều lần.

**Nguyên nhân:** `git config user.email` chưa set trong WSL → mặc định `you@example.com`.

**Fix:**
```bash
# Set đúng email
git config user.email "thanhnn.ict@gmail.com"
git config user.name "Nam Thanh Nguyen"

# Amend tất cả commits sai author
git rebase upstream/main --exec 'git commit --amend --reset-author --no-edit'
# Nếu gặp empty commit → thêm --allow-empty
git commit --amend --reset-author --no-edit --allow-empty
git rebase --continue

# Force push (thêm history đã thay đổi)
git push origin <branch> --force-with-lease

# Ký CLA lại
gh pr comment <pr> --repo continuedev/continue \
  --body "I have read the CLA Document and I hereby sign the CLA"
```

### Lỗi 6: Push nhầm vào upstream thay vì origin

```bash
# Kiểm tra trước khi push
git remote -v

# Push chỉ lên origin (fork của bạn)
git push origin <branch-name>
# Không bao giờ: git push upstream
```

---

## 8. Quick Reference

### Quy trình đầy đủ — từ đầu đến khi PR sẵn sàng

```bash
# === SETUP (1 lần duy nhất) ===
git clone git@github.com:<your-username>/continue.git
cd continue
git remote add upstream https://github.com/continuedev/continue.git
git config core.fileMode false

# === CHUẨN BỊ MỖI LẦN LÀM PR ===
# 1. Fetch upstream mới nhất
git fetch upstream refs/heads/main:refs/remotes/upstream/main

# 2. Tạo branch từ upstream/main
git checkout -b fix/ten-van-de upstream/main

# === VIẾT CODE ===
# ... sửa file, test local ...

# 3. Commit
git add <files-liên-quan>
git commit -m "fix: mô tả ngắn gọn vấn đề"

# 4. Push lên fork
git push -u origin fix/ten-van-de

# === TẠO PR TRÊN GITHUB ===
# base: continuedev/continue → main
# head: thanhnnict/continue  → fix/ten-van-de

# === SAU KHI TẠO PR ===
# 5. Ký CLA (nếu chưa ký)
# Comment vào PR: "I have read the CLA Document and I hereby sign the CLA"

# 6. Theo dõi CI checks
# - CLA ✅ → done
# - CI fail liên quan code → fix và push lại
# - CI fail không liên quan → comment hỏi maintainer
```

### Checklist trước khi tạo PR

```
[ ] Branch tạo từ upstream/main (không phải main local custom)
[ ] Chỉ thay đổi files liên quan đến vấn đề đang fix
[ ] Commit message theo convention: type: mô tả
[ ] PR description điền đầy đủ theo template
[ ] Base branch là continuedev:main (không phải fork của bạn)
[ ] Không commit node_modules, *.vsix, build artifacts
```

### Anatomy của 3 PR thực tế

| PR | Branch | File thay đổi | Type |
|----|--------|---------------|------|
| [#13091](https://github.com/continuedev/continue/pull/13091) | `fix/empty-response-retry` | `packages/openai-adapters/src/apis/OpenAI.ts` | Bug fix NIM/vLLM empty response |
| [#13092](https://github.com/continuedev/continue/pull/13092) | `fix/sanitize-tool-arguments` | `core/llm/openaiTypeConverters.ts` | Bug fix malformed JSON tool args |
| [#13093](https://github.com/continuedev/continue/pull/13093) | `feat/always-on-context-usage` | GUI components | Feature context usage display |

---

## 9. Tooling Setup — gh CLI và prettier

### gh CLI trong WSL

```bash
# Kiểm tra đã cài chưa
gh --version
# gh version 2.97.0 (2026-07-31)

# Kiểm tra auth
gh auth status
# ✓ Logged in to github.com account thanhnnict
# ✓ Token scopes: '...repo...write:discussion...'

# Nếu chưa auth (PAT lưu trong ~/.env)
gh auth login --with-token <<< "ghp_YOUR_CLASSIC_PAT"
```

> **Classic PAT** (không phải Fine-grained) với scope `repo` + `write:discussion`.
> Fine-grained PAT thiếu permission comment PR → `gh pr comment` fail.

### conda env `node20`

```bash
# Kiểm tra
conda env list | grep node20

# Tạo mới nếu chưa có
conda create -n node20 -y nodejs=20

# Verify
conda run -n node20 node --version  # v20.17.0
conda run -n node20 npm --version   # 10.8.2
```

### prettier tools

```bash
# Cài vào /tmp/prettier-tools để tái sử dụng
ls /tmp/prettier-tools/node_modules/.bin/prettier 2>/dev/null || {
  mkdir -p /tmp/prettier-tools && cd /tmp/prettier-tools
  conda run -n node20 npm install \
    --registry http://localhost:7081/repository/npm-group/ \
    prettier@3.3.3 prettier-plugin-tailwindcss@0.6.8
}

# Check & fix formatting
cd /tmp/prettier-tools
conda run -n node20 node_modules/.bin/prettier --check /path/to/file.tsx
conda run -n node20 node_modules/.bin/prettier --write /path/to/file.tsx
```

---

## Tài liệu tham khảo

- [CONTRIBUTING.md của Continue](https://github.com/continuedev/continue/blob/main/CONTRIBUTING.md)
- [CLA của Continue](https://github.com/continuedev/continue/blob/main/CLA.md)
- [Conventional Commits specification](https://www.conventionalcommits.org/)
- [Release Flow (git workflow)](http://releaseflow.org)
- [GitHub Discussions của Continue](https://github.com/continuedev/continue/discussions)
