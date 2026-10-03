#!/usr/bin/env python3
"""Prepare split Zero Hour Enhanced profile archives for the private CI input release."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import shutil
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
LEGACY_BUILDER = HERE / "build-all-in-one-ipa.py"
DEFAULT_PART_BYTES = 1750 * 1024 * 1024


def load_builder():
    spec = importlib.util.spec_from_file_location("generals_enhanced_input_builder", LEGACY_BUILDER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {LEGACY_BUILDER}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


b = load_builder()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--enhanced", type=Path, required=True)
    p.add_argument("--output-dir", type=Path, required=True)
    p.add_argument("--max-part-bytes", type=int, default=DEFAULT_PART_BYTES)
    return p.parse_args()


def entry_size(entry) -> int:
    if entry.disk_path is not None:
        return entry.disk_path.stat().st_size
    if entry.zip_info is not None:
        return entry.zip_info.file_size
    raise RuntimeError(f"cannot determine size for {entry.rel}")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_entry(zout: zipfile.ZipFile, entry, target: str) -> None:
    info = zipfile.ZipInfo("ZHE/" + b.normalized_rel(target))
    info.date_time = (2026, 1, 1, 0, 0, 0)
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    with entry.open_stream() as src, zout.open(info, "w") as dst:
        shutil.copyfileobj(src, dst, length=1024 * 1024)


def main() -> None:
    args = parse_args()
    if args.max_part_bytes < 512 * 1024 * 1024:
        raise SystemExit("--max-part-bytes must be at least 512 MiB")
    if not args.enhanced.exists():
        raise SystemExit(f"Enhanced source not found: {args.enhanced}")
    if not b.contains_enhanced_patch(args.enhanced):
        raise SystemExit("Enhanced patch 28/03/2024 (!!ZHE8Patch_99.big) is missing")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for old in args.output_dir.glob("EnhancedProfile-part-*.zip"):
        old.unlink()
    for name in ("enhanced-inputs.json", "enhanced-inputs.sha256"):
        path = args.output_dir / name
        if path.exists():
            path.unlink()

    with b.ModSource(args.enhanced) as source:
        entries = b.build_enhanced_entries([source])

        groups = []
        current = []
        current_bytes = 0
        total_bytes = 0

        for entry, target in entries:
            size = entry_size(entry)
            if size > args.max_part_bytes:
                raise SystemExit(
                    f"single Enhanced file exceeds part limit: {target} ({size} bytes)"
                )
            if current and current_bytes + size > args.max_part_bytes:
                groups.append(current)
                current = []
                current_bytes = 0
            current.append((entry, target, size))
            current_bytes += size
            total_bytes += size
        if current:
            groups.append(current)

        parts = []
        for index, group in enumerate(groups, start=1):
            part = args.output_dir / f"EnhancedProfile-part-{index:02d}.zip"
            with zipfile.ZipFile(part, "w", allowZip64=True) as zout:
                for entry, target, _ in group:
                    write_entry(zout, entry, target)
            digest = sha256(part)
            parts.append(
                {
                    "name": part.name,
                    "sha256": digest,
                    "sizeBytes": part.stat().st_size,
                    "profileFiles": len(group),
                }
            )
            print(
                f"{part.name}: {part.stat().st_size / 1024 / 1024:.1f} MiB, "
                f"{len(group)} files"
            )

    manifest = {
        "schemaVersion": 1,
        "profile": "enhanced",
        "patch": "28/03/2024",
        "patchPresent": True,
        "profileFiles": len(entries),
        "profileBytes": total_bytes,
        "maxPartBytes": args.max_part_bytes,
        "parts": parts,
    }
    (args.output_dir / "enhanced-inputs.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    (args.output_dir / "enhanced-inputs.sha256").write_text(
        "".join(f'{part["sha256"]}  {part["name"]}\n' for part in parts),
        encoding="utf-8",
    )

    print()
    print(f"READY: {args.output_dir.resolve()}")
    print(f"Enhanced profile: {len(entries)} files, {total_bytes / 1024 / 1024:.1f} MiB")
    print(f"Parts: {len(parts)}")


if __name__ == "__main__":
    main()
