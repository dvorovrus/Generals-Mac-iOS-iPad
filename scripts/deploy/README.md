# Deployment tooling

`catalog.json` is the source of truth for platform/variant ownership, workflow names, artifacts and install behavior.

Do not hard-code workflow names in new helper scripts when the value already exists in the catalog.

Windows:
```powershell
.\scripts\deploy\windows\generals-deploy.ps1 help
```

macOS:
```bash
./scripts/deploy/macos/generals-deploy.sh help
```

The deployment tools intentionally preserve the older `../input`, `../shell` and `../output` directories because the existing iPad packagers depend on them. New downloaded CI artifacts go under `../artifacts`.
