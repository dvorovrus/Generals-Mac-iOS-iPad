$ErrorActionPreference = "Stop"
$Workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
$Repo = Join-Path $Workspace "repo"
if (-not (Test-Path (Join-Path $Repo "scripts\build\ios\build-gxmod.py"))) {
    $Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
}
$Builder = Join-Path $Repo "scripts\build\ios\build-gxmod.py"
$InputDir = Join-Path $Workspace "input"
$OutputDir = Join-Path $Workspace "output\mods"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$Python = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }
& $Python $Builder --variant enhanced --enhanced (Join-Path $InputDir "ZHE") --output (Join-Path $OutputDir "enhanced.gxmod")
if ($LASTEXITCODE -ne 0) { throw "Enhanced .gxmod build failed." }
