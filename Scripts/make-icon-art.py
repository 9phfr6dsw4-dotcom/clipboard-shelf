#!/usr/bin/env python3
"""Draws Clipboard Shelf's icon art (the "bold clip"). Needs Pillow; not run in CI.

Writes these files from one geometry:
- Resources/AppIcon.icon/Assets/clipboard.png: the transparent glyph layer for Icon Composer
  (macOS draws the rounded square, shadow and glass; the gradient is the .icon's own fill, which
  must match BUILT_IN's gradient below).
- Resources/AppIcon-1024.png: the flat icon (the .icns fallback) on the macOS grid.
- docs/images/clipboard-shelf-icon.png: the same flat icon, for the README.
- Resources/SkinIcons/icon-<skin>.png: the flat icon in each other skin's colours, which the app
  puts on itself in Finder when that skin is chosen (Classic, the default, is the app's own icon).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SS = 2  # draw at 2x, then reduce, for smooth edges
SIZE = 1024

# Each skin's gradient, lit from above, built around its accent colour (ShelfSkin.accent).
SKIN_GRADIENTS = {
    "classic": ((0x3A, 0xA2, 0xFF), (0x0A, 0x4B, 0xA6)),
    "lagoon": ((0x1F, 0xC4, 0xB0), (0x07, 0x62, 0x70)),
    "grape": ((0xA4, 0x80, 0xFA), (0x4A, 0x2A, 0x9A)),
    "sunset": ((0xFF, 0x8C, 0x5E), (0xB0, 0x38, 0x2C)),
    "meadow": ((0x4E, 0xCF, 0x7A), (0x14, 0x6C, 0x38)),
    "rose": ((0xF7, 0x72, 0xA2), (0x9C, 0x22, 0x56)),
}
BUILT_IN = "classic"  # the app's own icon: ShelfSkin.builtInIcon
TOP, BOTTOM = SKIN_GRADIENTS[BUILT_IN]
GOLD_TOP = (0xF8, 0xB9, 0x3C)
GOLD_BOTTOM = (0xD9, 0x8A, 0x12)
WHITE = (255, 255, 255, 255)
SHIFT = 27  # centres the glyph's visual weight on the canvas


def s(value: float) -> int:
    return round(value * SS)


def vertical_gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    strip = Image.new("RGB", (1, height))
    for y in range(height):
        t = y / max(1, height - 1)
        strip.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return strip.resize(size)


def glyph() -> Image.Image:
    """The clipboard outline, its three lines and its gold clip, on a transparent canvas."""
    canvas = Image.new("RGBA", (s(SIZE), s(SIZE)), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        (s(296), s(262 + SHIFT), s(728), s(762 + SHIFT)), radius=s(84), outline=WHITE, width=s(46)
    )
    for y, right in ((480, 632), (574, 632), (668, 532)):
        draw.rounded_rectangle((s(392), s(y - 20 + SHIFT), s(right), s(y + 20 + SHIFT)), radius=s(20), fill=(255, 255, 255, 235))
    clip_box = (s(402), s(208 + SHIFT), s(622), s(324 + SHIFT))
    clip_mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(clip_mask).rounded_rectangle(clip_box, radius=s(44), fill=255)
    gold = vertical_gradient(canvas.size, GOLD_TOP, GOLD_BOTTOM).convert("RGBA")
    canvas.paste(gold, (0, 0), clip_mask)
    return canvas


def flat_icon(art: Image.Image, top: tuple[int, int, int] = TOP, bottom: tuple[int, int, int] = BOTTOM) -> Image.Image:
    """The macOS-grid icon: an 824-point body with a 185-point radius, soft shadow, gradient and sheen."""
    full = (s(SIZE), s(SIZE))
    body_box = (s(100), s(100), s(924), s(924))
    body_mask = Image.new("L", full, 0)
    ImageDraw.Draw(body_mask).rounded_rectangle(body_box, radius=s(185), fill=255)

    shadow = Image.new("RGBA", full, (0, 0, 0, 0))
    shadow.putalpha(body_mask.filter(ImageFilter.GaussianBlur(s(22))).point(lambda v: int(v * 0.30)))
    shadow = ImageChops.offset(shadow, 0, s(14))

    body = vertical_gradient(full, top, bottom).convert("RGBA")
    sheen = Image.new("RGBA", full, (255, 255, 255, 0))
    sheen_alpha = Image.new("L", full, 0)
    sheen_draw = ImageDraw.Draw(sheen_alpha)
    for y in range(s(100), s(520)):
        t = (y - s(100)) / (s(520) - s(100))
        sheen_draw.line((0, y, full[0], y), fill=round(70 * (1 - t)))
    sheen.putalpha(ImageChops.multiply(sheen_alpha, body_mask))
    body = Image.alpha_composite(body, sheen)

    art_shadow = Image.new("RGBA", full, (0, 0, 0, 0))
    art_shadow.putalpha(art.getchannel("A").filter(ImageFilter.GaussianBlur(s(14))).point(lambda v: int(v * 0.30)))
    art_shadow = ImageChops.offset(art_shadow, 0, s(10))

    icon = Image.new("RGBA", full, (0, 0, 0, 0))
    icon = Image.alpha_composite(icon, shadow)
    body_layer = Image.new("RGBA", full, (0, 0, 0, 0))
    body_layer.paste(body, (0, 0), body_mask)
    icon = Image.alpha_composite(icon, body_layer)
    icon = Image.alpha_composite(icon, art_shadow)
    icon = Image.alpha_composite(icon, art)
    return icon.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    art = glyph()
    layer = art.resize((SIZE, SIZE), Image.LANCZOS)
    layer_path = ROOT / "Resources/AppIcon.icon/Assets/clipboard.png"
    layer.save(layer_path)
    flat = flat_icon(art)
    flat.save(ROOT / "Resources/AppIcon-1024.png")
    flat.save(ROOT / "docs/images/clipboard-shelf-icon.png")
    skin_dir = ROOT / "Resources/SkinIcons"
    skin_dir.mkdir(exist_ok=True)
    for stale in skin_dir.glob("icon-*.png"):
        stale.unlink()
    for name, (top, bottom) in SKIN_GRADIENTS.items():
        if name == BUILT_IN:
            continue
        flat_icon(art, top, bottom).save(skin_dir / f"icon-{name}.png", optimize=True)
    print("Wrote", layer_path, "the flat icons and the skin icons.")


if __name__ == "__main__":
    main()
