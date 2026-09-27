#!/usr/bin/env bash
# macOS CI regression check for capture popover geometry. Two copies of a synthetic
# status-item/NSPopover fixture (no pasteboard, no screenshots) share one status description
# and are driven through the same PID-bound code the capture uses:
# - Before a click, selection for fixture A must fail with no_adjacent_app_window.
# - After clicking A, geometry for A must be exactly the popover frame AppKit reports, while
#   B must still find no popover even though A's popover is on screen (PID binding).
# - A description that differs only in case must match no status item.
# - The fixture's real preference domain must be absent beforehand; afterwards it may hold
#   only AppKit's status-item bookkeeping keys, whose names are logged.
# The original selector enumerated System Events windows, which on the macOS 15/26 runners
# expose no NSPopover window, so it could never find one.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HELPER="$ROOT/.github/scripts/render-readme-media.swift"
source "$ROOT/.github/scripts/readme-media-runtime.sh"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
[[ "$RUNNER_TEMP" == /* && -d "$RUNNER_TEMP" && ! -L "$RUNNER_TEMP" ]] || { printf 'RUNNER_TEMP must be an existing absolute directory.\n' >&2; exit 2; }
DESCRIPTION='Popover Fixture — recording paused'
DOMAIN=local.readme-media.popover-fixture
STATUS_SCRIPT="$ROOT/.github/scripts/readme-media-status-item.applescript"
VALIDATOR="$ROOT/.github/scripts/validate_readme_media_capture.py"

fail() { printf '%s\n' "$1" >&2; exit 1; }

REAL_HOME="$(real_user_home)"
clipboard_domain_absent "$REAL_HOME" "$DOMAIN" || fail "Precondition failed: the real $DOMAIN domain must be absent."

WORK="$(mktemp -d "$RUNNER_TEMP/status-popover-geometry.XXXXXXXX")"
FIXTURE_A="$WORK/a/ReadmeMediaPopoverFixture.app"
FIXTURE_B="$WORK/b/ReadmeMediaPopoverFixture.app"
mkdir -p "$FIXTURE_A/Contents/MacOS"
cat > "$FIXTURE_A/Contents/Info.plist" <<'PLIST'
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
swiftc -O "$ROOT/.github/scripts/readme-media-popover-fixture.swift" -o "$FIXTURE_A/Contents/MacOS/ReadmeMediaPopoverFixture"
codesign --force --sign - "$FIXTURE_A" >/dev/null
mkdir -p "$WORK/b"
cp -R "$FIXTURE_A" "$FIXTURE_B"

stop_fixtures() {
  stop_app_instances "$FIXTURE_A/Contents/MacOS/ReadmeMediaPopoverFixture" \
    && stop_app_instances "$FIXTURE_B/Contents/MacOS/ReadmeMediaPopoverFixture"
}
trap 'stop_fixtures >/dev/null 2>&1 || true' EXIT

launch_fixture() { # bundle report -> PID once its status item is visible to System Events
  local bundle="$1" report="$2" pid='' attempt
  open -n "$bundle" --args "$report"
  for attempt in {1..20}; do
    pid="$(swift "$HELPER" pid "$bundle" 2>/dev/null)" && break
    pid=''
    sleep 0.5
  done
  [[ "$pid" =~ ^[0-9]+$ ]] || fail "Fixture $bundle did not start."
  for attempt in {1..20}; do
    osascript "$STATUS_SCRIPT" frame "$pid" "$DESCRIPTION" >/dev/null 2>&1 && break
    sleep 0.5
  done
  osascript "$STATUS_SCRIPT" frame "$pid" "$DESCRIPTION" >/dev/null || fail "Fixture $bundle status item never appeared."
  printf '%s\n' "$pid"
}

# Prints select-popover's rejection reason for PID; succeeds only if a popover was selected.
selection_reason() {
  local pid="$1" status inventory display_info frame status_x status_y status_w status_h
  status="$(osascript "$STATUS_SCRIPT" frame "$pid" "$DESCRIPTION")" || { printf 'status_item_query_failed\n'; return 1; }
  inventory="$(swift "$HELPER" windows-pid "$pid")" || { printf 'window_inventory_failed\n'; return 1; }
  display_info="$(swift "$HELPER" display-info)" || { printf 'display_query_failed\n'; return 1; }
  frame="${display_info%%|*}"
  frame="${frame#frame=}"
  IFS='|' read -r status_x status_y status_w status_h <<< "$status"
  # shellcheck disable=SC2069 # deliberately keep only the rejection reason from stderr
  printf '%s\n' "$inventory" | python3 "$VALIDATOR" select-popover --pid "$pid" \
    --status "$status_x" "$status_y" "$status_w" "$status_h" --display "${frame%x*}" "${frame#*x}" 2>&1 >/dev/null
}

PID_A="$(launch_fixture "$FIXTURE_A" "$WORK/a-popover.txt")"
PID_B="$(launch_fixture "$FIXTURE_B" "$WORK/b-popover.txt")"
[[ "$PID_A" != "$PID_B" ]] || fail 'Both fixtures resolved to one PID.'

reason="$(selection_reason "$PID_A")" && fail 'A popover was selected before the click.'
[[ "$reason" == no_adjacent_app_window ]] || fail "Before the click, selection failed for the wrong reason: $reason"
printf 'Before the click, selection fails with %s.\n' "$reason"

if error="$(osascript "$STATUS_SCRIPT" frame "$PID_A" 'popover fixture — recording paused' 2>&1)"; then
  fail 'A description differing only in case matched the status item.'
fi
[[ "$error" == *status_item_not_unique:0* ]] || fail "Case-changed description failed for the wrong reason: $error"
printf 'A description differing only in case matches no status item.\n'

osascript "$STATUS_SCRIPT" click "$PID_A" "$DESCRIPTION" >/dev/null
geometry=''
for attempt in {1..12}; do
  geometry="$(status_popover_geometry "$PID_A" "$DESCRIPTION" 2>/dev/null)" && break
  geometry=''
  sleep 0.25
done
[[ -n "$geometry" ]] || fail 'No unique popover was selected after the click.'
for attempt in {1..20}; do
  [[ -s "$WORK/a-popover.txt" ]] && break
  sleep 0.25
done
expected="$(cat "$WORK/a-popover.txt")"
IFS='|' read -r pop_x pop_y pop_w pop_h status_x status_y status_w status_h fallback <<< "$geometry"
[[ "$pop_x|$pop_y|$pop_w|$pop_h" == "$expected" && "$fallback" == 0 ]] \
  || fail "Selected popover $pop_x|$pop_y|$pop_w|$pop_h does not match the AppKit frame $expected."
printf 'Selected fixture A popover %s beside status item %s.\n' "$expected" "$status_x|$status_y|$status_w|$status_h"

reason="$(selection_reason "$PID_B")" && fail "Fixture B selected fixture A's popover."
[[ "$reason" == no_adjacent_app_window ]] || fail "Fixture B failed for the wrong reason: $reason"
[[ ! -s "$WORK/b-popover.txt" ]] || fail 'Fixture B unexpectedly opened a popover.'
printf 'With A open, fixture B still selects nothing (%s): selection is bound to the PID.\n' "$reason"

stop_fixtures || fail 'A fixture survived SIGKILL.'
app_state_absent "$REAL_HOME" "$DOMAIN" || fail "Postcondition failed: unexpected state in the real $DOMAIN domain."
printf 'The real %s domain holds no app state after the fixtures stopped.\n' "$DOMAIN"
