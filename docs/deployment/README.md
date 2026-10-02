# Generals Apple deployment handbook

This directory defines one lifecycle for all maintained iPad and macOS variants.

## Standard lifecycle

Every variant follows the same stages:

1. **Update** — fetch the branch that owns the variant.
2. **Build** — GitHub Actions for canonical cloud builds, or a documented local packager where cloud packaging does not exist.
3. **Download** — store the exact artifact under the workspace `artifacts/<platform>/<variant>/<run-id>/`.
4. **Install** — Sideloadly for iPad, app-bundle install for macOS.
5. **Verify** — launch once and confirm the expected profile/version.
6. **Collect logs** — keep device/runtime logs in the standard location before changing code again.

The single source of truth is `scripts/deploy/catalog.json`.

## Variant matrix

| Platform | Variant | Canonical build | Install status |
|---|---|---|---|
| iPad | Original | GitHub Actions | Ready |
| iPad | Contra X | GitHub Actions | Ready |
| iPad | Enhanced | Local Windows packager | Ready |
| iPad | All-in-One | Local Windows packager | Ready |
| iPad | Online | GitHub Actions + Windows GameData packager | Experimental; full IPA build supported |
| macOS | Original | GitHub Actions | Ready |
| macOS | Contra X | GitHub Actions | Ready |
| macOS | Online | GitHub Actions | Experimental but installable |
| macOS | Enhanced | — | Not supported |
| macOS | All-in-One | — | Not supported |

## One-time workspace initialization

Windows:

```powershell
.\scripts\deploy\windows\generals-deploy.ps1 init
```

macOS/Linux shell environments can run:

```bash
python3 scripts/deploy/init-workspace.py
```

This creates the canonical folders without moving or deleting existing user files.

## Canonical commands

### Windows / iPad

```powershell
# Show everything
.\scripts\deploy\windows\generals-deploy.ps1 list

# Build latest Contra iPad and wait
.\scripts\deploy\windows\generals-deploy.ps1 build -Platform ipad -Variant contra -Wait

# Download latest successful Contra iPad artifact
.\scripts\deploy\windows\generals-deploy.ps1 download -Platform ipad -Variant contra

# Prepare it for Sideloadly
.\scripts\deploy\windows\generals-deploy.ps1 install -Platform ipad -Variant contra

# Full update -> build -> download -> install preparation
.\scripts\deploy\windows\generals-deploy.ps1 full -Platform ipad -Variant contra

# Build a complete Generals Online iPad IPA from the latest Online shell + Original GameData
.\scripts\build\ios\windows\build-online.ps1
```

### macOS

```bash
# Show everything
./scripts/deploy/macos/generals-deploy.sh list

# Full Contra flow. The IPA supplies retail GameData + Contra profile.
./scripts/deploy/macos/generals-deploy.sh full macos contra \
  --ipa ~/Downloads/GeneralsZH-ContraX-unsigned.ipa

# Original
./scripts/deploy/macos/generals-deploy.sh full macos original \
  --ipa ~/Downloads/GeneralsZH-iPad-unsigned.ipa

# Online
./scripts/deploy/macos/generals-deploy.sh full macos online \
  --ipa ~/Downloads/GeneralsZH-iPad-unsigned.ipa

# Fast local Online development after GameData is installed once
./scripts/build/macos/build-macos-online-local.sh --run
```

## Workspace layout

The deployment tools use the repository's parent directory as the workspace:

```text
Generals-iPad/
├─ repo/                    # git checkout
├─ input/                   # user-supplied game/mod inputs for local packagers
├─ shell/                   # downloaded reusable engine shell
├─ output/                  # local packager output + iPad logs
│  └─ logs/
└─ artifacts/               # canonical downloaded CI artifacts
   ├─ ipad/
   │  ├─ original/
   │  ├─ contra/
   │  ├─ enhanced/
   │  ├─ all/
   │  └─ online/
   └─ macos/
      ├─ original/
      ├─ contra/
      └─ online/
```

Existing `input/`, `shell/` and `output/` paths are intentionally preserved so older local packaging scripts keep working.

## Per-variant guides

iPad:
- `docs/deployment/ipad/original.md`
- `docs/deployment/ipad/contra.md`
- `docs/deployment/ipad/enhanced.md`
- `docs/deployment/ipad/all-in-one.md`
- `docs/deployment/ipad/online.md`

macOS:
- `docs/deployment/macos/original.md`
- `docs/deployment/macos/contra.md`
- `docs/deployment/macos/online.md`

Troubleshooting:
- `docs/deployment/troubleshooting.md`
