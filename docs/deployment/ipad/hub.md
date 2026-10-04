# iPad — Generals Hub

Generals Hub is the single-app iPad layout for Zero Hour plus installable mod profiles.

## Base app

The Hub IPA contains the current shared iPad engine and launcher, Zero Hour 1.04 GameData, and `HubCatalog.json`. Enhanced and Contra X are not bundled.

Build on Windows from the Hub worktree:

```powershell
.\scripts\build\ios\windows\build-hub.ps1
```

Expected output: `D:\project\test\Generals-iPad\output\GeneralsZH-Hub-unsigned.ipa`.

## Mod packages

Hub packages use the `.gxmod` extension. A package is an uncompressed USTAR archive with `manifest.json` first and mod files under `profile/`. iOS streams extraction to `Documents/Mods/<profileId>/profile`.

Windows builders:

```powershell
.\scripts\build\ios\windows\build-enhanced-gxmod.ps1
.\scripts\build\ios\windows\build-contra-gxmod.ps1
```

Outputs are `output\mods\enhanced.gxmod` and `output\mods\contra-x.gxmod`.

## First device test

1. Install `GeneralsZH-Hub-unsigned.ipa` with Sideloadly.
2. Open Generals Hub. The main screen should show Zero Hour 1.04, Mods, Settings, and Diagnostics.
3. Put `enhanced.gxmod` somewhere accessible in the iPad Files picker.
4. Open Mods -> Import .gxmod and select it.
5. Enhanced should become Installed and expose Play and Remove.
6. Start Enhanced and play a skirmish.
7. Export Diagnostics/logs.

Expected log markers:

```text
[HUB] installed profile='enhanced' ...
[HUB] external profile selected id='enhanced' path='.../Documents/Mods/enhanced/profile'
INFO: iOS launcher: profile 'enhanced' -> -mod ...
```

Enhanced then builds its normal `Documents/EnhancedRuntime` overlay from the externally installed source profile.

## Updates and remote install

`HubCatalog.json` contains catalog version, package size, SHA-256 and `packageURL`. When the catalog version differs from the installed manifest, Mods exposes Update.

Remote Install/Update requires HTTPS and a matching SHA-256. The development catalog intentionally leaves `packageURL` empty; use Import .gxmod for the first device test. Never embed private GitHub credentials in the app.

## Storage and runtime precedence

Hub checks free space before extraction. Files import opens the security-scoped source directly instead of first copying the multi-gigabyte package into the app.

Profile source precedence is:

1. `Documents/Mods/<profileId>/profile`
2. bundled `Profiles/<profileId>` fallback

This keeps the signed app immutable while allowing mods to be installed and updated after sideloading.
