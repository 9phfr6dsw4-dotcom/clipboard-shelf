#!/usr/bin/env python3
"""Verify the pinned Clipboard Shelf release before extraction or launch."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import sys
import zipfile

RELEASE_TAG = "v1.0.2"
ARCHIVE_NAME = "Clipboard-Shelf-1.0.2.zip"
SIDECAR_NAME = "Clipboard-Shelf-1.0.2.zip.sha256"
RELEASE_COMMIT = "f25223855444d19e204016e27b8940afec806b20"
RELEASE_SHA256 = "ed25cf9e18a6b268ec802f63c16e469ccbece92558760a14413b66585233312f"
BUNDLE_PATH = "Clipboard Shelf.app/Contents/Info.plist"
BUNDLE_ID = "local.clipboardshelf"
BUNDLE_VERSION = "1.0.2"
BUNDLE_EXECUTABLE = "ClipboardShelf"


def verify_release_asset(
    archive_path: Path,
    sidecar_path: Path,
    *,
    expected_sha256: str,
    expected_archive_name: str,
    expected_bundle_id: str,
    expected_version: str,
    expected_executable: str,
) -> dict[str, str]:
    if archive_path.name != expected_archive_name or sidecar_path.name != expected_archive_name + ".sha256":
        raise ValueError("invalid_release_asset_names")
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha256):
        raise ValueError("invalid_pinned_release_checksum")
    try:
        sidecar_fields = sidecar_path.read_text(encoding="ascii").strip().split()
    except (OSError, UnicodeError):
        raise ValueError("invalid_release_sidecar") from None
    if len(sidecar_fields) != 2 or sidecar_fields[1] != expected_archive_name:
        raise ValueError("invalid_release_sidecar")
    if not re.fullmatch(r"[0-9a-f]{64}", sidecar_fields[0]):
        raise ValueError("invalid_release_sidecar")
    try:
        actual_sha256 = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    except OSError:
        raise ValueError("missing_release_archive") from None
    if actual_sha256 != expected_sha256 or sidecar_fields[0] != expected_sha256:
        raise ValueError("release_checksum_mismatch")

    try:
        with zipfile.ZipFile(archive_path) as archive:
            names = archive.namelist()
            info_paths = [name for name in names if name.endswith(".app/Contents/Info.plist")]
            if info_paths != [BUNDLE_PATH]:
                raise ValueError("release_bundle_identity_mismatch")
            info = plistlib.loads(archive.read(BUNDLE_PATH))
            executable_path = f"Clipboard Shelf.app/Contents/MacOS/{expected_executable}"
            if executable_path not in names:
                raise ValueError("release_bundle_identity_mismatch")
    except (OSError, zipfile.BadZipFile, KeyError, plistlib.InvalidFileException):
        raise ValueError("invalid_release_archive") from None

    actual = {
        "bundle_id": str(info.get("CFBundleIdentifier", "")),
        "version": str(info.get("CFBundleShortVersionString", "")),
        "executable": str(info.get("CFBundleExecutable", "")),
    }
    if actual != {
        "bundle_id": expected_bundle_id,
        "version": expected_version,
        "executable": expected_executable,
    }:
        raise ValueError("release_bundle_identity_mismatch")
    return actual


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("sidecar", type=Path)
    args = parser.parse_args()
    try:
        verify_release_asset(
            args.archive,
            args.sidecar,
            expected_sha256=RELEASE_SHA256,
            expected_archive_name=ARCHIVE_NAME,
            expected_bundle_id=BUNDLE_ID,
            expected_version=BUNDLE_VERSION,
            expected_executable=BUNDLE_EXECUTABLE,
        )
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1
    print("Pinned Clipboard Shelf release checksum and bundle identity verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
