# Generals Zero Hour for iPad

A focused iPad build of **Command & Conquer: Generals – Zero Hour** based on GeneralsX.

This branch intentionally contains only the source and tooling needed for the current iPad workflow:

1. GitHub Actions compiles the arm64 iOS engine and native UIKit launcher.
2. The workflow publishes `GeneralsXZH-launcher-unsigned.ipa`.
3. On Windows, `scripts/build/ios/build-all-in-one.ps1` injects the user's own Zero Hour 1.04 data plus optional Enhanced and Contra X profiles.
4. The resulting `GeneralsZH-AllInOne-unsigned.ipa` is signed with the user's normal sideloading tool.

## Native launcher

The launcher is compiled into the iOS executable. It does not use React, Vite, WebKit, or remote content.

Profiles:

- Zero Hour 1.04
- Zero Hour Enhanced
- Contra X Beta 2 + Patch 1

The Settings screen edits the shared `Documents/iPadOverrides.ini`, which the engine loads as the final GameData override layer for every profile.

## GitHub builds

Full engine/shell workflow:

`.github/workflows/build-ios-shell.yml`

Fast launcher-only workflow:

`.github/workflows/build-ios-launcher-fast.yml`

Both publish:

`GeneralsXZH-launcher-unsigned`

The fast workflow reuses the latest successful full shell, recompiles only
`IOSProfileLauncher.mm` into `libGeneralsXLauncher.dylib`, injects that library
into the IPA, verifies the Mach-O linkage, and uploads the refreshed shell.

## Windows final assembly

Keep these user-supplied files outside the repository:

```text
GeneralsXZH-launcher-unsigned.ipa
GeneralsZH-FULL-unsigned.ipa
ZHE/
ContraXBeta2.zip
ContraXBeta2Patch1.zip
```

Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File \
  ".\scripts\build\ios\build-all-in-one.ps1" \
  -Shell ".\GeneralsXZH-launcher-unsigned.ipa" \
  -BaseIpa ".\GeneralsZH-FULL-unsigned.ipa" \
  -Enhanced ".\ZHE" \
  -ContraBeta2 ".\ContraXBeta2.zip" \
  -ContraPatch1 ".\ContraXBeta2Patch1.zip" \
  -Output ".\GeneralsZH-AllInOne-unsigned.ipa"
```

Retail game data and mod archives are never stored in this repository.


## Windows one-command builds

From the workspace folder `Generals-iPad`, the tracked scripts automatically use:

- `input/` for retail/mod sources
- `shell/` for the GitHub-built native iOS shell
- `output/` for generated IPAs

Available scripts:

```powershell
.\repo\scripts\build\ios\windows\build-launcher.ps1
.\repo\scripts\build\ios\windows\build-original.ps1
.\repo\scripts\build\ios\windows\build-enhanced.ps1
.\repo\scripts\build\ios\windows\build-contra.ps1
.\repo\scripts\build\ios\windows\build-all.ps1
```

`build-launcher.ps1` now uses the fast launcher-only GitHub workflow by default,
waits for it, and downloads `GeneralsXZH-launcher-unsigned.ipa` into `shell/`.

Use:

```powershell
.\repo\scripts\build\ios\windows\build-launcher.ps1
```

for a fast launcher-only rebuild after UI/settings changes.

Use:

```powershell
.\repo\scripts\build\ios\windows\build-launcher.ps1 -FullBuild
```

when the engine/runtime itself changed and a full iOS shell rebuild is required.

Pass `-NoBuild` to download the latest successful fast launcher artifact without
starting a new run. Combine `-NoBuild -FullBuild` to download the latest successful
full-shell artifact instead.

The native launcher detects which profile directories exist in the assembled IPA,
so single-mod builds only show the games that are actually installed.
