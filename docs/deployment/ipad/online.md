# iPad — Generals Online

Branch: `feature/generals-online-apple`.

Workflow: `Online | iPad | Build`.

Status: **experimental**.

The GitHub Actions artifact is an unsigned Online engine shell. Retail Zero Hour `GameData` is added on Windows from an existing full Original IPA; mod profiles are intentionally not included.

## One-command Windows build

Prerequisites:

- GitHub CLI (`gh`) authenticated with `gh auth login`.
- Python 3 in `PATH`.
- Base Zero Hour IPA at `../input/GeneralsZH-FULL-unsigned.ipa`.

From the repository root:

```powershell
.\scripts\build\ios\windows\build-online.ps1
```

The script:

1. selects the latest iPad Online workflow run on `feature/generals-online-apple`;
2. waits for it if it is still running and fails closed if that run fails;
3. downloads/caches `GeneralsXZH-online-unsigned.ipa` under `../artifacts/ipad/online/<run-id>/`;
4. copies clean retail Zero Hour `GameData` from the base IPA;
5. verifies the final IPA;
6. writes:

```text
../output/GeneralsZH-Online-FULL-unsigned.ipa
```

To reproduce a specific engine build:

```powershell
.\scripts\build\ios\windows\build-online.ps1 -RunId 37022312575
```

Custom source/output paths are also supported:

```powershell
.\scripts\build\ios\windows\build-online.ps1 `
  -BaseIpa "D:\path\to\GeneralsZH-FULL-unsigned.ipa" `
  -Output "D:\path\to\GeneralsZH-Online-FULL-unsigned.ipa"
```

The resulting IPA is unsigned. Sign/install it with Sideloadly.

The generic deployment CLI can still trigger or download the raw engine shell:

```powershell
.\scripts\deploy\windows\generals-deploy.ps1 build -Platform ipad -Variant online -Wait
.\scripts\deploy\windows\generals-deploy.ps1 download -Platform ipad -Variant online
```

The generic `install` / `full` deployment commands remain disabled for Online because they operate on the raw shell rather than the locally completed full IPA.
