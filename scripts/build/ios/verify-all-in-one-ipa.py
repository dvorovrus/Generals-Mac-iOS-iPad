#!/usr/bin/env python3
"""Validate a GeneralsXZH all-in-one unsigned iOS IPA.

Checks the bundle layout produced by build-all-in-one-ipa.py without requiring
retail/mod data to be stored in the repository.

GeneralsX @build dvorovrus 26/09/2026
"""
from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import PurePosixPath


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def find_app(names: list[str]) -> str:
    apps: set[str] = set()
    for name in names:
        normalized = name.replace("\\", "/")
        if normalized.startswith("Payload/") and ".app/" in normalized:
            component = normalized.split("/", 2)[1]
            if component.endswith(".app"):
                apps.add(f"Payload/{component}/")
    if len(apps) != 1:
        fail(f"expected one .app bundle, found {sorted(apps)}")
    return next(iter(apps))


def lower_names(names: list[str]) -> set[str]:
    return {name.replace("\\", "/").lower() for name in names}


def require_file(names_lower: set[str], path: str, label: str) -> None:
    if path.lower() not in names_lower:
        fail(f"missing {label}: {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa")
    args = parser.parse_args()

    if not zipfile.is_zipfile(args.ipa):
        fail(f"not a valid IPA/ZIP: {args.ipa}")

    with zipfile.ZipFile(args.ipa, "r") as z:
        names = [i.filename.replace("\\", "/") for i in z.infolist() if not i.is_dir()]
        names_lower = lower_names(names)
        app = find_app(names)

        require_file(names_lower, app + "Launcher/index.html", "Vite launcher")
        require_file(names_lower, app + "Info.plist", "Info.plist")

        executable_candidates = [
            n for n in names
            if n.startswith(app)
            and "/" not in n[len(app):]
            and PurePosixPath(n).name.lower() in {"generalsxzh", "z_generals"}
        ]
        if not executable_candidates:
            fail("missing GeneralsXZH executable in app root")

        game_prefix = (app + "GameData/").lower()
        enhanced_prefix = (app + "Profiles/enhanced/").lower()
        contra_prefix = (app + "Profiles/contra-x/").lower()

        game_files = [n for n in names_lower if n.startswith(game_prefix)]
        enhanced_files = [n for n in names_lower if n.startswith(enhanced_prefix)]
        contra_files = [n for n in names_lower if n.startswith(contra_prefix)]

        if len(game_files) < 10:
            fail(f"GameData looks incomplete: only {len(game_files)} files")
        if not any(n.endswith(".big") for n in game_files):
            fail("GameData contains no .big archives")

        if not enhanced_files:
            fail("Enhanced profile is empty")
        enhanced_big = [n for n in enhanced_files if n.endswith(".big")]
        if not enhanced_big:
            fail("Enhanced profile contains no active .big archives")

        if not contra_files:
            fail("Contra X profile is empty")

        required_contra_suffixes = {
            "_ini.big",
            "_maps.big",
            "_ai.big",
            "_terrain.big",
            "_textures.big",
            "_w3d.big",
            "_window.big",
            "_audio.big",
            "_gamedata.big",
            "_unitvoicesenglish.big",
            "_hotkeysoriginal_english.big",
            "_patch1.big",
        }
        missing = [
            suffix
            for suffix in sorted(required_contra_suffixes)
            if not any(n.endswith(suffix) for n in contra_files)
        ]
        if missing:
            fail("Contra X missing active archives: " + ", ".join(missing))

        windows_suffixes = (".exe", ".dll", ".bat", ".cmd", ".pdb", ".lnk")
        profile_windows_files = [
            n for n in enhanced_files + contra_files
            if n.endswith(windows_suffixes)
        ]
        if profile_windows_files:
            fail(
                "Windows-only files leaked into iOS profiles: "
                + ", ".join(profile_windows_files[:10])
            )

        active_contra = sum(1 for n in contra_files if n.endswith(".big"))
        inactive_contra = sum(1 for n in contra_files if n.endswith(".ctr"))

        print("ALL-IN-ONE IPA VALID")
        print(f"App:             {app}")
        print(f"GameData files:  {len(game_files)}")
        print(f"Enhanced files:  {len(enhanced_files)} ({len(enhanced_big)} active BIG)")
        print(
            f"Contra X files:  {len(contra_files)} "
            f"({active_contra} active BIG, {inactive_contra} inactive CTR)"
        )
        print("Contra Patch 1:  active")


if __name__ == "__main__":
    main()
