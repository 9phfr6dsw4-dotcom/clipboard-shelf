from __future__ import annotations

import struct
import sys
from pathlib import Path


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as image:
        header = image.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise AssertionError(f"not a readable PNG: {path}")
    return struct.unpack(">II", header[16:24])


def verify(source: Path, app: Path) -> None:
    bundled_source = app / "Contents" / "Resources" / "AppIcon-1024.png"
    icns = app / "Contents" / "Resources" / "AppIcon.icns"
    if png_dimensions(source) != (1024, 1024):
        raise AssertionError(f"source icon must be 1024x1024: {source}")
    if not bundled_source.is_file() or bundled_source.read_bytes() != source.read_bytes():
        raise AssertionError("the original 1024px source icon is not bundled byte-for-byte")
    if not icns.is_file() or icns.stat().st_size < 12:
        raise AssertionError("the app bundle is missing a nonempty AppIcon.icns")
    icns_header = icns.read_bytes()[:8]
    if icns_header[:4] != b"icns" or int.from_bytes(icns_header[4:], "big") != icns.stat().st_size:
        raise AssertionError("AppIcon.icns has an invalid container header")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: test_icon_package.py SOURCE.png APP.app")
    verify(Path(sys.argv[1]), Path(sys.argv[2]))
    print("App icon package verification passed.")
