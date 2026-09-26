param(
    [switch]$NoBuild,
    [switch]$FullBuild
)

$ErrorActionPreference = "Stop"
$RepoName = "dvorovrus/Generals-Mac-iOS-iPad"
$Branch = "ios-clean"
$FastWorkflow = "build-ios-launcher-fast.yml"
$FullWorkflow = "build-ios-shell.yml"
$Artifact = "GeneralsXZH-launcher-unsigned"

$Workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
$ShellDir = Join-Path $Workspace "shell"
New-Item -ItemType Directory -Force -Path $ShellDir | Out-Null

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) was not found in PATH."
}

$Workflow = if ($FullBuild) { $FullWorkflow } else { $FastWorkflow }

if (-not $NoBuild) {
    $mode = if ($FullBuild) { "full iOS shell" } else { "fast launcher-only" }
    Write-Host "Starting GitHub $mode build..." -ForegroundColor Yellow

    $before = gh run list --repo $RepoName --workflow $Workflow --branch $Branch --limit 1 --json databaseId --jq '.[0].databaseId'
    gh workflow run $Workflow --repo $RepoName --ref $Branch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start GitHub workflow: $Workflow"
    }

    $runId = $null
    for ($i = 0; $i -lt 45 -and -not $runId; $i++) {
        Start-Sleep -Seconds 2
        $candidate = gh run list --repo $RepoName --workflow $Workflow --branch $Branch --limit 1 --json databaseId --jq '.[0].databaseId'
        if ($candidate -and $candidate -ne $before) {
            $runId = $candidate
        }
    }

    if (-not $runId) {
        throw "Could not find the newly started GitHub Actions run for $Workflow."
    }

    Write-Host "Watching GitHub run $runId..."
    gh run watch $runId --repo $RepoName --exit-status
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub workflow failed: $Workflow"
    }
}
else {
    $runId = gh run list --repo $RepoName --workflow $Workflow --branch $Branch --status success --limit 1 --json databaseId --jq '.[0].databaseId'

    if (-not $runId -and -not $FullBuild) {
        Write-Host "No successful fast launcher build found; falling back to latest full shell." -ForegroundColor DarkYellow
        $Workflow = $FullWorkflow
        $runId = gh run list --repo $RepoName --workflow $Workflow --branch $Branch --status success --limit 1 --json databaseId --jq '.[0].databaseId'
    }

    if (-not $runId) {
        throw "No successful iOS launcher/shell workflow run was found."
    }
}

$tmp = Join-Path $env:TEMP "generals-ipad-shell-$runId"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Host "Downloading artifact from run $runId ($Workflow)..."
gh run download $runId --repo $RepoName --name $Artifact --dir $tmp
if ($LASTEXITCODE -ne 0) {
    throw "Failed to download shell artifact."
}

$ipa = Get-ChildItem $tmp -Filter "*.ipa" -Recurse | Select-Object -First 1
if (-not $ipa) {
    throw "Downloaded artifact contains no IPA."
}

$target = Join-Path $ShellDir "GeneralsXZH-launcher-unsigned.ipa"
Copy-Item $ipa.FullName $target -Force
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

$ProjectVersion = "0.0.0"
$LauncherVersion = "0.0.0"
$VersionFile = Join-Path $Workspace "repo\ios\version.env"
if (Test-Path -LiteralPath $VersionFile) {
    foreach ($line in Get-Content -LiteralPath $VersionFile) {
        if ($line -match '^PROJECT_VERSION=(.+)) {
            $ProjectVersion = $Matches[1].Trim()
        }
        elseif ($line -match '^LAUNCHER_VERSION=(.+)) {
            $LauncherVersion = $Matches[1].Trim()
        }
    }
}

$versionedTarget = Join-Path $ShellDir "GeneralsZH-iPad-$ProjectVersion-Launcher-$LauncherVersion-unsigned.ipa"
Copy-Item $target $versionedTarget -Force

$size = [math]::Round((Get-Item $target).Length / 1MB, 1)
Write-Host ""
Write-Host "READY: $target ($size MB)" -ForegroundColor Green
Write-Host "ALIAS: $versionedTarget"
Write-Host "Source workflow: $Workflow / run $runId"
