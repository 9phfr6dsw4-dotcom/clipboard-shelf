#!/usr/bin/env python3
"""Fail-closed checks for real README capture geometry and PNG pixels."""
from __future__ import annotations

import argparse
from pathlib import Path
import struct
import sys
from typing import Sequence


class CaptureValidationError(ValueError):
    """A capture candidate is incomplete, ambiguous, or inconsistent."""


def _frame(values: Sequence[int], reason: str) -> tuple[int, int, int, int]:
    if len(values) != 4 or any(type(value) is not int for value in values):
        raise CaptureValidationError(reason)
    x, y, width, height = values
    if min(x, y) < 0 or min(width, height) <= 0:
        raise CaptureValidationError(reason)
    return x, y, width, height


def select_unique_popover(
    status_frame: Sequence[int],
    window_frames: Sequence[Sequence[int]],
    display_size: Sequence[int],
) -> tuple[int, int, int, int]:
    """Select one app window using the existing strict AX adjacency bounds."""
    status_x, status_y, status_width, status_height = _frame(
        status_frame, "invalid_status_item_geometry"
    )
    if (
        len(display_size) != 2
        or any(type(value) is not int for value in display_size)
        or min(display_size) < 240
    ):
        raise CaptureValidationError("invalid_display_geometry")
    screen_width, screen_height = display_size
    if status_x + status_width > screen_width or status_y + status_height > screen_height:
        raise CaptureValidationError("status_item_outside_display")

    status_right = status_x + status_width
    status_bottom = status_y + status_height
    matches: list[tuple[int, int, int, int]] = []
    for raw_frame in window_frames:
        x, y, width, height = _frame(raw_frame, "invalid_app_window_geometry")
        vertical_gap = y - status_bottom
        horizontal_overlap = x < status_right + 80 and x + width > status_x - 80
        if (
            horizontal_overlap
            and -8 <= vertical_gap <= 120
            and width >= 240
            and height >= 240
        ):
            if x + width > screen_width or y + height > screen_height:
                raise CaptureValidationError("adjacent_app_window_outside_display")
            matches.append((x, y, width, height))

    if not matches:
        raise CaptureValidationError("no_adjacent_app_window")
    if len(matches) != 1:
        raise CaptureValidationError("ambiguous_adjacent_app_windows")
    return matches[0]


WINDOW_INVENTORY_HEADER = ["windowID", "PID", "layer", "alpha", "x", "y", "width", "height"]


def select_popover_from_inventory(
    inventory: str,
    *,
    pid: int,
    status_frame: Sequence[int],
    display_size: Sequence[int],
) -> tuple[int, int, int, int]:
    """Apply the strict adjacency predicate to every visible window the launched PID owns.

    The inventory is the render helper's `windows-pid` TSV. Any malformed row or row for
    another process means the enumeration cannot be trusted, so selection fails closed.
    """
    rows = [line.split("\t") for line in inventory.splitlines()]
    if not rows or rows[0] != WINDOW_INVENTORY_HEADER:
        raise CaptureValidationError("invalid_app_window_inventory")
    frames: list[tuple[int, int, int, int]] = []
    for row in rows[1:]:
        try:
            if len(row) != len(WINDOW_INVENTORY_HEADER):
                raise ValueError("row shape")
            window_id, row_pid, _layer = (int(value) for value in row[:3])
            alpha = float(row[3])
            x, y, width, height = (int(value) for value in row[4:])
        except ValueError:
            raise CaptureValidationError("invalid_app_window_inventory") from None
        if window_id <= 0 or row_pid != pid or not 0 <= alpha <= 1:
            raise CaptureValidationError("invalid_app_window_inventory")
        if alpha > 0:
            frames.append((x, y, width, height))
    return select_unique_popover(status_frame, frames, display_size)


def png_dimensions(path: Path) -> tuple[int, int]:
    """Read only the PNG signature/IHDR dimensions; never decode image pixels."""
    try:
        if path.is_symlink() or not path.is_file():
            raise CaptureValidationError("missing_capture")
        with path.open("rb") as stream:
            header = stream.read(24)
    except OSError:
        raise CaptureValidationError("missing_capture") from None
    if (
        len(header) != 24
        or header[:8] != b"\x89PNG\r\n\x1a\n"
        or struct.unpack(">I", header[8:12])[0] != 13
        or header[12:16] != b"IHDR"
    ):
        raise CaptureValidationError("invalid_png_header")
    width, height = struct.unpack(">II", header[16:24])
    if width <= 0 or height <= 0:
        raise CaptureValidationError("invalid_png_dimensions")
    return width, height


def validate_png_dimensions(path: Path, *, expected_width: int, expected_height: int) -> None:
    if type(expected_width) is not int or type(expected_height) is not int or min(expected_width, expected_height) <= 0:
        raise CaptureValidationError("invalid_expected_png_dimensions")
    actual = png_dimensions(path)
    if actual != (expected_width, expected_height):
        raise CaptureValidationError("png_dimensions_mismatch")


def main() -> int:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    geometry = commands.add_parser("geometry")
    geometry.add_argument("--status", nargs=4, type=int, required=True)
    geometry.add_argument("--popover", nargs=4, type=int, required=True)
    geometry.add_argument("--display", nargs=2, type=int, required=True)
    select = commands.add_parser("select-popover", help="read a windows-pid TSV inventory on stdin")
    select.add_argument("--pid", type=int, required=True)
    select.add_argument("--status", nargs=4, type=int, required=True)
    select.add_argument("--display", nargs=2, type=int, required=True)
    png = commands.add_parser("png")
    png.add_argument("path", type=Path)
    png.add_argument("--expected", nargs=2, type=int, required=True)
    args = parser.parse_args()
    try:
        if args.command == "geometry":
            selected = select_unique_popover(args.status, [args.popover], args.display)
            print("|".join(str(value) for value in selected))
        elif args.command == "select-popover":
            selected = select_popover_from_inventory(
                sys.stdin.read(), pid=args.pid, status_frame=args.status, display_size=args.display
            )
            print("|".join(str(value) for value in selected))
        else:
            validate_png_dimensions(
                args.path,
                expected_width=args.expected[0],
                expected_height=args.expected[1],
            )
            print("PNG pixel dimensions match the measured capture bounds")
    except CaptureValidationError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
