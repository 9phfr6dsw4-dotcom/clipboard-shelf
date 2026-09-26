#!/usr/bin/env bash
set -euo pipefail

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
    clipboard-shelf)
      show_menu_popover
      osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "ClipboardShelf"
    set frontmost to true
    click text field 1 of window 1
    keystroke "b"
    delay 0.25
    keystroke "u"
    delay 0.25
    keystroke "i"
    delay 0.25
    keystroke "l"
    delay 0.25
    keystroke "d"
    delay 0.5
    set value of text field 1 of window 1 to ""
    delay 0.5
    click button "Pin clipboard item" of row 3 of table 1 of scroll area 1 of window 1
    delay 0.5
    click row 4 of table 1 of scroll area 1 of window 1
    delay 1
  end tell
end tell
APPLESCRIPT
      show_menu_popover
      ;;
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
