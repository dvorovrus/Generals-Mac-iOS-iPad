#!/usr/bin/env python3
"""
Build one unsigned iOS IPA containing:
- the current GeneralsXZH engine + embedded Vite launcher (from CI shell IPA),
- shared Zero Hour 1.04 GameData (copied from a user's existing full IPA),
- Zero Hour Enhanced as an isolated -mod profile,
- Contra X Beta 2 + Patch 1 as an isolated -mod profile.

The script never downloads or redistributes retail game data. It only combines
files supplied by the user.

Typical Windows usage:

    py scripts\build\ios\build-all-in-one-ipa.py ^
      --shell GeneralsXZH-launcher-unsigned.ipa ^
      --base-ipa GeneralsZH-FULL-unsigned.ipa ^
      --enhanced ZHE ^
      --contra-beta2 ContraXBeta2.zip ^
      --contra-patch1 ContraXBeta2Patch1.zip

GeneralsX @build dvorovrus 25/09/2026
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import os
import shutil
import sys
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Callable, Iterable

EXPECTED_CONTRA_BETA2_MD5 = "8750dd02d36547b7d3bf6fd233c02675"
EXPECTED_CONTRA_PATCH1_MD5 = "d013988243cb9945f1adeae335921c24"

WINDOWS_ONLY_SUFFIXES = {
    ".exe", ".dll", ".bat", ".cmd", ".pdb", ".lnk",
}
SKIP_DIR_NAMES = {
    "plugins", "reshade-shaders", "screenshots",
}

ZHE_ACTIVATE = {
    "!zhe8windows_98.zhe",
    "!zhe8texturesbasehd_95.zhe",
    "!zhe8texturesbasehd_96.zhe",
    "!zhe8texturesbasehd_97.zhe",
    "!zhe8texturesbasehd_98.zhe",
    "!zhe8texturesbasehd_99.zhe",
}
ZHE_KEEP_INI = {"zhepatch.ini", "defaultpreset.ini"}

# Defaults mirrored from the current official Contra X Beta 2 launcher:
# base content always on, English language/voices, original English hotkeys,
# standard music, normal portraits, Control Bar Pro, HD cameos on widescreen,
# fog effects disabled, water effects enabled, extra building props enabled,
# and Patch 1 enabled.
CONTRA_REQUIRED_CTR_SUFFIXES = {
    "_ini.ctr",
    "_maps.ctr",
    "_ai.ctr",
    "_terrain.ctr",
    "_textures.ctr",
    "_w3d.ctr",
    "_window.ctr",
    "_audio.ctr",
    "_gamedata.ctr",
    "_unitvoicesenglish.ctr",
    "_hotkeysoriginal_english.ctr",
    "_patch1.ctr",
}
CONTRA_OPTIONAL_DEFAULT_CTR_SUFFIXES = {
    "_controlbarpro.ctr",
    "_cameoshd.ctr",
    "_disablefogeffects.ctr",
}


def die(message: str) -> "NoReturn":
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalized_rel(name: str) -> str:
    value = name.replace("\\", "/").lstrip("/")
    while value.startswith("./"):
        value = value[2:]
    parts = [p for p in PurePosixPath(value).parts if p not in ("", ".")]
    if any(p == ".." for p in parts):
        raise ValueError(f"unsafe relative path: {name}")
    return "/".join(parts)


def clone_info(info: zipfile.ZipInfo, name: str) -> zipfile.ZipInfo:
    out = zipfile.ZipInfo(name)
    out.date_time = info.date_time
    out.compress_type = zipfile.ZIP_DEFLATED
    out.comment = info.comment
    out.extra = info.extra
    out.internal_attr = info.internal_attr
    out.external_attr = info.external_attr
    out.create_system = info.create_system
    out.flag_bits = info.flag_bits & ~0x08
    return out


def file_info(name: str, src: Path) -> zipfile.ZipInfo:
    st = src.stat()
    out = zipfile.ZipInfo(name)
    out.date_time = tuple(time.localtime(st.st_mtime)[:6])
    out.compress_type = zipfile.ZIP_DEFLATED
    out.create_system = 3
    out.external_attr = (0o100755 if os.access(src, os.X_OK) else 0o100644) << 16
    return out


def stream_copy(src: BinaryIO, dst: BinaryIO) -> int:
    total = 0
    while True:
        chunk = src.read(1024 * 1024)
        if not chunk:
            break
        dst.write(chunk)
        total += len(chunk)
    return total


def zip_copy(
    zin: zipfile.ZipFile,
    info: zipfile.ZipInfo,
    zout: zipfile.ZipFile,
    target_name: str,
) -> int:
    if info.is_dir():
        return 0
    with zin.open(info, "r") as src, zout.open(clone_info(info, target_name), "w") as dst:
        return stream_copy(src, dst)


def disk_copy(src_path: Path, zout: zipfile.ZipFile, target_name: str) -> int:
    with src_path.open("rb") as src, zout.open(file_info(target_name, src_path), "w") as dst:
        return stream_copy(src, dst)


def find_single_app(names: Iterable[str]) -> str:
    apps = set()
    for raw in names:
        name = raw.replace("\\", "/")
        if not name.startswith("Payload/") or ".app/" not in name:
            continue
        app_component = name.split("/", 2)[1]
        if app_component.endswith(".app"):
            apps.add(f"Payload/{app_component}/")
    if len(apps) != 1:
        die(f"expected exactly one .app in IPA, found: {sorted(apps)}")
    return next(iter(apps))


def md5_file(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


@dataclass
class SourceEntry:
    rel: str
    open_stream: Callable[[], contextlib.AbstractContextManager[BinaryIO]]
    zip_info: zipfile.ZipInfo | None = None
    disk_path: Path | None = None


class ModSource:
    def __init__(self, path: Path):
        self.path = path
        self._zip: zipfile.ZipFile | None = None
        self._entries: list[SourceEntry] = []

    def __enter__(self) -> "ModSource":
        if self.path.is_dir():
            self._load_dir()
        elif self.path.is_file() and zipfile.is_zipfile(self.path):
            self._load_zip()
        else:
            die(f"mod source must be a directory or ZIP: {self.path}")
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        if self._zip is not None:
            self._zip.close()

    @property
    def entries(self) -> list[SourceEntry]:
        return self._entries

    def _load_dir(self) -> None:
        root = unwrap_single_directory(self.path)
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            rel = normalized_rel(path.relative_to(root).as_posix())
            self._entries.append(
                SourceEntry(
                    rel=rel,
                    open_stream=lambda p=path: p.open("rb"),
                    disk_path=path,
                )
            )

    def _load_zip(self) -> None:
        self._zip = zipfile.ZipFile(self.path, "r")
        infos = [i for i in self._zip.infolist() if not i.is_dir()]
        prefix = zip_common_wrapper([i.filename for i in infos])
        for info in infos:
            raw = normalized_rel(info.filename)
            rel = raw[len(prefix):] if prefix and raw.startswith(prefix) else raw
            rel = rel.lstrip("/")
            if not rel:
                continue

            @contextlib.contextmanager
            def opener(z=self._zip, i=info):
                assert z is not None
                with z.open(i, "r") as stream:
                    yield stream

            self._entries.append(
                SourceEntry(rel=rel, open_stream=opener, zip_info=info)
            )


def unwrap_single_directory(root: Path) -> Path:
    current = root
    while True:
        children = [p for p in current.iterdir() if p.name not in {".DS_Store", "__MACOSX"}]
        files = [p for p in children if p.is_file()]
        dirs = [p for p in children if p.is_dir()]
        if files or len(dirs) != 1:
            return current
        current = dirs[0]


def zip_common_wrapper(names: list[str]) -> str:
    cleaned = [normalized_rel(n) for n in names if normalized_rel(n)]
    if not cleaned:
        return ""
    first_components = {name.split("/", 1)[0] for name in cleaned}
    has_root_file = any("/" not in name for name in cleaned)
    if len(first_components) == 1 and not has_root_file:
        return next(iter(first_components)) + "/"
    return ""


def should_skip_common(rel: str) -> bool:
    path = PurePosixPath(rel)
    parts_lower = [p.lower() for p in path.parts]
    if any(part in SKIP_DIR_NAMES for part in parts_lower):
        return True
    if path.suffix.lower() in WINDOWS_ONLY_SUFFIXES:
        return True
    if path.name.lower() in {
        "contra_launcher.exe",
        "launcher.exe",
        "dbghelp.dll",
    }:
        return True
    return False


def build_enhanced_entries(source: ModSource) -> list[tuple[SourceEntry, str]]:
    result: list[tuple[SourceEntry, str]] = []
    seen: set[str] = set()

    for entry in source.entries:
        rel = normalized_rel(entry.rel)
        p = PurePosixPath(rel)
        lower_name = p.name.lower()
        lower_parts = [x.lower() for x in p.parts]

        if should_skip_common(rel):
            continue

        target: str | None = None
        if p.suffix.lower() == ".big":
            target = rel
        elif lower_parts and lower_parts[0] == "data" and p.suffix.lower() not in {
            ".dll", ".exe", ".zhe", ".bat", ".cmd"
        }:
            target = rel
        elif lower_name in ZHE_ACTIVATE:
            target = str(p.with_suffix(".big"))
        elif lower_name in ZHE_KEEP_INI:
            target = rel

        if target is None:
            continue

        key = target.lower()
        if key in seen:
            continue
        seen.add(key)
        result.append((entry, target))

    active = [target for _, target in result if target.lower().endswith(".big")]
    if not active:
        die("Enhanced profile contains no active .big archives")
    return result


def contra_activate_ctr(rel: str) -> bool:
    lower = rel.lower()
    return any(
        lower.endswith(suffix)
        for suffix in (CONTRA_REQUIRED_CTR_SUFFIXES | CONTRA_OPTIONAL_DEFAULT_CTR_SUFFIXES)
    )


def contra_category(rel: str) -> str | None:
    lower = rel.lower()
    for suffix in CONTRA_REQUIRED_CTR_SUFFIXES:
        if lower.endswith(suffix):
            return suffix
    return None


def rewrite_contra_path(rel: str) -> str:
    normalized = normalized_rel(rel)
    lower = normalized.lower()
    if lower.startswith("data/scripts/"):
        return "Data/Scripts1/" + normalized[len("Data/Scripts/"):]
    if lower == "data/scripts":
        return "Data/Scripts1"
    return normalized


def build_contra_entries(
    beta: ModSource,
    patch: ModSource,
) -> tuple[list[tuple[SourceEntry, str]], set[str]]:
    # Patch archive overwrites Beta 2 using Windows-style case-insensitive paths.
    merged: dict[str, SourceEntry] = {}
    for source in (beta, patch):
        for entry in source.entries:
            rel = rewrite_contra_path(entry.rel)
            if should_skip_common(rel):
                continue
            copy = SourceEntry(
                rel=rel,
                open_stream=entry.open_stream,
                zip_info=entry.zip_info,
                disk_path=entry.disk_path,
            )
            merged[rel.lower()] = copy

    output: list[tuple[SourceEntry, str]] = []
    found_required: set[str] = set()
    target_seen: set[str] = set()

    for entry in sorted(merged.values(), key=lambda e: e.rel.lower()):
        rel = entry.rel
        p = PurePosixPath(rel)
        target = rel

        if p.suffix.lower() == ".ctr":
            if contra_activate_ctr(rel):
                category = contra_category(rel)
                if category:
                    found_required.add(category)
                target = str(p.with_suffix(".big"))
            # Leave every non-selected .ctr in place and inactive. This exactly
            # mirrors the Windows launcher attach/detach model.
        elif p.suffix.lower() == ".big":
            # A distributed .big is already active. Count it for validation.
            synthetic_ctr = str(p.with_suffix(".ctr"))
            category = contra_category(synthetic_ctr)
            if category:
                found_required.add(category)

        key = target.lower()
        if key in target_seen:
            continue
        target_seen.add(key)
        output.append((entry, target))

    missing = CONTRA_REQUIRED_CTR_SUFFIXES - found_required
    if missing:
        pretty = ", ".join(sorted(missing))
        die(
            "Contra X profile is missing required/default archives after Beta 2 + "
            f"Patch 1 merge: {pretty}"
        )

    return output, found_required


def write_source_entry(
    entry: SourceEntry,
    target_name: str,
    zout: zipfile.ZipFile,
) -> int:
    if entry.disk_path is not None:
        return disk_copy(entry.disk_path, zout, target_name)

    info = entry.zip_info
    if info is None:
        raise RuntimeError(f"source entry has no backing data: {entry.rel}")

    with entry.open_stream() as src:
        zi = clone_info(info, target_name)
        with zout.open(zi, "w") as dst:
            return stream_copy(src, dst)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build GeneralsXZH all-in-one unsigned iOS IPA."
    )
    parser.add_argument(
        "--shell",
        type=Path,
        default=Path("GeneralsXZH-launcher-unsigned.ipa"),
        help="Unsigned engine+launcher shell IPA from GitHub Actions.",
    )
    parser.add_argument(
        "--base-ipa",
        type=Path,
        default=Path("GeneralsZH-FULL-unsigned.ipa"),
        help="Existing full Zero Hour 1.04 unsigned IPA used only as GameData source.",
    )
    parser.add_argument(
        "--enhanced",
        type=Path,
        default=Path("ZHE"),
        help="Extracted Zero Hour Enhanced directory or ZIP.",
    )
    parser.add_argument(
        "--contra-beta2",
        type=Path,
        default=Path("ContraXBeta2.zip"),
        help="Contra X Beta 2 archive/directory.",
    )
    parser.add_argument(
        "--contra-patch1",
        type=Path,
        default=Path("ContraXBeta2Patch1.zip"),
        help="Contra X Beta 2 Patch 1 archive/directory.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("GeneralsZH-AllInOne-unsigned.ipa"),
        help="Output unsigned IPA.",
    )
    parser.add_argument(
        "--skip-md5",
        action="store_true",
        help="Skip Contra archive MD5 checks.",
    )
    return parser.parse_args()


def validate_inputs(args: argparse.Namespace) -> None:
    for label, path in (
        ("launcher shell IPA", args.shell),
        ("base full IPA", args.base_ipa),
        ("Enhanced", args.enhanced),
        ("Contra X Beta 2", args.contra_beta2),
        ("Contra X Patch 1", args.contra_patch1),
    ):
        if not path.exists():
            die(f"{label} not found: {path}")

    if not zipfile.is_zipfile(args.shell):
        die(f"shell is not a valid IPA/ZIP: {args.shell}")
    if not zipfile.is_zipfile(args.base_ipa):
        die(f"base IPA is not a valid IPA/ZIP: {args.base_ipa}")

    if not args.skip_md5:
        for label, path, expected in (
            ("Contra X Beta 2", args.contra_beta2, EXPECTED_CONTRA_BETA2_MD5),
            ("Contra X Beta 2 Patch 1", args.contra_patch1, EXPECTED_CONTRA_PATCH1_MD5),
        ):
            if path.is_file() and zipfile.is_zipfile(path):
                actual = md5_file(path)
                if actual.lower() != expected.lower():
                    die(
                        f"{label} MD5 mismatch for {path.name}: "
                        f"expected {expected}, got {actual}. "
                        "Use --skip-md5 only if you intentionally use a repacked archive."
                    )
                print(f"MD5 OK: {label} ({actual})")


def main() -> None:
    args = parse_args()
    validate_inputs(args)

    if args.output.exists():
        args.output.unlink()

    print("=== GeneralsXZH all-in-one IPA builder ===")
    print(f"Shell:       {args.shell}")
    print(f"Base 1.04:   {args.base_ipa}")
    print(f"Enhanced:    {args.enhanced}")
    print(f"Contra B2:   {args.contra_beta2}")
    print(f"Contra P1:   {args.contra_patch1}")
    print(f"Output:      {args.output}")
    print()

    with (
        zipfile.ZipFile(args.shell, "r") as shell,
        zipfile.ZipFile(args.base_ipa, "r") as base,
        ModSource(args.enhanced) as enhanced_source,
        ModSource(args.contra_beta2) as contra_beta_source,
        ModSource(args.contra_patch1) as contra_patch_source,
        zipfile.ZipFile(
            args.output,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=6,
            allowZip64=True,
        ) as out,
    ):
        shell_app = find_single_app(shell.namelist())
        base_app = find_single_app(base.namelist())

        launcher_index = shell_app + "Launcher/index.html"
        if launcher_index not in shell.namelist():
            die(
                "shell IPA does not contain Launcher/index.html; "
                "download the all-in-one launcher shell artifact from GitHub Actions"
            )

        print(f"Shell app:    {shell_app}")
        print(f"Base app:     {base_app}")

        # Start with current engine, frameworks, native bridge and Vite launcher.
        skipped_prefixes = (
            shell_app + "GameData/",
            shell_app + "Profiles/",
        )
        shell_bytes = 0
        for info in shell.infolist():
            name = info.filename.replace("\\", "/")
            if info.is_dir():
                continue
            if any(name.startswith(prefix) for prefix in skipped_prefixes):
                continue
            shell_bytes += zip_copy(shell, info, out, name)

        # Copy shared Zero Hour retail data exactly once from the user's known-good IPA.
        base_prefix = base_app + "GameData/"
        base_bytes = 0
        base_files = 0
        for info in base.infolist():
            name = info.filename.replace("\\", "/")
            if info.is_dir() or not name.startswith(base_prefix):
                continue
            rel = name[len(base_prefix):]
            if not rel:
                continue
            target = shell_app + "GameData/" + rel
            base_bytes += zip_copy(base, info, out, target)
            base_files += 1

        if base_files == 0:
            die("base IPA contains no GameData files")

        enhanced_entries = build_enhanced_entries(enhanced_source)
        enhanced_bytes = 0
        for entry, rel in enhanced_entries:
            target = shell_app + "Profiles/enhanced/" + normalized_rel(rel)
            enhanced_bytes += write_source_entry(entry, target, out)

        contra_entries, _ = build_contra_entries(
            contra_beta_source,
            contra_patch_source,
        )
        contra_bytes = 0
        for entry, rel in contra_entries:
            target = shell_app + "Profiles/contra-x/" + normalized_rel(rel)
            contra_bytes += write_source_entry(entry, target, out)

    size = args.output.stat().st_size

    print()
    print("DONE")
    print(f"Shell/runtime:  {shell_bytes / 1024 / 1024:.1f} MB raw")
    print(f"GameData 1.04:  {base_bytes / 1024 / 1024:.1f} MB raw ({base_files} files)")
    print(
        f"Enhanced:       {enhanced_bytes / 1024 / 1024:.1f} MB raw "
        f"({len(enhanced_entries)} staged files)"
    )
    print(
        f"Contra X:       {contra_bytes / 1024 / 1024:.1f} MB raw "
        f"({len(contra_entries)} staged files)"
    )
    print(f"IPA:            {size / 1024 / 1024:.1f} MB")
    print(f"Path:           {args.output.resolve()}")
    print()
    print("The IPA is unsigned. Sign/install it with your normal iOS sideloading tool.")


if __name__ == "__main__":
    main()
