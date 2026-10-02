# iPad — Original Zero Hour

Canonical source: branch `main`, workflow `Original | iPad | Full Build`.

## Full flow

```powershell
.\scripts\deploy\windows\generals-deploy.ps1 full -Platform ipad -Variant original
```

The tool triggers `build-ipad.yml`, waits for success, downloads artifact `GeneralsZH-iPad-unsigned`, then opens the IPA location and Sideloadly when available.

Expected IPA: `GeneralsZH-iPad-unsigned.ipa`.

Local fallback exists on `main`:

```powershell
.\scripts\build\ios\windows\build-original.ps1
```

Use the cloud build as the default unless specifically debugging the local packaging path.
