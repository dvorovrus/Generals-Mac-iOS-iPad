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

## GitHub build

Workflow:

`.github/workflows/build-ios-shell.yml`

Artifact:

`GeneralsXZH-launcher-unsigned`

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
