# package-deploy.ps1
# MASTER SCRIPT: Build VSIX + Download VSCode Portable + Package all-in-one
# Chạy trên máy CÓ INTERNET (máy build)
# Output: deploy\package\Continue-Offline-Deploy.zip — mang đi bất cứ đâu

param(
    [string]$OutputDir = (Join-Path $PSScriptRoot "package"),
    [string]$VscodeVersion = "stable"
)

$ErrorActionPreference = "Stop"
$ROOT = "E:\08-Sources\1.AI\continue"
$START = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Continue Offline Deployment Package" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build VSIX
Write-Host ">>> Step 1/4: Building VSIX..." -ForegroundColor Yellow
Push-Location $ROOT
try {
    & ".\scripts\build-all.ps1" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }
    
    $vsixFile = Get-ChildItem "extensions\vscode\build\*.vsix" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $vsixFile) { throw "No VSIX produced" }
    
    Write-Host "  [OK] VSIX: $($vsixFile.Name) ($([math]::Round($vsixFile.Length/1MB,1)) MB)" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] $_" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location

# Step 2: Download VSCode Portable
Write-Host ""
Write-Host ">>> Step 2/4: Downloading VSCode Portable..." -ForegroundColor Yellow
$vscodeDir = Join-Path $OutputDir "VSCode-win32-x64"
try {
    & ".\deploy\scripts\download-vscode-portable.ps1" -OutputDir $OutputDir -Version $VscodeVersion 2>&1 | Out-Null
    if (-not (Test-Path (Join-Path $vscodeDir "Code.exe"))) { throw "VSCode download/extract failed" }
    Write-Host "  [OK] VSCode Portable ready" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] $_" -ForegroundColor Red
    exit 1
}

# Step 3: Copy VSIX into package
Write-Host ""
Write-Host ">>> Step 3/4: Copying VSIX into package..." -ForegroundColor Yellow
$vsixDest = Join-Path $OutputDir "extensions"
New-Item -Path $vsixDest -ItemType Directory -Force | Out-Null
Copy-Item -Path $vsixFile.FullName -Destination (Join-Path $vsixDest $vsixFile.Name) -Force
Write-Host "  [OK] VSIX copied to package" -ForegroundColor Green

# Step 4: Copy scripts
Write-Host ""
Write-Host ">>> Step 4/4: Copying deployment scripts..." -ForegroundColor Yellow
$scriptsDest = Join-Path $OutputDir "scripts"
New-Item -Path $scriptsDest -ItemType Directory -Force | Out-Null
Copy-Item -Path ".\deploy\scripts\install-offline.ps1" -Destination $scriptsDest -Force
Copy-Item -Path ".\deploy\scripts\verify-offline.ps1" -Destination $scriptsDest -Force
Copy-Item -Path ".\deploy\README.md" -Destination $OutputDir -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Scripts copied" -ForegroundColor Green

# Summary
$TOTAL = (Get-Date) - $START
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  PACKAGE CREATED!" -ForegroundColor Green
Write-Host "  Time: $($TOTAL.TotalMinutes.ToString('0.0')) min" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Show package contents
Write-Host "Package contents ($OutputDir):" -ForegroundColor White
Get-ChildItem $OutputDir -Depth 0 | ForEach-Object {
    if ($_.PSIsContainer) {
        $size = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($size / 1MB, 0)
        Write-Host "  [DIR] $($_.Name) (~${sizeMB}MB)" -ForegroundColor Cyan
    } else {
        $sizeMB = [math]::Round($_.Length / 1MB, 1)
        Write-Host "  [FILE] $($_.Name) ($sizeMB MB)" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "To deploy on Jump Server:" -ForegroundColor White
Write-Host "  1. Copy '$OutputDir' to Jump Server (USB/SCP)" -ForegroundColor Gray
Write-Host "  2. On Jump Server, run:" -ForegroundColor Gray
Write-Host "     cd $OutputDir" -ForegroundColor Gray
Write-Host "     .\scripts\install-offline.ps1" -ForegroundColor Gray
Write-Host "  3. Run VSCode:" -ForegroundColor Gray
Write-Host "     .\VSCode-win32-x64\Code.exe" -ForegroundColor Gray
