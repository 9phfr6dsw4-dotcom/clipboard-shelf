# Manual capture geometry diagnostics

The README media capture is opt-in through `workflow_dispatch` on the canonical repository's `main` branch. Routine CI runs safety, geometry, release-fixture, and synthetic-preferences tests only; it does not capture screens or launch the published app.

## What run 36270162668 proves

The failed run on September 26, 2026 identified a Clipboard Shelf status-bar item, then failed to find exactly one visible app-process window satisfying the existing adjacency predicate after 12 polls. The log does not include the candidate window frames or a more specific rejection. The capture helper suppressed `menu_geometry` stdout/stderr in the polling loop and ignored per-window accessibility-query errors. The run predates failure-only geometry artifacts, and GitHub reports no artifact for that run. Therefore the precise cause—missing AX windows, inaccessible geometry, zero qualifying candidates, or ambiguous candidates—remains **unproven**. Do not describe a guessed cause as a fix.

## Fail-closed changes in this PR

- Keep the original adjacency thresholds unchanged: horizontal overlap within 80 points, vertical gap from -8 through 120 points, and minimum window size 240×240 points. Revalidate measured status-item/popover geometry before capture and reject missing, invalid, off-display, or ambiguous candidates.
- Read and validate the PNG pixel dimensions from each still capture, requiring an exact match to measured region bounds multiplied by display scale. A missing, malformed, or mismatched image fails the capture.
- Pin the published `v1.0.2` release tag to commit `f25223855444d19e204016e27b8940afec806b20`, archive `Clipboard-Shelf-1.0.2.zip`, and SHA-256 `ed25cf9e18a6b268ec802f63c16e469ccbece92558760a14413b66585233312f`. Verify the release asset digest/sidecar plus bundle identifier/version/executable before extraction or quarantine removal.
- Create the exact synthetic Shelf history and paused-recording preference under a fresh `$RUNNER_TEMP` demo home. Verify all eight expected entries and the pause flag before app launch. The published app's `NSPasteboard` polling checks pause before reading clipboard text; the demo does not copy or paste real clipboard content.
- Keep captures, temporary release files, demo preferences, and logs under `$RUNNER_TEMP`; successful artifact upload lists only the two stills, GIF, and MP4. The Clipboard Shelf path does not generate a composed social preview.
- Remove desktop modifications, Finder restarts, Finder and Terminal window closes, and broad `system_profiler` output.
- On failure, upload only a short-retention JSON geometry snapshot containing the status-item match/frame, launched app PID, that PID's window IDs/layers/bounds/alpha, display geometry, and allowlisted reason/error codes. It excludes window titles, clipboard text, unrelated processes, screenshots, and credentials.

Deterministic fixtures cover the existing strict geometry boundaries, absent/ambiguous candidates, malformed PNGs, and exact pixel-size mismatches. They do not reconstruct the missing geometry from run `36270162668`.

## Retry status

No retry has been dispatched. It is not safe to retry until the PR branch guards and tests pass, the macOS synthetic-preferences isolation check passes, and the historical geometry cause is either proven or a new privacy-safe diagnostic run is explicitly authorized. The fixed release and its sidecar have been downloaded and verified in an isolated scratch directory; the ZIP reports bundle ID `local.clipboardshelf`, version `1.0.2`, and executable `ClipboardShelf`. The exact historical geometry failure still cannot be proven from the available log/artifacts. No qualifying GIF/MP4 artifact was produced in this work.
