#!/usr/bin/env bash
# macOS CI regression check for the Clipboard Shelf demo fixture. A probe bundle with the
# app's identifier is launched through LaunchServices with the same launch arguments the
# capture uses, and must read exactly the paused synthetic fixture. Withholding the
# arguments must leave it with no history (negative control), and the real user's
# preference domain must stay absent throughout: cfprefsd ignores HOME/CFFIXED_USER_HOME,
# so any preference write would land there.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HELPER="$ROOT/.github/scripts/render-readme-media.swift"
source "$ROOT/.github/scripts/readme-media-runtime.sh"
DOMAIN=local.clipboardshelf
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
[[ "$RUNNER_TEMP" == /* && -d "$RUNNER_TEMP" && ! -L "$RUNNER_TEMP" ]] || { printf 'RUNNER_TEMP must be an existing absolute directory.\n' >&2; exit 2; }

REAL_HOME="$(real_user_home)"
clipboard_domain_absent "$REAL_HOME" "$DOMAIN" || { printf 'Precondition failed: the real %s domain must be absent.\n' "$DOMAIN" >&2; exit 1; }

WORK="$(mktemp -d "$RUNNER_TEMP/clipboard-demo-isolation.XXXXXXXX")"
PROBE="$WORK/ClipboardShelfDefaultsProbe.app"
mkdir -p "$PROBE/Contents/MacOS"
cat > "$PROBE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.clipboardshelf</string>
  <key>CFBundleExecutable</key><string>ClipboardShelfDefaultsProbe</string>
  <key>CFBundleName</key><string>ClipboardShelfDefaultsProbe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
swiftc -O "$ROOT/.github/scripts/readme-media-defaults-probe.swift" -o "$PROBE/Contents/MacOS/ClipboardShelfDefaultsProbe"
codesign --force --sign - "$PROBE" >/dev/null

run_probe() {
  local report="$1" attempt
  shift
  rm -f "$report"
  open -n "$PROBE" --args "$report" "$@"
  for attempt in {1..20}; do
    [[ -s "$report" ]] && break
    sleep 0.5
  done
  [[ -s "$report" ]] || { printf 'The defaults probe produced no report.\n' >&2; return 1; }
  cat "$report"
}

expected="$(swift "$HELPER" clipboard-demo-summary)"
load_clipboard_demo_args
actual="$(run_probe "$WORK/with-fixture.txt" "${CLIPBOARD_DEMO_ARGS[@]}")"
if [[ "$actual" != "$expected" ]]; then
  printf 'Launched bundle did not read the exact paused synthetic fixture.\nexpected: %s\nactual:   %s\n' "$expected" "$actual" >&2
  exit 1
fi
printf 'Launched bundle read the exact paused synthetic fixture: %s\n' "$actual"

control="$(run_probe "$WORK/without-fixture.txt")"
if [[ "$control" != 'paused=false history=absent' ]]; then
  printf 'Negative control failed: without launch arguments the bundle read: %s\n' "$control" >&2
  exit 1
fi
printf 'Negative control: without launch arguments the bundle reads no fixture (%s).\n' "$control"

clipboard_domain_absent "$REAL_HOME" "$DOMAIN" || { printf 'Postcondition failed: fixture state reached the real %s domain.\n' "$DOMAIN" >&2; exit 1; }
printf 'The real %s preference domain stayed absent.\n' "$DOMAIN"
