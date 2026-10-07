param(
    [long]$RunId = 0,
    [string]$Branch = "feature/online-deterministic-math",
    [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"
$RepoName = "dvorovrus/Generals-Mac-iOS-iPad"
$Workflow = "build-macos-online.yml"
$SourceRepo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $SourceParent = Split-Path $SourceRepo -Parent
    if ((Split-Path $SourceParent -Leaf) -in @("worktrees", ".webcodex-worktrees")) {
        $Workspace = Split-Path $SourceParent -Parent
    } else {
        $Workspace = $SourceParent
    }
}
$Workspace = (Resolve-Path $Workspace).Path
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) was not found in PATH."
}
if ($RunId -eq 0) {
    $runsJson = gh run list --repo $RepoName --workflow $Workflow --branch $Branch --limit 1 --json databaseId
    if ($LASTEXITCODE -ne 0) { throw "Could not query macOS Online builds. Check gh auth status." }
    $runs = @($runsJson | ConvertFrom-Json)
    if ($runs.Count -eq 0) { throw "No macOS Online build was found." }
    $RunId = $runs[0].databaseId
}
$runJson = gh run view $RunId --repo $RepoName --json status,conclusion,url,headSha,headBranch
if ($LASTEXITCODE -ne 0) { throw "Could not inspect run $RunId." }
$run = $runJson | ConvertFrom-Json
$expected = gh api "repos/$RepoName/actions/workflows/$Workflow" --jq '.id'
if ($LASTEXITCODE -ne 0) { throw "Could not resolve workflow $Workflow." }
$actual = gh api "repos/$RepoName/actions/runs/$RunId" --jq '.workflow_id'
if ($LASTEXITCODE -ne 0) { throw "Could not resolve the workflow for run $RunId." }
if ([long]$actual -ne [long]$expected -or $run.headBranch -ne $Branch) {
    throw "Run $RunId is not a macOS Online build from $Branch."
}
Write-Host "macOS Online build: $($run.url)" -ForegroundColor Cyan
Write-Host "Commit: $($run.headSha)"
if ($run.status -ne "completed") {
    gh run watch $RunId --repo $RepoName --exit-status
    if ($LASTEXITCODE -ne 0) { throw "macOS build did not succeed: $($run.url)" }
}
elseif ($run.conclusion -ne "success") {
    throw "Latest macOS build ended with '$($run.conclusion)': $($run.url). No older build will be substituted."
}
$Download = Join-Path $Workspace "output\macos-online-$RunId-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $Download | Out-Null
gh run download $RunId --repo $RepoName --name GeneralsZH-Online-macos-arm64 --dir $Download
if ($LASTEXITCODE -ne 0) { throw "macOS artifact download failed." }
$Archive = Join-Path $Download "GeneralsZH-Online-macos-arm64.tar"
if (-not (Test-Path -LiteralPath $Archive)) { throw "Downloaded artifact contains no macOS archive: $Download" }
[System.IO.File]::WriteAllText("$Archive.source.txt", "Run: $RunId`nCommit: $($run.headSha)`nURL: $($run.url)`n")
Write-Host "READY: $Archive" -ForegroundColor Green
Write-Host "Copy the archive to your Mac, extract it, and run Install Online Data.command with your Original/Online IPA."
