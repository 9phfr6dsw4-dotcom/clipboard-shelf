#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/readme-media-runtime.sh"

ffprobe() { printf '%s\n' "${MOCK_VIDEO_DIMENSIONS:?}"; }

assert_equal() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s (expected=%s, actual=%s)\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

MOCK_VIDEO_DIMENSIONS=1280x900
assert_equal null "$(video_region_filter /unused 0 0 640 450 2)" 'accept exact region dimensions'

assert_equal '476,0,468,650,2' "$(menu_region_from_geometry 500 30 420 600 700 5 25 24 1440 900 2)" 'compute capture rectangle from verified popover and status item geometry'
if menu_region_from_geometry 500 30 420 600 700 5 25 24 1440 900 >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: reject missing capture scale geometry' >&2
  exit 1
fi
for geometry in \
  '500 30 0 600 700 5 25 24 1440 900 2' \
  '500 30 239 600 700 5 25 24 1440 900 2' \
  '500 30 420 600 700 5 25 24 800 600 2' \
  '500 30 420 600 700 5 25 24 1440 900 0' \
  '-1 30 420 600 700 5 25 24 1440 900 2'; do
  read -r -a values <<< "$geometry"
  if menu_region_from_geometry "${values[@]}" >/dev/null 2>&1; then
    printf 'FAIL: reject invalid capture geometry: %s\n' "$geometry" >&2
    exit 1
  fi
done

MOCK_VIDEO_DIMENSIONS=2560x1800
assert_equal 'crop=1280:900:200:80' "$(video_region_filter /unused 100 40 640 450 2)" 'crop full-display recording to exact requested region'

MOCK_VIDEO_DIMENSIONS=1300x900
if video_region_filter /unused 100 0 640 450 2 >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: reject a region that does not fit the source recording' >&2
  exit 1
fi

MOCK_VIDEO_DIMENSIONS=1280x900
if video_region_filter /unused -1 0 640 450 2 >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: reject negative capture coordinates' >&2
  exit 1
fi

if duration_is_acceptable 12.0001; then
  printf '%s\n' 'FAIL: reject fractional duration over 12 seconds' >&2
  exit 1
fi
if duration_is_acceptable 12.999; then
  printf '%s\n' 'FAIL: reject truncated integer duration over 12 seconds' >&2
  exit 1
fi
if duration_is_acceptable 5.999; then
  printf '%s\n' 'FAIL: reject fractional duration under 6 seconds' >&2
  exit 1
fi
for duration in 6 6.0001 11.999 12 12.000; do
  duration_is_acceptable "$duration" || { printf 'FAIL: accept duration %s within 6–12 seconds\n' "$duration" >&2; exit 1; }
done
if duration_is_acceptable invalid; then
  printf '%s\n' 'FAIL: reject malformed duration' >&2
  exit 1
fi

mock_appearance_result=light
mock_osascript_status=0
osascript() {
  if (( mock_osascript_status != 0 )); then return "$mock_osascript_status"; fi
  printf '%s' "$mock_appearance_result"
}
sleep() { :; }
if ! set_appearance false; then
  printf '%s\n' 'FAIL: accept verified light appearance' >&2
  exit 1
fi
mock_appearance_result=dark
if ! set_appearance true; then
  printf '%s\n' 'FAIL: accept verified dark appearance' >&2
  exit 1
fi
mock_appearance_result=light
if set_appearance true >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: reject appearance mismatch' >&2
  exit 1
fi
mock_osascript_status=1
if set_appearance false >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: fail closed when AppleScript cannot set appearance' >&2
  exit 1
fi

mock_osascript_status=0
for mode in true false; do
  mock_appearance_result="$mode"
  assert_equal "$mode" "$(get_appearance)" "read original dark mode=$mode"
done
mock_appearance_result=unknown
if get_appearance >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: reject unreadable original appearance' >&2
  exit 1
fi
mock_osascript_status=1
if get_appearance >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: fail closed when AppleScript cannot read appearance' >&2
  exit 1
fi

osascript_calls="$(mktemp)"
trap 'rm -f "$osascript_calls"' EXIT
osascript() {
  printf '%s\n' "$*" >> "$osascript_calls"
  if (( mock_osascript_status != 0 )); then return "$mock_osascript_status"; fi
  printf '%s' "$mock_appearance_result"
}
mock_osascript_status=0
unset ORIGINAL_DARK_MODE
restore_appearance || { printf '%s\n' 'FAIL: no-op restore before any appearance snapshot' >&2; exit 1; }
[[ ! -s "$osascript_calls" ]] || { printf '%s\n' 'FAIL: restore without snapshot must not touch appearance' >&2; exit 1; }
ORIGINAL_DARK_MODE=true
mock_appearance_result=dark
restore_appearance || { printf '%s\n' 'FAIL: restore original dark appearance' >&2; exit 1; }
assert_equal '- true' "$(tail -n 1 "$osascript_calls")" 'restore requests the snapshotted appearance'
mock_appearance_result=light
if restore_appearance >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: report an appearance restore that did not take effect' >&2
  exit 1
fi
ORIGINAL_DARK_MODE=maybe
if restore_appearance >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: reject a corrupted appearance snapshot' >&2
  exit 1
fi

# Leak detector for the app's real preference domain (defaults and the file system are mocked).
fake_home="$(mktemp -d)"
trap 'rm -f "$osascript_calls"; rm -rf "$fake_home"' EXIT
mkdir -p "$fake_home/Library/Preferences/ByHost"
mock_defaults_status=1
defaults() { [[ "$1" == read && "$2" == local.clipboardshelf ]] || return 64; return "$mock_defaults_status"; }
clipboard_domain_absent "$fake_home" local.clipboardshelf || { printf '%s\n' 'FAIL: accept an absent real preference domain' >&2; exit 1; }
if clipboard_domain_absent relative/home local.clipboardshelf >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: reject a relative real home' >&2
  exit 1
