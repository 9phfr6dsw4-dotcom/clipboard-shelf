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

# Real preference-domain checks (defaults and the file system are mocked; key names only).
fake_home="$(mktemp -d)"
trap 'rm -f "$osascript_calls"; rm -rf "$fake_home"' EXIT
mkdir -p "$fake_home/Library/Preferences/ByHost"
write_plist() { python3 - "$@" <<'PY_PLIST'
import plistlib, sys
path, keys = sys.argv[1], sys.argv[2:]
with open(path, "wb") as stream:
    plistlib.dump({key: "Sensitive Clipboard Text" for key in keys}, stream)
PY_PLIST
}
mock_domain_state=absent
mock_domain_keys=()
defaults() {
  [[ "$2" == local.clipboardshelf ]] || return 64
  case "$1:$mock_domain_state" in
    read:absent) printf 'Domain %s does not exist\n' "$2" >&2; return 1 ;;
    read:error) printf 'Could not connect to cfprefsd\n' >&2; return 1 ;;
    read:present) printf '{ values }\n'; return 0 ;;
    export:present)
      [[ "$3" == - ]] || return 64
      write_plist /dev/stdout ${mock_domain_keys[@]+"${mock_domain_keys[@]}"} ;;
    *) return 64 ;;
  esac
}
expect_rejected() {
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s\n' "$label" >&2
    exit 1
  fi
}
reset_domain() { mock_domain_state=absent; mock_domain_keys=(); rm -rf "$fake_home/Library/Preferences"; mkdir -p "$fake_home/Library/Preferences/ByHost"; }

clipboard_domain_absent "$fake_home" local.clipboardshelf || { printf '%s\n' 'FAIL: accept an absent real preference domain' >&2; exit 1; }
label='reject a relative real home'; expect_rejected clipboard_domain_absent relative/home local.clipboardshelf
for planted in "Preferences/local.clipboardshelf.plist" "Preferences/ByHost/local.clipboardshelf.0123-ABCD.plist"; do
  : > "$fake_home/Library/$planted"
  label="detect planted preference file $planted"; expect_rejected clipboard_domain_absent "$fake_home" local.clipboardshelf
  rm -f "$fake_home/Library/$planted"
done
ln -s /nonexistent "$fake_home/Library/Preferences/local.clipboardshelf.plist"
label='detect a dangling preference symlink'; expect_rejected clipboard_domain_absent "$fake_home" local.clipboardshelf
reset_domain
mock_domain_state=present; mock_domain_keys=("NSStatusItem Preferred Position Item-0")
label='strict precondition rejects even AppKit-only values'; expect_rejected clipboard_domain_absent "$fake_home" local.clipboardshelf
mock_domain_state=error
label='a defaults failure other than "does not exist" is not absence'; expect_rejected clipboard_domain_absent "$fake_home" local.clipboardshelf

# Postcondition: only AppKit status-item bookkeeping keys are tolerated, and only their names are logged.
reset_domain
app_state_absent "$fake_home" local.clipboardshelf || { printf '%s\n' 'FAIL: accept an absent domain after the run' >&2; exit 1; }
mock_domain_state=present; mock_domain_keys=("NSStatusItem Preferred Position Item-0" "NSStatusItem VisibleCC Item-0")
appkit_log="$(app_state_absent "$fake_home" local.clipboardshelf 2>&1)" || { printf '%s\n' 'FAIL: tolerate AppKit status-item keys' >&2; exit 1; }
[[ "$appkit_log" == *'NSStatusItem Preferred Position Item-0'* && "$appkit_log" != *Sensitive* ]] || { printf 'FAIL: log AppKit key names only: %s\n' "$appkit_log" >&2; exit 1; }
for leaked in ClipboardShelfHistoryV1 ClipboardShelfRecordingPausedV1 "NSStatusItem Preferred Position Item-0 extra" NSWindow; do
  mock_domain_keys=("NSStatusItem Visible Item-0" "$leaked")
  label="reject key $leaked"; expect_rejected app_state_absent "$fake_home" local.clipboardshelf
  leak_log="$(app_state_absent "$fake_home" local.clipboardshelf 2>&1)" || true
  [[ "$leak_log" != *Sensitive* ]] || { printf '%s\n' 'FAIL: never log preference values' >&2; exit 1; }
