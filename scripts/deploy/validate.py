#!/usr/bin/env python3
"""Validate scripts/deploy/catalog.json and deployment documentation coverage."""

from __future__ import annotations

import json
import sys
from pathlib import Path


REQUIRED_GITHUB = {"branch", "workflow", "artifact", "artifactFile"}
REQUIRED_LOCAL = {"branch", "localFallbackScript", "localOutput"}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    deploy = Path(__file__).resolve().parent
    repo = deploy.parents[1]
    catalog_path = deploy / "catalog.json"
    data = json.loads(catalog_path.read_text(encoding="utf-8"))

    if data.get("schemaVersion") != 1:
        fail("unsupported catalog schemaVersion")
    if not data.get("repository"):
        fail("repository is required")

    errors: list[str] = []
    for platform, variants in data.get("variants", {}).items():
        for key, cfg in variants.items():
            where = f"{platform}/{key}"
            mode = cfg.get("buildMode")
            if mode not in {"github", "local", "none"}:
                errors.append(f"{where}: invalid buildMode {mode!r}")
                continue

            required = REQUIRED_GITHUB if mode == "github" else REQUIRED_LOCAL if mode == "local" else set()
            missing = sorted(field for field in required if not cfg.get(field))
            if missing:
                errors.append(f"{where}: missing {', '.join(missing)}")

            if cfg.get("installReady") and platform == "ipad" and cfg.get("installMode") != "sideloadly":
                errors.append(f"{where}: install-ready iPad variant must use sideloadly")
            if cfg.get("installReady") and platform == "macos" and not cfg.get("appName"):
                errors.append(f"{where}: install-ready macOS variant needs appName")

            doc_name = "all-in-one" if key == "all" else key
            doc = repo / "docs" / "deployment" / platform / f"{doc_name}.md"
            if cfg.get("status") != "not-supported" and not doc.is_file():
                errors.append(f"{where}: missing guide {doc.relative_to(repo)}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)

    print("deployment catalog OK")


if __name__ == "__main__":
    main()
