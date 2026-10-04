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

The app opens a native Enhanced settings launcher first. After Save/Play it builds `~/GeneralsX/EnhancedRuntime` from the immutable source profile and launches with:

```text
-mod ~/GeneralsX/EnhancedRuntime
```

Available Enhanced-specific options are faction textures (`Vanilla`/`High`), UI quality (`HD`/`FHD`/`QHD`), infantry icons (`100%`/`75%`/`50%`), Cameos (`SD`/`HD`), and AI scripts (`Default`/`Restrained`/`Skynet`). Selected visual/AI overlays are renamed to last-sorting `zzzz__...` runtime archives so they win `-mod` archive precedence. ReShade/DXWrapper remain excluded because they require the Windows DLL path.

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
