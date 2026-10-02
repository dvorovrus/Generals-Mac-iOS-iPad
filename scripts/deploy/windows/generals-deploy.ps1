#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("help", "init", "list", "status", "update", "build", "download", "install", "full", "logs")]
    [string]$Command = "help",

    [ValidateSet("ipad", "macos")]
    [string]$Platform,

    [string]$Variant,
    [string]$RunId,
    [string]$File,
    [switch]$Wait,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..\..")).Path
$Workspace = Split-Path -Parent $RepoRoot
$CatalogPath = Join-Path $DeployDir "catalog.json"
$Catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
$GitHubRepo = $Catalog.repository
$ArtifactRoot = Join-Path $Workspace "artifacts"
$LocalOutputRoot = Join-Path $Workspace "output"
$IpadLogs = Join-Path $LocalOutputRoot "logs"

function Show-Help {
@"
Generals Apple deployment CLI

Usage:
  .\scripts\deploy\windows\generals-deploy.ps1 init
  .\scripts\deploy\windows\generals-deploy.ps1 list
  .\scripts\deploy\windows\generals-deploy.ps1 status   -Platform ipad  -Variant contra
  .\scripts\deploy\windows\generals-deploy.ps1 update   -Platform ipad  -Variant contra
  .\scripts\deploy\windows\generals-deploy.ps1 build    -Platform ipad  -Variant contra -Wait
  .\scripts\deploy\windows\generals-deploy.ps1 download -Platform ipad  -Variant contra
  .\scripts\deploy\windows\generals-deploy.ps1 install  -Platform ipad  -Variant contra
  .\scripts\deploy\windows\generals-deploy.ps1 full     -Platform ipad  -Variant contra
  .\scripts\deploy\windows\generals-deploy.ps1 logs     -Platform ipad  -Variant contra

Notes:
  - Cloud builds use GitHub CLI (gh).
  - Enhanced/All-in-One use the existing local ios-clean packagers.
  - iPad signing remains in Sideloadly; this tool prepares the exact IPA and opens it.
  - macOS installation is performed on the Mac with scripts/deploy/macos/generals-deploy.sh.
"@
}

function Get-VariantConfig {
    param([string]$P, [string]$V)
    if (-not $P -or -not $V) {
        throw "-Platform and -Variant are required for '$Command'."
    }
    $platformNode = $Catalog.variants.PSObject.Properties[$P]
    if (-not $platformNode) {
        throw "Unknown platform: $P"
    }
    $variantNode = $platformNode.Value.PSObject.Properties[$V]
    if (-not $variantNode) {
        throw "Unknown variant '$V' for platform '$P'. Use 'list'."
    }
    return $variantNode.Value
}

function Assert-Gh {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) is required. Install it and run: gh auth login"
    }
    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI is not authenticated. Run: gh auth login"
    }
}

function Invoke-Gh {
    param([Parameter(Mandatory)][string[]]$GhArgs)
    $result = & gh @GhArgs
    if ($LASTEXITCODE -ne 0) {
        throw "gh failed: gh $($GhArgs -join ' ')"
    }
    return $result
}

function Get-CurrentBranch {
    return ((& git -C $RepoRoot rev-parse --abbrev-ref HEAD) | Select-Object -First 1).Trim()
}

function Invoke-Update {
    param($Config)
    $branch = [string]$Config.branch
    if (-not $branch) {
        Write-Host "No source branch for this variant." -ForegroundColor Yellow
        return
    }

    Write-Host "==> Fetching origin/$branch" -ForegroundColor Cyan
    & git -C $RepoRoot fetch origin $branch
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }

    $current = Get-CurrentBranch
    if ($current -eq $branch) {
        $dirty = & git -C $RepoRoot status --porcelain
        if ($dirty) {
            Write-Host "Working tree has local changes; fetched only, did not pull." -ForegroundColor Yellow
        } else {
            & git -C $RepoRoot pull --ff-only origin $branch
            if ($LASTEXITCODE -ne 0) { throw "git pull --ff-only failed" }
        }
    } else {
        Write-Host "Current branch: $current" -ForegroundColor DarkGray
        Write-Host "Variant branch: $branch (fetched; no automatic branch switch)" -ForegroundColor DarkGray
    }
}

function Get-LatestRunId {
    param($Config, [switch]$Successful)
    Assert-Gh
    $args = @(
        "run", "list",
        "--repo", $GitHubRepo,
        "--workflow", [string]$Config.workflow,
        "--branch", [string]$Config.branch,
        "--limit", "1",
        "--json", "databaseId"
    )
    if ($Successful) {
        $args += @("--status", "success")
    }
    $json = Invoke-Gh -GhArgs $args | Out-String
    $rows = $json | ConvertFrom-Json
    if (-not $rows -or $rows.Count -eq 0) {
        throw "No matching workflow run found."
    }
    return [string]$rows[0].databaseId
}

