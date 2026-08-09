# install-offline.ps1
# Chạy trên Jump Server (air-gap, no-internet)
# Cài Continue extension vào VSCode Portable

param(
    [string]$VscodeDir = (Join-Path $PSScriptRoot "..\VSCode-win32-x64"),
    [string]$VsixPath = $null
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Install Continue Extension - OFFLINE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Kiểm tra VSCode Portable
$codeCmd = Join-Path $VscodeDir "bin\code.cmd"
if (-not (Test-Path $codeCmd)) {
    Write-Host "ERROR: VSCode Portable not found!" -ForegroundColor Red
    Write-Host "  Expected at: $codeCmd" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure you have:" -ForegroundColor Yellow
    Write-Host "  1. Downloaded VSCode Portable ZIP (run download-vscode-portable.ps1 on internet machine)"
    Write-Host "  2. Extracted to: $VscodeDir" -ForegroundColor Yellow
    Write-Host "  3. Created data/ directory inside VSCode-win32-x64/" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] VSCode Portable found at: $VscodeDir" -ForegroundColor Green

# 2. Tìm VSIX file
if (-not $VsixPath) {
    $vsixFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot "..") -Filter "*.vsix" -Recurse
    if (-not $vsixFiles) {
        $vsixFiles = Get-ChildItem -Path (Join-Path $VscodeDir "data\extensions") -Filter "*.vsix"
    }
    if ($vsixFiles) {
        $VsixPath = $vsixFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}

if (-not $VsixPath -or -not (Test-Path $VsixPath)) {
    Write-Host "ERROR: VSIX file not found!" -ForegroundColor Red
    Write-Host "  Place continue-win32-x64-*.vsix in the same folder as this script"
    Write-Host "  Or specify path: .\install-offline.ps1 -VsixPath D:\path\to\extension.vsix"
    exit 1
}
Write-Host "[OK] VSIX found: $VsixPath" -ForegroundColor Green

# 3. Kiểm tra version VSCode
$vscodeVersion = & $codeCmd --version 2>&1 | Select-Object -First 1
Write-Host "[OK] VSCode version: $vscodeVersion" -ForegroundColor Green

# 4. Uninstall extension cũ (nếu có)
Write-Host ""
Write-Host ">>> Checking for existing Continue installation..." -ForegroundColor Yellow
$existing = & $codeCmd --list-extensions 2>&1 | Select-String "continue"
if ($existing) {
    Write-Host "  Found existing: $existing" -ForegroundColor Yellow
    Write-Host "  Uninstalling..." -ForegroundColor Yellow
    & $codeCmd --uninstall-extension continue 2>&1 | Out-Null
    Write-Host "  Done." -ForegroundColor Green
}

# 5. Install VSIX
Write-Host ""
Write-Host ">>> Installing Continue extension..." -ForegroundColor Yellow
Write-Host "  This may take a moment..." -ForegroundColor Gray

$output = & $codeCmd --install-extension $VsixPath --force 2>&1
$exitCode = $LASTEXITCODE

# Check if extension is actually installed (ignore exit code due to deprecation warnings)
$installedCheck = & $codeCmd --list-extensions 2>&1 | Select-String "continue"
if ($installedCheck) {
    Write-Host "  SUCCESS! Extension installed." -ForegroundColor Green
    $exitCode = 0
} elseif ($exitCode -eq 0) {
    Write-Host "  SUCCESS! Extension installed." -ForegroundColor Green
} else {
    Write-Host "  FAILED (exit code: $exitCode)" -ForegroundColor Red
    Write-Host "  Output: $output"
    exit 1
}

# 6. Verify
Write-Host ""
Write-Host ">>> Verifying installation..." -ForegroundColor Yellow
$installed = & $codeCmd --list-extensions 2>&1 | Select-String "continue"
if ($installed) {
    Write-Host "  [OK] Extension verified: $installed" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Extension not found in list, but install reported success." -ForegroundColor Yellow
}

# 7. Kiểm tra native modules
Write-Host ""
Write-Host ">>> Checking native modules..." -ForegroundColor Yellow
$onnxDir = Join-Path $VscodeDir "data\extensions\continue-win32-x64-2.0.5\bin\napi-v3\win32-x64"
if (Test-Path $onnxDir) {
    $onnxFiles = Get-ChildItem $onnxDir
    Write-Host "  onnxruntime binaries: $($onnxFiles.Count) files" -ForegroundColor Green
} else {
    Write-Host "  Note: Native modules checked at runtime" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Run VSCode Portable:" -ForegroundColor White
Write-Host "  $VscodeDir\Code.exe" -ForegroundColor Cyan
Write-Host ""
Write-Host "After launching:" -ForegroundColor White
Write-Host "  1. Ctrl+Shift+P → 'Continue: Open config file'" -ForegroundColor Gray
Write-Host "  2. Configure your model endpoint (apiBase)" -ForegroundColor Gray
Write-Host "  3. Start coding with AI!" -ForegroundColor Gray

