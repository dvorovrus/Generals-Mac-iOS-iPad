#!/usr/bin/env python3
"""Build a stream-installable Generals Hub .gxmod package.

The format is a POSIX USTAR archive:
  manifest.json     (must be first)
  profile/<files>   (base GameData for Online, or a mod overlay for Enhanced/Contra)

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
import zipfile
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
    p.add_argument("--variant", choices=("online", "enhanced", "contra", "generic"), required=True)
    p.add_argument("--base-ipa", type=Path, help="Full retail Zero Hour IPA used to build the Online base content package.")
    p.add_argument("--online-data", type=Path, help="Official Generals Online parity-data root merged over retail GameData.")
    p.add_argument("--enhanced", type=Path)
    p.add_argument("--enhanced-patch", type=Path)
    p.add_argument("--contra-beta2", type=Path)
    p.add_argument("--contra-patch1", type=Path)
    p.add_argument("--generic-source", type=Path)
    p.add_argument("--profile-id")
    p.add_argument("--name")
    p.add_argument("--runtime-adapter", default="generic")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--version", help="Override package version written to manifest.json.")
    p.add_argument("--channel", choices=("stable", "beta"), default="stable")
    p.add_argument("--min-hub-version", default="0.1.0")
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


def write_sidecars(output: Path, manifest: dict, total: int) -> None:
    digest = sha256(output)
    output.with_suffix(output.suffix + ".sha256").write_text(
        f"{digest}  {output.name}\n", encoding="utf-8"
    )
    output.with_suffix(output.suffix + ".json").write_text(
        json.dumps({
            **manifest,
            "sha256": digest,
            "packageBytes": output.stat().st_size,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"READY: {output.resolve()}")
    print(f"Profile files: {manifest['profileFiles']}")
    print(f"Profile bytes: {total}")
    print(f"Package bytes: {output.stat().st_size}")
    print(f"SHA-256: {digest}")


def build_online(args: argparse.Namespace) -> None:
    if args.base_ipa is None or not args.base_ipa.exists() or not zipfile.is_zipfile(args.base_ipa):
        b.die("A valid retail Zero Hour base IPA is required for the Online package")
    if args.online_data is None or not args.online_data.exists():
        b.die("Official Generals Online data is required for the Online package")

    required_patch = args.online_data / "GeneralsOnlineGameData" / "500_900_CommunityPatch_CoreINI.big"
    required_parity = args.online_data / "GeneralsOnlineGameData" / "generals-online-parity.json"
    if not required_patch.is_file() or not required_parity.is_file():
        b.die("Generals Online parity data is incomplete")

    online_sources = [
        (path, path.relative_to(args.online_data).as_posix())
        for path in sorted(args.online_data.rglob("*"))
        if path.is_file()
    ]
    online_rel_lower = {rel.lower() for _, rel in online_sources}

    with zipfile.ZipFile(args.base_ipa, "r") as base:
        base_app = b.find_single_app(base.namelist())
        base_prefix = base_app + "GameData/"
        base_entries = []
        for info in base.infolist():
            name = info.filename.replace("\\", "/")
            if info.is_dir() or not name.startswith(base_prefix):
                continue
            rel = name[len(base_prefix):]
            if not rel or rel.lower() in online_rel_lower:
                continue
            base_entries.append((info, rel))

        if not base_entries:
            b.die("Base IPA contains no retail GameData files")

        manifest = {
            "schemaVersion": 1,
            "profileId": "online",
            "name": "Zero Hour + Online",
            "version": args.version or "1.04+GO-100126_QFE6",
            "channel": args.channel,
            "minHubVersion": args.min_hub_version,
            "runtimeAdapter": "online",
            "contentRole": "base",
            "profileFiles": len(base_entries) + len(online_sources),
        }
        manifest_bytes = (json.dumps(manifest, indent=2) + "\n").encode()
        total = 0
        with tarfile.open(args.output, "w", format=tarfile.USTAR_FORMAT) as tar:
            tar.addfile(tar_info("manifest.json", len(manifest_bytes)), io.BytesIO(manifest_bytes))
            for info, rel in base_entries:
                with base.open(info, "r") as src:
                    tar.addfile(tar_info("profile/" + b.normalized_rel(rel), info.file_size), src)
                total += info.file_size
            for source, rel in online_sources:
                size = source.stat().st_size
                with source.open("rb") as src:
                    tar.addfile(tar_info("profile/" + b.normalized_rel(rel), size), src)
                total += size

    write_sidecars(args.output, manifest, total)


def build_generic(args: argparse.Namespace) -> None:
    if args.generic_source is None or not args.generic_source.exists():
        b.die("Generic profile source is required")
    if not args.profile_id:
        b.die("--profile-id is required for generic profiles")
    if not args.name:
        b.die("--name is required for generic profiles")

    with b.ModSource(args.generic_source) as source:
        merged: dict[str, object] = {}
        for entry in source.entries:
            rel = b.normalized_rel(entry.rel)
            if not rel or b.should_skip_common(rel):
                continue
            merged[rel.lower()] = entry

        entries = sorted(
            ((entry, b.normalized_rel(entry.rel)) for entry in merged.values()),
            key=lambda pair: pair[1].lower(),
        )
        if not entries:
            b.die("Generic profile source contains no packageable files")

        manifest = {
            "schemaVersion": 1,
            "profileId": args.profile_id,
            "name": args.name,
            "version": args.version or "1.0",
            "channel": args.channel,
            "minHubVersion": args.min_hub_version,
            "runtimeAdapter": args.runtime_adapter,
            "profileFiles": len(entries),
        }
        manifest_bytes = (json.dumps(manifest, indent=2) + "\n").encode()
        total = 0
        with tarfile.open(args.output, "w", format=tarfile.USTAR_FORMAT) as tar:
            tar.addfile(tar_info("manifest.json", len(manifest_bytes)), io.BytesIO(manifest_bytes))
            for entry, rel in entries:
                total += add_source(tar, entry, rel)

    write_sidecars(args.output, manifest, total)


def main() -> None:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        args.output.unlink()

    if args.variant == "online":
        build_online(args)
        return
    if args.variant == "generic":
        build_generic(args)
        return

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
                "version": args.version or "1.0+2024-03-28",
                "channel": args.channel,
                "minHubVersion": args.min_hub_version,
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
                "version": args.version or "Beta2+Patch1",
                "channel": args.channel,
                "minHubVersion": args.min_hub_version,
                "runtimeAdapter": "contra",
                "profileFiles": len(entries),
            }
            manifest_bytes = (json.dumps(manifest, indent=2) + "\n").encode()
            total = 0
            with tarfile.open(args.output, "w", format=tarfile.USTAR_FORMAT) as tar:
                tar.addfile(tar_info("manifest.json", len(manifest_bytes)), io.BytesIO(manifest_bytes))
                for entry, rel in entries:
                    total += add_source(tar, entry, rel)
            write_sidecars(args.output, manifest, total)
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

    write_sidecars(args.output, manifest, total)


if __name__ == "__main__":
    main()
