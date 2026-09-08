# build-windows.ps1 - Build Continue VSCode Extension on Windows (Fresh or Incremental)
#
# ONE-COMMAND BUILD: handles everything from npm install to final VSIX.
# Safe to run on fresh environment or after clean.
#
# Requirements (install once):
#   - Miniconda/Anaconda with env "node20":
#       conda create -n node20 -y nodejs=20
#   - Git for Windows
#
# Usage (run from repo root OR deploy/01-build-extension/):
#   .\deploy\01-build-extension\build-windows.ps1
#   .\deploy\01-build-extension\build-windows.ps1 -SkipPackages  # skip if packages already built
#   .\deploy\01-build-extension\build-windows.ps1 -OnlyExt       # prepackage+vsce only (~15s)
#   .\deploy\01-build-extension\build-windows.ps1 -ShowOutput    # verbose npm output
#   .\deploy\01-build-extension\build-windows.ps1 -Registry "https://registry.npmjs.org/"
param(
    [string]$Target     = "win32-x64",
    [switch]$SkipPackages,
    [switch]$OnlyExt,
    [switch]$ShowOutput,
    [string]$Registry   = ""
)

$ErrorActionPreference = "Stop"
$StartTime = Get-Date
$RepoRoot  = Resolve-Path "$PSScriptRoot\..\.."
$ExtDir    = Join-Path $RepoRoot "extensions\vscode"

