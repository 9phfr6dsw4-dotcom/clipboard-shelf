#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
APP_KEY="${APP_KEY:?APP_KEY is required}"
RELEASE_TOKEN="${GH_TOKEN:?GH_TOKEN is required}"
export -n RELEASE_TOKEN
unset GH_TOKEN
HELPER="$ROOT/.github/scripts/render-readme-media.swift"
source "$ROOT/.github/scripts/readme-media-runtime.sh"
ORIGINAL_DARK_MODE=''

case "$APP_KEY" in
  clipboard-shelf)
    RELEASE_REPO='9phfr6dsw4-dotcom/clipboard-shelf'
    RELEASE_TAG='v1.0.2'
    RELEASE_ARCHIVE='Clipboard-Shelf-1.0.2.zip'
    RELEASE_SIDECAR='Clipboard-Shelf-1.0.2.zip.sha256'
    RELEASE_COMMIT='f25223855444d19e204016e27b8940afec806b20'
    APP_BUNDLE='Clipboard Shelf.app'; WINDOW_OWNER='ClipboardShelf'; APP_NAME='Clipboard Shelf'
    TAGLINE='A quiet macOS menu-bar clipboard history with search, pins, and a pause switch.'
    MENU_APP=1
    ;;
  quick-drop-zone)
    RELEASE_REPO='9phfr6dsw4-dotcom/quick-drop-zone'
    APP_BUNDLE='Quick Drop Zone.app'; WINDOW_OWNER='QuickDropZone'; APP_NAME='Quick Drop Zone'
    TAGLINE='A careful, local-first file organizer in the macOS menu bar.'
    MENU_APP=1
    ;;
  echotype)
    RELEASE_REPO='9phfr6dsw4-dotcom/echotype'
    APP_BUNDLE='EchoType.app'; WINDOW_OWNER='EchoType'; APP_NAME='EchoType'
    TAGLINE='Private, on-device dictation for macOS with Apple Speech, Parakeet v3, and Whisper.'
    MENU_APP=0
    ;;
  captiongrab)
    RELEASE_REPO='9phfr6dsw4-dotcom/captiongrab'
    APP_BUNDLE='CaptionGrab.app'; WINDOW_OWNER='CaptionGrab'; APP_NAME='CaptionGrab'
    TAGLINE='Get English YouTube captions and save them as Markdown or Word.'
    MENU_APP=0
    ;;
  *) printf 'Unknown APP_KEY: %s\n' "$APP_KEY" >&2; exit 2 ;;
esac
# The other APP_KEY paths below are shared with sibling repositories and do not meet this
# repository's isolation rules (for example, EchoType seeds files under the real home).
[[ "$APP_KEY" == clipboard-shelf ]] || { printf 'This repository captures only Clipboard Shelf; refusing APP_KEY=%s.\n' "$APP_KEY" >&2; exit 2; }

# Exact accessibility description of the launched app's status item. For Clipboard Shelf
# it also proves the app read the paused fixture: it reads "Clipboard Shelf" when recording.
case "$APP_KEY" in
  clipboard-shelf) STATUS_DESCRIPTION='Clipboard Shelf — recording paused' ;;
  *) STATUS_DESCRIPTION='' ;;
esac

case "$APP_KEY" in
  clipboard-shelf) SLUG='clipboard-shelf' ;;
  quick-drop-zone) SLUG='quick-drop-zone' ;;
  echotype) SLUG='echotype' ;;
  captiongrab) SLUG='captiongrab' ;;
esac

status_item_snapshot() {
  local frame
  [[ "$APP_PID" =~ ^[0-9]+$ && -n "$STATUS_DESCRIPTION" ]] || { printf '%s\n' '-1|0|0|0|0'; return 0; }
  if frame="$(osascript "$ROOT/.github/scripts/readme-media-status-item.applescript" frame "$APP_PID" "$STATUS_DESCRIPTION" 2>/dev/null)"; then
    printf '1|%s\n' "$frame"
  else
    printf '%s\n' '-1|0|0|0|0'
  fi
}

