#!/usr/bin/env python3
"""Create isolated synthetic demo files beneath RUNNER_TEMP."""
from __future__ import annotations

from pathlib import Path
import os
import sys
import tempfile

FIXTURES = {
    "Atlas-project-brief.pdf": b"Sample project brief for a fictional Atlas workspace.\n",
    "Atlas-review-notes.md": b"Review notes for the fictional Atlas workspace.\n",
    "Atlas-timeline.xlsx": b"Timeline data for the fictional Atlas workspace.\n",
    "Atlas-copy-draft.docx": b"Draft copy for the fictional Atlas workspace.\n",
    "Team-agenda-2026-08.docx": b"Sample team agenda.\n",
    "invoice-2026-08.pdf": b"Receipt sample.\n",
    "holiday-photos.zip": b"Archive sample.\n",
    "meeting-notes.md": b"Meeting notes sample.\n",
    "brand-board.sketch": b"Design draft sample.\n",
    "Sample Studio.dmg": b"Installer sample.\n",
    "export-final-2.csv": b"Temporary export sample.\n",
}
SCREENSHOT_NAME = "Screenshot 2026-09-20 at 10.14.03.png"


def _resolve_runner_temp(argument: str) -> Path:
    lexical = Path(os.path.abspath(argument))
    if not Path(argument).is_absolute():
        raise SystemExit("RUNNER_TEMP must be an absolute path")
    try:
        root = Path(argument).resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise SystemExit(f"RUNNER_TEMP is unavailable: {error}") from error
    if root != lexical:
        raise SystemExit("RUNNER_TEMP path contains a symlink; refusing demo fixture creation")
    if not root.is_dir():
        raise SystemExit("RUNNER_TEMP is not a directory")
    return root


def _write_exclusive(path: Path, content: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "wb") as output:
        output.write(content)


def prepare(runner_argument: str, wallpaper_argument: str) -> Path:
    runner_root = _resolve_runner_temp(runner_argument)
    wallpaper_lexical = Path(os.path.abspath(wallpaper_argument))
    expected_wallpaper = Path(runner_argument) / "readme-wallpaper.png"
    if wallpaper_lexical != expected_wallpaper:
        raise SystemExit("Wallpaper must be RUNNER_TEMP/readme-wallpaper.png")
    try:
        wallpaper = wallpaper_lexical.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise SystemExit(f"Demo wallpaper is unavailable: {error}") from error
    if wallpaper != wallpaper_lexical or wallpaper.parent != runner_root or not wallpaper.is_file():
        raise SystemExit("Demo wallpaper must be a regular, non-symlink file under RUNNER_TEMP")

    demo_root = Path(tempfile.mkdtemp(prefix="readme-demo-", dir=runner_root))
    downloads = demo_root / "Downloads"
    downloads.mkdir(mode=0o700)
    for name, content in FIXTURES.items():
        _write_exclusive(downloads / name, content)
    _write_exclusive(downloads / SCREENSHOT_NAME, wallpaper.read_bytes())
    return downloads


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: prepare-readme-media-demo.py RUNNER_TEMP WALLPAPER")
    print(prepare(sys.argv[1], sys.argv[2]))


if __name__ == "__main__":
    main()
