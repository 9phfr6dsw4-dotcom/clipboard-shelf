# Manual capture geometry diagnostics

The README media capture stays opt-in through `workflow_dispatch` on the canonical repository's `main` branch. A failed Clipboard Shelf popover geometry check now emits one short-retention JSON artifact, `clipboard-shelf-geometry-diagnostics-<run-id>`.

The snapshot contains the Shelf status-item match count and, only when uniquely matched, its frame; the launched app PID; that PID's on-screen Core Graphics window IDs/layers/frames/alpha values; the main display frame and scale; a fixed rejection reason; and any fixed collection-error codes. It does not include window titles, clipboard text, screenshots, unrelated processes, or credentials. The window inventory is filtered to the exact running app bundle's PID; malformed or mismatched inventory is discarded rather than included.

The geometry predicate remains strict. Diagnostics do not widen adjacency thresholds or make arbitrary windows eligible for capture. A capture still fails when the status item is not unique or no single app popover satisfies the existing geometry checks.

Run `36270162668` identified the Shelf status item and then failed the adjacency check. That run's helper suppressed the underlying geometry-query errors, so the precise geometry cause remains **unproven**. This diagnostic change is intended to collect enough sanitized evidence on a future authorized run to investigate it; it does not claim to fix the capture, and it does not create or replace any screenshot, GIF, or video.

## Remaining blockers before any capture retry

The current capture flow is not safe to retry yet. A separate audit found:

- The capture script downloads a ZIP using the latest-release default, then extracts it and removes quarantine without checking the published asset digest/sidecar or matching the app bundle version to the release tag.
- The visible-window check relies on a status-item/proximity/size heuristic; it does not prove that the selected window is the actual Clipboard Shelf popover.
- Screenshot validation checks that the file is nonempty, not that its pixel dimensions and bounds match the measured target. The screen-region fallback also lacks a verified captured-bounds check.
- Seeding synthetic preferences does not isolate the live pasteboard. The released app polls `NSPasteboard` and records changes while recording is unpaused, so unrelated clipboard content could enter the captured UI.
- The capture script disables and restarts Finder and closes every Finder and Terminal window, which are broad desktop side effects.

These issues are intentionally not addressed by this diagnostics-only PR. Do not dispatch a capture until window identity and pixel bounds are verified, pasteboard monitoring is isolated or safely paused with exact synthetic-entry assertions, and desktop cleanup no longer closes unrelated windows. No qualifying GIF/MP4 artifact has been produced.