if [[ -L "$ROOT/docs" || -L "$ROOT/docs/images" ]]; then
  printf 'Refusing to clear README media through a symlinked docs path.\n' >&2
  exit 1
fi
mkdir -p "$ROOT/docs/images"
IMAGE_DIR_REAL="$(cd "$ROOT/docs/images" && pwd -P)"
[[ "$IMAGE_DIR_REAL" == "$ROOT/docs/images" ]] || { printf 'README media directory escaped the worktree.\n' >&2; exit 1; }
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
[[ "$RUNNER_TEMP" == /* ]] || { printf 'RUNNER_TEMP must be an absolute path.\n' >&2; exit 2; }
ARTIFACT_DIR="$RUNNER_TEMP/readme-media"
DIAG_DIR="$ARTIFACT_DIR/diagnostics"
EXTRACT_DIR="$RUNNER_TEMP/release-app"
APP_PID=''
CLIPBOARD_REAL_HOME=''
GEOMETRY_REJECTION_REASON='capture_failed_before_geometry_check'
python3 "$ROOT/.github/scripts/prepare-readme-media-artifacts.py" "$RUNNER_TEMP" "$ARTIFACT_DIR"
[[ ! -L "$DIAG_DIR" ]] || { printf 'Refusing symlinked diagnostic directory.\n' >&2; exit 1; }
mkdir -p "$DIAG_DIR"

write_geometry_snapshot() {
  local reason="${1:-diagnostic_collection_failed}" status_item display_info windows_path windows_tsv
  case "$reason" in
    status_item_click_failed|strict_ax_adjacency_predicate_failed_after_12_polls|capture_failed_before_geometry_check|capture_failed_after_geometry_check|capture_pixel_validation_failed|diagnostic_collection_failed) ;;
    *) reason='diagnostic_collection_failed' ;;
  esac
  if [[ ! "$APP_PID" =~ ^[0-9]+$ && -n "${APP:-}" && -d "${APP:-}" ]]; then
    APP_PID="$(swift "$HELPER" pid "$APP" 2>/dev/null)" || APP_PID=''
  fi
  status_item='-1|0|0|0|0'
  if [[ "$APP_KEY" == clipboard-shelf ]]; then
    status_item="$(status_item_snapshot 2>/dev/null)" || status_item='-1|0|0|0|0'
  fi
  display_info="$(swift "$HELPER" display-geometry 2>/dev/null)" || display_info=''
  windows_path="$DIAG_DIR/app-windows.tsv"
  printf 'windowID\tPID\tlayer\talpha\tx\ty\twidth\theight\n' > "$windows_path"
  if [[ "$APP_PID" =~ ^[0-9]+$ ]]; then
    if windows_tsv="$(swift "$HELPER" windows-pid "$APP_PID" 2>/dev/null)"; then
      printf '%s\n' "$windows_tsv" > "$windows_path"
    fi
  fi
  if ! python3 "$ROOT/.github/scripts/build_readme_media_geometry_snapshot.py" --reason "$reason" --app-pid "${APP_PID:-}" --status-item "$status_item" --windows "$windows_path" --display-info "$display_info" --output "$DIAG_DIR/geometry-snapshot.json" >/dev/null 2>&1; then
    printf '%s\n' '{"schema":"clipboard-shelf-capture-geometry/v1","app_pid":null,"status_item":{"match_count":-1,"frame":null},"app_owned_windows":[],"display":null,"rejection_reason":"diagnostic_collection_failed","collection_errors":["snapshot_write_failed"]}' > "$DIAG_DIR/geometry-snapshot.json"
  fi
}

capture_exit_diagnostics() {
  local status=$?
  trap - EXIT
  set +e
  # Order: diagnostics need the app alive; stopping it and checking the real domain must not
  # wait behind the appearance restore.
  if (( status != 0 )) && [[ "$APP_KEY" == clipboard-shelf ]]; then
    write_geometry_snapshot "$GEOMETRY_REJECTION_REASON"
  fi
  if [[ "$APP_KEY" == clipboard-shelf && -n "$CLIPBOARD_REAL_HOME" ]]; then
    # SIGKILL every instance of the extracted executable: a normal quit runs saveHistory.
    if ! stop_app_instances "$APP/Contents/MacOS/ClipboardShelf"; then
      printf 'Could not stop Clipboard Shelf; failing the capture.\n' >&2
      (( status != 0 )) || status=1
    fi
    if ! app_state_absent "$CLIPBOARD_REAL_HOME" local.clipboardshelf; then
      printf 'Clipboard Shelf state reached the real preference domain; failing the capture.\n' >&2
      (( status != 0 )) || status=1
    fi
  fi
  if ! restore_appearance; then
    printf 'Could not restore the runner appearance snapshot (dark=%s).\n' "$ORIGINAL_DARK_MODE" >&2
    (( status != 0 )) || status=1
  fi
  exit "$status"
}
trap capture_exit_diagnostics EXIT

for runner_child in "$EXTRACT_DIR" "$RUNNER_TEMP/release-download"; do
  [[ ! -L "$runner_child" ]] || { printf 'Refusing symlinked RUNNER_TEMP child: %s\n' "$runner_child" >&2; exit 1; }
done
mkdir -p "$EXTRACT_DIR" "$RUNNER_TEMP/release-download"

printf '%s\n' '=== Display geometry ==='
swift "$HELPER" display-info | tee "$ARTIFACT_DIR/display-info.txt"

if [[ "$APP_KEY" != clipboard-shelf ]]; then
  rm -f "$ROOT/docs/images/$SLUG-light.png" "$ROOT/docs/images/$SLUG-dark.png" "$ROOT/docs/images/$SLUG-hero.gif" "$ROOT/docs/images/social-preview.png"
fi

if [[ "$APP_KEY" == clipboard-shelf ]]; then
  printf 'Verifying pinned published release %s from %s.\n' "$RELEASE_TAG" "$RELEASE_REPO"
  release_metadata="$(GH_TOKEN="$RELEASE_TOKEN" gh release view "$RELEASE_TAG" --repo "$RELEASE_REPO" --json tagName,isDraft,isPrerelease)"
  python3 -c 'import json,sys; m=json.loads(sys.argv[1]); sys.exit(0 if m.get("tagName")=="v1.0.2" and not m.get("isDraft") and not m.get("isPrerelease") else 1)' "$release_metadata"
  release_commit="$(GH_TOKEN="$RELEASE_TOKEN" gh api "repos/$RELEASE_REPO/git/ref/tags/$RELEASE_TAG" --jq '.object.sha')"
  [[ "$release_commit" == "$RELEASE_COMMIT" ]] || { printf 'Pinned release tag commit mismatch.\n' >&2; exit 1; }
  GH_TOKEN="$RELEASE_TOKEN" gh release download "$RELEASE_TAG" --repo "$RELEASE_REPO" \
    --pattern "$RELEASE_ARCHIVE" --pattern "$RELEASE_SIDECAR" --dir "$RUNNER_TEMP/release-download"
  unset RELEASE_TOKEN GH_TOKEN
  ZIP_PATH="$RUNNER_TEMP/release-download/$RELEASE_ARCHIVE"
  SIDECAR_PATH="$RUNNER_TEMP/release-download/$RELEASE_SIDECAR"
  python3 "$ROOT/.github/scripts/validate_readme_media_release.py" "$ZIP_PATH" "$SIDECAR_PATH"
else
  printf 'Downloading latest published release from %s.\n' "$RELEASE_REPO"
  GH_TOKEN="$RELEASE_TOKEN" gh release download --repo "$RELEASE_REPO" --pattern '*.zip' --dir "$RUNNER_TEMP/release-download"
  unset RELEASE_TOKEN GH_TOKEN
  ZIP_PATH="$(python3 - "$RUNNER_TEMP/release-download" <<'PY'
from pathlib import Path
import sys
files = sorted(Path(sys.argv[1]).glob('*.zip'))
if len(files) != 1:
    raise SystemExit(f'Expected one ZIP asset from the latest release; found {len(files)}')
print(files[0])
PY
)"
fi

ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"
APP="$EXTRACT_DIR/$APP_BUNDLE"
test -d "$APP"
xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1 || true
ICON="$ROOT/docs/images/$SLUG-icon.png"
test -s "$ICON"

show_menu_popover() {
  if menu_geometry >/dev/null 2>&1; then
    GEOMETRY_REJECTION_REASON='capture_failed_after_geometry_check'
    return 0
  fi
  if [[ ! "$APP_PID" =~ ^[0-9]+$ || -z "$STATUS_DESCRIPTION" ]] \
    || ! osascript "$ROOT/.github/scripts/readme-media-status-item.applescript" click "$APP_PID" "$STATUS_DESCRIPTION" >/dev/null; then
    GEOMETRY_REJECTION_REASON='status_item_click_failed'
    return 1
  fi
  local attempt
  for attempt in {1..12}; do
    if menu_geometry >/dev/null 2>&1; then
      GEOMETRY_REJECTION_REASON='capture_failed_after_geometry_check'
      return 0
    fi
    sleep 0.25
  done
  GEOMETRY_REJECTION_REASON='strict_ax_adjacency_predicate_failed_after_12_polls'
  printf 'Strict app-window adjacency check did not identify a unique popover after 12 polls.\n' >&2
  return 1
}

menu_geometry() {
  status_popover_geometry "$APP_PID" "$STATUS_DESCRIPTION"
}

window_info() {
  swift "$HELPER" window "$WINDOW_OWNER"
}

capture_app_window() {
  local output="$1"
  local info id x y width height scale
  rm -f "$output"
  info="$(window_info)"
  IFS='|' read -r id x y width height scale <<< "$info"
  [[ "$id" =~ ^[0-9]+$ && "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]]
  (( width >= 500 && height >= 400 ))
  printf 'Window %s bounds: id=%s x=%s y=%s width=%s height=%s backing-scale=%s\n' "$WINDOW_OWNER" "$id" "$x" "$y" "$width" "$height" "$scale"
  screencapture -x -l "$id" "$output"
  test -s "$output"
}

fit_app_window() {
  local max_width="$1" max_height="$2" info frame screen_width screen_height width height
  info="$(swift "$HELPER" display-info)"
  IFS='|' read -r frame _ _ <<< "$info"
  frame="${frame#frame=}"
  screen_width="${frame%x*}"
  screen_height="${frame#*x}"
  [[ "$screen_width" =~ ^[0-9]+$ && "$screen_height" =~ ^[0-9]+$ ]] || return 1
  width=$(( screen_width - 80 ))
  height=$(( screen_height - 100 ))
  (( width > max_width )) && width="$max_width"
  (( height > max_height )) && height="$max_height"
  (( width >= 680 && height >= 520 )) || return 1
  osascript - "$WINDOW_OWNER" "$width" "$height" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set windowWidth to item 2 of argv as integer
  set windowHeight to item 3 of argv as integer
  tell application "System Events"
    tell process appName
      set frontmost to true
      set size of window 1 to {windowWidth, windowHeight}
      set position of window 1 to {40, 40}
    end tell
  end tell
end run
APPLESCRIPT
  printf 'Fitted %s to %sx%s within a %sx%s display.\n' "$WINDOW_OWNER" "$width" "$height" "$screen_width" "$screen_height"
}

verified_menu_region() {
  local info display_info frame pixels scale screen_width screen_height
  local pop_x pop_y pop_w pop_h icon_x icon_y icon_w icon_h fallback_used value region
  if ! info="$(menu_geometry)"; then
    printf 'Could not read menu-bar and popover bounds for %s.\n' "$WINDOW_OWNER" >&2
    return 1
  fi
  IFS='|' read -r pop_x pop_y pop_w pop_h icon_x icon_y icon_w icon_h fallback_used <<< "$info"
  [[ "$fallback_used" == 0 ]] || { printf 'Popover bounds were not exposed for %s; refusing guessed geometry.\n' "$WINDOW_OWNER" >&2; return 1; }
  for value in "$pop_x" "$pop_y" "$pop_w" "$pop_h" "$icon_x" "$icon_y" "$icon_w" "$icon_h"; do
    [[ "$value" =~ ^[0-9]{1,6}$ ]] || { printf 'Invalid menu-bar geometry for %s: %s\n' "$WINDOW_OWNER" "$info" >&2; return 1; }
  done
  if ! display_info="$(swift "$HELPER" display-info)"; then
    printf 'Could not read native display geometry.\n' >&2
    return 1
  fi
  IFS='|' read -r frame pixels scale <<< "$display_info"
  frame="${frame#frame=}"
  scale="${scale#scale=}"
  [[ "$frame" =~ ^[0-9]{1,6}x[0-9]{1,6}$ && "$scale" =~ ^[0-9]{1,6}$ ]] || { printf 'Invalid native display geometry.\n' >&2; return 1; }
  screen_width="${frame%x*}"
  screen_height="${frame#*x}"
  if ! python3 "$ROOT/.github/scripts/validate_readme_media_capture.py" geometry \
    --status "$icon_x" "$icon_y" "$icon_w" "$icon_h" \
    --popover "$pop_x" "$pop_y" "$pop_w" "$pop_h" \
    --display "$screen_width" "$screen_height" >/dev/null; then
    printf 'Measured app-popover geometry failed independent strict validation.\n' >&2
    return 1
  fi
  if ! region="$(menu_region_from_geometry "$pop_x" "$pop_y" "$pop_w" "$pop_h" "$icon_x" "$icon_y" "$icon_w" "$icon_h" "$screen_width" "$screen_height" "$scale")"; then
    printf 'Popover/status-item bounds are absent, invalid, off-screen, or too small; refusing capture.\n' >&2
    return 1
  fi
  printf 'Verified status item %s,%s %sx%s; popover %s,%s %sx%s; display %sx%s @%sx; region %s\n'  "$icon_x" "$icon_y" "$icon_w" "$icon_h" "$pop_x" "$pop_y" "$pop_w" "$pop_h"  "$screen_width" "$screen_height" "$scale" "$region" >&2
  printf '%s\n' "$region"
}

capture_menu_region() {
  local output="$1" stem left top width height scale
  stem="${output##*/}"
  stem="${stem%.png}"
  rm -f "$output"
  if ! LAST_MENU_REGION="$(verified_menu_region 2>"$ARTIFACT_DIR/$stem-menu-geometry-error.txt")"; then
    printf 'Could not verify menu capture geometry for %s; capture failed.\n' "$WINDOW_OWNER" | tee "$ARTIFACT_DIR/$stem-capture-status.txt" >&2
    return 1
  fi
  IFS=',' read -r left top width height scale <<< "$LAST_MENU_REGION"
  printf 'Capturing verified region %s,%s,%s,%s at %sx.\n' "$left" "$top" "$width" "$height" "$scale"
  screencapture -x -R "$left,$top,$width,$height" "$output"
  if ! python3 "$ROOT/.github/scripts/validate_readme_media_capture.py" png "$output" \
    --expected "$((width * scale))" "$((height * scale))"; then
    GEOMETRY_REJECTION_REASON='capture_pixel_validation_failed'
    return 1
  fi
}

