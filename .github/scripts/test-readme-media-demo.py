#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("prepare-readme-media-demo.py")
TEST_ROOT = Path(os.environ.get("RUNNER_TEMP") or os.environ.get("TMPDIR") or "")
if not TEST_ROOT.is_absolute() or not TEST_ROOT.is_dir():
    raise SystemExit("Set RUNNER_TEMP or TMPDIR to an existing scratch directory for tests")


class PrepareDemoFixturesTests(unittest.TestCase):
    def invoke(self, runner: Path, wallpaper: Path, home: Path) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["HOME"] = str(home)
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(runner), str(wallpaper)],
            text=True,
            capture_output=True,
            check=False,
            env=env,
        )

    def test_creates_unique_fixtures_under_runner_temp_without_touching_home(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            root = Path(temporary)
            runner = root / "runner"
            runner.mkdir()
            wallpaper = runner / "readme-wallpaper.png"
            wallpaper.write_bytes(b"wallpaper fixture")
            home = root / "home"
            downloads = home / "Downloads"
            downloads.mkdir(parents=True)
            sentinel = downloads / "Atlas-project-brief.pdf"
            sentinel.write_text("keep existing user file", encoding="utf-8")

            first = self.invoke(runner, wallpaper, home)
            second = self.invoke(runner, wallpaper, home)

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(second.returncode, 0, second.stderr)
            first_downloads = Path(first.stdout.strip())
            second_downloads = Path(second.stdout.strip())
            self.assertTrue(first_downloads.is_relative_to(runner))
            self.assertTrue(second_downloads.is_relative_to(runner))
            self.assertNotEqual(first_downloads, second_downloads)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep existing user file")
            expected = {
                "Atlas-project-brief.pdf",
                "Atlas-review-notes.md",
                "Atlas-timeline.xlsx",
                "Atlas-copy-draft.docx",
                "Team-agenda-2026-08.docx",
                "invoice-2026-08.pdf",
                "holiday-photos.zip",
                "Screenshot 2026-09-20 at 10.14.03.png",
                "meeting-notes.md",
                "brand-board.sketch",
                "Sample Studio.dmg",
                "export-final-2.csv",
            }
            self.assertEqual({path.name for path in first_downloads.iterdir()}, expected)
            self.assertEqual((first_downloads / "Screenshot 2026-09-20 at 10.14.03.png").read_bytes(), wallpaper.read_bytes())
            self.assertEqual((first_downloads / "Atlas-project-brief.pdf").read_text(encoding="utf-8").splitlines()[0], "Sample project brief for a fictional Atlas workspace.")

    def test_rejects_symlinked_runner_temp(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            root = Path(temporary)
            runner = root / "runner"
            runner.mkdir()
            wallpaper = runner / "readme-wallpaper.png"
            wallpaper.write_bytes(b"wallpaper fixture")
            runner_link = root / "runner-link"
            runner_link.symlink_to(runner, target_is_directory=True)

            result = self.invoke(runner_link, wallpaper, root / "home")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", result.stderr.lower())
            self.assertEqual(list(runner.iterdir()), [wallpaper])


if __name__ == "__main__":
    unittest.main(verbosity=2)
