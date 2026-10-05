#!/usr/bin/env python3
"""Build a selected GeneralsXZH iPad IPA variant from user-supplied sources.

Variants:
- original: native launcher + shared Zero Hour 1.04 GameData
- hub: lightweight Generals Hub engine/launcher shell; Online base data and mods install later
- enhanced: original + Zero Hour Enhanced profile
- contra: original + Contra X Beta 2 + Patch 1 profile
- all: original + Enhanced + Contra X

The launcher-only shell is produced by GitHub Actions and downloaded by
scripts/build/ios/windows/build-launcher.ps1.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import importlib.util
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parents[2]
HUB_CATALOG = PROJECT_ROOT / "ios" / "hub" / "HubCatalog.json"
LAUNCHER_WEB = PROJECT_ROOT / "launcher_web"
LEGACY_BUILDER = HERE / "build-all-in-one-ipa.py"


def load_builder():
    spec = importlib.util.spec_from_file_location("generalsx_all_in_one", LEGACY_BUILDER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load builder module: {LEGACY_BUILDER}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


b = load_builder()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a selected GeneralsXZH iPad IPA variant.")
    parser.add_argument("--variant", choices=("original", "hub", "enhanced", "contra", "all"), required=True)
    parser.add_argument("--shell", type=Path, required=True)
    parser.add_argument("--base-ipa", type=Path, help="Base full IPA; required for variants that bundle GameData.")
    parser.add_argument("--enhanced", type=Path)
    parser.add_argument("--enhanced-patch", type=Path)
    parser.add_argument("--contra-beta2", type=Path)
    parser.add_argument("--contra-patch1", type=Path)
    parser.add_argument("--online-data", type=Path, help="Optional Generals Online data root containing GeneralsOnlineGameData/")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--skip-md5", action="store_true")
    return parser.parse_args()


def require(path: Path | None, label: str) -> Path:
    if path is None or not path.exists():
        b.die(f"{label} not found: {path}")
    return path


def validate(args: argparse.Namespace) -> None:
    require(args.shell, "launcher shell IPA")
    if args.variant != "hub":
        require(args.base_ipa, "base full IPA")

    if not zipfile.is_zipfile(args.shell):
        b.die(f"shell is not a valid IPA/ZIP: {args.shell}")
    if args.base_ipa is not None and not zipfile.is_zipfile(args.base_ipa):
        b.die(f"base IPA is not a valid IPA/ZIP: {args.base_ipa}")

    if args.online_data is not None:
        require(args.online_data, "Generals Online data root")
        patch = args.online_data / "GeneralsOnlineGameData" / "500_900_CommunityPatch_CoreINI.big"
        require(patch, "Generals Online community patch")

    if args.variant in ("enhanced", "all"):
        enhanced = require(args.enhanced, "Zero Hour Enhanced source")
        if args.enhanced_patch is not None:
            require(args.enhanced_patch, "Zero Hour Enhanced patch")
        elif not b.contains_enhanced_patch(enhanced):
            b.die(
                "Enhanced patch 28/03/2024 is not present in the Enhanced source. "
                "Either keep !!ZHE8Patch_99.big in ZHE or pass --enhanced-patch."
            )

    if args.variant in ("contra", "all"):
        beta = require(args.contra_beta2, "Contra X Beta 2")
        patch = require(args.contra_patch1, "Contra X Beta 2 Patch 1")
        if not args.skip_md5:
            for label, path, expected in (
                ("Contra X Beta 2", beta, b.EXPECTED_CONTRA_BETA2_MD5),
                ("Contra X Beta 2 Patch 1", patch, b.EXPECTED_CONTRA_PATCH1_MD5),
            ):
                if path.is_file() and zipfile.is_zipfile(path):
                    actual = b.md5_file(path)
                    if actual.lower() != expected.lower():
                        b.die(
                            f"{label} MD5 mismatch for {path.name}: "
                            f"expected {expected}, got {actual}."
                        )
                    print(f"MD5 OK: {label} ({actual})")


def main() -> None:
    args = parse_args()
    validate(args)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        args.output.unlink()

    want_enhanced = args.variant in ("enhanced", "all")
    want_contra = args.variant in ("contra", "all")

    print(f"=== GeneralsXZH iPad builder: {args.variant} ===")
    print(f"Shell:      {args.shell}")
    if args.base_ipa is not None:
        print(f"Base 1.04:  {args.base_ipa}")
    else:
        print("Base 1.04:  external downloadable package")
    if want_enhanced:
        print(f"Enhanced:   {args.enhanced}")
    if want_contra:
        print(f"Contra B2:  {args.contra_beta2}")
        print(f"Contra P1:  {args.contra_patch1}")
    if args.online_data is not None:
        print(f"Online data: {args.online_data}")
    print(f"Output:     {args.output}")
    print()

    base_ctx = (
        zipfile.ZipFile(args.base_ipa, "r")
        if args.base_ipa is not None
        else contextlib.nullcontext(None)
    )
    enhanced_ctx = (
        b.ModSource(args.enhanced)
        if want_enhanced and args.enhanced is not None
        else contextlib.nullcontext(None)
    )
    enhanced_patch_ctx = (
        b.ModSource(args.enhanced_patch)
        if want_enhanced and args.enhanced_patch is not None
        else contextlib.nullcontext(None)
    )
    contra_beta_ctx = (
        b.ModSource(args.contra_beta2)
        if want_contra and args.contra_beta2 is not None
        else contextlib.nullcontext(None)
    )
    contra_patch_ctx = (
        b.ModSource(args.contra_patch1)
        if want_contra and args.contra_patch1 is not None
        else contextlib.nullcontext(None)
    )

    with (
        zipfile.ZipFile(args.shell, "r") as shell,
        base_ctx as base,
        enhanced_ctx as enhanced_source,
        enhanced_patch_ctx as enhanced_patch_source,
        contra_beta_ctx as contra_beta_source,
        contra_patch_ctx as contra_patch_source,
        zipfile.ZipFile(
            args.output,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=6,
            allowZip64=True,
        ) as out,
    ):
        shell_app = b.find_single_app(shell.namelist())
        base_app = b.find_single_app(base.namelist()) if base is not None else None

        # Copy the current native engine/runtime shell, never stale data/profiles.
        skipped_prefixes = (shell_app + "GameData/", shell_app + "Profiles/")
        if args.variant == "hub":
            skipped_prefixes += (shell_app + "Launcher/",)
        shell_bytes = 0
        for info in shell.infolist():
            name = info.filename.replace("\\", "/")
            if info.is_dir() or any(name.startswith(prefix) for prefix in skipped_prefixes):
                continue
            if args.variant == "hub" and name.lower() == (shell_app + "HubCatalog.json").lower():
                continue
            shell_bytes += b.zip_copy(shell, info, out, name)

        online_sources: list[tuple[Path, str]] = []
        online_rel_lower: set[str] = set()
        if args.online_data is not None:
            online_sources = [
                (source, source.relative_to(args.online_data).as_posix())
                for source in sorted(path for path in args.online_data.rglob("*") if path.is_file())
            ]
            online_rel_lower = {rel.lower() for _, rel in online_sources}

        # Shared retail Zero Hour 1.04 data. The Hub intentionally keeps this
        # external so the signed IPA stays small and every profile reuses one
        # installed Online/base package.
        base_bytes = 0
        base_files = 0
        if base is not None and base_app is not None:
            base_prefix = base_app + "GameData/"
            for info in base.infolist():
                name = info.filename.replace("\\", "/")
                if info.is_dir() or not name.startswith(base_prefix):
                    continue
                rel = name[len(base_prefix):]
                if not rel:
                    continue
                if rel.replace("\\", "/").lower() in online_rel_lower:
                    continue
                base_bytes += b.zip_copy(base, info, out, shell_app + "GameData/" + rel)
                base_files += 1
            if base_files == 0:
                b.die("base IPA contains no GameData files")

        online_bytes = 0
        online_count = 0
        if args.online_data is not None:
            for source, rel in online_sources:
                payload = source.read_bytes()
                out.writestr(shell_app + "GameData/" + rel, payload)
                online_bytes += len(payload)
                online_count += 1

        if args.variant == "hub":
            if not HUB_CATALOG.is_file():
                b.die(f"Hub catalog not found: {HUB_CATALOG}")
            if not LAUNCHER_WEB.is_dir():
                b.die(f"Hub web launcher not found: {LAUNCHER_WEB}")
            out.writestr(shell_app + "HubCatalog.json", HUB_CATALOG.read_bytes())
            launcher_files = 0
            for source in sorted(path for path in LAUNCHER_WEB.rglob("*") if path.is_file()):
                rel = source.relative_to(LAUNCHER_WEB).as_posix()
                out.writestr(shell_app + "Launcher/" + rel, source.read_bytes())
                launcher_files += 1
            if launcher_files < 3:
                b.die("Hub web launcher looks incomplete")

        enhanced_bytes = 0
        enhanced_count = 0
        if want_enhanced:
            assert enhanced_source is not None
            sources = [enhanced_source]
            if enhanced_patch_source is not None:
                sources.append(enhanced_patch_source)
            entries = b.build_enhanced_entries(sources)
            enhanced_count = len(entries)
            for entry, rel in entries:
                enhanced_bytes += b.write_source_entry(
                    entry,
                    shell_app + "Profiles/enhanced/" + b.normalized_rel(rel),
                    out,
                )
            ai_archives = b.build_enhanced_ai_archives(entries)
            for rel, payload in ai_archives.items():
                target = shell_app + "Profiles/enhanced/" + rel
                info = zipfile.ZipInfo(target)
                info.date_time = (2026, 1, 1, 0, 0, 0)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                out.writestr(info, payload)
                enhanced_bytes += len(payload)
            enhanced_count += len(ai_archives)

        contra_bytes = 0
        contra_count = 0
        if want_contra:
            assert contra_beta_source is not None and contra_patch_source is not None
            entries, _ = b.build_contra_entries(contra_beta_source, contra_patch_source)
            contra_count = len(entries)
            for entry, rel in entries:
                contra_bytes += b.write_source_entry(
                    entry,
                    shell_app + "Profiles/contra-x/" + b.normalized_rel(rel),
                    out,
                )

        # Dedicated single-profile IPAs behave like standalone games while
        # keeping the native settings/diagnostics launcher available. All-in-one
        # intentionally has no marker and keeps the normal profile chooser.
        dedicated_profile = {
            "enhanced": "enhanced",
            "contra": "contra-x",
        }.get(args.variant)
        if dedicated_profile is not None:
            out.writestr(shell_app + "AutoLaunchProfile.txt", dedicated_profile + "\n")

    print()
    print("DONE")
    print(f"Shell/runtime: {shell_bytes / 1024 / 1024:.1f} MB raw")
    if args.variant == "hub":
        print("GameData:      external (downloadable online.gxmod)")
    else:
        print(f"GameData:      {base_bytes / 1024 / 1024:.1f} MB raw ({base_files} files)")
    if args.online_data is not None:
        print(f"Online data:   {online_bytes / 1024 / 1024:.1f} MB raw ({online_count} files)")
    if want_enhanced:
        print(f"Enhanced:      {enhanced_bytes / 1024 / 1024:.1f} MB raw ({enhanced_count} files)")
    if want_contra:
        print(f"Contra X:      {contra_bytes / 1024 / 1024:.1f} MB raw ({contra_count} files)")
    print(f"IPA:           {args.output.stat().st_size / 1024 / 1024:.1f} MB")
    print(f"Path:          {args.output.resolve()}")


if __name__ == "__main__":
    main()
