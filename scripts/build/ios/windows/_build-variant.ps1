param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("original", "enhanced", "contra", "all")]
    [string]$Variant,

    [Parameter(Mandatory = $true)]
    [string]$OutputName
)

$ErrorActionPreference = "Stop"

function Require-Path([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
}

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
$InputDir = Join-Path $Workspace "input"
$ShellDir = Join-Path $Workspace "shell"
$OutputDir = Join-Path $Workspace "output"

$Shell = Join-Path $ShellDir "GeneralsXZH-launcher-unsigned.ipa"
$Base = Join-Path $InputDir "GeneralsZH-FULL-unsigned.ipa"
$Enhanced = Join-Path $InputDir "ZHE"
$ContraBeta2 = Join-Path $InputDir "ContraXBeta2.zip"
$ContraPatch1 = Join-Path $InputDir "ContraXBeta2Patch1.zip"
$Output = Join-Path $OutputDir $OutputName

$Builder = Join-Path $Repo "scripts\build\ios\build-variant-ipa.py"
$Verifier = Join-Path $Repo "scripts\build\ios\verify-variant-ipa.py"

Require-Path $Builder "Variant builder"
Require-Path $Verifier "Variant verifier"
Require-Path $Shell "Launcher shell"
Require-Path $Base "Zero Hour base IPA"

if ($Variant -in @("enhanced", "all")) {
    Require-Path $Enhanced "Zero Hour Enhanced"
}
if ($Variant -in @("contra", "all")) {
    Require-Path $ContraBeta2 "Contra X Beta 2"
    Require-Path $ContraPatch1 "Contra X Patch 1"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$Python = Resolve-Python

$argsList = @(
    $Builder,
    "--variant", $Variant,
    "--shell", $Shell,
    "--base-ipa", $Base,
    "--output", $Output
)

if ($Variant -in @("enhanced", "all")) {
    $argsList += @("--enhanced", $Enhanced)
}
if ($Variant -in @("contra", "all")) {
    $argsList += @(
        "--contra-beta2", $ContraBeta2,
        "--contra-patch1", $ContraPatch1
    )
}

Write-Host ""
Write-Host "=== Building $Variant ===" -ForegroundColor Yellow
& $Python @argsList
if ($LASTEXITCODE -ne 0) {
    throw "IPA build failed with exit code $LASTEXITCODE."
}

& $Python $Verifier "--variant" $Variant $Output
if ($LASTEXITCODE -ne 0) {
    throw "IPA verification failed with exit code $LASTEXITCODE."
}

$size = [math]::Round((Get-Item -LiteralPath $Output).Length / 1MB, 1)
Write-Host ""
Write-Host "READY: $Output ($size MB)" -ForegroundColor Green
