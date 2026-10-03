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
    [string]$ShellRunId,
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
  - Enhanced and Contra X use hybrid mode on Windows: shared GitHub engine shell + local full IPA packaging.
  - Use -ShellRunId with build/full only when you need a specific Shared iPad Engine Shell run.
  - Full GitHub Enhanced/Contra artifacts remain available through the explicit download command / -RunId.
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
    & git -C $RepoRoot fetch origin "+refs/heads/$branch`:refs/remotes/origin/$branch" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }

    $current = Get-CurrentBranch
    if ($current -eq $branch) {
        & git -C $RepoRoot diff --quiet
        $worktreeDirty = $LASTEXITCODE -ne 0
        & git -C $RepoRoot diff --cached --quiet
        $indexDirty = $LASTEXITCODE -ne 0
        if ($worktreeDirty -or $indexDirty) {
            Write-Host "Working tree has tracked local changes; fetched only, did not fast-forward." -ForegroundColor Yellow
        } else {
            & git -C $RepoRoot merge --ff-only "refs/remotes/origin/$branch" | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "git merge --ff-only origin/$branch failed" }
        }
    } else {
        Write-Host "Current branch: $current" -ForegroundColor DarkGray
        Write-Host "Variant branch: $branch (fetched; no automatic branch switch in update-only mode)" -ForegroundColor DarkGray
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

function Ensure-VariantBranch {
    param($Config)
    $branch = [string]$Config.branch
    if (-not $branch) { return }

    $current = Get-CurrentBranch
    if ($current -eq $branch) { return }

    & git -C $RepoRoot diff --quiet
    $worktreeDirty = $LASTEXITCODE -ne 0
    & git -C $RepoRoot diff --cached --quiet
    $indexDirty = $LASTEXITCODE -ne 0
    if ($worktreeDirty -or $indexDirty) {
        throw "Cannot switch from '$current' to '$branch': tracked local changes are present. Commit or stash them first."
    }

    & git -C $RepoRoot show-ref --verify --quiet "refs/heads/$branch"
    if ($LASTEXITCODE -eq 0) {
        & git -C $RepoRoot switch $branch | Out-Host
    } else {
        & git -C $RepoRoot show-ref --verify --quiet "refs/remotes/origin/$branch"
        if ($LASTEXITCODE -ne 0) {
            throw "Remote branch origin/$branch is not available. Run update first."
        }
        & git -C $RepoRoot switch -c $branch --track "origin/$branch" | Out-Host
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to switch repository to '$branch'."
    }
}

function Sync-IpadEngineShell {
    param([string]$SpecificRunId)
    Assert-Gh

    $shellConfig = $Catalog.internal.ipadEngineShell
    $workflow = [string]$shellConfig.workflow
    $branch = [string]$shellConfig.branch
    $artifact = [string]$shellConfig.artifact

    $id = $SpecificRunId
    if (-not $id) {
        $json = Invoke-Gh -GhArgs @(
            "run", "list",
            "--repo", $GitHubRepo,
            "--workflow", $workflow,
            "--branch", $branch,
            "--status", "success",
            "--limit", "1",
            "--json", "databaseId"
        ) | Out-String
        $rows = $json | ConvertFrom-Json
        if (-not $rows -or $rows.Count -eq 0) {
            throw "No successful Shared iPad Engine Shell run found on '$branch'."
        }
        $id = [string]$rows[0].databaseId
    }

    $run = (Invoke-Gh -GhArgs @(
        "run", "view", [string]$id,
        "--repo", $GitHubRepo,
        "--json", "conclusion,headBranch,headSha,workflowName"
    ) | Out-String) | ConvertFrom-Json
    if ([string]$run.conclusion -ne "success") {
        throw "Shared shell run $id is not successful (conclusion: $($run.conclusion))."
    }

    $shellDir = Join-Path $Workspace "shell"
    New-Item -ItemType Directory -Force -Path $shellDir | Out-Null
    $target = Join-Path $shellDir "GeneralsXZH-launcher-unsigned.ipa"
    $stamp = Join-Path $shellDir "GeneralsXZH-launcher-unsigned.run-id"
    $cachedRunId = if (Test-Path -LiteralPath $stamp) { (Get-Content -LiteralPath $stamp -Raw).Trim() } else { "" }

    if ((Test-Path -LiteralPath $target) -and $cachedRunId -eq [string]$id) {
        Write-Host "==> Reusing cached Shared iPad Engine Shell run $id" -ForegroundColor DarkGray
        return $target
    }

    $tmp = Join-Path $env:TEMP "generals-ipad-shared-shell-$id"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    Write-Host "==> Downloading Shared iPad Engine Shell (~20 MB) from run $id" -ForegroundColor Cyan
    Invoke-Gh -GhArgs @(
        "run", "download", [string]$id,
        "--repo", $GitHubRepo,
        "--name", $artifact,
        "--dir", $tmp
    ) | Out-Null

    $ipa = Get-ChildItem -LiteralPath $tmp -Recurse -File -Filter "*.ipa" | Select-Object -First 1
    if (-not $ipa) {
        throw "Shared shell artifact from run $id contains no IPA."
    }

    Copy-Item -LiteralPath $ipa.FullName -Destination $target -Force
    Set-Content -LiteralPath $stamp -Value ([string]$id) -NoNewline
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    $size = [math]::Round((Get-Item -LiteralPath $target).Length / 1MB, 1)
    Write-Host "SHELL READY: $target ($size MB, run $id, $($run.headSha))" -ForegroundColor Green
    return $target
}

function Invoke-HybridBuild {
    param($Config)
    Ensure-VariantBranch $Config
    Invoke-Update $Config
    $null = Sync-IpadEngineShell $ShellRunId
    return Invoke-LocalBuild $Config
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
    & pwsh -NoProfile -File $script | Out-Host
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
    if ([string]$Config.buildMode -eq "hybrid") {
        return Invoke-HybridBuild $Config
    }
    if ([string]$Config.buildMode -eq "local") {
        Ensure-VariantBranch $Config
        Invoke-Update $Config
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

    if ([string]$Config.buildMode -notin @("github", "hybrid")) {
        throw "This variant has no downloadable GitHub artifact."
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
        if ([string]$Config.buildMode -eq "hybrid" -and -not $RunId) {
            $local = Join-Path $LocalOutputRoot ([string]$Config.localOutput)
            if (-not (Test-Path -LiteralPath $local)) {
                throw "Local IPA not found: $local. Run 'full' or 'build' first, or pass -RunId to install a full GitHub backup artifact."
            }
            $InstallFile = $local
        } else {
            $InstallFile = Invoke-Download $Config $RunId
        }
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
    } elseif ([string]$Config.buildMode -in @("local", "hybrid")) {
        $path = Join-Path $LocalOutputRoot ([string]$Config.localOutput)
        if (Test-Path -LiteralPath $path) {
            Get-Item -LiteralPath $path | Select-Object FullName, Length, LastWriteTime
        } else {
            Write-Host "No local output yet: $path" -ForegroundColor Yellow
        }
        if ([string]$Config.buildMode -eq "hybrid") {
            $shell = Join-Path (Join-Path $Workspace "shell") "GeneralsXZH-launcher-unsigned.ipa"
            if (Test-Path -LiteralPath $shell) {
                Get-Item -LiteralPath $shell | Select-Object FullName, Length, LastWriteTime
            } else {
                Write-Host "No cached shared iPad engine shell yet." -ForegroundColor Yellow
            }
            Write-Host "Cloud backup workflow: $($Config.workflow)" -ForegroundColor DarkGray
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
