#!/usr/bin/env bash
# macOS CI regression check for capture popover geometry. A synthetic status-item/NSPopover
# fixture (no pasteboard, no screenshots) is driven through the same PID-bound code the
# capture uses. Before its popover opens, and for a non-matching status description,
# geometry must fail closed. After the click it must select exactly the popover frame that
# AppKit reports. The original selector enumerated System Events windows, which on the
# macOS 15/26 runners expose no NSPopover window, so it could never find one.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HELPER="$ROOT/.github/scripts/render-readme-media.swift"
source "$ROOT/.github/scripts/readme-media-runtime.sh"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
[[ "$RUNNER_TEMP" == /* && -d "$RUNNER_TEMP" && ! -L "$RUNNER_TEMP" ]] || { printf 'RUNNER_TEMP must be an existing absolute directory.\n' >&2; exit 2; }
DESCRIPTION='Popover Fixture — recording paused'
STATUS_SCRIPT="$ROOT/.github/scripts/readme-media-status-item.applescript"

WORK="$(mktemp -d "$RUNNER_TEMP/status-popover-geometry.XXXXXXXX")"
FIXTURE="$WORK/ReadmeMediaPopoverFixture.app"
REPORT="$WORK/popover-frame.txt"
mkdir -p "$FIXTURE/Contents/MacOS"
cat > "$FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.readme-media.popover-fixture</string>
  <key>CFBundleExecutable</key><string>ReadmeMediaPopoverFixture</string>
  <key>CFBundleName</key><string>ReadmeMediaPopoverFixture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
swiftc -O "$ROOT/.github/scripts/readme-media-popover-fixture.swift" -o "$FIXTURE/Contents/MacOS/ReadmeMediaPopoverFixture"
codesign --force --sign - "$FIXTURE" >/dev/null

FIXTURE_PID=''
trap '[[ ! "$FIXTURE_PID" =~ ^[0-9]+$ ]] || kill -KILL "$FIXTURE_PID" 2>/dev/null || true' EXIT
open -n "$FIXTURE" --args "$REPORT"
for attempt in {1..20}; do
  FIXTURE_PID="$(swift "$HELPER" pid "$FIXTURE" 2>/dev/null)" && break
  FIXTURE_PID=''
  sleep 0.5
done
[[ "$FIXTURE_PID" =~ ^[0-9]+$ ]] || { printf 'Fixture did not start.\n' >&2; exit 1; }
for attempt in {1..20}; do
  osascript "$STATUS_SCRIPT" frame "$FIXTURE_PID" "$DESCRIPTION" >/dev/null 2>&1 && break
  sleep 0.5
done

if status_popover_geometry "$FIXTURE_PID" "$DESCRIPTION" >/dev/null 2>&1; then
  printf 'Geometry was accepted before the popover opened.\n' >&2
  exit 1
fi
printf 'Before the click, geometry fails closed.\n'

osascript "$STATUS_SCRIPT" click "$FIXTURE_PID" "$DESCRIPTION" >/dev/null
geometry=''
for attempt in {1..12}; do
  geometry="$(status_popover_geometry "$FIXTURE_PID" "$DESCRIPTION" 2>/dev/null)" && break
  geometry=''
  sleep 0.25
done
[[ -n "$geometry" ]] || { printf 'No unique popover was selected after the click.\n' >&2; exit 1; }
for attempt in {1..20}; do
  [[ -s "$REPORT" ]] && break
  sleep 0.25
done
expected="$(cat "$REPORT")"
IFS='|' read -r pop_x pop_y pop_w pop_h status_x status_y status_w status_h fallback <<< "$geometry"
if [[ "$pop_x|$pop_y|$pop_w|$pop_h" != "$expected" || "$fallback" != 0 ]]; then
  printf 'Selected popover %s does not match the AppKit frame %s.\n' "$pop_x|$pop_y|$pop_w|$pop_h" "$expected" >&2
  exit 1
fi
printf 'Selected the fixture popover %s beside status item %s.\n' "$expected" "$status_x|$status_y|$status_w|$status_h"

if status_popover_geometry "$FIXTURE_PID" 'Popover Fixture' >/dev/null 2>&1; then
  printf 'A non-matching status description was accepted.\n' >&2
  exit 1
fi
if status_popover_geometry 1 "$DESCRIPTION" >/dev/null 2>&1; then
  printf 'A different PID was accepted.\n' >&2
  exit 1
fi
printf 'Non-matching status description and PID fail closed.\n'
