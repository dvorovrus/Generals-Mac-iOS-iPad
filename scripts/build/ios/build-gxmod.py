#!/usr/bin/env python3
"""Build a stream-installable Generals Hub .gxmod package.

The format is a POSIX USTAR archive:
  manifest.json     (must be first)
  profile/<files>   (the mod profile consumed by the existing -mod runtime)

The archive is intentionally uncompressed: Generals BIG/CTR assets are already
compressed or binary-heavy, and an uncompressed TAR can be extracted on iOS in
a streaming pass without holding multi-gigabyte packages in memory.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import sys
import tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILDER_PATH = HERE / "build-all-in-one-ipa.py"


def load_builder():
    spec = importlib.util.spec_from_file_location("generalsx_gxmod_builder", BUILDER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {BUILDER_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


b = load_builder()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Build Generals Hub .gxmod package.")
    p.add_argument("--variant", choices=("enhanced", "contra"), required=True)
    p.add_argument("--enhanced", type=Path)
    p.add_argument("--enhanced-patch", type=Path)
    p.add_argument("--contra-beta2", type=Path)
    p.add_argument("--contra-patch1", type=Path)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--skip-md5", action="store_true")
    return p.parse_args()


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def tar_info(name: str, size: int) -> tarfile.TarInfo:
    info = tarfile.TarInfo(name)
    info.size = size
    info.mode = 0o644
    info.mtime = 0
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    return info


def source_size(entry) -> int:
    if entry.disk_path is not None:
        return entry.disk_path.stat().st_size
    if entry.zip_info is not None:
        return entry.zip_info.file_size
    raise RuntimeError(f"no size for {entry.rel}")


def add_source(tar: tarfile.TarFile, entry, target: str) -> int:
    size = source_size(entry)
    with entry.open_stream() as src:
        tar.addfile(tar_info("profile/" + b.normalized_rel(target), size), src)
    return size


def main() -> None:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        args.output.unlink()

    contexts = []
    generated: dict[str, bytes] = {}
    if args.variant == "enhanced":
        if args.enhanced is None or not args.enhanced.exists():
            b.die("Enhanced source is required")
        contexts.append(b.ModSource(args.enhanced))
        if args.enhanced_patch is not None:
            contexts.append(b.ModSource(args.enhanced_patch))
        elif not b.contains_enhanced_patch(args.enhanced):
            b.die("Enhanced patch 28/03/2024 is missing")

        opened = []
        try:
            opened = [ctx.__enter__() for ctx in contexts]
            entries = b.build_enhanced_entries(opened)
            generated = b.build_enhanced_ai_archives(entries)
            manifest = {
                "schemaVersion": 1,
                "profileId": "enhanced",
                "name": "Zero Hour Enhanced",
                "version": "1.0+2024-03-28",
                "runtimeAdapter": "enhanced",
                "profileFiles": len(entries) + len(generated),
            }
            write_entries = entries
        finally:
            for ctx in reversed(contexts[:len(opened)]):
                ctx.__exit__(None, None, None)
    else:
        if args.contra_beta2 is None or not args.contra_beta2.exists():
            b.die("Contra X Beta 2 source is required")
        if args.contra_patch1 is None or not args.contra_patch1.exists():
            b.die("Contra X Patch 1 source is required")
        if not args.skip_md5:
            for label, path, expected in (
                ("Contra X Beta 2", args.contra_beta2, b.EXPECTED_CONTRA_BETA2_MD5),
                ("Contra X Patch 1", args.contra_patch1, b.EXPECTED_CONTRA_PATCH1_MD5),
            ):
                if path.is_file():
                    actual = b.md5_file(path)
                    if actual.lower() != expected.lower():
                        b.die(f"{label} MD5 mismatch: expected {expected}, got {actual}")
        with b.ModSource(args.contra_beta2) as beta, b.ModSource(args.contra_patch1) as patch:
            entries, _ = b.build_contra_entries(beta, patch)
            # We must write while ZIP-backed SourceEntry streams are alive.
            manifest = {
                "schemaVersion": 1,
                "profileId": "contra-x",
                "name": "Contra X",
                "version": "Beta2+Patch1",
                "runtimeAdapter": "contra",
                "profileFiles": len(entries),
            }
            manifest_bytes = (json.dumps(manifest, indent=2) + "\n").encode()
            total = 0
            with tarfile.open(args.output, "w", format=tarfile.USTAR_FORMAT) as tar:
                tar.addfile(tar_info("manifest.json", len(manifest_bytes)), io.BytesIO(manifest_bytes))
                for entry, rel in entries:
                    total += add_source(tar, entry, rel)
            digest = sha256(args.output)
            args.output.with_suffix(args.output.suffix + ".sha256").write_text(
                f"{digest}  {args.output.name}\n", encoding="utf-8"
            )
            args.output.with_suffix(args.output.suffix + ".json").write_text(
                json.dumps({
                    **manifest,
                    "sha256": digest,
                    "packageBytes": args.output.stat().st_size,
                }, indent=2) + "\n",
                encoding="utf-8",
            )
            print(f"READY: {args.output.resolve()}")
            print(f"Profile files: {len(entries)}")
            print(f"Profile bytes: {total}")
            print(f"Package bytes: {args.output.stat().st_size}")
            print(f"SHA-256: {digest}")
            return

    # Enhanced sources are reopened because entries may be backed by ZIP streams.
    contexts = [b.ModSource(args.enhanced)]
    if args.enhanced_patch is not None:
        contexts.append(b.ModSource(args.enhanced_patch))
    opened = []
    try:
        opened = [ctx.__enter__() for ctx in contexts]
        entries = b.build_enhanced_entries(opened)
        generated = b.build_enhanced_ai_archives(entries)
        manifest["profileFiles"] = len(entries) + len(generated)
        manifest_bytes = (json.dumps(manifest, indent=2) + "\n").encode()
        total = 0
        with tarfile.open(args.output, "w", format=tarfile.USTAR_FORMAT) as tar:
            tar.addfile(tar_info("manifest.json", len(manifest_bytes)), io.BytesIO(manifest_bytes))
            for entry, rel in entries:
                total += add_source(tar, entry, rel)
            for rel, payload in generated.items():
                tar.addfile(tar_info("profile/" + rel, len(payload)), io.BytesIO(payload))
                total += len(payload)
    finally:
        for ctx in reversed(contexts[:len(opened)]):
            ctx.__exit__(None, None, None)

    digest = sha256(args.output)
    args.output.with_suffix(args.output.suffix + ".sha256").write_text(
        f"{digest}  {args.output.name}\n", encoding="utf-8"
    )
    args.output.with_suffix(args.output.suffix + ".json").write_text(
        json.dumps({
            **manifest,
            "sha256": digest,
            "packageBytes": args.output.stat().st_size,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"READY: {args.output.resolve()}")
    print(f"Profile files: {manifest['profileFiles']}")
    print(f"Profile bytes: {total}")
    print(f"Package bytes: {args.output.stat().st_size}")
    print(f"SHA-256: {digest}")


if __name__ == "__main__":
    main()
