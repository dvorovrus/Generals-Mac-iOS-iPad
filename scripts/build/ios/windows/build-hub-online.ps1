$ErrorActionPreference = "Stop"
$Workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
$RepoRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1).Trim()
if ((Split-Path -Leaf (Split-Path -Parent $RepoRoot)) -eq "worktrees") {
    $Workspace = Split-Path -Parent (Split-Path -Parent $RepoRoot)
}
$RepoName = "dvorovrus/Generals-Mac-iOS-iPad"
$Branch = "feature/generals-hub-online"
$Workflow = "build-ios-online.yml"
$ArtifactName = "GeneralsXZH-online-unsigned"
$ArtifactFile = "GeneralsXZH-online-unsigned.ipa"
$BaseIpa = Join-Path $Workspace "input\GeneralsZH-FULL-unsigned.ipa"
$Output = Join-Path $Workspace "output\GeneralsZH-Hub-Online-unsigned.ipa"
$Builder = Join-Path $RepoRoot "scripts\build\ios\build-variant-ipa.py"
$Verifier = Join-Path $RepoRoot "scripts\build\ios\verify-variant-ipa.py"
$SyncOnlineData = Join-Path $RepoRoot "scripts\build\common\sync-generals-online-data.py"
$OnlineDataStage = Join-Path $Workspace "artifacts\gamedata\online\official"
$OnlineDataCache = Join-Path $Workspace "cache\generals-online-official"
$Python = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }

foreach ($required in @($BaseIpa,$Builder,$Verifier,$SyncOnlineData)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required input not found: $required" }
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI (gh) is required." }
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated." }

$runsJson = & gh run list --repo $RepoName --workflow $Workflow --branch $Branch --status success --limit 1 --json databaseId
$runs = @($runsJson | ConvertFrom-Json)
if ($runs.Count -eq 0) { throw "No successful Hub Online engine build found on $Branch." }
$RunId = [long]$runs[0].databaseId
$run = (& gh run view $RunId --repo $RepoName --json status,conclusion,url,headSha,headBranch | ConvertFrom-Json)
if ($run.conclusion -ne "success" -or $run.headBranch -ne $Branch) { throw "Run $RunId is not a successful Hub Online build." }

$ArtifactDir = Join-Path $Workspace "artifacts\ipad\hub-online\$RunId"
$Shell = Join-Path $ArtifactDir $ArtifactFile
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
if (-not (Test-Path -LiteralPath $Shell)) {
    Write-Host "Downloading Hub Online engine shell..." -ForegroundColor Cyan
    & gh run download $RunId --repo $RepoName --name $ArtifactName --dir $ArtifactDir
    if ($LASTEXITCODE -ne 0) { throw "Artifact download failed." }
}

Write-Host "Syncing official Generals Online parity data..." -ForegroundColor Cyan
& $Python $SyncOnlineData --dest $OnlineDataStage --cache-dir $OnlineDataCache --expected-version 100126_QFE6 --expected-seed 0x808CB29E
if ($LASTEXITCODE -ne 0) { throw "Generals Online data sync/parity verification failed." }

Write-Host "Packaging Generals Hub (Online base + downloadable mods)..." -ForegroundColor Cyan
& $Python $Builder --variant hub --shell $Shell --base-ipa $BaseIpa --online-data $OnlineDataStage --output $Output
if ($LASTEXITCODE -ne 0) { throw "Hub Online IPA packaging failed." }

Write-Host "Verifying Hub Online IPA..." -ForegroundColor Cyan
& $Python $Verifier --variant hub --require-online-data $Output
if ($LASTEXITCODE -ne 0) { throw "Hub Online IPA verification failed." }

$sizeMb = [math]::Round((Get-Item -LiteralPath $Output).Length / 1MB, 1)
$nl = [Environment]::NewLine
$SourceInfo = "Run: $RunId" + $nl + "Commit: $($run.headSha)" + $nl + "URL: $($run.url)" + $nl + "Shell: $Shell" + $nl + "Base IPA: $BaseIpa" + $nl + "Online data: $OnlineDataStage" + $nl + "Official GO: 100126_QFE6" + $nl + "Windows 60Hz shift/add seed: 0x808CB29E" + $nl + "Mode: Generals Hub" + $nl
[System.IO.File]::WriteAllText("$Output.source.txt", $SourceInfo)

Write-Host ""
Write-Host "READY: $Output ($sizeMb MB)" -ForegroundColor Green
Write-Host "Install this IPA once with Sideloadly; add mods later from the Hub Mods screen."