# The synthetic history reaches the app only as NSArgumentDomain launch arguments, which
# are never persisted; macos-ci.yml proves a same-identifier bundle reads exactly this
# fixture that way. Refuse to run if the real domain already exists so real history is
# never read, captured, or overwritten.
prepare_clipboard_demo() {
  local real_home
  real_home="$(real_user_home)" || return 1
  clipboard_domain_absent "$real_home" local.clipboardshelf || {
    printf 'Refusing to launch: the real Clipboard Shelf preference domain already exists.\n' >&2
    return 1
  }
  # Arms the EXIT-trap postcondition only once the domain is known to be absent.
  CLIPBOARD_REAL_HOME="$real_home"
  load_clipboard_demo_args
}

DEMO_DOWNLOADS=''

prepare_quick_drop_demo() {
  DEMO_DOWNLOADS="$(python3 "$ROOT/.github/scripts/prepare-readme-media-demo.py" "$RUNNER_TEMP" "$RUNNER_TEMP/readme-wallpaper.png")"
  [[ "$DEMO_DOWNLOADS" == "$RUNNER_TEMP"/readme-demo-*/Downloads && -d "$DEMO_DOWNLOADS" && ! -L "$DEMO_DOWNLOADS" ]] || {
    printf 'Demo fixtures escaped RUNNER_TEMP or are unavailable.\n' >&2
    return 1
  }
}

