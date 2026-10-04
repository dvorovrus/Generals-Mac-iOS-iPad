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
& $Python $Builder --variant enhanced --enhanced (Join-Path $InputDir "ZHE") --output (Join-Path $OutputDir "enhanced.gxmod")
if ($LASTEXITCODE -ne 0) { throw "Enhanced .gxmod build failed." }
