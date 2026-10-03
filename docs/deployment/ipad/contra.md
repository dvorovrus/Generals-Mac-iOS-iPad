# iPad — Contra X

Default Windows flow: hybrid packaging. GitHub supplies only the shared iPad engine shell (~20 MB); Zero Hour GameData and Contra X are packaged locally on Windows.

The workflow `Contra X | iPad | Full Build` remains available as a manual backup/release build that publishes a complete cloud IPA.

## Full flow

```powershell
.\scripts\deploy\windows\generals-deploy.ps1 full -Platform ipad -Variant contra
```

The deploy CLI downloads/reuses the latest successful `Shared | iPad | Engine Shell`, then runs the local packager against `input/GeneralsZH-FULL-unsigned.ipa`, `input/ContraXBeta2.zip`, and `input/ContraXBeta2Patch1.zip`.

Expected local IPA: `../output/GeneralsZH-ContraX-unsigned.ipa`.

Direct local packager:

```powershell
.\scripts\build\ios\windows\build-contra.ps1
```

Runtime/device logs belong in `../output/logs/`.