launch_app() {
  if [[ "$APP_KEY" == quick-drop-zone ]]; then
    [[ -n "$DEMO_DOWNLOADS" ]] || { printf 'Quick Drop demo fixtures are not prepared.\n' >&2; return 1; }
    open --env "HOME=${DEMO_DOWNLOADS%/Downloads}" "$APP"
  else
    open "$APP"
  fi
}

open_cleanup_review() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "QuickDropZone"
    set frontmost to true
    set reviewOpen to false
    try
      set reviewOpen to (exists button "Approve & Move" of window 1)
    on error
      set reviewOpen to false
    end try
    if not reviewOpen then
      try
        click button "Clean up…" of window 1
      on error
        click button "Clean up..." of window 1
      end try
    end if
    delay 2
    if not (exists button "Approve & Move" of window 1) then error "Cleanup review did not open."
    set sawAtlas to false
    repeat with itemText in every static text of window 1
      try
        if (value of itemText as text) contains "Atlas-" then set sawAtlas to true
      end try
    end repeat
    if not sawAtlas then error "Synthetic Atlas demo files are not visible in Cleanup review."
    set groupToggles to every checkbox of window 1 whose name contains "Include group"
    if (count of groupToggles) is not 1 then error "Expected exactly one Atlas Include group checkbox."
    set groupToggle to item 1 of groupToggles
    if (value of groupToggle as text) is not "1" then click groupToggle
    delay 1
    if (value of groupToggle as text) is not "1" then error "Atlas group selection did not register."
  end tell
