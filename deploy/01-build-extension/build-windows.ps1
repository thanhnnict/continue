# =============================================================================
# build-windows.ps1 — Build Continue VSIX on Windows
#
# Requirements:
#   - Node.js 20.x installed directly (NOT via conda)
#     Download: https://nodejs.org/  or  nvm-windows: nvm install 20
#   - Git for Windows
#
# Usage (PowerShell):
#   .\build-windows.ps1 [-Target win32-x64] [-SkipPackages] [-OnlyExt]
# =============================================================================
param(
  [string]$Target = "win32-x64",
  [switch]$SkipPackages,
  [switch]$OnlyExt
)

$ErrorActionPreference = "Stop"

# --- Colors ---
function Write-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok      { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Write-Timer   { param($msg) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $msg" -ForegroundColor Blue }

$StartTime = Get-Date
$RepoRoot = Resolve-Path "$PSScriptRoot\..\.."

Write-Host ""
Write-Host "================================================" -ForegroundColor White
Write-Host "  Continue Extension Build — Windows"          -ForegroundColor White
Write-Host "  Target:  $Target"
Write-Host "  Repo:    $RepoRoot"
Write-Host "================================================" -ForegroundColor White
Write-Host ""

Set-Location $RepoRoot

# --- Verify Node.js ---
Write-Info "Checking Node.js version..."
try {
  $NodeVer = node --version 2>&1
  $NpmVer  = npm --version 2>&1
} catch {
  Write-Err "Node.js not found. Install Node.js 20.x from https://nodejs.org/"
}

$NodeMajor = ($NodeVer -replace 'v','').Split('.')[0]
if ($NodeMajor -ne "20") {
  Write-Warn "Node.js version is $NodeVer — expected v20.x"
  Write-Warn "Switch with nvm-windows: nvm use 20"
}
Write-Ok "Node: $NodeVer | npm: $NpmVer"

# --- Verify branch ---
$Branch = git branch --show-current 2>&1
Write-Info "Branch: $Branch"

# --- Build packages ---
if (-not $SkipPackages -and -not $OnlyExt) {
  Write-Timer "Building packages..."
  $packages = @("config-types","llm-info","fetch","openai-adapters","config-yaml","terminal-security")
  foreach ($pkg in $packages) {
    Write-Timer "  packages\$pkg"
    Push-Location "packages\$pkg"
    npm run build 2>&1 | Select-Object -Last 2 | Write-Host
    Pop-Location
  }
  Write-Ok "Packages built"
}

# --- Build core & gui ---
if (-not $OnlyExt) {
  Write-Timer "Building core..."
  Push-Location "core"; npm run build 2>&1 | Select-Object -Last 3 | Write-Host; Pop-Location
  Write-Ok "Core built"

  Write-Timer "Building gui..."
  Push-Location "gui"; npm run build 2>&1 | Select-Object -Last 3 | Write-Host; Pop-Location
  Write-Ok "GUI built"
}

# --- Build extension ---
Write-Timer "Packaging extension (target: $Target)..."
Push-Location "extensions\vscode"
npm run prepackage -- --target $Target 2>&1 | Select-Object -Last 5 | Write-Host
npm run package -- --target $Target 2>&1 | Select-Object -Last 5 | Write-Host
Pop-Location

# --- Result ---
$Vsix = Get-ChildItem "extensions\vscode\build\continue-${Target}-*.vsix" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $Vsix) { Write-Err "Build failed — no VSIX found" }

$Elapsed = (Get-Date) - $StartTime
$SizeMB = [math]::Round($Vsix.Length / 1MB, 1)

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  BUILD COMPLETE"                                -ForegroundColor Green
Write-Host "  Time:    $($Elapsed.Minutes)m $($Elapsed.Seconds)s"
Write-Host "  Output:  $($Vsix.Name)"
Write-Host "  Size:    ${SizeMB} MB"
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Install:"
Write-Host "  code --install-extension $($Vsix.FullName) --force"
Write-Host ""
