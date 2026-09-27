#!/usr/bin/env bash
set -euo pipefail
README_MEDIA_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

set_appearance() {
  local requested="${1:-}" expected actual
  case "$requested" in
    true) expected=dark ;;
    false) expected=light ;;
    *) printf 'Appearance must be true or false; got: %s\n' "$requested" >&2; return 2 ;;
  esac

  if ! actual="$(osascript - "$requested" <<'APPLESCRIPT'
on run argv
  set requestedMode to item 1 of argv
  if requestedMode is "true" then
    set expectedDarkMode to true
  else if requestedMode is "false" then
    set expectedDarkMode to false
  else
    error "Invalid requested appearance mode."
  end if
  tell application "System Events"
    tell appearance preferences
      set dark mode to expectedDarkMode
      delay 2
      if dark mode is not expectedDarkMode then error "Appearance preference did not take effect."
      if dark mode then
        return "dark"
      else
        return "light"
      end if
    end tell
  end tell
end run
APPLESCRIPT
)"; then
    printf 'Could not set and verify appearance dark=%s.\n' "$requested" >&2
    return 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    printf 'Appearance verification failed: requested=%s actual=%s.\n' "$expected" "$actual" >&2
    return 1
  fi
}

get_appearance() {
  local actual
  actual="$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')" || return 1
  case "$actual" in
    true|false) printf '%s\n' "$actual" ;;
    *) printf 'Unreadable appearance state: %s\n' "$actual" >&2; return 1 ;;
  esac
}

# Restores the appearance snapshotted in ORIGINAL_DARK_MODE; a no-op when nothing was snapshotted.
restore_appearance() {
  [[ -n "${ORIGINAL_DARK_MODE:-}" ]] || return 0
  case "$ORIGINAL_DARK_MODE" in
    true|false) set_appearance "$ORIGINAL_DARK_MODE" ;;
    *) printf 'Refusing to restore a corrupted appearance snapshot.\n' >&2; return 1 ;;
  esac
}