end tell
APPLESCRIPT
}

caption_transcript_loaded() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "CaptionGrab"
    set foundTranscriptURL to false
    repeat with itemText in every static text of window 1
      try
        if (value of itemText as text) starts with "YouTube Video url:" then set foundTranscriptURL to true
      end try
    end repeat
    if not foundTranscriptURL then error "No transcript-only video URL is visible."
  end tell
end tell
APPLESCRIPT
}

# Snapshot before any appearance change; the EXIT trap restores it on every path.
ORIGINAL_DARK_MODE="$(get_appearance)"

case "$APP_KEY" in
  clipboard-shelf)
    prepare_clipboard_demo
    open -n "$APP" --args "${CLIPBOARD_DEMO_ARGS[@]}"
    sleep 5
    APP_PID="$(swift "$HELPER" pid "$APP")"
    set_appearance false
    show_menu_popover
    capture_menu_region "$ARTIFACT_DIR/clipboard-shelf-light.png"
    set_appearance true
    sleep 2
    show_menu_popover
    capture_menu_region "$ARTIFACT_DIR/clipboard-shelf-dark.png"
    ;;
  quick-drop-zone)
    prepare_quick_drop_demo
    launch_app
    sleep 5
    set_appearance false
    show_menu_popover
    open_cleanup_review
    capture_menu_region "$ROOT/docs/images/quick-drop-zone-light.png"
    set_appearance true
    sleep 2
    capture_menu_region "$ROOT/docs/images/quick-drop-zone-dark.png"
    set_appearance false
    show_menu_popover
    open_cleanup_review
    capture_video_region "$LAST_MENU_REGION"
    ;;
  echotype)
    swift "$HELPER" seed-echotype
    defaults write com.echotype.app EchoType.hasSeenLaunchAtLoginOption -bool true
    open "$APP"
    sleep 8
    fit_app_window 1100 950
    set_appearance false
    capture_app_window "$ROOT/docs/images/echotype-light.png"
    osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "EchoType"
    click radio button "Speech Models" of tab group 1 of window 1
  end tell
