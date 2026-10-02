# iPad — Generals Online

Branch: `feature/generals-online-apple`.

Workflow: `Online | iPad | Build`.

Status: **experimental**.

The current Online artifact is an engine shell and does not contain retail GameData, so it is not treated as a normal end-user full IPA by the deployment CLI.

You can build/download it for engine testing:

```powershell
.\scripts\deploy\windows\generals-deploy.ps1 build -Platform ipad -Variant online -Wait
.\scripts\deploy\windows\generals-deploy.ps1 download -Platform ipad -Variant online
```

The `install` / `full` command will warn that this variant is not yet install-ready. This is intentional: the standard should describe the real state, not hide the missing GameData integration.
