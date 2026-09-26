#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
APP_KEY="${APP_KEY:?APP_KEY is required}"
RELEASE_TOKEN="${GH_TOKEN:?GH_TOKEN is required}"
export -n RELEASE_TOKEN
unset GH_TOKEN
HELPER="$ROOT/.github/scripts/render-readme-media.swift"

case "$APP_KEY" in
  clipboard-shelf)
    RELEASE_REPO='9phfr6dsw4-dotcom/clipboard-shelf'
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

STATUS_LABEL="$APP_NAME"

case "$APP_KEY" in
  clipboard-shelf) SLUG='clipboard-shelf' ;;
  quick-drop-zone) SLUG='quick-drop-zone' ;;
  echotype) SLUG='echotype' ;;
  captiongrab) SLUG='captiongrab' ;;
esac

status_item_snapshot() {
  osascript - "$WINDOW_OWNER" "$STATUS_LABEL" 2>/dev/null <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set statusLabel to item 2 of argv
  try
    tell application "System Events"
      tell process appName
        set statusItem to missing value
        set matches to 0
        try
          repeat with candidate in every menu bar item of menu bar 2
            set itemName to ""
            set itemDescription to ""
            try
              set itemName to name of candidate as text
            end try
            try
              set itemDescription to description of candidate as text
            end try
            if itemName contains appName or itemName contains statusLabel or itemDescription contains statusLabel then
              set statusItem to candidate
              set matches to matches + 1
            end if
          end repeat
        end try
        try
          repeat with candidate in every menu bar item of menu bar 1
            set itemName to ""
            set itemDescription to ""
            try
              set itemName to name of candidate as text
            end try
            try
              set itemDescription to description of candidate as text
            end try
            if itemName contains appName or itemName contains statusLabel or itemDescription contains statusLabel then
              set statusItem to candidate
              set matches to matches + 1
            end if
          end repeat
        end try
        if matches is not 1 then return ((matches as integer) as text) & "|0|0|0|0"
        set itemPosition to position of statusItem
        set itemSize to size of statusItem
        return "1|" & ((item 1 of itemPosition as integer) as text) & "|" & ((item 2 of itemPosition as integer) as text) & "|" & ((item 1 of itemSize as integer) as text) & "|" & ((item 2 of itemSize as integer) as text)
      end tell
    end tell
  on error
    return "-1|0|0|0|0"
  end try
end run
APPLESCRIPT
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
GEOMETRY_REJECTION_REASON='capture_failed_before_geometry_check'
python3 "$ROOT/.github/scripts/prepare-readme-media-artifacts.py" "$RUNNER_TEMP" "$ARTIFACT_DIR"
[[ ! -L "$DIAG_DIR" ]] || { printf 'Refusing symlinked diagnostic directory.\n' >&2; exit 1; }
mkdir -p "$DIAG_DIR"

write_geometry_snapshot() {
  local reason="${1:-diagnostic_collection_failed}" status_item display_info windows_path windows_tsv
  case "$reason" in
    status_item_click_failed|strict_ax_adjacency_predicate_failed_after_12_polls|capture_failed_before_geometry_check|capture_failed_after_geometry_check|diagnostic_collection_failed) ;;
    *) reason='diagnostic_collection_failed' ;;
  esac
  status_item='-1|0|0|0|0'
  if [[ "$APP_KEY" == clipboard-shelf ]]; then
    status_item="$(status_item_snapshot 2>/dev/null)" || status_item='-1|0|0|0|0'
  fi
  display_info="$(swift "$HELPER" display-geometry 2>/dev/null)" || display_info=''
  windows_path="$DIAG_DIR/app-windows.tsv"
  printf 'windowID\tPID\tlayer\talpha\tx\ty\twidth\theight\n' > "$windows_path"
  if [[ ! "$APP_PID" =~ ^[0-9]+$ && -n "${APP:-}" && -d "${APP:-}" ]]; then
    APP_PID="$(swift "$HELPER" pid "$APP" 2>/dev/null)" || APP_PID=''
  fi
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
  if (( status != 0 )) && [[ "$APP_KEY" == clipboard-shelf ]]; then
    set +e
    write_geometry_snapshot "$GEOMETRY_REJECTION_REASON"
  fi
  exit "$status"
}
trap capture_exit_diagnostics EXIT