end tell
APPLESCRIPT
    sleep 3
    capture_app_window "$ROOT/docs/images/echotype-model-library-light.png"
    set_appearance true
    osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "EchoType"
    click radio button "Home" of tab group 1 of window 1
  end tell
end tell
APPLESCRIPT
    sleep 2
    capture_app_window "$ROOT/docs/images/echotype-dark.png"
    set_appearance false
    ;;
  captiongrab)
    open "$APP"
    sleep 6
    fit_app_window 1100 950
    if [[ "${ALLOW_LIVE_YOUTUBE_FETCH:-false}" != "true" ]]; then
      printf '%s\n' 'YouTube was already tried once and returned no transcript; not repeating the live request. No CaptionGrab screenshots or social preview will be emitted.' | tee "$ARTIFACT_DIR/captiongrab-live-fetch-status.txt"
    else
      osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "CaptionGrab"
    set frontmost to true
    set value of text field 1 of window 1 to "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
    click button "Get transcript" of window 1
  end tell
end tell
APPLESCRIPT
      sleep 18
      if caption_transcript_loaded; then
        set_appearance false
        capture_app_window "$ROOT/docs/images/captiongrab-light.png"
        set_appearance true
        capture_app_window "$ROOT/docs/images/captiongrab-dark.png"
        set_appearance false
      else
        printf '%s\n' 'Live fetch produced no transcript-only URL; empty-state image and social preview omitted.' | tee "$ARTIFACT_DIR/captiongrab-live-fetch-status.txt"
      fi
    fi
    ;;