function Invoke-CloudBuild {
    param($Config, [bool]$ShouldWait)
    Assert-Gh
    Write-Host "==> Triggering $($Config.workflow) on $($Config.branch)" -ForegroundColor Cyan
    $out = Invoke-Gh -GhArgs @(
        "workflow", "run", [string]$Config.workflow,
        "--repo", $GitHubRepo,
        "--ref", [string]$Config.branch
    )
    $text = ($out | Out-String).Trim()
    $id = $null
    if ($text -match "/actions/runs/(\d+)") {
        $id = $Matches[1]
    }
    if (-not $id) {
        Start-Sleep -Seconds 3
        $id = Get-LatestRunId $Config
    }
    Write-Host "Run: $id"

    if ($ShouldWait) {
        & gh run watch $id --repo $GitHubRepo --exit-status
        if ($LASTEXITCODE -ne 0) {
            throw "Build run $id failed."
        }
    }
    return $id
}

function Invoke-LocalBuild {
    param($Config)
    $branch = [string]$Config.branch
    $current = Get-CurrentBranch
    if ($current -ne $branch) {
        throw "Local packaging for this variant requires branch '$branch'. Current branch is '$current'. Switch/pull it first."
    }

    $scriptRel = [string]$Config.localFallbackScript
    $script = Join-Path $RepoRoot $scriptRel
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Local packager not found on this branch: $scriptRel"
    }

    Write-Host "==> Local package: $scriptRel" -ForegroundColor Cyan
    & pwsh -NoProfile -File $script
    if ($LASTEXITCODE -ne 0) {
        throw "Local packaging failed."
    }

    $output = Join-Path $LocalOutputRoot ([string]$Config.localOutput)
    if (-not (Test-Path -LiteralPath $output)) {
        throw "Build completed but expected output is missing: $output"
    }
    return $output
}

function Invoke-Build {
    param($Config, [bool]$ShouldWait)
    if ([string]$Config.buildMode -eq "github") {
        return Invoke-CloudBuild $Config $ShouldWait
    }
    if ([string]$Config.buildMode -eq "local") {
        return Invoke-LocalBuild $Config
    }
    throw "This variant has no build path. $($Config.note)"
}

function Find-ArtifactFile {
    param([string]$Dir, $Config)
    $wanted = [string]$Config.artifactFile
    if ($wanted) {
        $exact = Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $wanted } |
            Select-Object -First 1
        if ($exact) { return $exact.FullName }
    }

    $fallback = Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".ipa", ".tar", ".zip") } |
        Select-Object -First 1
    if ($fallback) { return $fallback.FullName }

    throw "Downloaded artifact contains no expected installable file."
}

function Invoke-Download {
    param($Config, [string]$SpecificRunId)

    if ([string]$Config.buildMode -eq "local") {
        $local = Join-Path $LocalOutputRoot ([string]$Config.localOutput)
        if (-not (Test-Path -LiteralPath $local)) {
            throw "Local output not found: $local. Run 'build' first."
        }
        return $local
    }

    if ([string]$Config.buildMode -ne "github") {
        throw "This variant has no downloadable artifact."
    }

    Assert-Gh
    $id = if ($SpecificRunId) { $SpecificRunId } else { Get-LatestRunId $Config -Successful }
    $dest = Join-Path $ArtifactRoot "$Platform\$Variant\$id"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    $existing = Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "==> Downloading artifact $($Config.artifact) from run $id" -ForegroundColor Cyan
        Invoke-Gh -GhArgs @(
            "run", "download", $id,
            "--repo", $GitHubRepo,
            "--name", [string]$Config.artifact,
            "--dir", $dest
        ) | Out-Null
    }

    $filePath = Find-ArtifactFile $dest $Config
    Write-Host "READY: $filePath" -ForegroundColor Green
    return $filePath
}

