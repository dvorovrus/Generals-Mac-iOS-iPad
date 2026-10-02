# iPad — Zero Hour Enhanced

Enhanced currently uses the local Windows packaging path on branch `main`.

Required local inputs are the existing base full IPA and `input/ZHE`.

## Full flow

```powershell
git switch main
git pull --ff-only
.\scripts\deploy\windows\generals-deploy.ps1 full -Platform ipad -Variant enhanced
```

The deployment CLI delegates to:

```text
scripts/build/ios/windows/build-enhanced.ps1
```

Expected output:

```text
../output/GeneralsZH-Enhanced-unsigned.ipa
```

Installation is the same Sideloadly flow as Original and Contra.