esac

if [[ "$APP_KEY" != clipboard-shelf && -s "$ROOT/docs/images/$SLUG-light.png" ]]; then
  swift "$HELPER" social "$ARTIFACT_DIR/social-preview.png" "$ICON" "$APP_NAME" "$TAGLINE" "$ROOT/docs/images/$SLUG-light.png"
  printf '%s\n' 'Social preview generated from the real app screenshot.' | tee "$ARTIFACT_DIR/social-preview-status.txt"
elif [[ "$APP_KEY" == clipboard-shelf ]]; then
  printf '%s\n' 'Social preview omitted; Clipboard Shelf media is limited to uncomposited app captures.' | tee "$ARTIFACT_DIR/social-preview-status.txt"
else
  printf 'Social preview omitted because there is no qualifying real app screenshot.\n' | tee "$ARTIFACT_DIR/social-preview-status.txt"
fi
if [[ "$APP_KEY" != clipboard-shelf ]]; then
  for image in "$ROOT/docs/images/$SLUG-light.png" "$ROOT/docs/images/$SLUG-dark.png" "$ROOT/docs/images/$SLUG-hero.gif"; do
    [[ ! -e "$image" ]] || cp "$image" "$ARTIFACT_DIR/"
  done
fi
printf 'Capture candidates and diagnostics are confined to %s\n' "$ARTIFACT_DIR"
