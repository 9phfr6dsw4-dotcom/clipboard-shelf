#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("prepare-readme-media-artifacts.py")
TEST_ROOT = Path(os.environ.get("RUNNER_TEMP") or os.environ.get("TMPDIR") or "")
if not TEST_ROOT.is_absolute() or not TEST_ROOT.is_dir():
    raise SystemExit("Set RUNNER_TEMP or TMPDIR to an existing scratch directory for tests")


class PrepareArtifactDirectoryTests(unittest.TestCase):
    def invoke(self, runner: Path, artifact: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(runner), str(artifact)],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_clears_only_artifacts_and_unlinks_child_symlinks(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            runner = Path(temporary) / "runner"
            runner.mkdir()
            artifacts = runner / "readme-media"
            artifacts.mkdir()
            (artifacts / "old.png").write_text("stale", encoding="utf-8")
            nested = artifacts / "nested"
            nested.mkdir()
            (nested / "old.txt").write_text("stale", encoding="utf-8")
            outside = Path(temporary) / "outside"
            outside.mkdir()
            sentinel = outside / "keep.txt"
            sentinel.write_text("keep", encoding="utf-8")
            (artifacts / "outside-link").symlink_to(outside, target_is_directory=True)

            result = self.invoke(runner, artifacts)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(artifacts.iterdir()), [])
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")

    def test_rejects_artifact_directory_symlink_without_touching_target(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            root = Path(temporary)
            runner = root / "runner"
            runner.mkdir()
            outside = root / "outside"
            outside.mkdir()
            sentinel = outside / "keep.txt"
            sentinel.write_text("keep", encoding="utf-8")
            artifacts = runner / "readme-media"
            artifacts.symlink_to(outside, target_is_directory=True)

            result = self.invoke(runner, artifacts)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", result.stderr.lower())
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")

    def test_rejects_symlinked_runner_temp_without_touching_target(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            root = Path(temporary)
            real_runner = root / "real-runner"
            real_runner.mkdir()
            artifacts = real_runner / "readme-media"
            artifacts.mkdir()
            sentinel = artifacts / "keep.txt"
            sentinel.write_text("keep", encoding="utf-8")
            runner_link = root / "runner-link"
            runner_link.symlink_to(real_runner, target_is_directory=True)

            result = self.invoke(runner_link, runner_link / "readme-media")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlink", result.stderr.lower())
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")

    def test_rejects_path_outside_designated_artifact_directory(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            runner = Path(temporary) / "runner"
            runner.mkdir()
            outside = Path(temporary) / "valuable"
            outside.mkdir()
            sentinel = outside / "keep.txt"
            sentinel.write_text("keep", encoding="utf-8")

            result = self.invoke(runner, outside)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")


if __name__ == "__main__":
    unittest.main(verbosity=2)