for runner_child in "$EXTRACT_DIR" "$RUNNER_TEMP/release-download"; do
  [[ ! -L "$runner_child" ]] || { printf 'Refusing symlinked RUNNER_TEMP child: %s\n' "$runner_child" >&2; exit 1; }
done
mkdir -p "$EXTRACT_DIR" "$RUNNER_TEMP/release-download"
rm -f "$ROOT/docs/images/$SLUG-light.png" "$ROOT/docs/images/$SLUG-dark.png" "$ROOT/docs/images/$SLUG-hero.gif" "$ROOT/docs/images/social-preview.png"

printf '%s\n' '=== Display configuration ==='
system_profiler SPDisplaysDataType 2>&1 | tee "$ARTIFACT_DIR/display-info.txt"
swift "$HELPER" display-info | tee -a "$ARTIFACT_DIR/display-info.txt"
echo '=== Preparing a clean synthetic-demo desktop ==='
swift "$HELPER" wallpaper "$RUNNER_TEMP/readme-wallpaper.png"
osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$RUNNER_TEMP/readme-wallpaper.png\"" || printf '%s\n' 'Wallpaper AppleScript was unavailable.'
defaults write com.apple.finder CreateDesktop false || true
killall Finder >/dev/null 2>&1 || true
osascript -e 'tell application "Finder" to close every window' >/dev/null 2>&1 || true
osascript -e 'tell application "Terminal" to close every window' >/dev/null 2>&1 || true

printf 'Downloading latest published release from %s.\n' "$RELEASE_REPO"
mkdir -p "$RUNNER_TEMP/release-download"
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
  osascript - "$WINDOW_OWNER" "$STATUS_LABEL" <<'APPLESCRIPT' || { GEOMETRY_REJECTION_REASON='status_item_click_failed'; return 1; }
on run argv
  set appName to item 1 of argv
  set statusLabel to item 2 of argv
  tell application "System Events"
    tell process appName
      set frontmost to true
      set statusItem to missing value
      set matches to 0
      try
        repeat with candidate in every menu bar item of menu bar 2
          set itemName to ""
          set itemDescription to ""
          try
            set itemName to name of candidate as text
          end try
          try
            set itemDescription to description of candidate as text
          end try
          if itemName contains appName or itemName contains statusLabel or itemDescription contains statusLabel then
            set statusItem to candidate
            set matches to matches + 1
          end if
        end repeat
      end try
      if matches is 0 then
        try
          repeat with candidate in every menu bar item of menu bar 1
            set itemName to ""
            set itemDescription to ""
            try
              set itemName to name of candidate as text
            end try
            try
              set itemDescription to description of candidate as text
            end try
            if itemName contains appName or itemName contains statusLabel or itemDescription contains statusLabel then
              set statusItem to candidate
              set matches to matches + 1
            end if
          end repeat
        end try
      end if
      if matches is not 1 then error "Could not uniquely identify this app's menu-bar status item."
      click statusItem
    end tell
  end tell
