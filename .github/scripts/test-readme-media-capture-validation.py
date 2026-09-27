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


def synthetic_png(width: int, height: int, *, rows: bytes | None = None, interlace: int = 0) -> bytes:
    """A complete 8-bit RGBA PNG: signature, IHDR, one IDAT, IEND."""
    if rows is None:
        rows = b"".join(b"\x00" + b"\x40\x80\xc0\xff" * width for _ in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, interlace)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


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
        }
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            png = Path(temporary) / "candidate.png"
            for label, data in cases.items():
                png.write_bytes(data)
                with self.subTest(label), self.assertRaisesRegex(CaptureValidationError, "invalid_png_structure"):
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
