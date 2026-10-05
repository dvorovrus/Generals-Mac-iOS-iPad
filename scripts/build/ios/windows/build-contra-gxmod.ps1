param(
    [ValidateSet("stable", "beta")]
    [string] $Channel = "stable",
    [string] $Version = "Beta2+Patch1",
    [string] $MinHubVersion = "0.1.0"
)

$ErrorActionPreference = "Stop"
$SourceRepo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$SourceParent = Split-Path $SourceRepo -Parent
if ((Split-Path $SourceParent -Leaf) -eq "worktrees") {
    $Workspace = Split-Path $SourceParent -Parent
} else {
    $Workspace = $SourceParent
}
$Builder = Join-Path $SourceRepo "scripts\build\ios\build-gxmod.py"
$InputDir = Join-Path $Workspace "input"
$OutputDir = Join-Path $Workspace "output\mods"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$Python = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }
& $Python $Builder --variant contra --contra-beta2 (Join-Path $InputDir "ContraXBeta2.zip") --contra-patch1 (Join-Path $InputDir "ContraXBeta2Patch1.zip") --channel $Channel --version $Version --min-hub-version $MinHubVersion --output (Join-Path $OutputDir "contra-x.gxmod")
if ($LASTEXITCODE -ne 0) { throw "Contra X .gxmod build failed." }
