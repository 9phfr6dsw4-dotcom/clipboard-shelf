#!/usr/bin/env python3
"""Build a macOS iconset from the supplied, unmodified 1024px PNG."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ICON_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as image:
        header = image.read(24)
    if len(header) != 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValueError(f"not a readable PNG: {path}")
    width = int.from_bytes(header[16:20], "big")
    height = int.from_bytes(header[20:24], "big")
    return width, height


def validate_source_png(source: Path) -> tuple[int, int]:
    dimensions = png_dimensions(source)
    if dimensions != (1024, 1024):
        raise ValueError(f"source icon must be 1024x1024, got {dimensions[0]}x{dimensions[1]}")
    return dimensions


def generate_iconset(source: Path, output: Path) -> None:
    validate_source_png(source)
    output.mkdir(parents=True, exist_ok=True)
    for filename, size in ICON_SIZES.items():
        destination = output / filename
        if size == 1024:
            # Keep the approved original PNG byte-for-byte for the @2x 512px slot.
            shutil.copyfile(source, destination)
        else:
            subprocess.run(
                [
                    "/usr/bin/sips",
                    "-s",
                    "format",
                    "png",
                    "-z",
                    str(size),
                    str(size),
                    str(source),
                    "--out",
                    str(destination),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
            )
        if png_dimensions(destination) != (size, size):
            raise ValueError(f"iconset image has unexpected dimensions: {destination}")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate_icon.py OUTPUT.iconset SOURCE-1024.png")
    generate_iconset(Path(sys.argv[2]), Path(sys.argv[1]))


if __name__ == "__main__":
    main()
