#!/usr/bin/env python3
"""Sync the official Generals Online data patch used for Apple/Windows parity."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

DEFAULT_MANIFEST_URL = "https://cdn.playgenerals.online/manifest.json"
PATCH_MEMBER = "GeneralsOnlineGameData/500_900_CommunityPatch_CoreINI.big"
MAPS_PREFIX = "Maps/"
WINDOWS_60_EXE = "GeneralsOnlineZH_60.exe"
METADATA_NAME = "generals-online-parity.json"


def parse_int(value: str) -> int:
    return int(value, 0)


def shift_add_crc(data: bytes, seed: int = 0) -> int:
    crc = seed & 0xFFFFFFFF
    for byte in data:
        high = 1 if crc & 0x80000000 else 0
        crc = ((crc << 1) & 0xFFFFFFFF)
        crc = (crc + byte + high) & 0xFFFFFFFF
    return crc


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def load_json_url(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "GeneralsXZH-Apple-Builder/1"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def download(url: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".part")
    if tmp.exists():
        tmp.unlink()
    req = urllib.request.Request(url, headers={"User-Agent": "GeneralsXZH-Apple-Builder/1"})
    with urllib.request.urlopen(req, timeout=120) as response, tmp.open("wb") as out:
        shutil.copyfileobj(response, out)
    tmp.replace(path)


def ready_metadata(dest: Path, expected_version: str, expected_seed: int) -> dict | None:
    metadata_path = dest / "GeneralsOnlineGameData" / METADATA_NAME
    patch_path = dest / PATCH_MEMBER
    if not metadata_path.is_file() or not patch_path.is_file():
        return None
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if metadata.get("version") != expected_version:
        return None
    if int(metadata.get("windows_60_shift_add_seed", -1)) != expected_seed:
        return None
    expected_patch_hash = str(metadata.get("patch_sha256", "")).upper()
    if not expected_patch_hash or sha256_file(patch_path) != expected_patch_hash:
        return None
    expected_maps = int(metadata.get("maps_file_count", 0))
    maps_root = dest / "Maps"
    if expected_maps <= 0 or not maps_root.is_dir():
        return None
    actual_maps = sum(1 for path in maps_root.rglob("*") if path.is_file())
    if actual_maps < expected_maps:
        return None
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dest", type=Path, required=True, help="GameData root or staging root")
    parser.add_argument("--cache-dir", type=Path, required=True)
    parser.add_argument("--manifest-url", default=DEFAULT_MANIFEST_URL)
    parser.add_argument("--expected-version", default="100126_QFE6A")
    parser.add_argument("--expected-seed", type=parse_int, default=0x808CB29E)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()

    args.dest.mkdir(parents=True, exist_ok=True)
    args.cache_dir.mkdir(parents=True, exist_ok=True)

    if not args.refresh:
        cached = ready_metadata(args.dest, args.expected_version, args.expected_seed)
        if cached is not None:
            print(f"GO DATA READY: version={cached['version']} seed=0x{args.expected_seed:08X}")
            print(args.dest / PATCH_MEMBER)
            return 0

    manifest = load_json_url(args.manifest_url)
    version = str(manifest.get("version", "")).strip()
    download_url = str(manifest.get("download_url", "")).strip()
    archive_sha = str(manifest.get("sha256", "")).strip().upper()
    if version != args.expected_version:
        raise SystemExit(
            f"Official Generals Online version changed: expected {args.expected_version}, got {version}. "
            "Update Apple network parity before packaging."
        )
    if not download_url or not archive_sha:
        raise SystemExit("Official Generals Online manifest is missing download_url or sha256")

    archive = args.cache_dir / f"GeneralsOnline_portable_{version}.zip"
    if not archive.is_file() or sha256_file(archive) != archive_sha:
        if archive.exists():
            archive.unlink()
        print(f"Downloading official Generals Online {version}...")
        download(download_url, archive)
    actual_archive_sha = sha256_file(archive)
    if actual_archive_sha != archive_sha:
        raise SystemExit(f"Portable SHA256 mismatch: expected {archive_sha}, got {actual_archive_sha}")

    with zipfile.ZipFile(archive, "r") as zf:
        names = {name.replace("\\", "/"): name for name in zf.namelist()}
        patch_key = PATCH_MEMBER.replace("\\", "/")
        if patch_key not in names or WINDOWS_60_EXE not in names:
            raise SystemExit("Official portable is missing the community patch or 60 Hz executable")
        patch_bytes = zf.read(names[patch_key])
        exe_bytes = zf.read(names[WINDOWS_60_EXE])
        map_members = sorted(
            (normalized, original)
            for normalized, original in names.items()
            if normalized.startswith(MAPS_PREFIX) and not normalized.endswith("/")
        )

    seed = shift_add_crc(exe_bytes)
    if seed != args.expected_seed:
        raise SystemExit(
            f"Windows 60 Hz shift/add seed changed: expected 0x{args.expected_seed:08X}, got 0x{seed:08X}. "
            "Rebuild the Apple engine with the new parity seed before packaging."
        )

    patch_path = args.dest / PATCH_MEMBER
    patch_path.parent.mkdir(parents=True, exist_ok=True)
    patch_path.write_bytes(patch_bytes)
    patch_sha = hashlib.sha256(patch_bytes).hexdigest().upper()

    maps_bytes = 0
    maps_count = 0
    with zipfile.ZipFile(archive, "r") as zf:
        for normalized, original in map_members:
            rel = Path(*Path(normalized).parts)
            if ".." in rel.parts:
                raise SystemExit(f"Rejected unsafe map path in official portable: {normalized}")
            target = args.dest / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            payload = zf.read(original)
            target.write_bytes(payload)
            maps_bytes += len(payload)
            maps_count += 1

    metadata = {
        "version": version,
        "manifest_url": args.manifest_url,
        "download_url": download_url,
        "portable_sha256": actual_archive_sha,
        "patch_sha256": patch_sha,
        "windows_60_shift_add_seed": seed,
        "windows_60_shift_add_seed_hex": f"0x{seed:08X}",
        "maps_file_count": maps_count,
        "maps_bytes": maps_bytes,
    }
    metadata_path = patch_path.parent / METADATA_NAME
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    print(f"GO DATA READY: version={version} seed=0x{seed:08X}")
    print(f"Patch: {patch_path}")
    print(f"Patch SHA256: {patch_sha}")
    print(f"Official maps: {maps_count} files, {maps_bytes / 1024 / 1024:.1f} MB")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
