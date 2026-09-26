param(
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$RepoName = "dvorovrus/Generals-Mac-iOS-iPad"
$Branch = "ios-clean"
$Workflow = "build-ios-shell.yml"
$Artifact = "GeneralsXZH-launcher-unsigned"

$Workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
$ShellDir = Join-Path $Workspace "shell"
New-Item -ItemType Directory -Force -Path $ShellDir | Out-Null

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) was not found in PATH."
}

if (-not $NoBuild) {
    Write-Host "Starting GitHub iOS shell build..." -ForegroundColor Yellow
    $before = gh run list --repo $RepoName --workflow $Workflow --branch $Branch --limit 1 --json databaseId --jq '.[0].databaseId'
    gh workflow run $Workflow --repo $RepoName --ref $Branch

    $runId = $null
    for ($i = 0; $i -lt 30 -and -not $runId; $i++) {
        Start-Sleep -Seconds 2
        $candidate = gh run list --repo $RepoName --workflow $Workflow --branch $Branch --limit 1 --json databaseId --jq '.[0].databaseId'
        if ($candidate -and $candidate -ne $before) {
            $runId = $candidate
        }
    }
    if (-not $runId) {
        throw "Could not find the newly started GitHub Actions run."
    }

    Write-Host "Watching GitHub run $runId..."
    gh run watch $runId --repo $RepoName --exit-status
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub iOS shell build failed."
    }
} else {
    $runId = gh run list --repo $RepoName --workflow $Workflow --branch $Branch --status success --limit 1 --json databaseId --jq '.[0].databaseId'
    if (-not $runId) {
        throw "No successful iOS shell workflow run was found."
    }
}

$tmp = Join-Path $env:TEMP "generals-ipad-shell-$runId"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

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

$size = [math]::Round((Get-Item $target).Length / 1MB, 1)
Write-Host ""
Write-Host "READY: $target ($size MB)" -ForegroundColor Green
