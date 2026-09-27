#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".github/scripts"))
import build_readme_media_geometry_snapshot as geometry_snapshot
WORKFLOW = ROOT / ".github/workflows/readme-media.yml"
MACOS_CI = ROOT / ".github/workflows/macos-ci.yml"
CAPTURE = ROOT / ".github/scripts/capture-readme-media.sh"


class ReadmeMediaSecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")
        cls.capture = CAPTURE.read_text(encoding="utf-8")
        cls.runtime = (ROOT / ".github/scripts/readme-media-runtime.sh").read_text(encoding="utf-8")

    def test_capture_checkout_does_not_persist_credentials(self) -> None:
        self.assertIn(
            "      - uses: actions/checkout@v4\n        with:\n          persist-credentials: false",
            self.workflow,
        )

    def test_pr_validation_runs_media_tests_without_capture_or_release_secrets(self) -> None:
        self.assertIn("  pull_request:\n", MACOS_CI.read_text(encoding="utf-8"))
        macos_ci = MACOS_CI.read_text(encoding="utf-8")
        self.assertIn("  readme-media-safety:\n", macos_ci)
        self.assertIn(
            "      - uses: actions/checkout@v4\n        with:\n          persist-credentials: false",
            macos_ci,
        )
        for command in (
            "bash .github/scripts/test-readme-media-runtime.sh",
            "python3 .github/scripts/test-readme-media-artifacts.py",
            "python3 .github/scripts/test-readme-media-security.py",
            "python3 .github/scripts/test-readme-media-demo.py",
        ):
            self.assertIn(command, macos_ci)
        self.assertNotIn("capture-readme-media.sh", macos_ci)
        self.assertNotIn("GH_TOKEN", macos_ci)
        self.assertNotIn("gh release download", macos_ci)

    def test_capture_job_is_dispatch_only_on_trusted_main(self) -> None:
        trigger = self.workflow.split("permissions:", maxsplit=1)[0]
        self.assertEqual(trigger, "name: README media\n\non:\n  workflow_dispatch:\n\n")
        self.assertIn("permissions:\n  contents: read", self.workflow)
        self.assertIn("if: github.event_name == 'workflow_dispatch' && github.repository == '9phfr6dsw4-dotcom/clipboard-shelf' && github.ref == 'refs/heads/main'", self.workflow)

    def test_github_token_is_scoped_to_release_download_before_application_launch(self) -> None:
        copy_token = self.capture.index('RELEASE_TOKEN="${GH_TOKEN:?GH_TOKEN is required}"')
        unexport_token = self.capture.index("export -n RELEASE_TOKEN", copy_token)
        unset_inherited_token = self.capture.index("unset GH_TOKEN", unexport_token)
        release_view = self.capture.index('GH_TOKEN="$RELEASE_TOKEN" gh release view')
        tag_lookup = self.capture.index('GH_TOKEN="$RELEASE_TOKEN" gh api')
        download = self.capture.index('GH_TOKEN="$RELEASE_TOKEN" gh release download "$RELEASE_TAG"')
        release_marker = 'if [[ "$APP_KEY" == clipboard-shelf ]]; then\n  printf \'Verifying pinned published release'
        shelf_release = self.capture.split(release_marker, 1)[1].split("\nelse\n", 1)[0]
        clear_token = shelf_release.index("unset RELEASE_TOKEN GH_TOKEN")
        first_launch = self.capture.index('open -n "$APP" --args "${CLIPBOARD_DEMO_ARGS[@]}"')
        self.assertLess(copy_token, unexport_token)
        self.assertLess(unexport_token, unset_inherited_token)
        self.assertLess(unset_inherited_token, release_view)
        self.assertLess(release_view, tag_lookup)
        self.assertLess(tag_lookup, download)
        self.assertLess(download, self.capture.index("unset RELEASE_TOKEN GH_TOKEN", download))
        self.assertLess(clear_token, len(shelf_release))
        self.assertLess(self.capture.index("validate_readme_media_release.py"), first_launch)
        self.assertNotIn("GH_TOKEN", shelf_release[clear_token + len("unset RELEASE_TOKEN GH_TOKEN"):])
        self.assertNotIn("export GH_TOKEN", self.capture)

    def test_appearance_errors_are_not_swallowed(self) -> None:
        self.assertIn("set_appearance()", self.runtime)
        self.assertIn("appearance preferences", self.runtime)
        self.assertNotIn("Could not switch appearance", self.capture)

    def test_capture_job_proves_isolation_and_geometry_on_its_own_runner_first(self) -> None:
        capture_step = self.workflow.index("run: bash .github/scripts/capture-readme-media.sh")
        for check in ("verify-clipboard-demo-isolation.sh", "verify-status-popover-geometry.sh"):
            self.assertLess(self.workflow.index(f"run: bash .github/scripts/{check}"), capture_step)

    def test_only_clipboard_shelf_can_be_captured_from_this_repository(self) -> None:
        guard = self.capture.index('[[ "$APP_KEY" == clipboard-shelf ]] || {')
        self.assertLess(guard, self.capture.index("prepare-readme-media-artifacts.py"))
        animate = self.runtime.split("animate_app() {", 1)[1].split("\n}\n", 1)[0]
        self.assertNotIn("clipboard-shelf)", animate)
        self.assertNotIn("ClipboardShelf", animate)

    def test_status_description_match_is_exact(self) -> None:
        status_script = (ROOT / ".github/scripts/readme-media-status-item.applescript").read_text(encoding="utf-8")
        considering = status_script.index("considering case, diacriticals, hyphens, punctuation and white space")
        self.assertLess(considering, status_script.index("(itemDescription as text) is expectedDescription"))
        verifier = (ROOT / ".github/scripts/verify-status-popover-geometry.sh").read_text(encoding="utf-8")
        self.assertIn("'popover fixture — recording paused'", verifier)
        self.assertIn('reason="$(selection_reason "$PID_B")"', verifier)
        self.assertIn('app_state_absent "$REAL_HOME" "$DOMAIN"', verifier)
        self.assertNotIn("status_popover_geometry 1 ", verifier)

    def test_original_appearance_is_snapshotted_and_restored_on_every_exit(self) -> None:
        snapshot = self.capture.index('ORIGINAL_DARK_MODE="$(get_appearance)"')
        self.assertLess(snapshot, self.capture.index("set_appearance false"))
        self.assertLess(snapshot, self.capture.index("set_appearance true"))
        trap_fn = self.capture.split("capture_exit_diagnostics() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("restore_appearance", trap_fn)
        self.assertLess(self.capture.index("capture_exit_diagnostics() {"), self.capture.index("trap capture_exit_diagnostics EXIT"))
        self.assertLess(self.capture.index('source "$ROOT/.github/scripts/readme-media-runtime.sh"'), self.capture.index("trap capture_exit_diagnostics EXIT"))

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

    def test_fixed_shelf_release_is_verified_before_extraction_and_quarantine_removal(self) -> None:
        marker = 'if [[ "$APP_KEY" == clipboard-shelf ]]; then\n  printf \'Verifying pinned published release'
        shelf_release = self.capture.split(marker, 1)[1].split("\nelse\n", 1)[0]
        for required in (
            "RELEASE_TAG='v1.0.2'",
            "RELEASE_ARCHIVE='Clipboard-Shelf-1.0.2.zip'",
            "RELEASE_SIDECAR='Clipboard-Shelf-1.0.2.zip.sha256'",
            "RELEASE_COMMIT='f25223855444d19e204016e27b8940afec806b20'",
            "validate_readme_media_release.py",
        ):
            self.assertIn(required, self.capture)
        release_validator = (ROOT / ".github/scripts/validate_readme_media_release.py").read_text(encoding="utf-8")
        for pinned in (
            'RELEASE_TAG = "v1.0.2"',
            'ARCHIVE_NAME = "Clipboard-Shelf-1.0.2.zip"',
            'SIDECAR_NAME = "Clipboard-Shelf-1.0.2.zip.sha256"',
            'RELEASE_COMMIT = "f25223855444d19e204016e27b8940afec806b20"',
            'RELEASE_SHA256 = "ed25cf9e18a6b268ec802f63c16e469ccbece92558760a14413b66585233312f"',
        ):
            self.assertIn(pinned, release_validator)
        verify = shelf_release.index("validate_readme_media_release.py")
        extract = self.capture.index('ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"')
        quarantine = self.capture.index('xattr -dr com.apple.quarantine "$APP"')
        self.assertLess(self.capture.index("validate_readme_media_release.py"), extract)
        self.assertLess(extract, quarantine)
        self.assertNotIn("--pattern '*.zip'", shelf_release)
        self.assertLess(verify, len(shelf_release))

    def test_clipboard_demo_is_isolated_paused_and_only_uses_synthetic_history(self) -> None:
        helper = (ROOT / ".github/scripts/render-readme-media.swift").read_text(encoding="utf-8")
        # cfprefsd ignores HOME/CFFIXED_USER_HOME, so any preference write reaches the real user domain.
        for forbidden in ("CFPreferencesSetAppValue", "CFPreferencesAppSynchronize", "seed-clipboard", "UserDefaults.standard", "UserDefaults("):
            self.assertNotIn(forbidden, helper)
        arguments = helper.split("func printClipboardDemoArguments() throws", 1)[1].split("func seedEchoType()", 1)[0]
        for printed in ('print("-ClipboardShelfHistoryV1")', 'print("-ClipboardShelfRecordingPausedV1")', 'print("YES")'):
            self.assertIn(printed, arguments)
        self.assertIn("clipboardDemoFixture.enumerated()", arguments)
        fixture = helper.split("let clipboardDemoFixture: [(text: String, isPinned: Bool)] = [", 1)[1].split("\n]\n", 1)[0]
        entries = re.findall(r'^    \("(.+)", (true|false)\),?$', fixture, flags=re.MULTILINE)
        self.assertEqual(len(entries), 8)
        self.assertEqual(len(fixture.strip().splitlines()), 8)
        self.assertEqual(sum(pinned == "true" for _, pinned in entries), 2)

        prepare = self.capture.split("prepare_clipboard_demo() {", 1)[1].split("\n}\n", 1)[0]
        self.assertLess(prepare.index("clipboard_domain_absent"), prepare.index('CLIPBOARD_REAL_HOME="$real_home"'))
        self.assertLess(prepare.index('CLIPBOARD_REAL_HOME="$real_home"'), prepare.index("load_clipboard_demo_args"))
        shelf = self.capture.split("  clipboard-shelf)\n    prepare_clipboard_demo", 1)[1].split("\n    ;;", 1)[0]
        self.assertTrue(shelf.startswith('\n    open -n "$APP" --args "${CLIPBOARD_DEMO_ARGS[@]}"\n'))
        self.assertIn('APP_PID="$(swift "$HELPER" pid "$APP")"', shelf)
        for stale in ("DEMO_HOME", "CFFIXED_USER_HOME", "verify-clipboard-demo"):
            self.assertNotIn(stale, self.capture)
        trap_fn = self.capture.split("capture_exit_diagnostics() {", 1)[1].split("\n}\n", 1)[0]
        snapshot = trap_fn.index("write_geometry_snapshot")
        stop = trap_fn.index('stop_app_instances "$APP/Contents/MacOS/ClipboardShelf"')
        postcondition = trap_fn.index('app_state_absent "$CLIPBOARD_REAL_HOME" local.clipboardshelf')
        restore = trap_fn.index("restore_appearance")
        self.assertLess(snapshot, stop)
        self.assertLess(stop, postcondition)
        self.assertLess(postcondition, restore)
        stopper = self.runtime.split("stop_app_instances() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('pkill -KILL -f -- "$pattern"', stopper)
        self.assertIn('pgrep -f -- "$pattern"', stopper)
        self.assertIn('pattern="^$(printf', stopper)

        self.assertIn('dscl . -read "/Users/$(id -un)" NFSHomeDirectory', self.runtime)
        detector = self.runtime.split("clipboard_domain_absent() {", 1)[1].split("\n}\n", 1)[0]
        for check in ('/Library/Preferences/$domain.plist', "ByHost/$domain.*.plist", '-L "$plist"', 'preference_domain_keys "$domain"'):
            self.assertIn(check, detector)
        keys = self.runtime.split("preference_domain_keys() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('[[ "$error" == *"Domain $domain does not exist"* ]] && return 0', keys)
        self.assertIn('defaults export "$domain" - | plist_key_names -', keys)
        postcondition_fn = self.runtime.split("app_state_absent() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("(key names only)", postcondition_fn)
        self.assertIn("APPKIT_STATUS_ITEM_KEY='^NSStatusItem (Preferred Position|Visible|VisibleCC) [A-Za-z0-9_-]+$'", self.runtime)

        macos_ci = MACOS_CI.read_text(encoding="utf-8")
        self.assertIn("run: bash .github/scripts/verify-clipboard-demo-isolation.sh", macos_ci)
        self.assertNotIn("CFFIXED_USER_HOME", macos_ci)
        verifier = (ROOT / ".github/scripts/verify-clipboard-demo-isolation.sh").read_text(encoding="utf-8")
        precondition = verifier.index('clipboard_domain_absent "$REAL_HOME" "$DOMAIN" || { printf \'Precondition')
        with_fixture = verifier.index('run_probe "$WORK/with-fixture.txt" "${CLIPBOARD_DEMO_ARGS[@]}"')
        control = verifier.index('run_probe "$WORK/without-fixture.txt")')
        postcondition = verifier.index('clipboard_domain_absent "$REAL_HOME" "$DOMAIN" || { printf \'Postcondition')
        self.assertLess(precondition, with_fixture)
        self.assertLess(with_fixture, control)
        self.assertLess(control, postcondition)
        self.assertIn('[[ "$actual" != "$expected" ]]', verifier)
        self.assertIn("[[ \"$control\" != 'paused=false history=absent' ]]", verifier)
        self.assertIn("<key>CFBundleIdentifier</key><string>local.clipboardshelf</string>", verifier)
        probe = (ROOT / ".github/scripts/readme-media-defaults-probe.swift").read_text(encoding="utf-8")
        self.assertNotIn("NSPasteboard", probe)
        self.assertNotIn(".set(", probe)
        self.assertIn("[ClipboardEntry].self", probe)

        launch = (ROOT / "Sources/main.swift").read_text(encoding="utf-8")
        pasteboard_check = launch.split("@objc private func checkPasteboard()", 1)[1].split("func clipboardShelfViewController", 1)[0]
        self.assertLess(pasteboard_check.index("guard !isRecordingPaused"), pasteboard_check.index("pasteboard.string(forType: .string)"))
        description = launch.split("private func updateStatusItemAppearance()", 1)[1].split("@objc", 1)[0]
        self.assertIn('isRecordingPaused ? "Clipboard Shelf — recording paused" : "Clipboard Shelf"', description)
        self.assertIn("STATUS_DESCRIPTION='Clipboard Shelf — recording paused'", self.capture)

    def test_shelf_capture_has_no_desktop_cleanup_and_outputs_stay_under_runner_temp(self) -> None:
        for forbidden in (
            "system_profiler",
            "killall Finder",
            'close every window',
            "CreateDesktop false",
            "set picture to",
        ):
            self.assertNotIn(forbidden, self.capture)
        shelf = self.capture.split('  clipboard-shelf)\n    prepare_clipboard_demo', 1)[1].split('\n    ;;', 1)[0]
        self.assertIn('capture_menu_region "$ARTIFACT_DIR/clipboard-shelf-light.png"', shelf)
        self.assertIn('capture_menu_region "$ARTIFACT_DIR/clipboard-shelf-dark.png"', shelf)
        self.assertNotIn("$ROOT/docs/images/clipboard-shelf-", shelf)
        self.assertNotIn("capture_video_region", shelf)
        runtime = (ROOT / ".github/scripts/readme-media-runtime.sh").read_text(encoding="utf-8")
        self.assertIn('local gif="$ARTIFACT_DIR/$SLUG-hero.gif"', runtime)
        self.assertIn('validate_readme_media_capture.py" geometry', self.capture)
        self.assertIn('validate_readme_media_capture.py" png', self.capture)
        success = self.workflow.split("if: success()", 1)[1]
        self.assertIn('${{ runner.temp }}/readme-media/clipboard-shelf-light.png', success)
        self.assertIn('${{ runner.temp }}/readme-media/clipboard-shelf-dark.png', success)
        self.assertNotIn("clipboard-shelf-hero", success)
        self.assertNotIn("readme-media/*", success)
        self.assertNotIn("docs/images/", success)

    def test_new_geometry_pixel_and_release_fixtures_run_in_validation_workflows_only(self) -> None:
        for name in (
            "test-readme-media-capture-validation.py",
            "test-readme-media-release.py",
            "test-readme-media-popover-selection.py",
        ):
            self.assertIn(name, self.workflow)
            self.assertIn(name, MACOS_CI.read_text(encoding="utf-8"))
        macos_ci = MACOS_CI.read_text(encoding="utf-8")
        self.assertNotIn("capture-readme-media.sh", macos_ci)
        self.assertIn("run: bash .github/scripts/verify-status-popover-geometry.sh", macos_ci)
        self.assertIn("workflow_dispatch", self.workflow)
        self.assertNotIn("  pull_request:", self.workflow)

    def test_sanitized_geometry_snapshot_is_uploaded_only_on_failure(self) -> None:
        self.assertIn("name: Upload sanitized geometry diagnostics on failure", self.workflow)
        failure_step = self.workflow.split("name: Upload sanitized geometry diagnostics on failure", 1)[1].split(
            "      - uses: actions/upload-artifact@v4", 1
        )[0]
        self.assertIn("if: failure()", failure_step)
        self.assertIn("path: ${{ runner.temp }}/readme-media/diagnostics/geometry-snapshot.json", failure_step)
        self.assertIn("retention-days: 3", failure_step)
        self.assertNotIn(".png", failure_step)
        self.assertNotIn("windows.tsv", failure_step)

    def test_geometry_snapshot_contains_only_shelf_pid_geometry_and_rejection(self) -> None:
        capture = self.capture
        self.assertIn("trap capture_exit_diagnostics EXIT", capture)
        self.assertIn("status_item_snapshot", capture)
        status_snapshot_fn = capture.split("status_item_snapshot() {", 1)[1].split("if [[ -L", 1)[0]
        self.assertIn('readme-media-status-item.applescript" frame "$APP_PID" "$STATUS_DESCRIPTION"', status_snapshot_fn)
        status_script = (ROOT / ".github/scripts/readme-media-status-item.applescript").read_text(encoding="utf-8")
        self.assertIn("every process whose unix id is appPid", status_script)
        self.assertIn("repeat with barIndex from 1 to barCount", status_script)
        self.assertIn("(itemDescription as text) is expectedDescription", status_script)
        self.assertIn('if (count of statusMatches) is not 1 then error', status_script)
        self.assertIsNone(re.search(r"\btry\b", status_script))
        self.assertNotIn("tell process", status_script)
        self.assertNotIn("contains", status_script)
        self.assertNotIn("tell process appName", capture.split("show_menu_popover() {", 1)[1].split("window_info() {", 1)[0])
        snapshot_body = capture.split("write_geometry_snapshot() {", 1)[1]
        self.assertLess(snapshot_body.index('APP_PID="$(swift "$HELPER" pid "$APP"'), snapshot_body.index("status_item_snapshot"))
        self.assertIn('swift "$HELPER" pid "$APP"', capture)
        self.assertIn('swift "$HELPER" windows-pid "$APP_PID"', capture)
        self.assertIn('swift "$HELPER" display-geometry', capture)
        self.assertIn("build_readme_media_geometry_snapshot.py", capture)
        self.assertIn("strict_ax_adjacency_predicate_failed_after_12_polls", capture)
        self.assertIn("capture_pixel_validation_failed", capture)
        self.assertIn("geometry-snapshot.json", capture)
        snapshot_fn = capture.split("write_geometry_snapshot() {", 1)[1].split("capture_exit_diagnostics() {", 1)[0]
        self.assertNotIn("screencapture", snapshot_fn)
        self.assertNotIn("CGWindowListCopyWindowInfo", snapshot_fn)
        helper = (ROOT / ".github/scripts/render-readme-media.swift").read_text(encoding="utf-8")
        pid_windows = helper.split("func printWindowsForPID", 1)[1].split("func printAppPID", 1)[0]
        self.assertIn("int32Value == pid", pid_windows)
        self.assertIn('throw MediaError(description: "Incomplete window record', pid_windows)
        self.assertNotIn("continue }\n        let layer", pid_windows)
        self.assertNotIn("kCGWindowName", pid_windows)
        self.assertNotIn("kCGWindowOwnerName", pid_windows)
        self.assertIn(r"windowID\tPID\tlayer", pid_windows)

    def test_strict_adjacency_limits_are_unchanged_and_not_widened(self) -> None:
        validator = (ROOT / ".github/scripts/validate_readme_media_capture.py").read_text(encoding="utf-8")
        predicate = validator.split("def select_unique_popover(", 1)[1].split("\ndef ", 1)[0]
        self.assertIn("horizontal_overlap = x < status_right + 80 and x + width > status_x - 80", predicate)
        self.assertIn("and -8 <= vertical_gap <= 120", predicate)
        self.assertIn("and width >= 240", predicate)
        self.assertIn("and height >= 240", predicate)
        # Every visible window of the launched PID is judged; none can be skipped by a query error.
        self.assertIn("select_popover_from_inventory", validator)
        self.assertIn("menu_geometry() {\n  status_popover_geometry \"$APP_PID\" \"$STATUS_DESCRIPTION\"\n}", self.capture)
        self.assertIn('windows-pid "$pid"', self.runtime)
        self.assertIn("select-popover", self.runtime)
        self.assertNotIn("every window", self.capture)

    def test_geometry_snapshot_redacts_titles_and_rejects_unrelated_pids(self) -> None:
        scratch_root = Path(os.environ.get("RUNNER_TEMP") or os.environ.get("TMPDIR") or "/tmp")
        with tempfile.TemporaryDirectory(dir=scratch_root) as temporary:
            inventory = Path(temporary) / "windows.tsv"
            header = "\t".join(["windowID", "PID", "layer", "alpha", "x", "y", "width", "height"])
            inventory.write_text(header + "\n" + "\t".join(["71", "4242", "0", "1.0", "100", "24", "430", "500"]) + "\n", encoding="utf-8")
            snapshot = geometry_snapshot.make_snapshot(
                reason="strict_ax_adjacency_predicate_failed_after_12_polls",
                app_pid_raw="4242",
                status_item_raw="1|800|0|28|24",
                windows_path=inventory,
                display_info_raw="frame=0,0,1024,768|pixels=1024x768|scale=1",
            )
            self.assertEqual(snapshot["status_item"], {"match_count": 1, "frame": [800, 0, 28, 24]})
            self.assertEqual(snapshot["app_owned_windows"], [{
                "window_id": 71, "pid": 4242, "layer": 0, "alpha": 1.0, "frame": [100, 24, 430, 500]
            }])
            self.assertEqual(snapshot["display"]["frame_points"], [0, 0, 1024, 768])
            self.assertEqual(snapshot["display"]["scale"], 1)
            self.assertEqual(snapshot["rejection_reason"], "strict_ax_adjacency_predicate_failed_after_12_polls")
            snapshot_path = Path(temporary) / "geometry-snapshot.json"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / ".github/scripts/build_readme_media_geometry_snapshot.py"),
                    "--reason", "strict_ax_adjacency_predicate_failed_after_12_polls",
                    "--app-pid", "4242",
                    "--status-item", "1|800|0|28|24",
                    "--windows", str(inventory),
                    "--display-info", "frame=0,0,1024,768|pixels=1024x768|scale=1",
                    "--output", str(snapshot_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(json.loads(snapshot_path.read_text(encoding="utf-8")), snapshot)
            serialized = json.dumps(snapshot)
            for forbidden in ("window_title", "owner_name", "clipboard_text", "Sensitive Clipboard Text"):
                self.assertNotIn(forbidden, serialized)

            inventory.write_text(
                header + "\tname\n" + "\t".join(["72", "9999", "0", "1.0", "1", "2", "430", "500", "Sensitive Clipboard Text"]) + "\n",
                encoding="utf-8",
            )
            rejected = geometry_snapshot.make_snapshot(
                reason="strict_ax_adjacency_predicate_failed_after_12_polls",
                app_pid_raw="4242",
                status_item_raw="2|0|0|0|0",
                windows_path=inventory,
                display_info_raw="frame=0,0,1024,768|pixels=1024x768|scale=1",
            )
            rejected_json = json.dumps(rejected)
            self.assertEqual(rejected["app_owned_windows"], [])
            self.assertIsNone(rejected["status_item"]["frame"])
            self.assertIn("invalid_app_window_inventory", rejected["collection_errors"])
            self.assertNotIn("Sensitive Clipboard Text", rejected_json)

    def test_capture_diagnostics_document_the_unproven_geometry_blocker(self) -> None:
        doc = (ROOT / "docs/readme-media-capture-diagnostics.md").read_text(encoding="utf-8")
        self.assertIn("36270162668", doc)
        self.assertIn("unproven", doc)
        self.assertIn("window titles", doc)
        self.assertIn("not safe to retry", doc)
        self.assertIn("pixel dimensions", doc)
        self.assertIn("asset digest/sidecar", doc)
        self.assertIn("release tag", doc)
        self.assertIn("NSPasteboard", doc)
        self.assertIn("Finder and Terminal window", doc)
        self.assertIn("No qualifying GIF/MP4 artifact", doc)


if __name__ == "__main__":
    unittest.main(verbosity=2)
