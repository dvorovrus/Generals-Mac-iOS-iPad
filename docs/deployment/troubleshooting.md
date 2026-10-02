# Deployment troubleshooting

## First checks

```text
1. Confirm the platform + variant in scripts/deploy/catalog.json.
2. Confirm the expected branch.
3. Confirm the latest workflow run is green.
4. Confirm the expected artifact exists and is not expired.
5. Confirm the installed app/IPA matches that run.
6. Only then debug runtime behavior.
```

## GitHub CLI

Both deployment CLIs expect `gh` for cloud builds.

```bash
gh auth status
```

If authentication is missing:

```bash
gh auth login
```

## iPad / Sideloadly

The Windows installer intentionally does not automate Apple-ID signing. It locates the IPA, opens Explorer, and launches Sideloadly when found. Drag the exact IPA shown by the tool into Sideloadly and install it to the connected iPad.

After reinstalling, confirm whether iOS created a new app container before assuming old GameData/logs are still present.

Canonical copied logs:

```text
../output/logs/
```

## macOS Gatekeeper

Cloud macOS development builds are ad-hoc signed and not notarized. The deployment script removes the quarantine xattr from the copied app. If macOS still blocks it, use System Settings -> Privacy & Security -> Open Anyway once for that app.

## Wrong data/profile

Use the same IPA family as the target:

- Original macOS: any full Original-compatible IPA with retail GameData.
- Contra macOS: a full Contra IPA so both GameData and `Profiles/contra-x` are present.
- Online macOS: Original/full IPA; only GameData is imported.

## Logs

```text
iPad copied logs: ../output/logs/
Contra macOS: ~/Library/Logs/GeneralsXZH/contra-dev.log
Online macOS: ~/Library/Logs/GeneralsXZH/online-dev.log
Original macOS local runner: repo/logs/run_zh_macos.log
```
