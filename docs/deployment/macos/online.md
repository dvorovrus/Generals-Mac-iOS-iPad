# macOS — Generals Online

Canonical branch: `feature/generals-online-apple`.

Workflow: `Online | macOS | Build`.

Status: experimental, but the macOS app is installable.

## Full flow

```bash
./scripts/deploy/macos/generals-deploy.sh full macos online \
  --ipa ~/Downloads/GeneralsZH-iPad-unsigned.ipa
```

The app is installed to `~/Applications/GeneralsZH-Online-Dev.app`.

Retail GameData is extracted from the supplied IPA into:

```text
~/GeneralsX/Online/GeneralsZH
```

Runtime log:

```text
~/Library/Logs/GeneralsXZH/online-dev.log
```

Use an Original/full IPA as the data source. Mod profiles are intentionally not imported into the Online runtime.
