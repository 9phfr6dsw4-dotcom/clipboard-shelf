from __future__ import annotations

import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
import generate_icon  # noqa: E402


class IconSourceValidationTests(unittest.TestCase):
    def test_accepts_the_supplied_square_1024_png(self) -> None:
        source = ROOT / "Resources" / "AppIcon-1024.png"
        self.assertEqual((1024, 1024), generate_icon.validate_source_png(source))

    def test_rejects_non_1024_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "small.png"
            source.write_bytes(
                b"\x89PNG\r\n\x1a\n"
                + struct.pack(">IIBBBBB", 512, 512, 8, 6, 0, 0, 0)
            )
            with self.assertRaises(ValueError):
                generate_icon.validate_source_png(source)


if __name__ == "__main__":
    unittest.main()