fi
for planted in "Preferences/local.clipboardshelf.plist" "Preferences/ByHost/local.clipboardshelf.0123-ABCD.plist"; do
  : > "$fake_home/Library/$planted"
  if clipboard_domain_absent "$fake_home" local.clipboardshelf >/dev/null 2>&1; then
    printf 'FAIL: detect planted preference file %s\n' "$planted" >&2
    exit 1
  fi
  rm -f "$fake_home/Library/$planted"
done
ln -s /nonexistent "$fake_home/Library/Preferences/local.clipboardshelf.plist"
if clipboard_domain_absent "$fake_home" local.clipboardshelf >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: detect a dangling preference symlink' >&2
  exit 1
fi
rm -f "$fake_home/Library/Preferences/local.clipboardshelf.plist"
mock_defaults_status=0
if clipboard_domain_absent "$fake_home" local.clipboardshelf >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: detect a populated domain that has no plist on disk yet' >&2
  exit 1
fi

# Launch-argument fixture loader accepts only the exact four-argument shape.
HELPER=/unused
mock_swift_output=$'-ClipboardShelfHistoryV1\n<5b7b7d5d>\n-ClipboardShelfRecordingPausedV1\nYES'
mock_swift_status=0
swift() { [[ "$1" == /unused && "$2" == clipboard-demo-args ]] || return 64; printf '%s\n' "$mock_swift_output"; return "$mock_swift_status"; }
load_clipboard_demo_args || { printf '%s\n' 'FAIL: accept the exact launch-argument fixture' >&2; exit 1; }
assert_equal 4 "${#CLIPBOARD_DEMO_ARGS[@]}" 'fixture argument count'
assert_equal '<5b7b7d5d>' "${CLIPBOARD_DEMO_ARGS[1]}" 'fixture history literal preserved verbatim'
for bad in $'-ClipboardShelfHistoryV1\n<5b7b7d5d>\n-ClipboardShelfRecordingPausedV1\nNO' \
           $'-ClipboardShelfHistoryV1\n<not hex>\n-ClipboardShelfRecordingPausedV1\nYES' \
           $'-ClipboardShelfHistoryV1\n<5b7b7d5d>\n-ClipboardShelfRecordingPausedV1\nYES\n-Extra\n1' \
           $'-Other\n<5b7b7d5d>\n-ClipboardShelfRecordingPausedV1\nYES'; do
  mock_swift_output="$bad"
  if load_clipboard_demo_args >/dev/null 2>&1; then
    printf 'FAIL: reject malformed fixture arguments: %q\n' "$bad" >&2
    exit 1
  fi
done
mock_swift_output=$'-ClipboardShelfHistoryV1\n<5b7b7d5d>\n-ClipboardShelfRecordingPausedV1\nYES'
mock_swift_status=1
if load_clipboard_demo_args >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: fail closed when the fixture helper fails' >&2
  exit 1
fi

# Popover geometry: PID-bound status item frame plus that PID's window inventory.
mock_status_output='762|3|24|24'
mock_status_rc=0
mock_inventory=$'windowID\tPID\tlayer\talpha\tx\ty\twidth\theight\n32\t4428\t25\t1.0\t546\t26\t456\t526'
osascript() {
  [[ "$1" == */readme-media-status-item.applescript && "$2" == frame && "$3" == 4428 && "$4" == 'Clipboard Shelf — recording paused' ]] || return 64
  printf '%s\n' "$mock_status_output"
  return "$mock_status_rc"
}
swift() {
  [[ "$1" == /unused ]] || return 64
  case "$2" in
    windows-pid) [[ "$3" == 4428 ]] || return 64; printf '%s\n' "$mock_inventory" ;;
    display-info) printf '%s\n' 'frame=1024x768|pixels=1024x768|scale=1' ;;
    *) return 64 ;;
  esac
}
assert_equal '546|26|456|526|762|3|24|24|0' "$(status_popover_geometry 4428 'Clipboard Shelf — recording paused')" 'select the observed macOS 26 popover for the launched PID'
geometry_rejected() {
  if status_popover_geometry "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s\n' "$label" >&2
    exit 1
  fi
}
label='reject a different status description'; geometry_rejected 4428 'Clipboard Shelf'
label='reject a missing PID'; geometry_rejected '' 'Clipboard Shelf — recording paused'
mock_status_rc=1; label='fail closed when the status item query fails'; geometry_rejected 4428 'Clipboard Shelf — recording paused'
mock_status_rc=0; mock_status_output='762|3|24'; label='reject a malformed status frame'; geometry_rejected 4428 'Clipboard Shelf — recording paused'
mock_status_output='762|3|24|24'; mock_inventory=$'windowID\tPID\tlayer\talpha\tx\ty\twidth\theight'
label='fail closed before the popover window exists'; geometry_rejected 4428 'Clipboard Shelf — recording paused'
mock_inventory=$'windowID\tPID\tlayer\talpha\tx\ty\twidth\theight\n32\t4428\t25\t1.0\t546\t26\t456\t526\n33\t4428\t25\t1.0\t500\t30\t300\t300'
label='fail closed on ambiguous popover candidates'; geometry_rejected 4428 'Clipboard Shelf — recording paused'

printf '%s\n' 'PASS: video crop, duration, appearance, preference-leak, fixture-argument, and popover-geometry cases'