end run
APPLESCRIPT
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
  osascript - "$WINDOW_OWNER" "$STATUS_LABEL" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set statusLabel to item 2 of argv
  tell application "System Events"
    tell process appName
      set statusItem to missing value
      set matches to 0
      try
        repeat with candidate in every menu bar item of menu bar 2
          set itemName to ""
          set itemDescription to ""
          try
            set itemName to name of candidate as text
          end try
          try
            set itemDescription to description of candidate as text
          end try
          if itemName contains appName or itemName contains statusLabel or itemDescription contains statusLabel then
            set statusItem to candidate
            set matches to matches + 1
          end if
        end repeat
      end try
      if matches is 0 then
        try
          repeat with candidate in every menu bar item of menu bar 1
            set itemName to ""
            set itemDescription to ""
            try
              set itemName to name of candidate as text
            end try
            try
              set itemDescription to description of candidate as text
            end try
            if itemName contains appName or itemName contains statusLabel or itemDescription contains statusLabel then
              set statusItem to candidate
              set matches to matches + 1
            end if
          end repeat
        end try
      end if
      if matches is not 1 then error "Could not uniquely identify this app's menu-bar status item."
      set statusPosition to position of statusItem
      set statusSize to size of statusItem
      set statusLeft to item 1 of statusPosition as integer
      set statusTop to item 2 of statusPosition as integer
      set statusRight to statusLeft + (item 1 of statusSize as integer)
      set statusBottom to statusTop + (item 2 of statusSize as integer)
      set matchingWindows to 0
      set windowPosition to {0, 0}
      set windowSize to {0, 0}
      repeat with candidateWindow in every window
        try
          if visible of candidateWindow then
            set candidatePosition to position of candidateWindow
            set candidateSize to size of candidateWindow
            set candidateLeft to item 1 of candidatePosition as integer
            set candidateTop to item 2 of candidatePosition as integer
            set candidateWidth to item 1 of candidateSize as integer
            set candidateHeight to item 2 of candidateSize as integer
            set verticalGap to candidateTop - statusBottom
            set overlapsStatusItem to (candidateLeft < statusRight + 80) and (candidateLeft + candidateWidth > statusLeft - 80)
            if overlapsStatusItem and verticalGap >= -8 and verticalGap <= 120 and candidateWidth >= 240 and candidateHeight >= 240 then
              set matchingWindows to matchingWindows + 1
              set windowPosition to candidatePosition
              set windowSize to candidateSize
            end if
          end if
        end try
      end repeat
      if matchingWindows is not 1 then error "Could not uniquely identify a visible popover adjacent to the app status item."
    end tell
  end tell
  set fields to {item 1 of windowPosition, item 2 of windowPosition, item 1 of windowSize, item 2 of windowSize, item 1 of statusPosition, item 2 of statusPosition, item 1 of statusSize, item 2 of statusSize, 0}
  set output to ""
  repeat with fieldValue in fields
    if output is not "" then set output to output & "|"
    set output to output & (((fieldValue as integer) as text))
  end repeat
  return output
end run
APPLESCRIPT
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
  [[ "$frame" =~ ^[0-9]{1,6}x[0-9]{1,6}$ && "$scale" =~ ^[0-9]{1,6}$ ]] || { printf 'Invalid native display geometry: %s\n' "$display_info" >&2; return 1; }
  screen_width="${frame%x*}"
  screen_height="${frame#*x}"
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
  test -s "$output"
}

prepare_clipboard_demo() {
  swift "$HELPER" seed-clipboard
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

source "$ROOT/.github/scripts/readme-media-runtime.sh"

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

case "$APP_KEY" in
  clipboard-shelf)
    prepare_clipboard_demo
    open "$APP"
    sleep 5
    set_appearance false
    show_menu_popover
    capture_menu_region "$ROOT/docs/images/clipboard-shelf-light.png"
    set_appearance true
    sleep 2
    show_menu_popover
    capture_menu_region "$ROOT/docs/images/clipboard-shelf-dark.png"
    set_appearance false
    show_menu_popover
    LAST_MENU_REGION="$(verified_menu_region)"
    capture_video_region "$LAST_MENU_REGION"
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

if [[ -s "$ROOT/docs/images/$SLUG-light.png" ]]; then
  swift "$HELPER" social "$ROOT/docs/images/social-preview.png" "$ICON" "$APP_NAME" "$TAGLINE" "$ROOT/docs/images/$SLUG-light.png"
  cp "$ROOT/docs/images/social-preview.png" "$ARTIFACT_DIR/social-preview.png"
else
  printf 'Social preview omitted because there is no qualifying real app screenshot.\n' | tee "$ARTIFACT_DIR/social-preview-status.txt"
fi
for image in "$ROOT/docs/images/$SLUG-light.png" "$ROOT/docs/images/$SLUG-dark.png" "$ROOT/docs/images/$SLUG-hero.gif" "$ROOT/docs/images/social-preview.png"; do
  [[ ! -e "$image" ]] || cp "$image" "$ARTIFACT_DIR/"
done
printf 'Capture candidates are in docs/images and artifacts in %s\n' "$ARTIFACT_DIR"
