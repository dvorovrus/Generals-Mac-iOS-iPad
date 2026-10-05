param(
    [string] $Workspace = "D:\project\test\Generals-iPad",
    [string] $AwsProfile = "generals-r2",
    [switch] $CommitAndPush
)

$ErrorActionPreference = "Stop"
$SourceRepo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$Publisher = Join-Path $SourceRepo "scripts\publish\windows\publish-gxmod-r2.ps1"
$ModsDir = Join-Path $Workspace "output\mods"

foreach ($required in @("CLOUDFLARE_ACCOUNT_ID", "R2_BUCKET", "R2_PUBLIC_BASE_URL")) {
    if (-not (Get-Item "Env:$required" -ErrorAction SilentlyContinue)) {
        $value = [Environment]::GetEnvironmentVariable($required, "User")
        if ($value) { Set-Item "Env:$required" $value }
    }
}

$env:AWS_PROFILE = $AwsProfile

$packages = @(
    @{ Path = (Join-Path $ModsDir "enhanced.gxmod"); Notes = "Zero Hour Enhanced v1.0 + 28/03/2024 patch." },
    @{ Path = (Join-Path $ModsDir "contra-x.gxmod"); Notes = "Contra X Beta 2 + Patch 1." }
)

foreach ($package in $packages) {
    if (-not (Test-Path $package.Path)) { throw "Missing package: $($package.Path)" }
    Write-Host ""
    Write-Host "Publishing $(Split-Path $package.Path -Leaf) to STABLE..." -ForegroundColor Cyan
    & $Publisher -PackagePath $package.Path -Channel stable -ReleaseNotes $package.Notes -MinHubVersion "0.1.0"
    if ($LASTEXITCODE -ne 0) { throw "Publish failed: $($package.Path)" }
}

if ($CommitAndPush) {
    git -C $SourceRepo add -- ios/hub/HubCatalog.json
    if (-not (git -C $SourceRepo diff --cached --quiet)) {
        git -C $SourceRepo commit -m "release(mods): publish stable Enhanced and Contra X [skip ci]"
        if ($LASTEXITCODE -ne 0) { throw "Catalog commit failed." }
        git -C $SourceRepo push
        if ($LASTEXITCODE -ne 0) { throw "Catalog push failed." }
    }
}

Write-Host ""
Write-Host "STABLE MODS PUBLISHED" -ForegroundColor Green
Write-Host "Enhanced and Contra X are now available to Generals Hub through the remote catalog."
