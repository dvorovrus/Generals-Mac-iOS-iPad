#!/usr/bin/env python3
"""Create the canonical local deployment workspace without moving user files."""

from pathlib import Path


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    workspace = repo.parent
    paths = [
        workspace / "input",
        workspace / "shell",
        workspace / "output",
        workspace / "output" / "logs",
    ]
    for platform, variants in {
        "ipad": ("original", "contra", "enhanced", "all", "online"),
        "macos": ("original", "contra", "online"),
    }.items():
        for variant in variants:
            paths.append(workspace / "artifacts" / platform / variant)

    for path in paths:
        path.mkdir(parents=True, exist_ok=True)
        print(path)


if __name__ == "__main__":
    main()
