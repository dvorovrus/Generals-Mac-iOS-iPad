param(
    [ValidateSet("stable", "beta")]
    [string] $Channel = "stable",
    [string] $Version = "1.0+2024-03-28",
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
& $Python $Builder --variant enhanced --enhanced (Join-Path $InputDir "ZHE") --channel $Channel --version $Version --min-hub-version $MinHubVersion --output (Join-Path $OutputDir "enhanced.gxmod")
if ($LASTEXITCODE -ne 0) { throw "Enhanced .gxmod build failed." }
