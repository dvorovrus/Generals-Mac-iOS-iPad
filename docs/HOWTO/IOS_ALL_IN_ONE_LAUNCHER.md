# iOS all-in-one launcher build

The all-in-one package keeps **one shared Zero Hour 1.04 GameData** and two isolated
mod overlays:

```text
GeneralsXZH.app/
  GameData/               # Zero Hour 1.04, stored once
  Launcher/               # Vite UI
  Profiles/
    enhanced/             # Enhanced overlay only
    contra-x/             # Contra X Beta 2 + Patch 1 overlay only
  Frameworks/
```

The iOS launcher selects a profile before engine initialization. Vanilla adds no
mod path. Enhanced and Contra X use the game's existing `-mod <directory>`
mechanism.

## Windows 11 assembly

Download the unsigned launcher shell produced by the
`Build iOS Launcher Shell` GitHub Actions workflow. Put it next to:

- your existing `GeneralsZH-FULL-unsigned.ipa`;
- the extracted `ZHE` directory (or a ZIP);
- `ContraXBeta2.zip`;
- `ContraXBeta2Patch1.zip`.

Then run:

```powershell
py .\scripts\build\ios\build-all-in-one-ipa.py `
  --shell .\GeneralsXZH-launcher-unsigned.ipa `
  --base-ipa .\GeneralsZH-FULL-unsigned.ipa `
  --enhanced .\ZHE `
  --contra-beta2 .\ContraXBeta2.zip `
  --contra-patch1 .\ContraXBeta2Patch1.zip
```

Output:

```text
GeneralsZH-AllInOne-unsigned.ipa
```

The script validates the official Contra X Beta 2 and Patch 1 archive MD5 values
when the original ZIP archives are supplied. Use `--skip-md5` only for a
deliberately repacked archive.

### Contra defaults

The staging rules mirror the current official Contra Launcher defaults rather
than blindly enabling every `.ctr` archive. Core content is enabled together
with English voices, original English hotkeys and Patch 1. Standard music and
the Contra control bar use the mod defaults; optional conflicting archive
variants remain detached.

## macOS direct package

A Mac build can package prepared local profiles directly:

```bash
GX_ENHANCED_DATA=/path/to/enhanced \
GX_CONTRA_X_DATA=/path/to/contra-x \
./scripts/build/ios/package-ios-zh.sh --all-in-one
```

For CI or Windows-side assembly, create a launcher/engine shell without retail
assets:

```bash
./scripts/build/ios/package-ios-zh.sh --dev --unsigned
```
