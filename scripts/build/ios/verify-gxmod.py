#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tarfile
from pathlib import PurePosixPath


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def safe_path(name: str) -> bool:
    p = PurePosixPath(name)
    return bool(name) and not p.is_absolute() and ".." not in p.parts and "." not in p.parts


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("package")
    ap.add_argument("--sha256")
    args = ap.parse_args()

    if args.sha256:
        actual = sha256(args.package)
        if actual.lower() != args.sha256.lower():
            fail(f"SHA-256 mismatch: {actual}")

    with tarfile.open(args.package, "r:") as tar:
        members = tar.getmembers()
        if not members or members[0].name != "manifest.json":
            fail("manifest.json must be the first archive entry")
        if not all(safe_path(m.name) for m in members):
            fail("unsafe archive path")
        bad_types = [m.name for m in members if not (m.isfile() or m.isdir())]
        if bad_types:
            fail("links/special entries are forbidden: " + ", ".join(bad_types[:10]))

        manifest_file = tar.extractfile(members[0])
        if manifest_file is None:
            fail("manifest.json cannot be read")
        manifest = json.load(manifest_file)
        for key in ("schemaVersion", "profileId", "name", "version", "profileFiles"):
            if key not in manifest:
                fail(f"manifest missing {key}")
        if manifest["schemaVersion"] != 1:
            fail("unsupported schemaVersion")

        profile_files = [m for m in members if m.isfile() and m.name.startswith("profile/")]
        if len(profile_files) != int(manifest["profileFiles"]):
            fail(
                f"profileFiles mismatch: manifest={manifest['profileFiles']} archive={len(profile_files)}"
            )

    print("GXMOD VALID")
    print(f"Profile: {manifest['profileId']}")
    print(f"Name: {manifest['name']}")
    print(f"Version: {manifest['version']}")
    print(f"Profile files: {len(profile_files)}")
    print(f"SHA-256: {sha256(args.package)}")


if __name__ == "__main__":
    main()
