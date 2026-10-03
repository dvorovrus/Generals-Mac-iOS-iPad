# iPad — Zero Hour Enhanced

Canonical source: workflow `Zero Hour Enhanced | iPad | Full Build`.

Enhanced follows the same lifecycle as Contra X: the current shared iOS engine shell is combined with Zero Hour 1.04 GameData and an isolated Enhanced profile, verified, and published as a full unsigned IPA.

## One-time CI input seed

The workflow reads user-supplied game/mod data from the draft release `enhanced-ipad-inputs-v1`. From the packaging workspace on Windows, prepare and upload those inputs once:

```powershell
.\repo\scripts\build\ios\windows\seed-enhanced-ci-inputs.ps1
```

The seed tool keeps only files that are active on iPad, splits the Enhanced profile into release-safe ZIP parts, verifies the base IPA hash, and keeps the release as a draft.

## Full flow

```powershell
.\scripts\deploy\windows\generals-deploy.ps1 full -Platform ipad -Variant enhanced
```

Published artifact:

```text
GeneralsZH-Enhanced-iPad-unsigned
└─ GeneralsZH-Enhanced-unsigned.ipa
```

The standalone IPA contains `AutoLaunchProfile.txt=enhanced`, so the native launcher exposes only Enhanced plus Settings and Diagnostics instead of the multi-profile chooser.

Local fallback on `ios-clean`:

```powershell
.\scripts\build\ios\windows\build-enhanced.ps1
```

Installation uses the same Sideloadly flow as Original and Contra. Runtime/device logs belong in `../output/logs/`.
