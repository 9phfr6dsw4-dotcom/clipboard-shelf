#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/readme-media.yml"
CAPTURE = ROOT / ".github/scripts/capture-readme-media.sh"


class ReadmeMediaSecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")
        cls.capture = CAPTURE.read_text(encoding="utf-8")
        cls.runtime = (ROOT / ".github/scripts/readme-media-runtime.sh").read_text(encoding="utf-8")

    def test_capture_job_is_dispatch_only_on_trusted_main(self) -> None:
        trigger = self.workflow.split("permissions:", maxsplit=1)[0]
        self.assertEqual(trigger, "name: README media\n\non:\n  workflow_dispatch:\n\n")
        self.assertIn("if: github.event_name == 'workflow_dispatch' && github.repository == '9phfr6dsw4-dotcom/clipboard-shelf' && github.ref == 'refs/heads/main'", self.workflow)

    def test_github_token_is_scoped_to_release_download_before_application_launch(self) -> None:
        copy_token = self.capture.index('RELEASE_TOKEN="${GH_TOKEN:?GH_TOKEN is required}"')
        unexport_token = self.capture.index("export -n RELEASE_TOKEN", copy_token)
        unset_inherited_token = self.capture.index("unset GH_TOKEN", unexport_token)
        download = self.capture.index('GH_TOKEN="$RELEASE_TOKEN" gh release download --repo')
        clear_token = self.capture.index("unset RELEASE_TOKEN GH_TOKEN", download)
        first_launch = self.capture.index('open "$APP"')
        self.assertLess(copy_token, unexport_token)
        self.assertLess(unexport_token, unset_inherited_token)
        self.assertLess(unset_inherited_token, download)
        self.assertLess(download, clear_token)
        self.assertLess(clear_token, first_launch)
        self.assertNotIn("GH_TOKEN", self.capture[unset_inherited_token + len("unset GH_TOKEN"):download])
        self.assertNotIn("GH_TOKEN", self.capture[clear_token + len("unset RELEASE_TOKEN GH_TOKEN"):first_launch])

    def test_appearance_errors_are_not_swallowed(self) -> None:
        self.assertIn("set_appearance()", self.runtime)
        self.assertIn("appearance preferences", self.runtime)
        self.assertNotIn("Could not switch appearance", self.capture)

    def test_demo_files_are_created_without_home_or_system_writes(self) -> None:
        self.assertIn("prepare-readme-media-demo.py", self.capture)
        self.assertIn('open --env "HOME=${DEMO_DOWNLOADS%/Downloads}"', self.capture)
        self.assertNotIn('$HOME/Downloads', self.capture)
        self.assertNotIn('$HOME/Downloads', self.runtime)
        self.assertNotIn("/Applications/", self.capture)
        self.assertNotIn("sudo ", self.capture)

    def test_capture_cleanup_keeps_symlink_and_worktree_guards(self) -> None:
        self.assertIn('if [[ -L "$ROOT/docs" || -L "$ROOT/docs/images" ]]', self.capture)
        self.assertIn('[[ "$IMAGE_DIR_REAL" == "$ROOT/docs/images" ]]', self.capture)
        artifact_setup = self.capture.index('prepare-readme-media-artifacts.py')
        clear_outputs = self.capture.index('rm -f "$ROOT/docs/images/$SLUG-light.png"')
        self.assertLess(artifact_setup, clear_outputs)
        self.assertNotIn('rm -rf "$ROOT/docs/images"', self.capture)


if __name__ == "__main__":
    unittest.main(verbosity=2)
