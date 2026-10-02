#!/usr/bin/env python3
"""Extract user-supplied retail GameData and an optional mod profile from an IPA."""

from __future__ import annotations

import argparse
import shutil
import sys
import zipfile
from pathlib import Path, PurePosixPath


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def safe_rel(raw: str) -> Path:
    p = PurePosixPath(raw)
    if any(part in ("", ".", "..") for part in p.parts):
        fail(f"unsafe IPA path: {raw}")
    return Path(*p.parts)


def find_app_prefix(names: list[str]) -> str:
    apps: set[str] = set()
    for raw in names:
        name = raw.replace("\\", "/")
        if not name.startswith("Payload/") or ".app/" not in name:
            continue
        app = name.split("/", 2)[1]
        if app.endswith(".app"):
            apps.add(f"Payload/{app}/")
    if len(apps) != 1:
        fail(f"expected one app bundle, found {sorted(apps)}")
    return next(iter(apps))


def extract_prefix(z: zipfile.ZipFile, prefix: str, target: Path) -> tuple[int, int]:
    files = 0
    total = 0
    for info in z.infolist():
        name = info.filename.replace("\\", "/")
        if info.is_dir() or not name.startswith(prefix):
            continue
        rel = name[len(prefix):]
        if not rel:
            continue
        dst = target / safe_rel(rel)
        dst.parent.mkdir(parents=True, exist_ok=True)
        with z.open(info, "r") as src, dst.open("wb") as out:
            shutil.copyfileobj(src, out, 1024 * 1024)
        files += 1
        total += info.file_size
    return files, total


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--ipa", type=Path, required=True)
    p.add_argument("--game-target", type=Path, required=True)
    p.add_argument("--profile")
    p.add_argument("--profile-target", type=Path)
    p.add_argument("--replace", action="store_true")
    args = p.parse_args()

    if not args.ipa.is_file() or not zipfile.is_zipfile(args.ipa):
        fail(f"not a valid IPA/ZIP: {args.ipa}")
    if bool(args.profile) != bool(args.profile_target):
        fail("--profile and --profile-target must be used together")

    if args.replace:
        shutil.rmtree(args.game_target, ignore_errors=True)
        if args.profile_target:
            shutil.rmtree(args.profile_target, ignore_errors=True)

    args.game_target.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(args.ipa, "r") as z:
        app = find_app_prefix(z.namelist())
        game_prefix = app + "GameData/"
        game_files, game_bytes = extract_prefix(z, game_prefix, args.game_target)
        if game_files == 0:
            fail("IPA contains no GameData files")

        profile_files = 0
        profile_bytes = 0
        if args.profile and args.profile_target:
            args.profile_target.mkdir(parents=True, exist_ok=True)
            profile_prefix = app + f"Profiles/{args.profile}/"
            profile_files, profile_bytes = extract_prefix(z, profile_prefix, args.profile_target)
            if profile_files == 0:
                fail(f"IPA contains no profile: {args.profile}")

    print(f"GameData: {game_files} files, {game_bytes / 1024 / 1024:.1f} MiB -> {args.game_target}")
    if args.profile_target:
        print(
            f"Profile {args.profile}: {profile_files} files, "
            f"{profile_bytes / 1024 / 1024:.1f} MiB -> {args.profile_target}"
        )


if __name__ == "__main__":
    main()
