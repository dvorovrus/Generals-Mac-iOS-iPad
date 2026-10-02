# macOS — Contra X

Canonical branch: `ios-clean`.

Workflow: `Contra X | macOS | Dev Build`.

## Full flow

Copy/download a full Contra iPad IPA to the Mac, then run:

```bash
./scripts/deploy/macos/generals-deploy.sh full macos contra \
  --ipa ~/Downloads/GeneralsZH-ContraX-unsigned.ipa
```

The standardized installer copies:

- app -> `~/Applications/GeneralsZH-ContraX-Dev.app`
- retail GameData -> `~/GeneralsX/GeneralsZH`
- Contra profile -> `~/GeneralsX/ContraX`

Runtime log:

```text
~/Library/Logs/GeneralsXZH/contra-dev.log
```

To only install the latest already-built artifact:

```bash
./scripts/deploy/macos/generals-deploy.sh download macos contra
./scripts/deploy/macos/generals-deploy.sh install macos contra --ipa /path/to/Contra.ipa
```
