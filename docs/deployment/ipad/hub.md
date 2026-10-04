# iPad — Generals Hub

Generals Hub is the single iPad app for Generals Online plus installable mod profiles. The Hub does not expose a separate vanilla Zero Hour launch mode.

## Base app

The Hub IPA contains the Online-capable iPad engine (`SAGE_USE_GENERALS_ONLINE=ON` + deterministic math), Zero Hour 1.04 GameData, official Generals Online parity data, the native Hub launcher, and `HubCatalog.json`. Enhanced and Contra X are not bundled.

Build on Windows from the Hub worktree:

```powershell
.\scripts\build\ios\windows\build-hub-online.ps1
```

Expected output: `D:\project\test\Generals-iPad\output\GeneralsZH-Hub-Online-unsigned.ipa`.

## Mod packages

Hub packages use the `.gxmod` extension. A package is an uncompressed USTAR archive with `manifest.json` first and mod files under `profile/`. iOS streams extraction to `Documents/Mods/<profileId>/profile`.

Windows builders:

```powershell
.\scripts\build\ios\windows\build-enhanced-gxmod.ps1
.\scripts\build\ios\windows\build-contra-gxmod.ps1
```

Outputs are `output\mods\enhanced.gxmod` and `output\mods\contra-x.gxmod`.

## First device test

1. Install `GeneralsZH-Hub-Online-unsigned.ipa` with Sideloadly.
2. Open Generals Hub. The main screen should show Generals Online, Mods, Hub Settings, and Diagnostics. There should be no separate Zero Hour button.
3. Put `enhanced.gxmod` somewhere accessible in the iPad Files picker.
4. Open Mods -> Import .gxmod and select it.
5. Enhanced should become Installed and expose Play, Settings, and Remove.
6. Open Enhanced Settings, change one Enhanced-only option, save, and return to Mods.
7. Start Enhanced and play a skirmish.
8. Export Diagnostics/logs.

Expected log markers:

```text
[HUB] installed profile='enhanced' ...
[HUB] external profile selected id='enhanced' path='.../Documents/Mods/enhanced/profile'
INFO: iOS launcher: profile 'enhanced' -> -mod ...
```

Enhanced then builds its normal `Documents/EnhancedRuntime` overlay from the externally installed source profile.

## Settings isolation

Hub Settings contains only shared engine, graphics, camera and performance options. Mod-specific launcher options are never mixed into Hub Settings.

Known mod settings are stored independently:

```text
Documents/Mods/enhanced/settings.ini
Documents/Mods/contra-x/settings.ini
```

Updating a `.gxmod` package preserves its existing `settings.ini`. Legacy standalone `Documents/EnhancedSettings.ini` / `Documents/ContraSettings.ini` files are migrated when present.

## Updates and remote install

`HubCatalog.json` contains catalog version, package size, SHA-256 and `packageURL`. When the catalog version differs from the installed manifest, Mods exposes Update.

Remote Install/Update requires HTTPS and a matching SHA-256. The development catalog intentionally leaves `packageURL` empty; use Import .gxmod for the first device test. Never embed private GitHub credentials in the app.

## Storage and runtime precedence

Hub checks free space before extraction. Files import opens the security-scoped source directly instead of first copying the multi-gigabyte package into the app.

Profile source precedence is:

1. `Documents/Mods/<profileId>/profile`
2. bundled `Profiles/<profileId>` fallback

This keeps the signed app immutable while allowing mods to be installed and updated after sideloading.
