# download-vscode-portable.ps1
# Chạy trên máy CÓ INTERNET để download VSCode Portable
# Sau đó copy toàn bộ thư mục deploy/ sang Jump Server (air-gap)

param(
    [string]$OutputDir = (Join-Path $PSScriptRoot "..\vscode-portable"),
    [string]$Version = "stable"  # "stable" or "insider"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Download VSCode Portable (win32-x64)" -ForegroundColor Cyan
Write-Host "  Version: $Version" -ForegroundColor Cyan
Write-Host "  Output: $OutputDir" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Tạo thư mục output
New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

# URL download VSCode Portable ZIP
$url = "https://code.visualstudio.com/sha/download?build=$Version&os=win32-x64-archive"
$zipPath = Join-Path $OutputDir "VSCode-win32-x64-$Version.zip"

Write-Host ">>> Downloading VSCode Portable..." -ForegroundColor Yellow
Write-Host "  URL: $url"
Write-Host "  Save to: $zipPath"
Write-Host ""

try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
    $ProgressPreference = 'Continue'
    
    $fileSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "  DONE! Downloaded: $fileSize MB" -ForegroundColor Green
} catch {
    Write-Host "  FAILED: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternative: Download manually from:" -ForegroundColor Yellow
    Write-Host "  https://code.visualstudio.com/Download"
    Write-Host "  Choose 'Windows' → '.zip' (Portable)"
    exit 1
}

Write-Host ""
Write-Host ">>> Extracting..." -ForegroundColor Yellow

$extractDir = Join-Path $OutputDir "VSCode-win32-x64"
if (Test-Path $extractDir) {
    Remove-Item -Path $extractDir -Recurse -Force
}

try {
    Expand-Archive -Path $zipPath -DestinationPath $OutputDir -Force
    
    # VSCode zip thường extract ra thư mục có tên như "VSCode-win32-x64-1.96.0"
    # Tìm thư mục vừa extract
    $extracted = Get-ChildItem -Path $OutputDir -Directory | Where-Object { $_.Name -like "VSCode-win32-x64-*" } | Select-Object -First 1
    
    if ($extracted) {
        # Rename thành tên chuẩn
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Rename-Item -Path $extracted.FullName -NewName "VSCode-win32-x64"
    }
    
    Write-Host "  DONE! Extracted to: $extractDir" -ForegroundColor Green
} catch {
    Write-Host "  FAILED: $_" -ForegroundColor Red
    exit 1
}

# Tạo thư mục data cho portable mode
$dataDir = Join-Path $extractDir "data"
New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $dataDir "extensions") -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $dataDir "user-data") -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $dataDir "tmp") -ItemType Directory -Force | Out-Null

Write-Host "  Created data/ directory for portable mode" -ForegroundColor Green

# Copy VSIX vào thư mục extensions để install sẵn
$vsixSource = Join-Path $PSScriptRoot "..\..\extensions\vscode\build\continue-win32-x64-*.vsix"
$vsixFiles = Get-ChildItem -Path $vsixSource
if ($vsixFiles) {
    $vsixFile = $vsixFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $vsixDest = Join-Path $dataDir "extensions" $vsixFile.Name
    Copy-Item -Path $vsixFile.FullName -Destination $vsixDest -Force
    Write-Host "  Copied VSIX: $($vsixFile.Name)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: No VSIX found at $vsixSource" -ForegroundColor Yellow
    Write-Host "  Build VSIX first with: .\scripts\build-all.ps1" -ForegroundColor Yellow
}

# Copy scripts
$scriptsSource = Join-Path $PSScriptRoot "*.ps1"
$scriptsDest = Join-Path $OutputDir "scripts"
New-Item -Path $scriptsDest -ItemType Directory -Force | Out-Null
Copy-Item -Path $scriptsSource -Destination $scriptsDest -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ALL DONE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Copy entire 'deploy' folder to Jump Server (USB/SCP)"
Write-Host "  2. On Jump Server, run:"
Write-Host "     cd deploy\vscode-portable"
Write-Host "     .\scripts\install-offline.ps1"
Write-Host "  3. Run VSCode Portable:"
Write-Host "     .\VSCode-win32-x64\Code.exe"
