#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".github/scripts"))
from validate_readme_media_capture import (
    CaptureValidationError,
    select_unique_popover,
    validate_png_dimensions,
)

TEST_ROOT = Path(os.environ.get("RUNNER_TEMP") or "")
if not TEST_ROOT.is_absolute() or not TEST_ROOT.is_dir():
    raise SystemExit("Set RUNNER_TEMP to an existing scratch directory for tests")


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def synthetic_png(
    width: int,
    height: int,
    *,
    rows: bytes | None = None,
    interlace: int = 0,
    bit_depth: int = 8,
    color_type: int = 6,
    stream: bytes | None = None,
    before_idat: bytes = b"",
    idat_chunks: int = 1,
    between_idat: bytes = b"",
) -> bytes:
    """A complete PNG: signature, IHDR, optional chunks, IDAT(s), IEND. Defaults to 8-bit RGBA."""
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    row_bytes = (width * bit_depth * channels + 7) // 8
    if rows is None:
        rows = b"".join(b"\x00" + bytes((index * 37) % 256 for index in range(row_bytes)) for _ in range(height))
    compressed = zlib.compress(rows) if stream is None else stream
    ihdr = struct.pack(">IIBBBBB", width, height, bit_depth, color_type, 0, 0, interlace)
    size = -(-len(compressed) // idat_chunks)
    parts = [compressed[index:index + size] for index in range(0, len(compressed), size)]
    idats = between_idat.join(chunk(b"IDAT", part) for part in parts)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + before_idat + idats + chunk(b"IEND", b"")


class CaptureValidationTests(unittest.TestCase):
    def test_unique_strictly_adjacent_app_window_is_selected(self) -> None:
        status = (800, 0, 28, 24)
        windows = [(500, 24, 420, 600)]
        selected = select_unique_popover(status, windows, (1024, 768))
        self.assertEqual(selected, (500, 24, 420, 600))

    def test_original_adjacency_thresholds_remain_strict(self) -> None:
        status = (800, 0, 28, 24)
        rejected = (
            (500, 145, 420, 600),  # vertical gap exceeds 120 points
            (0, 24, 420, 600),  # no horizontal overlap within the existing 80-point tolerance
            (500, 24, 239, 600),  # width below the existing 240-point minimum
            (500, 24, 420, 239),  # height below the existing 240-point minimum
            (700, 24, 420, 600),  # extends beyond the display
        )
        for window in rejected:
            with self.subTest(window=window), self.assertRaises(CaptureValidationError):
                select_unique_popover(status, [window], (1024, 768))

    def test_absent_or_ambiguous_adjacent_window_fails_closed(self) -> None:
        status = (800, 0, 28, 24)
        adjacent = (500, 24, 420, 600)
        with self.assertRaisesRegex(CaptureValidationError, "no_adjacent_app_window"):
            select_unique_popover(status, [], (1024, 768))
        with self.assertRaisesRegex(CaptureValidationError, "ambiguous_adjacent_app_windows"):
            select_unique_popover(status, [adjacent, adjacent], (1024, 768))

    def test_capture_png_must_match_measured_bounds_times_scale(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            png = Path(temporary) / "synthetic.png"
            png.write_bytes(synthetic_png(84, 120))
            validate_png_dimensions(png, expected_width=84, expected_height=120)
            with self.assertRaisesRegex(CaptureValidationError, "png_dimensions_mismatch"):
                validate_png_dimensions(png, expected_width=84, expected_height=118)

    def test_structurally_incomplete_png_fails_closed(self) -> None:
        good = synthetic_png(84, 120)
        signature_and_ihdr = good[: 8 + 25]
        idat_offset = good.index(b"IDAT")
        corrupt_crc = bytearray(good)
        corrupt_crc[idat_offset + 10] ^= 0xFF
        short_rows = b"".join(b"\x00" + b"\x00" * 84 * 4 for _ in range(119))
        bad_filter = b"".join(b"\x07" + b"\x00" * 84 * 4 for _ in range(120))
        cases = {
            "header only": signature_and_ihdr,
            "truncated": good[:-20],
            "missing IEND": good[: good.index(b"IEND") - 4],
            "trailing bytes": good + b"extra",
            "corrupt chunk CRC": bytes(corrupt_crc),
            "missing scanlines": synthetic_png(84, 120, rows=short_rows),
            "invalid filter byte": synthetic_png(84, 120, rows=bad_filter),
            "interlaced": synthetic_png(84, 120, interlace=1),
            "bit depth 0": synthetic_png(84, 120, bit_depth=0),
            "16-bit palette": synthetic_png(84, 120, bit_depth=16, color_type=3, before_idat=chunk(b"PLTE", b"\x00" * 3)),
            "palette without PLTE": synthetic_png(84, 120, bit_depth=8, color_type=3),
            "data after the zlib stream": synthetic_png(84, 120, stream=zlib.compress(b"".join(b"\x00" + b"\x00" * 336 for _ in range(120))) + b"junk"),
            "IDAT chunks split by another chunk": synthetic_png(84, 120, idat_chunks=2, between_idat=chunk(b"tEXt", b"k\x00v")),
            "second IHDR": synthetic_png(84, 120, before_idat=chunk(b"IHDR", struct.pack(">IIBBBBB", 84, 120, 8, 6, 0, 0, 0))),
        }
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            png = Path(temporary) / "candidate.png"
            for label, data in cases.items():
                png.write_bytes(data)
                with self.subTest(label), self.assertRaisesRegex(CaptureValidationError, "invalid_png_structure"):
                    validate_png_dimensions(png, expected_width=84, expected_height=120)

    def test_valid_png_variants_are_accepted(self) -> None:
        variants = {
            "16-bit RGBA": synthetic_png(84, 120, bit_depth=16),
            "8-bit RGB": synthetic_png(84, 120, color_type=2),
            "palette with PLTE": synthetic_png(84, 120, color_type=3, before_idat=chunk(b"PLTE", b"\x00\x10\x20")),
            "several consecutive IDATs": synthetic_png(84, 120, idat_chunks=3),
            "ancillary chunk before IDAT": synthetic_png(84, 120, before_idat=chunk(b"pHYs", struct.pack(">IIB", 2835, 2835, 1))),
        }
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            png = Path(temporary) / "candidate.png"
            for label, data in variants.items():
                png.write_bytes(data)
                with self.subTest(label):
                    validate_png_dimensions(png, expected_width=84, expected_height=120)

    def test_declared_size_is_checked_before_inflating(self) -> None:
        bomb_header = struct.pack(">IIBBBBB", 100_000, 100_000, 8, 6, 0, 0, 0)
        bomb = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", bomb_header) + chunk(b"IDAT", zlib.compress(b"\x00" * 4096)) + chunk(b"IEND", b"")
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            png = Path(temporary) / "bomb.png"
            png.write_bytes(bomb)
            with self.assertRaisesRegex(CaptureValidationError, "png_dimensions_mismatch"):
                validate_png_dimensions(png, expected_width=84, expected_height=120)

    def test_malformed_or_missing_png_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            png = Path(temporary) / "bad.png"
            png.write_bytes(b"not a PNG")
            with self.assertRaisesRegex(CaptureValidationError, "invalid_png_header"):
                validate_png_dimensions(png, expected_width=100, expected_height=100)
            with self.assertRaisesRegex(CaptureValidationError, "missing_capture"):
                validate_png_dimensions(Path(temporary) / "missing.png", expected_width=100, expected_height=100)


if __name__ == "__main__":
    unittest.main(verbosity=2)
