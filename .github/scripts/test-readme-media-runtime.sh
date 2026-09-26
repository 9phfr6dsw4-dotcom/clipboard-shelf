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

printf '%s\n' 'PASS: video crop and duration validation cases'
