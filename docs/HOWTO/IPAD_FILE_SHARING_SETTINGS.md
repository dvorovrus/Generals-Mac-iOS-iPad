# iPad File Sharing settings

The iOS port exposes its Documents directory through Apple File Sharing.

After installing a build with this feature, the following files can be copied into
the app's Documents directory using Apple Devices, iTunes, Finder, or the iPad
Files app:

- `iPadOverrides.ini` — final `GameData` override layer. Loaded after the
  normal game INIs and after `SagePatch.ini`.
- `Options.ini` — mirrored into GeneralsX's normal writable user-data folder
  before the engine starts.
- `SagePatch.ini` — mirrored into the normal writable user-data folder before
  the engine starts.

## Recommended workflow

1. Fully close Generals/Zero Hour on the iPad.
2. Replace the desired file in Documents.
3. Launch the game again.

No IPA rebuild or re-sign is required.

## Camera example

```ini
GameData
  MaxCameraHeight = 550.0
  MinCameraHeight = 70.0
  CameraPitch = 37.0
  EnforceMaxCameraHeight = No
  KeyboardScrollSpeedFactor = 1.0
  TerrainDrawDistanceScale = 1.20
End
```

## Graphics example (Options.ini)

```ini
IdealStaticGameLOD = High
StaticGameLOD = High
TextureReduction = 0
HeatEffects = yes
DynamicLOD = no
AntiAliasing = 4
AnisotropyLevel = 16
```

When `Documents/Options.ini` or `Documents/SagePatch.ini` exists, it is copied
over the internal working copy on every launch. Remove the Documents copy if you
want in-game changes to remain authoritative on future launches.