done
reset_domain
write_plist "$fake_home/Library/Preferences/local.clipboardshelf.plist" "NSStatusItem Preferred Position Item-0"
app_state_absent "$fake_home" local.clipboardshelf 2>/dev/null || { printf '%s\n' 'FAIL: tolerate an on-disk AppKit-only plist' >&2; exit 1; }
write_plist "$fake_home/Library/Preferences/ByHost/local.clipboardshelf.0123-ABCD.plist" ClipboardShelfHistoryV1
label='reject app keys in a ByHost plist'; expect_rejected app_state_absent "$fake_home" local.clipboardshelf
reset_domain
printf 'not a plist' > "$fake_home/Library/Preferences/local.clipboardshelf.plist"
label='reject an unreadable plist'; expect_rejected app_state_absent "$fake_home" local.clipboardshelf
reset_domain
ln -s /nonexistent "$fake_home/Library/Preferences/local.clipboardshelf.plist"
label='reject a preference symlink after the run'; expect_rejected app_state_absent "$fake_home" local.clipboardshelf
reset_domain
mock_domain_state=error
label='reject an unreadable domain after the run'; expect_rejected app_state_absent "$fake_home" local.clipboardshelf
reset_domain

# Stopping the launched app kills every instance of the exact extracted executable.
pkill_calls="$(mktemp)"
trap 'rm -f "$osascript_calls" "$pkill_calls"; rm -rf "$fake_home"' EXIT
mock_survivors=0
pkill() { printf '%s\n' "$*" >> "$pkill_calls"; return 1; }
pgrep() { (( mock_survivors > 0 )); }
stop_app_instances '/tmp/run/release-app/Clipboard Shelf.app/Contents/MacOS/ClipboardShelf' || { printf '%s\n' 'FAIL: stop app instances' >&2; exit 1; }
assert_equal '-KILL -f -- ^/tmp/run/release-app/Clipboard Shelf\.app/Contents/MacOS/ClipboardShelf( |$)' "$(tail -n 1 "$pkill_calls")" 'anchored, escaped executable pattern'
mock_survivors=1
label='fail when an instance survives SIGKILL'; expect_rejected stop_app_instances '/tmp/run/release-app/Clipboard Shelf.app/Contents/MacOS/ClipboardShelf'
mock_survivors=0
label='reject a relative executable path'; expect_rejected stop_app_instances 'Clipboard Shelf.app/Contents/MacOS/ClipboardShelf'
unset -f pkill pgrep

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
status_calls="$(mktemp)"
trap 'rm -f "$osascript_calls" "$pkill_calls" "$status_calls"; rm -rf "$fake_home"' EXIT
osascript() {
  printf '%s\n' "${1##*/}|$2|$3|$4" >> "$status_calls"
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
assert_equal 'readme-media-status-item.applescript|frame|4428|Clipboard Shelf — recording paused' "$(tail -n 1 "$status_calls")" 'status item is looked up by the exact PID and description'
geometry_rejected() {
  if status_popover_geometry "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s\n' "$label" >&2
    exit 1
  fi
}
label='reject a missing PID'; geometry_rejected '' 'Clipboard Shelf — recording paused'
mock_status_rc=1; label='fail closed when the status item query fails'; geometry_rejected 4428 'Clipboard Shelf — recording paused'
mock_status_rc=0; mock_status_output='762|3|24'; label='reject a malformed status frame'; geometry_rejected 4428 'Clipboard Shelf — recording paused'
mock_status_output='762|3|24|24'; mock_inventory=$'windowID\tPID\tlayer\talpha\tx\ty\twidth\theight'
label='fail closed before the popover window exists'; geometry_rejected 4428 'Clipboard Shelf — recording paused'
mock_inventory=$'windowID\tPID\tlayer\talpha\tx\ty\twidth\theight\n32\t4428\t25\t1.0\t546\t26\t456\t526\n33\t4428\t25\t1.0\t500\t30\t300\t300'
label='fail closed on ambiguous popover candidates'; geometry_rejected 4428 'Clipboard Shelf — recording paused'

printf '%s\n' 'PASS: video crop, duration, appearance, preference-domain, app-stop, fixture-argument, and popover-geometry cases'
