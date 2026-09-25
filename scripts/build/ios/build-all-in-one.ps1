param(
    [string]$Shell = "GeneralsXZH-launcher-unsigned.ipa",
    [string]$BaseIpa = "GeneralsZH-FULL-unsigned.ipa",
    [string]$Enhanced = "ZHE",
    [string]$ContraBeta2 = "ContraXBeta2.zip",
    [string]$ContraPatch1 = "ContraXBeta2Patch1.zip",
    [string]$Output = "GeneralsZH-AllInOne-unsigned.ipa"
)

$ErrorActionPreference = "Stop"

function Resolve-Python {
    foreach ($candidate in @("py", "python", "python3")) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $candidate }
    }
    throw "Python 3 was not found in PATH."
}

function Require-Path([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
}

$Builder = Join-Path $PSScriptRoot "build-all-in-one-ipa.py"

Require-Path $Builder "IPA builder"
Require-Path $Shell "Launcher shell IPA"
Require-Path $BaseIpa "Zero Hour 1.04 base IPA"
Require-Path $Enhanced "Zero Hour Enhanced source"
Require-Path $ContraBeta2 "Contra X Beta 2 archive"
Require-Path $ContraPatch1 "Contra X Beta 2 Patch 1 archive"

$Python = Resolve-Python

Write-Host ""
Write-Host "=== Zero Hour All-In-One iPad Builder ===" -ForegroundColor Yellow
Write-Host "Shell:          $Shell"
Write-Host "Base 1.04:      $BaseIpa"
Write-Host "Enhanced:       $Enhanced"
Write-Host "Contra Beta 2:  $ContraBeta2"
Write-Host "Contra Patch 1: $ContraPatch1"
Write-Host "Output:         $Output"
Write-Host ""

& $Python $Builder `
    --shell $Shell `
    --base-ipa $BaseIpa `
    --enhanced $Enhanced `
    --contra-beta2 $ContraBeta2 `
    --contra-patch1 $ContraPatch1 `
    --output $Output

if ($LASTEXITCODE -ne 0) {
    throw "All-in-one IPA builder failed with exit code $LASTEXITCODE."
}

Require-Path $Output "Final unsigned IPA"

$sizeMb = [math]::Round((Get-Item -LiteralPath $Output).Length / 1MB, 1)
Write-Host ""
Write-Host "DONE: $Output ($sizeMb MB)" -ForegroundColor Green
Write-Host "Sign this IPA with your normal iOS sideloading/signing tool."
