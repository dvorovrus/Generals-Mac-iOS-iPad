# iPad — Contra X

Canonical source: workflow `Contra X | iPad | Full Build`.

## Full flow

```powershell
.\scripts\deploy\windows\generals-deploy.ps1 full -Platform ipad -Variant contra
```

The workflow uses the current shared iOS engine, Zero Hour GameData and Contra X Beta 2 + Patch 1, verifies hashes, packages a full IPA and publishes artifact `GeneralsZH-ContraX-iPad-unsigned`.

Expected IPA: `GeneralsZH-ContraX-unsigned.ipa`.

Local fallback on `main`:

```powershell
.\scripts\build\ios\windows\build-contra.ps1
```

Runtime/device logs belong in `../output/logs/`.
