param(
    [long]$RunId = 0,
    [string]$Branch = "feature/online-deterministic-math",
    [string]$BaseIpa = "",
    [string]$Output = ""
)

$ErrorActionPreference = "Stop"

$RepoName = "dvorovrus/Generals-Mac-iOS-iPad"
$Workflow = "build-ios-online.yml"
$ArtifactName = "GeneralsXZH-online-unsigned"
$ArtifactFile = "GeneralsXZH-online-unsigned.ipa"

function Resolve-Python {
    foreach ($candidate in @("py", "python", "python3")) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) { return $candidate }
    }
    throw "Python 3 was not found in PATH."
}

function Require-Path([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Label not found: $Path" }
}

function Resolve-RepoRoot {
    $root = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if (-not $root) { throw "Could not resolve the repository root." }
    return (Resolve-Path -LiteralPath $root.Trim()).Path
}

function Resolve-Workspace([string]$RepoRoot) {
    $parent = Split-Path -Parent $RepoRoot
    if ((Split-Path -Leaf $RepoRoot) -eq "repo") { return $parent }
    if ((Split-Path -Leaf $parent) -in @("worktrees", ".webcodex-worktrees")) { return (Split-Path -Parent $parent) }
    return $parent
}

function Assert-GitHubCli {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI (gh) was not found in PATH." }
    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated. Run: gh auth login" }
}

function Read-Run([long]$Id) {
    $json = & gh run view $Id --repo $RepoName --json status,conclusion,url,headSha,headBranch
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect GitHub Actions run $Id." }
    return ($json | ConvertFrom-Json)
}

$RepoRoot = Resolve-RepoRoot
$Workspace = Resolve-Workspace $RepoRoot

if (-not $BaseIpa) { $BaseIpa = Join-Path $Workspace "input\GeneralsZH-FULL-unsigned.ipa" }
if (-not $Output) { $Output = Join-Path $Workspace "output\GeneralsZH-Online-FULL-unsigned.ipa" }

$Builder = Join-Path $RepoRoot "scripts\build\ios\build-variant-ipa.py"
$Verifier = Join-Path $RepoRoot "scripts\build\ios\verify-variant-ipa.py"
$SyncOnlineData = Join-Path $RepoRoot "scripts\build\common\sync-generals-online-data.py"
$OnlineDataStage = Join-Path $Workspace "artifacts\gamedata\online\official"
$OnlineDataCache = Join-Path $Workspace "cache\generals-online-official"

Require-Path $BaseIpa "Zero Hour full base IPA"
Require-Path $Builder "IPA builder"
Require-Path $Verifier "IPA verifier"
Require-Path $SyncOnlineData "Generals Online data sync helper"
Assert-GitHubCli
$Python = Resolve-Python

if ($RunId -eq 0) {
    $runsJson = & gh run list --repo $RepoName --workflow $Workflow --branch $Branch --limit 1 --json databaseId
    if ($LASTEXITCODE -ne 0) { throw "Could not query iPad Online builds." }
    $runs = @($runsJson | ConvertFrom-Json)
    if ($runs.Count -eq 0) { throw "No iPad Online build was found." }
    $RunId = [long]$runs[0].databaseId
}

$run = Read-Run $RunId
$expectedWorkflowId = & gh api "repos/$RepoName/actions/workflows/$Workflow" --jq ".id"
if ($LASTEXITCODE -ne 0) { throw "Could not resolve workflow $Workflow." }
$actualWorkflowId = & gh api "repos/$RepoName/actions/runs/$RunId" --jq ".workflow_id"
if ($LASTEXITCODE -ne 0) { throw "Could not resolve the workflow for run $RunId." }
if ([long]$actualWorkflowId -ne [long]$expectedWorkflowId -or $run.headBranch -ne $Branch) {
    throw "Run $RunId is not an iPad Online build from $Branch."
}

Write-Host ""
Write-Host "=== Generals Online iPad full IPA builder ===" -ForegroundColor Yellow
Write-Host "Run:       $RunId"
Write-Host "Commit:    $($run.headSha)"
Write-Host "Base IPA:  $BaseIpa"
Write-Host "Output:    $Output"
Write-Host "Source:    $($run.url)"
Write-Host ""

if ($run.status -ne "completed") {
    Write-Host "Waiting for Online build $RunId..." -ForegroundColor Cyan
    & gh run watch $RunId --repo $RepoName --exit-status
    if ($LASTEXITCODE -ne 0) { throw "Online build $RunId did not succeed." }
    $run = Read-Run $RunId
}
if ($run.conclusion -ne "success") {
    throw "Online build $RunId ended with $($run.conclusion). No older build will be substituted."
}

$ArtifactDir = Join-Path $Workspace "artifacts\ipad\online\$RunId"
$Shell = Join-Path $ArtifactDir $ArtifactFile
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
if (-not (Test-Path -LiteralPath $Shell)) {
    Write-Host "Downloading Online shell..." -ForegroundColor Cyan
    & gh run download $RunId --repo $RepoName --name $ArtifactName --dir $ArtifactDir
    if ($LASTEXITCODE -ne 0) { throw "Artifact download failed for run $RunId." }
} else {
    Write-Host "Using cached Online shell: $Shell" -ForegroundColor DarkGray
}

Require-Path $Shell "Downloaded Online shell"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null

Write-Host "Syncing official Generals Online data patch and Windows 60 Hz parity seed..." -ForegroundColor Cyan
& $Python $SyncOnlineData --dest $OnlineDataStage --cache-dir $OnlineDataCache --expected-version 100126_QFE6 --expected-seed 0x808CB29E
if ($LASTEXITCODE -ne 0) { throw "Generals Online data sync/parity verification failed." }

Write-Host "Packaging retail GameData into the Online shell..." -ForegroundColor Cyan
& $Python $Builder --variant original --shell $Shell --base-ipa $BaseIpa --online-data $OnlineDataStage --output $Output
if ($LASTEXITCODE -ne 0) { throw "Online IPA packaging failed." }

Write-Host "Verifying final IPA..." -ForegroundColor Cyan
& $Python $Verifier --variant original --require-online-data $Output
if ($LASTEXITCODE -ne 0) { throw "Online IPA verification failed." }

$sizeMb = [math]::Round((Get-Item -LiteralPath $Output).Length / 1MB, 1)
$SourceInfo = "Run: $RunId`nCommit: $($run.headSha)`nURL: $($run.url)`nShell: $Shell`nBase IPA: $BaseIpa`nOnline data: $OnlineDataStage`nOfficial GO: 100126_QFE6`nWindows 60Hz shift/add seed: 0x808CB29E`n"
[System.IO.File]::WriteAllText("$Output.source.txt", $SourceInfo)

Write-Host ""
Write-Host "READY: $Output ($sizeMb MB)" -ForegroundColor Green
Write-Host "Source metadata: $Output.source.txt"
Write-Host "Next: sign/install this IPA with Sideloadly."
