#!/usr/bin/env python3
"""Popover selection from a launched PID's CGWindowList inventory.

The positive fixtures are the exact status-item frames and window inventories observed on
the GitHub macos-15 and macos-26 runners for a status-item/NSPopover fixture shaped like
Clipboard Shelf's (experiment run 36280841525), where System Events exposed no windows.
"""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_readme_media_capture import (  # noqa: E402
    CaptureValidationError,
    select_popover_from_inventory,
)

HEADER = "windowID\tPID\tlayer\talpha\tx\ty\twidth\theight\n"
MACOS_15 = HEADER + "24\t3064\t25\t1.0\t763\t0\t38\t24\n25\t3064\t25\t1.0\t554\t23\t456\t526\n"
MACOS_26 = HEADER + "32\t4428\t25\t1.0\t546\t26\t456\t526\n"
SCRIPT = Path(__file__).resolve().parent / "validate_readme_media_capture.py"


class PopoverSelectionTests(unittest.TestCase):
    def test_selects_the_observed_runner_popovers(self) -> None:
        self.assertEqual(
            select_popover_from_inventory(MACOS_15, pid=3064, status_frame=[770, 0, 24, 24], display_size=[1024, 768]),
            (554, 23, 456, 526),
        )
        self.assertEqual(
            select_popover_from_inventory(MACOS_26, pid=4428, status_frame=[762, 3, 24, 24], display_size=[1024, 768]),
            (546, 26, 456, 526),
        )

    def test_no_popover_before_the_click_fails_closed(self) -> None:
        before_click = HEADER + "24\t3064\t25\t1.0\t763\t0\t38\t24\n"
        for inventory in (before_click, HEADER):
            with self.assertRaisesRegex(CaptureValidationError, "no_adjacent_app_window"):
                select_popover_from_inventory(inventory, pid=3064, status_frame=[770, 0, 24, 24], display_size=[1024, 768])

    def test_two_adjacent_windows_are_ambiguous(self) -> None:
        inventory = MACOS_26 + "33\t4428\t25\t1.0\t500\t30\t300\t300\n"
        with self.assertRaisesRegex(CaptureValidationError, "ambiguous_adjacent_app_windows"):
            select_popover_from_inventory(inventory, pid=4428, status_frame=[762, 3, 24, 24], display_size=[1024, 768])

    def test_transparent_windows_are_not_candidates(self) -> None:
        inventory = MACOS_26 + "33\t4428\t25\t0.0\t500\t30\t300\t300\n"
        self.assertEqual(
            select_popover_from_inventory(inventory, pid=4428, status_frame=[762, 3, 24, 24], display_size=[1024, 768]),
            (546, 26, 456, 526),
        )

    def test_incomplete_or_foreign_inventory_fails_closed(self) -> None:
        bad_inventories = {
            "wrong header": "windowID\tPID\n32\t4428\n",
            "empty": "",
            "short row": HEADER + "32\t4428\t25\t1.0\t546\t26\t456\n",
            "non-numeric": HEADER + "32\t4428\t25\t1.0\t546\tabc\t456\t526\n",
            "other PID": MACOS_26 + "40\t999\t0\t1.0\t0\t0\t800\t600\n",
            "bad alpha": HEADER + "32\t4428\t25\t1.5\t546\t26\t456\t526\n",
        }
        for label, inventory in bad_inventories.items():
            with self.subTest(label), self.assertRaisesRegex(CaptureValidationError, "invalid_app_window_inventory"):
                select_popover_from_inventory(inventory, pid=4428, status_frame=[762, 3, 24, 24], display_size=[1024, 768])

    def test_command_line_reads_inventory_from_stdin(self) -> None:
        command = [sys.executable, str(SCRIPT), "select-popover", "--pid", "4428", "--status", "762", "3", "24", "24", "--display", "1024", "768"]
        accepted = subprocess.run(command, input=MACOS_26, capture_output=True, text=True, check=False)
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        self.assertEqual(accepted.stdout.strip(), "546|26|456|526")
        rejected = subprocess.run(command, input=HEADER, capture_output=True, text=True, check=False)
        self.assertEqual(rejected.returncode, 1)
        self.assertEqual(rejected.stdout, "")
        self.assertEqual(rejected.stderr.strip(), "no_adjacent_app_window")


if __name__ == "__main__":
    unittest.main(verbosity=2)
