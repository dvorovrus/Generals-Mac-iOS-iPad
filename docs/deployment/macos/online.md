# macOS — Generals Online

Canonical branch: `feature/generals-online-apple`.

Workflow: `Online | macOS | Build`.

Status: experimental, but the macOS app is installable.

## Fast local development

Use the existing repository checkout on `feature/generals-online-apple`; a second worktree is not required.

Generals Online keeps clean Zero Hour data separately at:

```text
~/GeneralsX/Online/GeneralsZH
```

If clean Zero Hour data already exists at `~/GeneralsX/GeneralsZH`, initialize Online data once with:

```bash
mkdir -p ~/GeneralsX/Online/GeneralsZH
rsync -a --delete ~/GeneralsX/GeneralsZH/ ~/GeneralsX/Online/GeneralsZH/
```

Verify that retail BIG archives are present:

```bash
find ~/GeneralsX/Online/GeneralsZH -maxdepth 1 -type f -iname "*.big" | wc -l
```

If there is no existing clean GameData directory, install it once from an Original/full IPA:

```bash
bash scripts/build/macos/install-macos-online-data.sh /path/to/GeneralsZH-FULL-unsigned.ipa
```

After that, the normal edit/test loop is only:

```bash
git pull --ff-only
./scripts/build/macos/build-macos-online-local.sh --run
```

The first run configures `macos-vulkan-online`. Later runs reuse `build/macos-vulkan-online` and rebuild only changed targets.

Useful options:

```bash
# Force CMake reconfigure when presets/build configuration changed.
./scripts/build/macos/build-macos-online-local.sh --configure --run

# Remove only the Online build/package outputs and rebuild from scratch.
./scripts/build/macos/build-macos-online-local.sh --clean --run
```

Local outputs:

```text
build/macos-vulkan-online/
build/macos-online-package/GeneralsZH-Online-Dev.app
GeneralsZH-Online-macos-arm64.tar
```

Runtime log:

```text
~/Library/Logs/GeneralsXZH/online-dev.log
```

## Cloud artifact flow

To build/download/install the GitHub Actions macOS artifact instead:

```bash
./scripts/deploy/macos/generals-deploy.sh full macos online \
  --ipa ~/Downloads/GeneralsZH-iPad-unsigned.ipa
```

That flow installs the app to `~/Applications/GeneralsZH-Online-Dev.app` and extracts retail GameData from the supplied IPA.

Use an Original/full IPA as the data source. Mod profiles are intentionally not imported into the Online runtime.

## Two-client headless Online smoke test

The macOS Online build includes an opt-in E2E smoke mode for clean Zero Hour. Normal launches are unchanged.

The automated path validates cached authentication, WebSocket connection, lobby creation/discovery/join, P2P/TURN full-mesh connectivity, `START_GAME`, map loading, and a configurable number of gameplay frames.

Two different Generals Online accounts are required. Prepare their isolated Keychain profiles once:

```bash
bash scripts/build/macos/run-online-smoke-local.sh --prepare host
bash scripts/build/macos/run-online-smoke-local.sh --prepare guest
```

Each command opens the normal Online client. Enter Online, finish the browser login for that profile, then close the game. The ordinary account keeps using the existing `refresh_token` Keychain entry; smoke profiles use separate `refresh_token:smoke-host` and `refresh_token:smoke-guest` entries.

After both profiles are prepared:

```bash
bash scripts/build/macos/run-online-smoke-local.sh
```

Optional bounds:

```bash
bash scripts/build/macos/run-online-smoke-local.sh --frames 600 --timeout 180
```

Per-client logs and machine-readable `.result` files are written under:

```text
build/online-smoke-results/
```

The script exits successfully only when both clients reach the gameplay frame target.

## Windows ↔ macOS cross-play test

Current validation branch: `feature/online-deterministic-math` (until the deterministic fixes are promoted back to the canonical Online branch).

For the real compatibility test, use the official Windows Generals Online client as the external peer and run only one automated Mac client.

The runner automatically uses a local dev app when present, otherwise it uses `~/Applications/GeneralsZH-Online-Dev.app` installed by the cloud deployment flow.

Prepare one dedicated macOS Keychain profile once:

```bash
bash scripts/build/macos/run-online-crossplay-local.sh --prepare
```

### Windows hosts, Mac joins

1. Start the official Windows client through `EAC_LaunchGeneralsOnline.exe`.
2. Create a public 2-player room with a unique name.
3. On the Mac run:

```bash
bash scripts/build/macos/run-online-crossplay-local.sh \
  --role guest \
  --room "GX-WIN-MAC-001"
```

Use exactly the same room name on Windows. The Mac client searches for the room, rejects it if the Windows network CRC or INI CRC is incompatible, joins it, marks ready, waits for the Windows host to start, then validates that synchronized gameplay actually advances.

### Mac hosts, Windows joins

Start:

```bash
bash scripts/build/macos/run-online-crossplay-local.sh \
  --role host \
  --room "GX-MAC-WIN-001"
```

Then join that public room from the official Windows client and mark Ready. The Mac host performs the full-mesh connectivity check and requests `START_GAME` after the Windows peer is ready.

Cross-play logs and machine-readable results are written under:

```text
build/online-crossplay-results/
```

A run passes only after the external peer has joined, the lobby/CRC checks have succeeded, P2P or TURN connectivity has reached the game-start path, the map has loaded, and the configured gameplay frame target has been reached.
