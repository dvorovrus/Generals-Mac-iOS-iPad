# macOS — Original Zero Hour

Canonical branch: `main`.

Workflow: `Original | macOS | Build`.

## Full flow

On the Mac:

```bash
./scripts/deploy/macos/generals-deploy.sh full macos original \
  --ipa ~/Downloads/GeneralsZH-iPad-unsigned.ipa
```

The script:

1. fetches the relevant branch;
2. triggers and waits for the macOS workflow;
3. downloads artifact `macos-generalsxzh-app`;
4. extracts/copies `GeneralsXZH.app` to `~/Applications`;
5. extracts retail GameData from the IPA into `~/GeneralsX/GeneralsZH`;
6. removes quarantine metadata;
7. optionally launches with `--run`.

The IPA is used only as the user's local source of retail GameData.
