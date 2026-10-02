# macOS — Generals Online

Canonical branch: `feature/generals-online-apple`.

Workflow: `Online | macOS | Build`.

Status: experimental, but the macOS app is installable.

## Fast local development

Install clean Zero Hour GameData once into:

```text
~/GeneralsX/Online/GeneralsZH
```

Then the normal edit/test loop is:

```bash
git pull --ff-only
./scripts/build/macos/build-macos-online-local.sh --run
```

The first run configures `macos-vulkan-online`. Later runs are incremental and rebuild only changed targets.

Useful options:

```bash
./scripts/build/macos/build-macos-online-local.sh --configure
./scripts/build/macos/build-macos-online-local.sh --clean --run
```

Local app:

```text
build/macos-online-package/GeneralsZH-Online-Dev.app
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
