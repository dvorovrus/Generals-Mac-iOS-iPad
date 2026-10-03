# iPad — Enhanced

Canonical source: workflow `Enhanced | iPad | Full Build`.

Enhanced follows the same lifecycle as Contra X: the shared iPad engine shell is combined with Zero Hour 1.04 GameData and the isolated Enhanced profile, verified, and published as a full unsigned IPA.

## One-time CI input seed

Private build inputs live in draft release `enhanced-ipad-inputs-v1`. To refresh them from the Windows workspace:

```powershell
.\repo\scripts\build\ios\windows\seed-enhanced-ci-inputs.ps1 -Replace
```

## Full flow

```powershell
.\scripts\deploy\windows\generals-deploy.ps1 full -Platform ipad -Variant enhanced
```

Published artifact:

```text
GeneralsZH-Enhanced-iPad-unsigned
└─ GeneralsZH-Enhanced-unsigned.ipa
```

The standalone IPA uses `AutoLaunchProfile.txt=enhanced`, so it opens the dedicated Enhanced launcher with Play, Settings, and Diagnostics.

Installation uses the same Sideloadly flow as Original and Contra. Runtime/device logs belong in `../output/logs/`.
