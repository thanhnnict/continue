# Continue Offline Deployment — VSCode Portable + Air-Gap

> Package chứa VSCode Portable + Continue Extension VSIX + Scripts cài đặt
> Dùng cho môi trường **air-gap (no-internet)** như Jump Server.

---

## Cấu trúc package

`
deploy/
├── package-deploy.ps1              # [INTERNET] Build VSIX + Download VSCode + Package
├── scripts/
│   ├── download-vscode-portable.ps1 # [INTERNET] Download VSCode Portable ZIP
│   ├── install-offline.ps1          # [JUMP] Cài Continue vào VSCode Portable
│   └── verify-offline.ps1           # [JUMP] Kiểm tra cài đặt
└── vscode-portable/                 # [JUMP] Thư mục deploy (sau khi chạy download)
    ├── VSCode-win32-x64/            # VSCode Portable (extracted)
    │   ├── Code.exe
    │   ├── bin/code.cmd
    │   └── data/                    # Portable mode data
    │       ├── extensions/          # Chứa VSIX + extensions
    │       ├── user-data/
    │       └── tmp/
    ├── extensions/
    │   └── continue-win32-x64-*.vsix
    └── scripts/
        ├── install-offline.ps1
        └── verify-offline.ps1
`

---

## Quy trình triển khai

### Phase 1: Trên máy Build (có internet)

Chạy 1 lần duy nhất để tạo deployment package:

`powershell
cd E:\08-Sources\1.AI\continue

# Cách 1: Build VSIX + Download VSCode + Package (all-in-one)
.\deploy\package-deploy.ps1

# Cách 2: Chỉ download VSCode Portable (nếu VSIX đã build sẵn)
.\deploy\scripts\download-vscode-portable.ps1
`

Kết quả: thư mục deploy\package\ chứa tất cả những gì cần thiết.

### Phase 2: Copy sang Jump Server

| Phương tiện | Lệnh |
|-------------|------|
| USB | Copy folder deploy\package\ vào USB |
| SCP | scp -r deploy/package user@jump-server:D:/Tools/ |
| Network share | Copy-Item -Recurse deploy/package \\jump-server\share\ |

### Phase 3: Trên Jump Server (air-gap)

`powershell
# Mở PowerShell trên Jump Server
cd D:\Tools\package

# Bước 1: Cài Continue extension
.\scripts\install-offline.ps1

# Bước 2: Kiểm tra (optional)
.\scripts\verify-offline.ps1

# Bước 3: Chạy VSCode Portable
.\VSCode-win32-x64\Code.exe
`

---

## Cấu hình Continue sau khi cài

Sau khi mở VSCode Portable:

1. Ctrl+Shift+P → Continue: Open config file
2. Cấu hình model endpoint (apiBase trỏ tới internal LLM server):

`yaml
models:
  - name: DeepSeek V4 Flash
    provider: openai
    model: deepseek-ai/DeepSeek-V4-Flash
    apiBase: http://internal-server:7021/v1
    apiKey: sk-your-key
    roles: [chat, edit, apply]
    capabilities:
      - tool_use
`

3. Bắt đầu sử dụng!

---

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| code.cmd không chạy được | Kiểm tra path: Test-Path .\VSCode-win32-x64\bin\code.cmd |
| Extension không install được | Chạy lại: .\scripts\install-offline.ps1 -VsixPath .\extensions\continue-win32-x64-*.vsix |
| VSCode không ở portable mode | Tạo thư mục data\ trong VSCode-win32-x64\ |
| Extension load nhưng không kết nối model | Kiểm tra piBase trong config.yaml |
| Cần update extension | Build VSIX mới → copy file .vsix → chạy install-offline lại |

---

## File tham chiếu

| File | Mô tả |
|------|-------|
| deploy/package-deploy.ps1 | Master script: build VSIX + download VSCode + package |
| deploy/scripts/download-vscode-portable.ps1 | Download VSCode Portable ZIP |
| deploy/scripts/install-offline.ps1 | Install Continue VSIX vào VSCode Portable |
| deploy/scripts/verify-offline.ps1 | Verify cài đặt |
| docs/build/README.md | Hướng dẫn build chi tiết |
| docs/build/troubleshooting.md | Xử lý lỗi build |

---

## Yêu cầu hệ thống (Jump Server)

| Component | Yêu cầu |
|-----------|---------|
| OS | Windows 10/11 64-bit |
| RAM | >= 8GB (recommended 16GB) |
| Disk | >= 500MB free cho VSCode + extension |
| Network | Kết nối tới internal LLM server (NIM/vLLM) |
| Internet | Không cần — hoàn toàn offline |