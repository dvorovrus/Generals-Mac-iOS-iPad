#!/usr/bin/env python3
"""Validate one of the local GeneralsXZH iPad IPA variants."""
from __future__ import annotations

import argparse
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

        if len(game) < 10 or not any(n.endswith(".big") for n in game):
            fail("GameData looks incomplete")

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
