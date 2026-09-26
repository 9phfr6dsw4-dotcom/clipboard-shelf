#!/usr/bin/env python3
"""Serialize a privacy-minimized, fail-closed capture geometry snapshot."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import re
import sys
from typing import Any

WINDOW_HEADER = ["windowID", "PID", "layer", "alpha", "x", "y", "width", "height"]
REASONS = {
    "status_item_click_failed",
    "strict_ax_adjacency_predicate_failed_after_12_polls",
    "capture_failed_before_geometry_check",
    "capture_failed_after_geometry_check",
    "capture_pixel_validation_failed",
    "diagnostic_collection_failed",
}


def _integer(value: str, *, signed: bool = False) -> int:
    pattern = r"-?[0-9]{1,7}" if signed else r"[0-9]{1,10}"
    if not re.fullmatch(pattern, value):
        raise ValueError("invalid integer")
    return int(value)


def parse_status_item(raw: str) -> tuple[dict[str, Any], str | None]:
    fields = raw.strip().split("|")
    if len(fields) != 5:
        return {"match_count": -1, "frame": None}, "invalid_status_item_result"
    try:
        count = _integer(fields[0])
        if count < 0 or count > 100:
            raise ValueError("invalid count")
        if count != 1:
            return {"match_count": count, "frame": None}, None
        x, y, width, height = (_integer(value, signed=True) for value in fields[1:])
        if width <= 0 or height <= 0:
            raise ValueError("invalid frame")
        return {"match_count": 1, "frame": [x, y, width, height]}, None
    except ValueError:
        return {"match_count": -1, "frame": None}, "invalid_status_item_result"


def parse_app_windows(path: Path, app_pid: int | None) -> tuple[list[dict[str, Any]], str | None]:
    if app_pid is None:
        return [], "app_pid_unavailable"
    try:
        with path.open("r", encoding="utf-8", newline="") as stream:
            rows = list(csv.reader(stream, delimiter="\t"))
        if not rows or rows[0] != WINDOW_HEADER:
            raise ValueError("unexpected window inventory schema")
        windows: list[dict[str, Any]] = []
        for row in rows[1:]:
            if not row:
                continue
            if len(row) != len(WINDOW_HEADER):
                raise ValueError("unexpected window inventory row")
            window_id = _integer(row[0])
            pid = _integer(row[1])
            layer = _integer(row[2], signed=True)
            alpha = float(row[3])
            x, y = _integer(row[4], signed=True), _integer(row[5], signed=True)
            width, height = _integer(row[6]), _integer(row[7])
            if window_id <= 0 or pid != app_pid or not 0 <= alpha <= 1 or width < 0 or height < 0:
                raise ValueError("invalid or unrelated app window")
            windows.append(
                {
                    "window_id": window_id,
                    "pid": pid,
                    "layer": layer,
                    "alpha": round(alpha, 4),
                    "frame": [x, y, width, height],
                }
            )
        return windows, None
    except (OSError, UnicodeError, csv.Error, ValueError):
        return [], "invalid_app_window_inventory"


def parse_display_info(raw: str) -> tuple[dict[str, Any] | None, str | None]:
    match = re.fullmatch(
        r"frame=(-?[0-9]{1,7}),(-?[0-9]{1,7}),([0-9]{1,6}),([0-9]{1,6})\|pixels=([0-9]{1,7})x([0-9]{1,7})\|scale=([1-8])",
        raw.strip(),
    )
    if not match:
        return None, "invalid_display_geometry"
    x, y, width, height, pixel_width, pixel_height, scale = map(int, match.groups())
    if min(width, height, pixel_width, pixel_height) <= 0:
        return None, "invalid_display_geometry"
    return {
        "frame_points": [x, y, width, height],
        "pixel_size": [pixel_width, pixel_height],
        "scale": scale,
    }, None


def make_snapshot(
    *,
    reason: str,
    app_pid_raw: str,
    status_item_raw: str,
    windows_path: Path,
    display_info_raw: str,
) -> dict[str, Any]:
    if reason not in REASONS:
        reason = "diagnostic_collection_failed"
    errors: list[str] = []
    try:
        app_pid = _integer(app_pid_raw)
        if app_pid <= 0:
            raise ValueError("invalid app PID")
    except ValueError:
        app_pid = None
        errors.append("app_pid_unavailable")

    status_item, status_error = parse_status_item(status_item_raw)
    if status_error:
        errors.append(status_error)
    windows, windows_error = parse_app_windows(windows_path, app_pid)
    if windows_error:
        errors.append(windows_error)
    display, display_error = parse_display_info(display_info_raw)
    if display_error:
        errors.append(display_error)

    return {
        "schema": "clipboard-shelf-capture-geometry/v1",
        "app_pid": app_pid,
        "status_item": status_item,
        "app_owned_windows": windows,
        "display": display,
        "rejection_reason": reason,
        "collection_errors": sorted(set(errors)),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reason", required=True)
    parser.add_argument("--app-pid", default="")
    parser.add_argument("--status-item", default="")
    parser.add_argument("--windows", type=Path, required=True)
    parser.add_argument("--display-info", default="")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    snapshot = make_snapshot(
        reason=args.reason,
        app_pid_raw=args.app_pid,
        status_item_raw=args.status_item,
        windows_path=args.windows,
        display_info_raw=args.display_info,
    )
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_name(args.output.name + ".tmp")
        temporary.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(args.output)
    except OSError as error:
        print(f"Could not write geometry snapshot ({type(error).__name__})", file=sys.stderr)
        return 1
    print("Wrote sanitized capture geometry snapshot")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