function Find-Sideloadly {
    $candidates = @()
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles "Sideloadly\Sideloadly.exe") }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} "Sideloadly\Sideloadly.exe") }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Sideloadly\Sideloadly.exe")
        $candidates += (Join-Path $env:LOCALAPPDATA "Programs\Sideloadly\Sideloadly.exe")
    }
    $cmd = Get-Command Sideloadly.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates = @($cmd.Source) + $candidates }

    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function Invoke-IpadInstall {
    param($Config, [string]$InstallFile)

    if (-not [bool]$Config.installReady) {
        throw "Variant '$Variant' is not install-ready: $($Config.note)"
    }

    if (-not $InstallFile) {
        $InstallFile = Invoke-Download $Config $RunId
    }
    $InstallFile = (Resolve-Path -LiteralPath $InstallFile).Path
    if ([IO.Path]::GetExtension($InstallFile).ToLowerInvariant() -ne ".ipa") {
        throw "Expected an IPA for iPad install, got: $InstallFile"
    }

    Write-Host ""
    Write-Host "IPA READY FOR SIDELOADLY" -ForegroundColor Green
    Write-Host $InstallFile
    Write-Host ""
    Write-Host "1. Connect the iPad and trust this computer."
    Write-Host "2. Drag this exact IPA into Sideloadly."
    Write-Host "3. Select the iPad / Apple ID and press Start."
    Write-Host "4. Trust the developer profile / enable Developer Mode if iOS asks."

    if (-not $NoLaunch) {
        Start-Process explorer.exe -ArgumentList "/select,`"$InstallFile`""
        $sideloadly = Find-Sideloadly
        if ($sideloadly) {
            Start-Process $sideloadly
            Write-Host "Sideloadly launched: $sideloadly" -ForegroundColor DarkGray
        } else {
            Write-Host "Sideloadly executable was not auto-detected; open it manually." -ForegroundColor Yellow
        }
    }
}

function Show-Status {
    param($Config)
    Write-Host "$Platform/$Variant — $($Config.title)"
    Write-Host "Status: $($Config.status)"
    Write-Host "Branch: $($Config.branch)"
    Write-Host "Build mode: $($Config.buildMode)"

    if ([string]$Config.buildMode -eq "github") {
        Assert-Gh
        Invoke-Gh -GhArgs @(
            "run", "list",
            "--repo", $GitHubRepo,
            "--workflow", [string]$Config.workflow,
            "--branch", [string]$Config.branch,
            "--limit", "5"
        )
    } elseif ([string]$Config.buildMode -eq "local") {
        $path = Join-Path $LocalOutputRoot ([string]$Config.localOutput)
        if (Test-Path -LiteralPath $path) {
            Get-Item -LiteralPath $path | Select-Object FullName, Length, LastWriteTime
        } else {
            Write-Host "No local output yet: $path" -ForegroundColor Yellow
        }
    } else {
        Write-Host $Config.note -ForegroundColor Yellow
    }
}

function Show-List {
    $rows = @()
    foreach ($p in $Catalog.variants.PSObject.Properties) {
        foreach ($v in $p.Value.PSObject.Properties) {
            $cfg = $v.Value
            $rows += [pscustomobject]@{
                Platform = $p.Name
                Variant = $v.Name
                Status = $cfg.status
                Build = $cfg.buildMode
                Branch = $cfg.branch
                InstallReady = $cfg.installReady
            }
        }
    }
    $rows | Sort-Object Platform, Variant | Format-Table -AutoSize
}

function Show-Logs {
    param($Config)
    if ($Platform -eq "ipad") {
        New-Item -ItemType Directory -Force -Path $IpadLogs | Out-Null
        Write-Host "Canonical iPad copied-log folder:"
        Write-Host $IpadLogs -ForegroundColor Green
        if (-not $NoLaunch) { Start-Process explorer.exe $IpadLogs }
        return
    }

    Write-Host "macOS log path: $($Config.logPath)"
    Write-Host "Run the macOS deployment CLI on the Mac for direct access."
}

if ($Command -eq "help") {
    Show-Help
    exit 0
}
if ($Command -eq "init") {
    & python (Join-Path $DeployDir "init-workspace.py")
    if ($LASTEXITCODE -ne 0) { throw "workspace initialization failed" }
    exit 0
}
if ($Command -eq "list") {
    Show-List
    exit 0
}

$config = Get-VariantConfig $Platform $Variant

switch ($Command) {
    "status" {
        Show-Status $config
    }
    "update" {
        Invoke-Update $config
    }
    "build" {
        $result = Invoke-Build $config ([bool]$Wait)
        Write-Host "Build result: $result" -ForegroundColor Green
    }
    "download" {
        $path = Invoke-Download $config $RunId
        Write-Host $path
    }
    "install" {
        if ($Platform -eq "ipad") {
            Invoke-IpadInstall $config $File
        } else {
            throw "macOS app installation must be run on the Mac: ./scripts/deploy/macos/generals-deploy.sh install macos $Variant"
        }
    }
    "logs" {
        Show-Logs $config
    }
    "full" {
        Invoke-Update $config

        if ($Platform -eq "macos") {
            throw "Run the full macOS flow on the Mac: ./scripts/deploy/macos/generals-deploy.sh full macos $Variant"
        }

        if (-not [bool]$config.installReady) {
            throw "Variant '$Variant' is not install-ready: $($config.note)"
        }

        if ([string]$config.buildMode -eq "github") {
            $builtRun = Invoke-Build $config $true
            $ipa = Invoke-Download $config ([string]$builtRun)
            Invoke-IpadInstall $config $ipa
        } else {
            $ipa = Invoke-Build $config $true
            Invoke-IpadInstall $config ([string]$ipa)
        }
    }
    default {
        Show-Help
    }
}
