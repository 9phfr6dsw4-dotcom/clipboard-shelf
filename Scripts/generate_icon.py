#!/usr/bin/env python3
"""Generate Clipboard Shelf's iconset using only Python's stdlib."""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path


def chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def rounded_box(
    x: float,
    y: float,
    left: float,
    top: float,
    right: float,
    bottom: float,
    radius: float,
    antialias: float,
) -> float:
    center_x = (left + right) / 2
    center_y = (top + bottom) / 2
    inner_half_width = max(0.0, (right - left) / 2 - radius)
    inner_half_height = max(0.0, (bottom - top) / 2 - radius)
    qx = abs(x - center_x) - inner_half_width
    qy = abs(y - center_y) - inner_half_height
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    signed_distance = outside + inside - radius
    return max(0.0, min(1.0, 0.5 - signed_distance / max(antialias, 1e-6)))


def blend(base: tuple[float, float, float, float], overlay: tuple[int, int, int, int], alpha: float) -> tuple[float, float, float, float]:
    amount = max(0.0, min(1.0, alpha * overlay[3] / 255.0))
    return (
        base[0] * (1 - amount) + overlay[0] * amount,
        base[1] * (1 - amount) + overlay[1] * amount,
        base[2] * (1 - amount) + overlay[2] * amount,
        max(base[3], amount * 255),
    )


def pixel(size: int, px: int, py: int) -> tuple[int, int, int, int]:
    x = (px + 0.5) / size
    y = (py + 0.5) / size
    edge = 1.25 / size

    outer = rounded_box(x, y, 0.055, 0.055, 0.945, 0.945, 0.205, edge)
    if outer <= 0:
        return 0, 0, 0, 0

    t = max(0.0, min(1.0, (y - 0.055) / 0.89))
    color: tuple[float, float, float, float] = (
        29 * (1 - t) + 7 * t,
        83 * (1 - t) + 38 * t,
        83 * (1 - t) + 47 * t,
        outer * 255,
    )

    # Gentle upper-left highlight.
    highlight = max(0.0, 1.0 - math.hypot(x - 0.25, y - 0.18) / 0.65) * 0.11
    color = blend(color, (255, 255, 255, 255), highlight * outer)

    paper = rounded_box(x, y, 0.255, 0.195, 0.745, 0.735, 0.065, edge)
    color = blend(color, (235, 242, 237, 255), paper * outer)

    # Clipboard clip.
    clip = rounded_box(x, y, 0.39, 0.145, 0.61, 0.285, 0.055, edge)
    color = blend(color, (244, 145, 54, 255), clip * outer)
    clip_inner = rounded_box(x, y, 0.445, 0.178, 0.555, 0.225, 0.022, edge)
    color = blend(color, (32, 76, 75, 255), clip_inner * outer)

    # Text lines on the clipboard.
    for top, right in ((0.36, 0.655), (0.455, 0.625), (0.55, 0.665)):
        line = rounded_box(x, y, 0.335, top, right, top + 0.035, 0.0175, edge)
        color = blend(color, (44, 89, 86, 255), line * 0.72 * outer)

    # Orange shelf at the bottom.
    shelf = rounded_box(x, y, 0.19, 0.755, 0.81, 0.855, 0.05, edge)
    color = blend(color, (244, 145, 54, 255), shelf * outer)
    shelf_glow = rounded_box(x, y, 0.235, 0.765, 0.765, 0.79, 0.012, edge)
    color = blend(color, (255, 194, 111, 255), shelf_glow * 0.7 * outer)

    return tuple(max(0, min(255, round(value))) for value in color)  # type: ignore[return-value]


def write_png(path: Path, size: int) -> None:
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            rows.extend(pixel(size, x, y))
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_icon.py OUTPUT.iconset")
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    files = {
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
    for name, size in files.items():
        write_png(output / name, size)


if __name__ == "__main__":
    main()
