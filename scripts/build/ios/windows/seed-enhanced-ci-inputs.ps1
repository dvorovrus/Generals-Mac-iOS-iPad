param(
    [string]$ReleaseTag = "enhanced-ipad-inputs-v1",
    [switch]$PrepareOnly,
    [switch]$Replace
)

$ErrorActionPreference = "Stop"

function Resolve-Python {
    foreach ($candidate in @("py", "python", "python3")) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) {
            return $candidate
        }
    }
    throw "Python 3 was not found in PATH."
}

$Workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
$Repo = Join-Path $Workspace "repo"
$Enhanced = Join-Path $Workspace "input\ZHE"
$Base = Join-Path $Workspace "input\GeneralsZH-FULL-unsigned.ipa"
$Output = Join-Path $Workspace "artifacts\enhanced-ci-inputs"
$Preparer = Join-Path $Repo "scripts\build\ios\prepare-enhanced-ci-inputs.py"
$Repository = "dvorovrus/Generals-Mac-iOS-iPad"
$ExpectedBaseSha256 = "8e45d25c86ad3892704cfd5b732b7c5fe6da0027473b2828cb82cf4d89a0f54f"

foreach ($required in @($Enhanced, $Base, $Preparer)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required input not found: $required"
    }
}

$Python = Resolve-Python
New-Item -ItemType Directory -Force -Path $Output | Out-Null

Write-Host "==> Preparing iPad-safe Enhanced CI inputs" -ForegroundColor Cyan
& $Python $Preparer --enhanced $Enhanced --output-dir $Output
if ($LASTEXITCODE -ne 0) {
    throw "Enhanced CI input preparation failed."
}

$baseHash = (Get-FileHash -LiteralPath $Base -Algorithm SHA256).Hash.ToLowerInvariant()
if ($baseHash -ne $ExpectedBaseSha256) {
    throw "Base IPA SHA-256 mismatch. Expected $ExpectedBaseSha256, got $baseHash"
}

if ($PrepareOnly) {
    Write-Host ""
    Write-Host "PREPARED ONLY: $Output" -ForegroundColor Green
    exit 0
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) is required."
}
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login"
}

$releaseJson = & gh release view $ReleaseTag --repo $Repository --json isDraft 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "==> Creating private draft release $ReleaseTag" -ForegroundColor Cyan
    $createArgs = @(
        "release", "create", $ReleaseTag,
        "--repo", $Repository,
        "--draft",
        "--title", "Enhanced iPad private build inputs v1",
        "--notes", "Private draft inputs for the Zero Hour Enhanced iPad packaging workflow. Do not publish."
    )
    & gh @createArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create draft release $ReleaseTag"
    }
} else {
    $release = $releaseJson | ConvertFrom-Json
    if (-not [bool]$release.isDraft) {
        throw "Release $ReleaseTag exists but is not a draft. Refusing to upload private build inputs."
    }
}

$assets = @(
    $Base,
    (Join-Path $Output "enhanced-inputs.json"),
    (Join-Path $Output "enhanced-inputs.sha256")
)
$assets += Get-ChildItem -LiteralPath $Output -File -Filter "EnhancedProfile-part-*.zip" |
    Sort-Object Name |
    Select-Object -ExpandProperty FullName

$argsList = @("release", "upload", $ReleaseTag, "--repo", $Repository)
$argsList += $assets
if ($Replace) {
    $argsList += "--clobber"
}

Write-Host "==> Uploading private Enhanced inputs to draft release" -ForegroundColor Cyan
& gh @argsList
if ($LASTEXITCODE -ne 0) {
    throw "Upload failed. Re-run with -Replace if the draft already contains older assets."
}

Write-Host ""
Write-Host "READY: $ReleaseTag" -ForegroundColor Green
Write-Host "Draft release remains unpublished."
