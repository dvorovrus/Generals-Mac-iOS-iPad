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
& $Python $Builder --variant contra --contra-beta2 (Join-Path $InputDir "ContraXBeta2.zip") --contra-patch1 (Join-Path $InputDir "ContraXBeta2Patch1.zip") --output (Join-Path $OutputDir "contra-x.gxmod")
if ($LASTEXITCODE -ne 0) { throw "Contra X .gxmod build failed." }
