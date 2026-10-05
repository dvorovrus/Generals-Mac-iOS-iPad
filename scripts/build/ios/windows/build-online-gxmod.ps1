param(
    [ValidateSet("stable", "beta")]
    [string] $Channel = "stable",
    [string] $Version = "1.04+GO-100126_QFE6",
    [string] $MinHubVersion = "0.1.0"
)

$ErrorActionPreference = "Stop"
$SourceRepo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$SourceParent = Split-Path $SourceRepo -Parent
if ((Split-Path $SourceParent -Leaf) -eq "worktrees") {
    $Workspace = Split-Path $SourceParent -Parent
} else {
    $Workspace = $SourceParent
}

$Builder = Join-Path $SourceRepo "scripts\build\ios\build-gxmod.py"
$SyncOnlineData = Join-Path $SourceRepo "scripts\build\common\sync-generals-online-data.py"
$BaseIpa = Join-Path $Workspace "input\GeneralsZH-FULL-unsigned.ipa"
$OnlineDataStage = Join-Path $Workspace "artifacts\gamedata\online\official"
$OnlineDataCache = Join-Path $Workspace "cache\generals-online-official"
$OutputDir = Join-Path $Workspace "output\mods"
$Output = Join-Path $OutputDir "online.gxmod"
$Python = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }

foreach ($required in @($Builder, $SyncOnlineData, $BaseIpa)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required input not found: $required" }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Write-Host "Syncing official Generals Online parity data..." -ForegroundColor Cyan
& $Python $SyncOnlineData --dest $OnlineDataStage --cache-dir $OnlineDataCache --expected-version 100126_QFE6 --expected-seed 0x808CB29E
if ($LASTEXITCODE -ne 0) { throw "Generals Online data sync/parity verification failed." }

Write-Host "Building downloadable Zero Hour + Online base package..." -ForegroundColor Cyan
& $Python $Builder --variant online --base-ipa $BaseIpa --online-data $OnlineDataStage --channel $Channel --version $Version --min-hub-version $MinHubVersion --output $Output
if ($LASTEXITCODE -ne 0) { throw "Online .gxmod build failed." }

Write-Host ""
Write-Host "READY: $Output" -ForegroundColor Green
Write-Host "This package contains the shared base GameData used by Online, Enhanced and Contra X."
