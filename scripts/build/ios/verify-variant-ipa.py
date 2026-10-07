#!/usr/bin/env python3
"""Validate one of the local GeneralsXZH iPad IPA variants."""
from __future__ import annotations

import argparse
import json
import sys
import zipfile
from pathlib import PurePosixPath


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def find_app(names: list[str]) -> str:
    apps = set()
    for name in names:
        normalized = name.replace("\\", "/")
        if normalized.startswith("Payload/") and ".app/" in normalized:
            app = normalized.split("/", 2)[1]
            if app.endswith(".app"):
                apps.add(f"Payload/{app}/")
    if len(apps) != 1:
        fail(f"expected one app bundle, found {sorted(apps)}")
    return next(iter(apps))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--variant", choices=("original", "enhanced", "contra", "all"), required=True)
    p.add_argument("ipa")
    p.add_argument("--require-online-data", action="store_true")
    args = p.parse_args()

    if not zipfile.is_zipfile(args.ipa):
        fail(f"not a valid IPA/ZIP: {args.ipa}")

    with zipfile.ZipFile(args.ipa, "r") as z:
        names = [i.filename.replace("\\", "/") for i in z.infolist() if not i.is_dir()]
        lower = {n.lower() for n in names}
        app = find_app(names)
        app_l = app.lower()

        if app_l + "info.plist" not in lower:
            fail("missing Info.plist")
        if any(n.startswith(app_l + "launcher/") for n in lower):
            fail("legacy web Launcher directory leaked into IPA")

        executable = [
            n for n in names
            if n.startswith(app)
            and "/" not in n[len(app):]
            and PurePosixPath(n).name.lower() in {"generalsxzh", "z_generals"}
        ]
        if not executable:
            fail("missing GeneralsXZH executable")

        game = [n for n in lower if n.startswith(app_l + "gamedata/")]
        enhanced = [n for n in lower if n.startswith(app_l + "profiles/enhanced/")]
        contra = [n for n in lower if n.startswith(app_l + "profiles/contra-x/")]
        auto_launch_marker = app_l + "autolaunchprofile.txt"

        if args.variant == "contra":
            if auto_launch_marker not in lower:
                fail("Contra-only IPA is missing AutoLaunchProfile.txt")
            marker_name = next(n for n in names if n.lower() == auto_launch_marker)
            marker_value = z.read(marker_name).decode("utf-8", errors="replace").strip()
            if marker_value != "contra-x":
                fail(f"invalid Contra auto-launch profile: {marker_value!r}")
        elif auto_launch_marker in lower:
            fail("unexpected AutoLaunchProfile.txt outside Contra-only variant")

        if len(game) < 10 or not any(n.endswith(".big") for n in game):
            fail("GameData looks incomplete")

        if args.require_online_data:
            patch_name = app_l + "gamedata/generalsonlinegamedata/500_900_communitypatch_coreini.big"
            parity_name = app_l + "gamedata/generalsonlinegamedata/generals-online-parity.json"
            if patch_name not in lower:
                fail("missing official Generals Online community data patch")
            if parity_name not in lower:
                fail("missing Generals Online parity metadata")
            parity_actual = next(n for n in names if n.lower() == parity_name)
            try:
                parity = json.loads(z.read(parity_actual).decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                fail(f"invalid Generals Online parity metadata: {exc}")
            if parity.get("version") != "100126_QFE6A":
                fail(f"unexpected Generals Online data version: {parity.get('version')!r}")
            if int(parity.get("windows_60_shift_add_seed", -1)) != 0x808CB29E:
                fail("unexpected Windows 60 Hz parity seed")
            expected_maps = int(parity.get("maps_file_count", 0))
            map_files = [n for n in lower if n.startswith(app_l + "gamedata/maps/")]
            if expected_maps <= 0 or len(map_files) < expected_maps:
                fail(f"official Generals Online maps are incomplete: expected {expected_maps}, found {len(map_files)}")

        want_e = args.variant in ("enhanced", "all")
        want_c = args.variant in ("contra", "all")

        if want_e:
            if not enhanced or not any(n.endswith(".big") for n in enhanced):
                fail("Enhanced profile is missing or inactive")
        elif enhanced:
            fail("unexpected Enhanced profile in this variant")

        if want_c:
            if not contra:
                fail("Contra X profile is missing")
            required = {
                "_ini.big", "_maps.big", "_ai.big", "_terrain.big",
                "_textures.big", "_w3d.big", "_window.big", "_audio.big",
                "_gamedata.big", "_unitvoicesenglish.big",
                "_hotkeysoriginal_english.big", "_patch1.big",
            }
            missing = [s for s in sorted(required) if not any(n.endswith(s) for n in contra)]
            if missing:
                fail("Contra X missing active archives: " + ", ".join(missing))
        elif contra:
            fail("unexpected Contra X profile in this variant")

        windows_suffixes = (".exe", ".dll", ".bat", ".cmd", ".pdb", ".lnk")
        leaked = [n for n in enhanced + contra if n.endswith(windows_suffixes)]
        if leaked:
            fail("Windows-only files leaked into profiles: " + ", ".join(leaked[:10]))

        print(f"IPA VALID: {args.variant}")
        print(f"GameData files: {len(game)}")
        print(f"Enhanced files: {len(enhanced)}")
        print(f"Contra X files: {len(contra)}")


if __name__ == "__main__":
    main()
