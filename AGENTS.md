# Repository Guide

## Workspace Boundaries

- The Git checkout is `repo/` inside the `Generals-iPad/` packaging workspace. Run source-build commands from `repo/`; run the tracked Windows wrappers from the workspace directory.
- Keep retail/mod inputs outside Git: `input/GeneralsZH-FULL-unsigned.ipa`, `input/ZHE/`, `input/ContraXBeta2.zip`, and `input/ContraXBeta2Patch1.zip`. Downloaded shells belong in `shell/`; generated IPAs belong in `output/`.
- Do not edit generated `build*/`, `vcpkg_installed/`, `ios/build/`, or `ios/GeneralsXZH.xcodeproj` content. XcodeGen regenerates the project from `ios/project.yml`.

## Windows Packaging

Run these from the workspace directory, not from `repo/`:

```powershell
.\repo\scripts\build\ios\windows\build-launcher.ps1
.\repo\scripts\build\ios\windows\build-original.ps1
.\repo\scripts\build\ios\windows\build-enhanced.ps1
.\repo\scripts\build\ios\windows\build-contra.ps1
.\repo\scripts\build\ios\windows\build-all.ps1
```

- `build-launcher.ps1` requires authenticated `gh`. Its default fast workflow rebuilds only `libGeneralsXLauncher.dylib`; use `-FullBuild` after engine/runtime changes. `-NoBuild` downloads the latest successful artifact.
- Build the launcher before a variant. Variant wrappers require Python 3 as `py`, `python`, or `python3`, consume `shell/GeneralsXZH-launcher-unsigned.ipa`, and automatically verify their output.
- Enhanced packaging requires the 28/03/2024 patch (`!!ZHE8Patch_99.big`) in `input/ZHE/`. Contra archives are checked against pinned MD5 values; do not bypass this with `--skip-md5` unless explicitly requested.
- Outputs are unsigned and still require external signing/sideloading.

## Focused Verification

There is no configured unit-test, lint, formatter, or static-typecheck suite. Validate packaging changes with the IPA verifier from the workspace directory:

```powershell
py .\repo\scripts\build\ios\verify-variant-ipa.py --variant original .\output\GeneralsZH-Original-unsigned.ipa
py .\repo\scripts\build\ios\verify-variant-ipa.py --variant enhanced .\output\GeneralsZH-Enhanced-unsigned.ipa
py .\repo\scripts\build\ios\verify-variant-ipa.py --variant contra .\output\GeneralsZH-ContraX-unsigned.ipa
py .\repo\scripts\build\ios\verify-variant-ipa.py --variant all .\output\GeneralsZH-AllInOne-unsigned.ipa
```

## Full iOS Build

The authoritative sequence is `.github/workflows/build-ios-shell.yml`; it requires macOS/Xcode, CMake 3.25+, Ninja, the pinned Vulkan SDK, vcpkg, Meson, XcodeGen, and related build tools:

```bash
git submodule update --init --recursive --depth 1 references/fbraz3-dxvk
./scripts/build/ios/fetch-moltenvk.sh
./scripts/build/ios/stage-fonts.sh
cmake --preset ios-vulkan
cmake --build build/ios-vulkan --target z_generals -j "$(sysctl -n hw.ncpu)"
GX_BUNDLE_ID=com.dvorov.generalszh.launcher ./scripts/build/ios/package-shell.sh
```

- Set `VCPKG_ROOT` and `VULKAN_SDK` before configuring. The iOS preset requires the local `references/fbraz3-dxvk` submodule and the `arm64-ios` overlay triplet; configuration intentionally fails rather than using an unpatched remote DXVK source.
- CMake rejects in-source builds. The preset builds arm64 iOS 16.0 `RelWithDebInfo` into `build/ios-vulkan/`.

## Architecture And Release Routing

- Online changes on `feature/generals-online-apple` run independent iOS and macOS workflows: `build-ios-online.yml` and `build-macos-online.yml`. Each platform has separate dependency/compiler caches and concurrency groups.
- macOS Online uses the `macos-vulkan-online` preset. Package it with `GX_MAC_ONLINE=1 bash scripts/build/macos/package-macos-contra-dev.sh`; the shared packager emits `GeneralsZH-Online-macos-arm64.tar` containing the app and `Install Online Data.command`. Retail data is imported locally from an Original/Online IPA into `~/GeneralsX/Online/GeneralsZH`. Runtime log: `~/Library/Logs/GeneralsXZH/online-dev.log`.

- `Core/` contains shared engine/libraries; `GeneralsMD/` is the Zero Hour implementation. The main target is `z_generals`, emitted as `GeneralsXZH`; non-Windows startup is `GeneralsMD/Code/Main/SDL3Main.cpp`.
- The native UIKit launcher is `GeneralsMD/Code/Main/IOSProfileLauncher.mm`, built as `libGeneralsXLauncher.dylib`. It is not React, Vite, WebKit, or remote content.
- Launcher selection becomes `-mod <app>/Profiles/enhanced` or `-mod <app>/Profiles/contra-x`; an explicit caller-supplied `-mod` takes precedence. Shared retail data is under `GameData/`; optional mods are isolated under `Profiles/`.
- Changes limited to launcher sources or `ios/version.env` use `.github/workflows/build-ios-launcher-fast.yml`. Engine/runtime changes require `.github/workflows/build-ios-shell.yml`; the fast workflow depends on a previous successful full-shell artifact.
- Versions live only in `ios/version.env`. `ENGINE_VERSION` and `LAUNCHER_VERSION` intentionally advance independently.
- Launcher settings write shared `Documents/iPadOverrides.ini`; the engine loads it last as a GameData override, and changes require a full app restart.
