# verify-offline.ps1
# Kiểm tra cài đặt trên Jump Server (air-gap)
# Chạy sau khi đã install extension

param(
    [string]$VscodeDir = (Join-Path $PSScriptRoot "..\VSCode-win32-x64")
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Verify Continue Installation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$allOk = $true

# 1. VSCode Portable
$codeExe = Join-Path $VscodeDir "Code.exe"
$codeCmd = Join-Path $VscodeDir "bin\code.cmd"
$dataDir = Join-Path $VscodeDir "data"

Write-Host "1. VSCode Portable:" -ForegroundColor Yellow
if (Test-Path $codeExe) { Write-Host "   [OK] Code.exe exists" -ForegroundColor Green }
else { Write-Host "   [FAIL] Code.exe missing" -ForegroundColor Red; $allOk = $false }

if (Test-Path $dataDir) { Write-Host "   [OK] data/ directory exists (portable mode)" -ForegroundColor Green }
else { Write-Host "   [FAIL] data/ missing - not portable mode" -ForegroundColor Red; $allOk = $false }

# 2. Extension installed
Write-Host ""
Write-Host "2. Continue Extension:" -ForegroundColor Yellow
if (Test-Path $codeCmd) {
    $extensions = & $codeCmd --list-extensions 2>&1
    $continueExt = $extensions | Select-String "continue"
    if ($continueExt) {
        Write-Host "   [OK] Installed: $continueExt" -ForegroundColor Green
    } else {
        Write-Host "   [FAIL] Not installed" -ForegroundColor Red
        Write-Host "   Run: .\scripts\install-offline.ps1" -ForegroundColor Yellow
        $allOk = $false
    }
}

# 3. VSIX file in package
Write-Host ""
Write-Host "3. VSIX Package:" -ForegroundColor Yellow
$vsixFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot "..") -Filter "*.vsix" -Recurse
if ($vsixFiles) {
    foreach ($f in $vsixFiles) {
        $size = [math]::Round($f.Length / 1MB, 1)
        Write-Host "   [OK] $($f.Name) ($size MB)" -ForegroundColor Green
    }
} else {
    Write-Host "   [WARN] No VSIX file found (may be installed already)" -ForegroundColor Yellow
}

# 4. Scripts
Write-Host ""
Write-Host "4. Deployment Scripts:" -ForegroundColor Yellow
$scripts = @("install-offline.ps1", "download-vscode-portable.ps1")
foreach ($s in $scripts) {
    $path = Join-Path $PSScriptRoot $s
    if (Test-Path $path) { Write-Host "   [OK] $s" -ForegroundColor Green }
    else { Write-Host "   [WARN] $s not found" -ForegroundColor Yellow }
}

# 5. Disk space
Write-Host ""
Write-Host "5. Disk Space:" -ForegroundColor Yellow
$vscodeSize = (Get-ChildItem -Path $VscodeDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
$vscodeSizeMB = [math]::Round($vscodeSize / 1MB, 0)
Write-Host "   VSCode Portable: ~${vscodeSizeMB}MB" -ForegroundColor Green

$drive = (Get-Item $VscodeDir).PSDrive
$freeGB = [math]::Round($drive.Free / 1GB, 1)
Write-Host "   Free space: ${freeGB}GB" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($allOk) {
    Write-Host "  VERIFICATION: ALL CHECKS PASSED!" -ForegroundColor Green
    Write-Host "  Ready to use on Jump Server!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Launch: $VscodeDir\Code.exe" -ForegroundColor White
} else {
    Write-Host "  VERIFICATION: SOME CHECKS FAILED!" -ForegroundColor Red
    Write-Host "  Review the [FAIL] items above." -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
