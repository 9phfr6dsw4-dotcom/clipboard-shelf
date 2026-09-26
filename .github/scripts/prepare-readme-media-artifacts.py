#!/usr/bin/env python3
"""Safely clear the manual README-media artifact directory under RUNNER_TEMP."""
from __future__ import annotations

from pathlib import Path
import os
import shutil
import sys


def prepare(runner_temp: str, artifact_dir: str) -> None:
    runner_argument = Path(runner_temp)
    artifact_argument = Path(artifact_dir)
    if not runner_argument.is_absolute() or not artifact_argument.is_absolute():
        raise SystemExit("RUNNER_TEMP and artifact directory must be absolute paths")

    try:
        runner_root = runner_argument.resolve(strict=True)
        runner_lexical = Path(os.path.abspath(runner_argument))
        if runner_root != runner_lexical:
            raise SystemExit("RUNNER_TEMP path contains a symlink; refusing artifact cleanup")
        if not runner_root.is_dir():
            raise SystemExit("RUNNER_TEMP is not a directory")
    except (OSError, RuntimeError) as error:
        raise SystemExit(f"RUNNER_TEMP is unavailable: {error}") from error

    expected_artifact = runner_argument / "readme-media"
    if artifact_argument != expected_artifact:
        raise SystemExit("Refusing to clean any directory except RUNNER_TEMP/readme-media")
    if artifact_argument.parent.resolve(strict=True) != runner_root:
        raise SystemExit("Artifact directory parent escaped RUNNER_TEMP")
    if artifact_argument.is_symlink():
        raise SystemExit("Refusing to clean a symlinked artifact directory")

    artifact_argument.mkdir(mode=0o700, exist_ok=True)
    if artifact_argument.is_symlink():
        raise SystemExit("Artifact directory became a symlink; refusing cleanup")
    artifact_root = artifact_argument.resolve(strict=True)
    if artifact_root.parent != runner_root or not artifact_root.is_dir():
        raise SystemExit("Artifact directory is not a direct directory under RUNNER_TEMP")

    for entry in artifact_root.iterdir():
        if entry.is_symlink() or not entry.is_dir():
            entry.unlink()
        else:
            shutil.rmtree(entry)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: prepare-readme-media-artifacts.py RUNNER_TEMP ARTIFACT_DIR")
    prepare(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
