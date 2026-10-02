# iPad — All-in-One

All-in-One contains the shared Original GameData plus the packaged Enhanced and Contra profiles. It is currently a local Windows packaging variant on `main`.

## Full flow

```powershell
git switch main
git pull --ff-only
.\scripts\deploy\windows\generals-deploy.ps1 full -Platform ipad -Variant all
```

Expected output:

```text
../output/GeneralsZH-AllInOne-unsigned.ipa
```

Use this when a single iPad install should expose multiple local profiles. For focused debugging, prefer the dedicated Contra or Enhanced IPA.