# The account's real home from directory services; HOME can be overridden and cfprefsd ignores it.
real_user_home() {
  local home
  home="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '$1 == "NFSHomeDirectory:" { print $2 }')" || return 1
  [[ "$home" == /* && -d "$home" ]] || { printf 'Could not resolve the real user home.\n' >&2; return 1; }
  printf '%s\n' "$home"
}

# Prints the key names (never values) cfprefsd holds for a domain, one per line. Only the
# explicit "does not exist" answer counts as an empty domain; any other failure fails closed.
preference_domain_keys() {
  local domain="${1:-}" error
  [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 2
  if ! error="$(defaults read "$domain" 2>&1 >/dev/null)"; then
    [[ "$error" == *"Domain $domain does not exist"* ]] && return 0
    printf 'Could not read the %s preference domain.\n' "$domain" >&2
    return 1
  fi
  defaults export "$domain" - | plist_key_names -
}

# Prints the top-level key names of a property list file (or - for stdin), one per line.
plist_key_names() {
  python3 -c '
import plistlib, sys
source = sys.stdin.buffer if sys.argv[1] == "-" else open(sys.argv[1], "rb")
data = plistlib.loads(source.read())
if not isinstance(data, dict) or any(not isinstance(k, str) or not k.isprintable() for k in data):
    sys.exit("unexpected property list shape")
print("\n".join(sorted(data)))
' "$1" | sed '/^$/d'
}

# Strict precondition: the real user's preference domain has no plist (plain, ByHost, or
# dangling symlink) and cfprefsd holds no values for it.
clipboard_domain_absent() {
  local real_home="${1:-}" domain="${2:-}" plist keys
  [[ "$real_home" == /* && "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 2
  plist="$real_home/Library/Preferences/$domain.plist"
  if [[ -e "$plist" || -L "$plist" ]] || compgen -G "$real_home/Library/Preferences/ByHost/$domain.*.plist" >/dev/null; then
    printf 'A real preference file exists for %s.\n' "$domain" >&2
    return 1
  fi
  keys="$(preference_domain_keys "$domain")" || return 1
  if [[ -n "$keys" ]]; then
    printf 'The real preference domain %s holds values.\n' "$domain" >&2
    return 1
  fi
}

# Postcondition after the app ran: the real domain may hold only AppKit's own status-item
# bookkeeping keys (which any menu-bar app launch can create), never app state. Key names
# are logged; values never are.
APPKIT_STATUS_ITEM_KEY='^NSStatusItem (Preferred Position|Visible|VisibleCC) [A-Za-z0-9_-]+$'
app_state_absent() {
  local real_home="${1:-}" domain="${2:-}" plist keys file file_keys unexpected appkit
  [[ "$real_home" == /* && "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 2
  plist="$real_home/Library/Preferences/$domain.plist"
  [[ ! -L "$plist" ]] || { printf 'The real %s preference file is a symlink.\n' "$domain" >&2; return 1; }
  keys="$(preference_domain_keys "$domain")" || return 1
  for file in "$plist" "$real_home/Library/Preferences/ByHost/$domain".*.plist; do
    [[ -e "$file" || -L "$file" ]] || continue
    [[ -f "$file" && ! -L "$file" ]] || { printf 'Unexpected preference file type for %s.\n' "$domain" >&2; return 1; }
    file_keys="$(plist_key_names "$file")" || { printf 'Unreadable preference file for %s.\n' "$domain" >&2; return 1; }
    keys="$keys"$'\n'"$file_keys"
  done
  unexpected="$(printf '%s\n' "$keys" | sed '/^$/d' | grep -Ev "$APPKIT_STATUS_ITEM_KEY" | sort -u | paste -sd, -)" || true
  appkit="$(printf '%s\n' "$keys" | grep -E "$APPKIT_STATUS_ITEM_KEY" | sort -u | paste -sd, -)" || true
  [[ -z "$appkit" ]] || printf 'AppKit status-item keys in the real %s domain (names only): %s\n' "$domain" "$appkit" >&2
  if [[ -n "$unexpected" ]]; then
    printf 'App state reached the real %s domain (key names only): %s\n' "$domain" "$unexpected" >&2
    return 1
  fi
}

# SIGKILLs every process whose command line starts with the exact executable path (a normal
# quit would let the app save state), then fails if any instance survives.
stop_app_instances() {
  local executable="${1:-}" pattern attempt
  [[ "$executable" == /* ]] || return 2
  pattern="^$(printf '%s' "$executable" | sed 's/[][\.*^$+?(){}|]/\\&/g')( |\$)"
  pkill -KILL -f -- "$pattern" 2>/dev/null
  for attempt in {1..20}; do
    pgrep -f -- "$pattern" >/dev/null 2>&1 || return 0
    sleep 0.25
  done
  printf 'An instance of %s survived SIGKILL.\n' "$executable" >&2
  return 1
}

# Loads the synthetic Clipboard Shelf fixture as NSArgumentDomain launch arguments into
# CLIPBOARD_DEMO_ARGS. Launch arguments are never persisted, unlike any CFPreferences write.
load_clipboard_demo_args() {
  local output line data_literal='^<[0-9a-f]+>$'
  CLIPBOARD_DEMO_ARGS=()
  output="$(swift "$HELPER" clipboard-demo-args)" || return 1
  while IFS= read -r line; do CLIPBOARD_DEMO_ARGS+=("$line"); done <<< "$output"
  if (( ${#CLIPBOARD_DEMO_ARGS[@]} != 4 )) \
    || [[ "${CLIPBOARD_DEMO_ARGS[0]}" != -ClipboardShelfHistoryV1 ]] \
    || [[ ! "${CLIPBOARD_DEMO_ARGS[1]}" =~ $data_literal ]] \
    || [[ "${CLIPBOARD_DEMO_ARGS[2]}" != -ClipboardShelfRecordingPausedV1 ]] \
    || [[ "${CLIPBOARD_DEMO_ARGS[3]}" != YES ]]; then
    CLIPBOARD_DEMO_ARGS=()
    printf 'Synthetic fixture arguments are malformed.\n' >&2
    return 1
  fi
}

# Prints pop_x|pop_y|pop_w|pop_h|status_x|status_y|status_w|status_h|0 for the popover of
# the launched PID. The status item is matched by PID and exact accessibility description;
# the popover comes from that PID's complete CGWindowList inventory, because System Events
# exposes no NSPopover windows. Absent, malformed, or ambiguous data fails closed.
status_popover_geometry() {
  local pid="${1:-}" description="${2:-}" status inventory display_info frame popover
  local status_x status_y status_w status_h
  local frame_re='^[0-9]{1,6}[|][0-9]{1,6}[|][0-9]{1,6}[|][0-9]{1,6}$'
  [[ "$pid" =~ ^[0-9]+$ && -n "$description" ]] || return 1
  status="$(osascript "$README_MEDIA_SCRIPTS/readme-media-status-item.applescript" frame "$pid" "$description")" || return 1
  [[ "$status" =~ $frame_re ]] || return 1
  IFS='|' read -r status_x status_y status_w status_h <<< "$status"
  inventory="$(swift "$HELPER" windows-pid "$pid")" || return 1
  display_info="$(swift "$HELPER" display-info)" || return 1
  frame="${display_info%%|*}"
  frame="${frame#frame=}"
  [[ "$frame" =~ ^[0-9]{1,6}x[0-9]{1,6}$ ]] || return 1
  popover="$(printf '%s\n' "$inventory" | python3 "$README_MEDIA_SCRIPTS/validate_readme_media_capture.py" select-popover \
    --pid "$pid" --status "$status_x" "$status_y" "$status_w" "$status_h" --display "${frame%x*}" "${frame#*x}")" || return 1
  [[ "$popover" =~ $frame_re ]] || return 1
  printf '%s|%s|0\n' "$popover" "$status"
}

duration_is_acceptable() {
  local duration="${1:-}"
  [[ "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  awk -v value="$duration" 'BEGIN { exit !(value >= 6 && value <= 12) }'
}

menu_region_from_geometry() {
  (( $# == 11 )) || return 1
  local pop_x="$1" pop_y="$2" pop_w="$3" pop_h="$4"
  local icon_x="$5" icon_y="$6" icon_w="$7" icon_h="$8"
  local screen_width="$9" screen_height="${10}" scale="${11}"
  local value left right bottom region_width

  for value in "$pop_x" "$pop_y" "$pop_w" "$pop_h" "$icon_x" "$icon_y" "$icon_w" "$icon_h" "$screen_width" "$screen_height" "$scale"; do
    [[ "$value" =~ ^[0-9]{1,6}$ ]] || return 1
  done
  (( pop_w >= 240 && pop_h >= 240 && icon_w > 0 && icon_h > 0 )) || return 1
  (( screen_width >= 240 && screen_height >= 240 && scale >= 1 && scale <= 8 )) || return 1
  (( pop_x + pop_w <= screen_width && pop_y + pop_h <= screen_height )) || return 1
  (( icon_x + icon_w <= screen_width && icon_y + icon_h <= screen_height )) || return 1

  left=$(( pop_x < icon_x ? pop_x : icon_x ))
  left=$(( left > 24 ? left - 24 : 0 ))
  right=$(( pop_x + pop_w > icon_x + icon_w ? pop_x + pop_w : icon_x + icon_w ))
  bottom=$(( pop_y + pop_h > icon_y + icon_h ? pop_y + pop_h : icon_y + icon_h ))
  right=$(( right + 24 < screen_width ? right + 24 : screen_width ))
  bottom=$(( bottom + 20 < screen_height ? bottom + 20 : screen_height ))
  region_width=$(( right - left ))
  (( region_width >= pop_w && bottom >= pop_h && region_width >= 240 && bottom >= 240 )) || return 1
  printf '%s,0,%s,%s,%s\n' "$left" "$region_width" "$bottom" "$scale"
}

video_region_filter() {
  local input="$1" x="$2" y="$3" width="$4" height="$5" scale="$6"
  local dimensions raw_width raw_height expected_width expected_height crop_x crop_y
  for value in "$x" "$y" "$width" "$height" "$scale"; do
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
  done
  (( width > 0 && height > 0 && scale > 0 )) || return 1
  dimensions="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$input" 2>/dev/null)" || return 1
  [[ "$dimensions" =~ ^[0-9]+x[0-9]+$ ]] || return 1
  raw_width="${dimensions%x*}"
  raw_height="${dimensions#*x}"
  expected_width=$(( width * scale ))
  expected_height=$(( height * scale ))
  if (( raw_width == expected_width && raw_height == expected_height )); then
    printf '%s\n' 'null'
    return 0
  fi
  crop_x=$(( x * scale ))
  crop_y=$(( y * scale ))
  if (( raw_width >= expected_width && raw_height >= expected_height && crop_x + expected_width <= raw_width && crop_y + expected_height <= raw_height )); then
    printf 'crop=%s:%s:%s:%s\n' "$expected_width" "$expected_height" "$crop_x" "$crop_y"
    return 0
  fi
  return 1
}

animate_app() {
  case "$APP_KEY" in
    quick-drop-zone)
      show_menu_popover
      open_cleanup_review
      osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "QuickDropZone"
    set frontmost to true
    click button "Approve & Move" of window 1
    delay 0.75
    set moved to false
    try
      click button "Move Selected Files" of window 1
      set moved to true
    on error
      try
        click button "Move Selected Files" of sheet 1 of window 1
        set moved to true
      end try
    end try
    if not moved then error "The explicit Move Selected Files confirmation did not appear."
    delay 1.5
    click button "Back" of window 1
    delay 0.5
    if not (exists button "Undo Last Move" of window 1) then error "Undo did not appear after the synthetic move."
    click button "Undo Last Move" of window 1
    delay 1
    if exists button "Undo Last Move" of window 1 then error "Undo did not complete."
  end tell
end tell
APPLESCRIPT
      for demo_file in \
        "${DEMO_DOWNLOADS}/Atlas-project-brief.pdf" \
        "${DEMO_DOWNLOADS}/Atlas-review-notes.md" \
        "${DEMO_DOWNLOADS}/Atlas-timeline.xlsx" \
        "${DEMO_DOWNLOADS}/Atlas-copy-draft.docx"; do
        [[ -f "$demo_file" ]] || { printf 'Undo failed to restore synthetic demo file: %s\n' "$demo_file" >&2; return 1; }
      done
      show_menu_popover
      ;;
    *)
      printf 'No animation routine for APP_KEY=%s\n' "$APP_KEY" >&2
      return 1
      ;;
  esac
}

capture_video_region() {
  local rect="$1" x y width height scale
  IFS=',' read -r x y width height scale <<< "$rect"
  for value in "$x" "$y" "$width" "$height" "$scale"; do
    [[ "$value" =~ ^[0-9]+$ ]] || { printf 'Invalid video region: %s\n' "$rect" >&2; return 1; }
  done
  (( width > 0 && height > 0 && scale > 0 )) || { printf 'Invalid video region size: %s\n' "$rect" >&2; return 1; }

  local raw="$RUNNER_TEMP/readme-capture.mov"
  local mp4="$ARTIFACT_DIR/$SLUG-hero.mp4"
  local gif="$ARTIFACT_DIR/$SLUG-hero.gif"
  local capture_log="$ARTIFACT_DIR/video-capture.log"
  local crop_filter=''
  rm -f "$raw" "$mp4" "$gif"
  : > "$capture_log"

  printf '%s\n' 'Trying macOS screencapture video mode for the verified menu-bar region.'
  screencapture -v -V 7 -R "$x,$y,$width,$height" -x "$raw" >"$capture_log" 2>&1 &
  local capture_pid=$!
  sleep 1
  if ! animate_app; then
    kill "$capture_pid" 2>/dev/null || true
    wait "$capture_pid" 2>/dev/null || true
    return 1
  fi
  wait "$capture_pid" || printf '%s\n' 'screencapture video mode did not finish cleanly; validating its output before fallback.'
  if [[ -s "$raw" ]]; then
    crop_filter="$(video_region_filter "$raw" "$x" "$y" "$width" "$height" "$scale")" || crop_filter=''
  fi
  if [[ -z "$crop_filter" ]]; then
    rm -f "$raw"
    if ! command -v ffmpeg >/dev/null 2>&1; then brew install ffmpeg; fi
    local screen_index="${AVFOUNDATION_SCREEN_INDEX:-0}"
    printf 'Trying AVFoundation screen device %s for the same region.\n' "$screen_index"
    ffmpeg -y -f avfoundation -framerate 30 -i "$screen_index:none" -t 7 -an "$raw" >>"$capture_log" 2>&1 &
    capture_pid=$!
    sleep 1
    if ! animate_app; then
      kill "$capture_pid" 2>/dev/null || true
      wait "$capture_pid" 2>/dev/null || true
      return 1
    fi
    wait "$capture_pid" || printf '%s\n' 'AVFoundation did not finish cleanly; validating its output before frame fallback.'
    if [[ -s "$raw" ]]; then
      crop_filter="$(video_region_filter "$raw" "$x" "$y" "$width" "$height" "$scale")" || crop_filter=''
    fi
  fi

  if [[ -z "$crop_filter" ]]; then
    rm -f "$raw"
    local frames="$RUNNER_TEMP/readme-frames-$SLUG"
    rm -rf "$frames"
    mkdir -p "$frames"
    printf '%s\n' 'Using the bounded still-frame burst fallback for the verified menu-bar region.'
    (
      for frame in {1..84}; do
        printf -v frame_name '%s/frame_%04d.png' "$frames" "$frame"
        screencapture -x -R "$x,$y,$width,$height" "$frame_name" >>"$capture_log" 2>&1 || exit 1
        sleep 0.04
      done
    ) &
    local frame_pid=$!
    sleep 1
    if ! animate_app; then
      kill "$frame_pid" 2>/dev/null || true
      wait "$frame_pid" 2>/dev/null || true
      return 1
    fi
    wait "$frame_pid"
    if ! compgen -G "$frames/frame_*.png" >/dev/null; then
      printf '%s\n' 'No screen frames were captured.' | tee "$ARTIFACT_DIR/video-status.txt"
      return 1
    fi
    if ! command -v ffmpeg >/dev/null 2>&1; then brew install ffmpeg; fi
    ffmpeg -y -framerate 12 -i "$frames/frame_%04d.png" -frames:v 84 -c:v libx264 -pix_fmt yuv420p "$raw" >>"$capture_log" 2>&1
    crop_filter='null'
  fi

  [[ -s "$raw" && -n "$crop_filter" ]] || { printf '%s\n' 'No usable video recording matched the requested region.' | tee "$ARTIFACT_DIR/video-status.txt"; return 1; }
  if ! command -v ffmpeg >/dev/null 2>&1; then brew install ffmpeg; fi
  ffmpeg -y -i "$raw" -vf "$crop_filter,fps=12,tpad=stop_mode=clone:stop_duration=1" -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$mp4" >>"$capture_log" 2>&1
  local duration gif_bytes frame_count dimensions gif_width
  duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$mp4")"
  duration_is_acceptable "$duration" || { printf 'MP4 duration outside 6–12 seconds: %s\n' "$duration" >&2; return 1; }
  ffmpeg -y -i "$mp4" -vf 'fps=12,scale=800:-1:flags=lanczos,palettegen=stats_mode=diff' "$RUNNER_TEMP/$SLUG-palette.png" >>"$capture_log" 2>&1
  ffmpeg -y -i "$mp4" -i "$RUNNER_TEMP/$SLUG-palette.png" -lavfi 'fps=12,scale=800:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4' -loop 0 "$gif" >>"$capture_log" 2>&1
  gif_bytes="$(stat -f '%z' "$gif")"
  if (( gif_bytes > 6291456 )); then
    if ! command -v gifsicle >/dev/null 2>&1; then brew install gifsicle; fi
    gifsicle -O3 --lossy=40 "$gif" -o "$RUNNER_TEMP/$SLUG-optimized.gif"
    mv "$RUNNER_TEMP/$SLUG-optimized.gif" "$gif"
    gif_bytes="$(stat -f '%z' "$gif")"
  fi
  (( gif_bytes <= 6291456 )) || { printf 'GIF exceeds 6 MiB after optimization: %s bytes\n' "$gif_bytes" >&2; return 1; }
  dimensions="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$gif")"
  gif_width="${dimensions%%$'\n'*}"
  [[ "$gif_width" == 800 ]] || { printf 'GIF width is not 800px: %s\n' "$gif_width" >&2; return 1; }
  frame_count="$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of default=noprint_wrappers=1:nokey=1 "$gif")"
  [[ "$frame_count" =~ ^[0-9]+$ ]] && (( frame_count <= 100 )) || { printf 'GIF frame count must be at most 100: %s\n' "$frame_count" >&2; return 1; }
  cp "$gif" "$ARTIFACT_DIR/$SLUG-hero.gif"
  printf 'Verified MP4 duration=%ss; GIF width=%spx frames=%s bytes=%s; outputs=%s, %s\n' \
    "$duration" "$gif_width" "$frame_count" "$gif_bytes" "$mp4" "$gif" | tee "$ARTIFACT_DIR/video-status.txt"
}
