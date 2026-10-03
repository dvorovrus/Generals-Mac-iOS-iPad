# iPad — Enhanced

Default Windows flow: hybrid packaging. GitHub supplies only the shared iPad engine shell (~20 MB); Zero Hour 1.04 GameData and the local Enhanced profile are packaged on Windows.

The workflow `Enhanced | iPad | Full Build` remains available as a manual backup/release build that publishes a complete cloud IPA.

## One-time CI input seed

Private build inputs live in draft release `enhanced-ipad-inputs-v1`. To refresh them from the Windows workspace:

```powershell
.\repo\scripts\build\ios\windows\seed-enhanced-ci-inputs.ps1 -Replace
```

## Full flow

```powershell
.\scripts\deploy\windows\generals-deploy.ps1 full -Platform ipad -Variant enhanced
```

Default local output:

```text
../output/GeneralsZH-Enhanced-unsigned.ipa
```

Manual cloud backup artifact:

```text
GeneralsZH-Enhanced-iPad-unsigned
└─ GeneralsZH-Enhanced-unsigned.ipa
```

The standalone IPA uses `AutoLaunchProfile.txt=enhanced`, so it opens the dedicated Enhanced launcher with Play, Settings, and Diagnostics.

## Enhanced settings

The native Settings screen exposes the portable options from the original Enhanced launcher:

- Texture resolution: `Vanilla` / `High`
- UI quality: `HD` / `FHD` / `QHD`
- Cameos: `SD` / `HD`
- AI scripts: `Default` / `Restrained` / `Skynet`

Selections are stored in `Documents/EnhancedSettings.ini`. On launch the engine builds `Documents/EnhancedRuntime` with only the selected `.big` overlays and selected `Data/Scripts`. The bundled `Profiles/enhanced` source remains unchanged.

ReShade/DXWrapper are intentionally excluded because those plugins depend on Windows DLL injection and are not part of the Apple rendering path.

Installation uses the same Sideloadly flow as Original and Contra. Runtime/device logs belong in `../output/logs/`.
