#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".github/scripts"))
from validate_readme_media_release import verify_release_asset

TEST_ROOT = Path(os.environ.get("RUNNER_TEMP") or "")
if not TEST_ROOT.is_absolute() or not TEST_ROOT.is_dir():
    raise SystemExit("Set RUNNER_TEMP to an existing scratch directory for tests")


class ReleaseAssetValidationTests(unittest.TestCase):
    def create_asset(self, root: Path, *, version: str = "1.0.2", bundle_id: str = "local.clipboardshelf") -> tuple[Path, Path, str]:
        archive = root / "Clipboard-Shelf-1.0.2.zip"
        info = {
            "CFBundleIdentifier": bundle_id,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "3",
            "CFBundleExecutable": "ClipboardShelf",
        }
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zipped:
            zipped.writestr(
                "Clipboard Shelf.app/Contents/Info.plist",
                plistlib.dumps(info, fmt=plistlib.FMT_BINARY),
            )
            zipped.writestr(
                "Clipboard Shelf.app/Contents/MacOS/ClipboardShelf",
                b"synthetic executable marker",
            )
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        sidecar = root / "Clipboard-Shelf-1.0.2.zip.sha256"
        sidecar.write_text(f"{digest}  {archive.name}\n", encoding="ascii")
        return archive, sidecar, digest

    def test_fixed_release_checksum_and_bundle_identity_are_verified(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            root = Path(temporary)
            archive, sidecar, digest = self.create_asset(root)
            verified = verify_release_asset(
                archive,
                sidecar,
                expected_sha256=digest,
                expected_archive_name=archive.name,
                expected_bundle_id="local.clipboardshelf",
                expected_version="1.0.2",
                expected_executable="ClipboardShelf",
            )
            self.assertEqual(verified, {"bundle_id": "local.clipboardshelf", "version": "1.0.2", "executable": "ClipboardShelf"})

    def test_checksum_sidecar_or_hash_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            root = Path(temporary)
            archive, sidecar, _ = self.create_asset(root)
            with self.assertRaisesRegex(ValueError, "release_checksum_mismatch"):
                verify_release_asset(
                    archive, sidecar,
                    expected_sha256="0" * 64,
                    expected_archive_name=archive.name,
                    expected_bundle_id="local.clipboardshelf",
                    expected_version="1.0.2",
                    expected_executable="ClipboardShelf",
                )
            sidecar.write_text(f"{'0' * 64}  unexpected.zip\n", encoding="ascii")
            with self.assertRaisesRegex(ValueError, "invalid_release_sidecar"):
                verify_release_asset(
                    archive, sidecar,
                    expected_sha256="0" * 64,
                    expected_archive_name=archive.name,
                    expected_bundle_id="local.clipboardshelf",
                    expected_version="1.0.2",
                    expected_executable="ClipboardShelf",
                )

    def test_wrong_bundle_identity_or_version_is_rejected_before_extraction(self) -> None:
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as temporary:
            root = Path(temporary)
            archive, sidecar, digest = self.create_asset(root, version="1.0.1")
            with self.assertRaisesRegex(ValueError, "release_bundle_identity_mismatch"):
                verify_release_asset(
                    archive, sidecar,
                    expected_sha256=digest,
                    expected_archive_name=archive.name,
                    expected_bundle_id="local.clipboardshelf",
                    expected_version="1.0.2",
                    expected_executable="ClipboardShelf",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