function Write-Info { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Write-Step { param($msg) Write-Host ""; Write-Host "==> $msg" -ForegroundColor Magenta }
function Get-Elapsed { "$([int]((Get-Date) - $StartTime).TotalSeconds)s" }

function Invoke-Cmd {
    param([string]$CmdStr, [string]$WorkDir = $RepoRoot, [string]$Label = "", [int]$Tail = 5)
    if ($Label -eq "") { $Label = $CmdStr.Split(" ")[0] }
    Write-Info "[$Label] $CmdStr"
    Push-Location $WorkDir
    try {
        if ($ShowOutput) { Invoke-Expression $CmdStr }
        else {
            $out = Invoke-Expression "$CmdStr 2>&1"
            $out | Select-Object -Last $Tail | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        }
        if ($LASTEXITCODE -ne 0) { throw "Exit $LASTEXITCODE" }
    } finally { Pop-Location }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor White
Write-Host "  Continue Extension Build - Windows"
Write-Host "  Target:  $Target"
Write-Host "  Repo:    $RepoRoot"
Write-Host "  Started: $($StartTime.ToString('HH:mm:ss'))"
Write-Host "================================================" -ForegroundColor White

# --- Step 1: Resolve Node.js runtime ---
Write-Step "Resolving Node.js runtime..."
$UseCondaNode = $false
$condaEnvList = (conda env list 2>&1) | Out-String
if ($condaEnvList -match "node20") {
    $testVer = conda run -n node20 node --version 2>&1
    if ($LASTEXITCODE -eq 0 -and "$testVer" -match "^v20") {
        $UseCondaNode = $true
        Write-Ok "Using conda env node20: $testVer"
    }
}
if (-not $UseCondaNode) {
    $sysVer = node --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Node.js not found. Run: conda create -n node20 -y nodejs=20"
    }
    $sysMajor = ($sysVer -replace 'v','').Split('.')[0]
    if ($sysMajor -ne "20") { Write-Warn "System Node $sysVer - expected v20.x" }
    Write-Ok "Using system Node: $sysVer"
}

function npm-run {
    param([string]$NpmCmd, [string]$WorkDir, [string]$Label)
    if ($UseCondaNode) { Invoke-Cmd "conda run -n node20 npm $NpmCmd" $WorkDir $Label }
    else               { Invoke-Cmd "npm $NpmCmd" $WorkDir $Label }
}
function npx-run {
    param([string]$NpxCmd, [string]$WorkDir, [string]$Label)
    if ($UseCondaNode) { Invoke-Cmd "conda run -n node20 npx $NpxCmd" $WorkDir $Label }
    else               { Invoke-Cmd "npx $NpxCmd" $WorkDir $Label }
}
function node-run {
    param([string]$NodeCmd, [string]$WorkDir, [string]$Label, [string]$EnvVar = "")
    $saved = if ($EnvVar -ne "") { $EnvVar.Split("=",2) } else { $null }
    if ($saved) { [System.Environment]::SetEnvironmentVariable($saved[0], $saved[1]) }
    try {
        if ($UseCondaNode) { Invoke-Cmd "conda run -n node20 node $NodeCmd" $WorkDir $Label 10 }
        else               { Invoke-Cmd "node $NodeCmd" $WorkDir $Label 10 }
    } finally {
        if ($saved) { [System.Environment]::SetEnvironmentVariable($saved[0], $null) }
    }
}

# --- Step 2: Detect npm registry ---
Write-Step "Detecting npm registry..."
$NexusUrl  = "http://localhost:7081/repository/npm-group/"
$PublicUrl = "https://registry.npmjs.org/"
if ($Registry -ne "") {
    $NpmRegistry = $Registry; Write-Ok "Using -Registry: $NpmRegistry"
} elseif ($env:NPM_REGISTRY) {
    $NpmRegistry = $env:NPM_REGISTRY; Write-Ok "Using env NPM_REGISTRY: $NpmRegistry"
} else {
    try {
        Invoke-WebRequest -Uri $NexusUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop | Out-Null
        $NpmRegistry = $NexusUrl; Write-Ok "Nexus available: $NpmRegistry"
    } catch {
        $NpmRegistry = $PublicUrl; Write-Warn "Nexus not available - using public: $NpmRegistry"
    }
}

function npm-install {
    param([string]$WorkDir, [string]$ExtraArgs = "", [string]$Label = "npm install")
    $cmd = "npm install --registry `"$NpmRegistry`" $ExtraArgs".Trim()
    Write-Info "[$Label] $cmd"
    Push-Location $WorkDir
    try {
        $out = Invoke-Expression "$cmd 2>&1"
        if ($ShowOutput) { $out | Write-Host }
        else { $out | Select-Object -Last 4 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray } }
        # ERESOLVE is a warning, not fatal error
        $realErr = $out | Where-Object { $_ -match "^npm error " -and $_ -notmatch "ERESOLVE" }
        if ($LASTEXITCODE -ne 0 -and $realErr) { throw "npm install failed: $($realErr -join '; ')" }
        Write-Ok "$Label done"
    } finally { Pop-Location }
}

# --- Step 3: npm install all (skip if node_modules already present) ---
if (-not $OnlyExt) {
    Write-Step "npm install packages + core + gui... $(Get-Elapsed)"
    $installDirs = @(
        "packages\config-types", "packages\terminal-security",
        "packages\llm-info", "packages\fetch",
        "packages\openai-adapters", "packages\config-yaml",
        "core", "gui"
    )
    foreach ($d in $installDirs) {
        $nm = Join-Path $RepoRoot "$d\node_modules"
        if (Test-Path $nm) { Write-Info "[$d] node_modules exists - skip" }
        else { npm-install -WorkDir (Join-Path $RepoRoot $d) -Label $d }
    }
}

# extensions/vscode always
$extNm = Join-Path $ExtDir "node_modules"
if (Test-Path $extNm) { Write-Info "[extensions/vscode] node_modules exists - skip" }
else { npm-install -WorkDir $ExtDir -Label "extensions/vscode" }

# --- Step 4: Fix native binaries ---
Write-Step "Verifying native binaries... $(Get-Elapsed)"

# @vscode/ripgrep - postinstall often skipped via Nexus proxy
$rgTarget = Join-Path $ExtDir "node_modules\@vscode\ripgrep\bin\rg.exe"
$rgSource  = Join-Path $ExtDir "node_modules\@vscode\ripgrep-win32-x64\bin\rg.exe"
if (-not (Test-Path $rgTarget)) {
    if (-not (Test-Path $rgSource)) {
        Write-Info "Installing @vscode/ripgrep-win32-x64..."
        npm-install -WorkDir $ExtDir -ExtraArgs "@vscode/ripgrep-win32-x64 --no-save" -Label "@vscode/ripgrep-win32-x64"
    }
    if (Test-Path $rgSource) {
        $binDir = Split-Path $rgTarget -Parent
        if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
        Copy-Item $rgSource $rgTarget -Force
        Write-Ok "Copied rg.exe -> @vscode/ripgrep/bin/"
    } else { Write-Err "Cannot find rg.exe after install" }
} else { Write-Ok "rg.exe present" }

# @lancedb
$lancedb = Join-Path $ExtDir "node_modules\@lancedb\vectordb-win32-x64-msvc\index.node"
if (-not (Test-Path $lancedb)) {
    npm-install -WorkDir $ExtDir -ExtraArgs "@lancedb/vectordb-win32-x64-msvc --no-save" -Label "@lancedb"
}
if (Test-Path $lancedb) { Write-Ok "lancedb binary present" }
else { Write-Err "lancedb binary missing" }

# --- Step 5: Build packages (parallel) ---
if (-not $SkipPackages -and -not $OnlyExt) {
    Write-Step "Building packages (parallel)... $(Get-Elapsed)"
    node-run -NodeCmd "`"$(Join-Path $RepoRoot 'scripts\build-packages.js')`"" -WorkDir $RepoRoot -Label "build-packages"
    Write-Ok "Packages built  $(Get-Elapsed)"
}

# --- Step 6: Build core ---
if (-not $OnlyExt) {
    Write-Step "Building core... $(Get-Elapsed)"
    npm-run -NpmCmd "run build" -WorkDir (Join-Path $RepoRoot "core") -Label "core"
    Write-Ok "Core built  $(Get-Elapsed)"

    Write-Step "Building GUI... $(Get-Elapsed)"
    npm-run -NpmCmd "run build" -WorkDir (Join-Path $RepoRoot "gui") -Label "gui"
    Write-Ok "GUI built  $(Get-Elapsed)"
}

# --- Step 7: Prepackage ---
Write-Step "Prepackage... $(Get-Elapsed)"

# Detect stale out/ (out/node_modules/@vscode/ripgrep/bin/rg.exe missing = stale)
$outDir = Join-Path $ExtDir "out"
if (Test-Path $outDir) {
    $outRg = Join-Path $outDir "node_modules\@vscode\ripgrep\bin\rg.exe"
    if (-not (Test-Path $outRg)) {
        Write-Warn "Stale out/ (missing rg.exe) - cleaning..."
        Remove-Item -Recurse -Force $outDir
        Write-Ok "Removed stale out/"
    }
}

if (-not (Test-Path (Join-Path $ExtDir "build"))) {
    New-Item -ItemType Directory -Path (Join-Path $ExtDir "build") -Force | Out-Null
}
node-run -NodeCmd "scripts/prepackage.js --target $Target" -WorkDir $ExtDir -Label "prepackage" -EnvVar "SKIP_INSTALLS=true"
Write-Ok "Prepackage done  $(Get-Elapsed)"

# --- Step 8: Package VSIX ---
Write-Step "Packaging VSIX... $(Get-Elapsed)"
npx-run -NpxCmd "@vscode/vsce package --out ./build --no-dependencies --target $Target" -WorkDir $ExtDir -Label "vsce"

# --- Result ---
$vsix = Get-ChildItem (Join-Path $ExtDir "build\continue-${Target}-*.vsix") `
    -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $vsix) { Write-Err "Build failed - no VSIX found in extensions\vscode\build\" }

$elapsed = (Get-Date) - $StartTime
$sizeMB  = [math]::Round($vsix.Length / 1MB, 1)

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  BUILD COMPLETE  $($elapsed.Minutes)m$($elapsed.Seconds)s" -ForegroundColor Green
Write-Host "  $($vsix.Name)"
Write-Host "  $sizeMB MB"
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Install command:" -ForegroundColor White
Write-Host "  code --install-extension '$($vsix.FullName)' --force" -ForegroundColor Gray
Write-Host ""
