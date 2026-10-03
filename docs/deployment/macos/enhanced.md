# macOS — Enhanced

Canonical branch: `main`.

Workflow: `Enhanced | macOS | Dev Build`.

## Full flow

Copy or download a full Enhanced iPad IPA to the Mac, then run:

```bash
./scripts/deploy/macos/generals-deploy.sh full macos enhanced \
  --ipa ~/Downloads/GeneralsZH-Enhanced-unsigned.ipa
```

The standardized installer copies:

- app -> `~/Applications/GeneralsZH-Enhanced-Dev.app`
- retail GameData -> `~/GeneralsX/GeneralsZH`
- Enhanced profile -> `~/GeneralsX/Enhanced`

The app launches with:

```text
-mod ~/GeneralsX/Enhanced
```

Runtime log:

```text
~/Library/Logs/GeneralsXZH/enhanced-dev.log
```

To install an already-built artifact without starting a new build:

```bash
./scripts/deploy/macos/generals-deploy.sh download macos enhanced
./scripts/deploy/macos/generals-deploy.sh install macos enhanced \
  --ipa /path/to/GeneralsZH-Enhanced-unsigned.ipa
```
