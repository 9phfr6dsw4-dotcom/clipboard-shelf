#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest

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
            png = Path(temporary) / "synthetic-header-only.png"
            png.write_bytes(
                b"\x89PNG\r\n\x1a\n"
                + struct.pack(">I", 13)
                + b"IHDR"
                + struct.pack(">IIBBBBB", 840, 1200, 8, 6, 0, 0, 0)
            )
            validate_png_dimensions(png, expected_width=840, expected_height=1200)
            with self.assertRaisesRegex(CaptureValidationError, "png_dimensions_mismatch"):
                validate_png_dimensions(png, expected_width=840, expected_height=1198)

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
