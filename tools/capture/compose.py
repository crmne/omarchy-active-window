#!/usr/bin/python3
"""Compose preview.png, the marketplace card, from capture.py's renders.

The marketplace card shows only a strip from the middle, about 2.7 times as
wide as it is tall, and the websites crop to 16:9. So the bar is shown large
inside that strip, with the widget's icon and title where every crop keeps
them, and the appearance panel under it shows all three sliders in that strip.

Usage: compose.py [captures-dir]  (default: screenshots/)
"""
import json
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
WALLPAPER = Path("/usr/share/omarchy/themes/ristretto/backgrounds/0-launch.png")
W, H = 2560, 1600
# Card pixels per logical pixel of the shell.
BAR_ZOOM, PANEL_ZOOM = 6, 3

shots = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "screenshots"
layout = json.loads((shots / "layout.json").read_text())


def cover(image, width, height):
    scale = max(width / image.width, height / image.height)
    image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    left, top = (image.width - width) // 2, (image.height - height) // 2
    return image.crop((left, top, left + width, top + height))


def shot(name, zoom):
    image = Image.open(shots / name).convert("RGBA")
    factor = zoom / layout["scale"]
    if factor == 1: return image
    return image.resize((round(image.width * factor), round(image.height * factor)), Image.LANCZOS)


# The wallpaper, blurred and dimmed so the widget reads first.
card = cover(Image.open(WALLPAPER).convert("RGB"), W, H).filter(ImageFilter.GaussianBlur(24))
card = ImageEnhance.Brightness(card).enhance(0.35).convert("RGBA")


def place(image, x, y, radius):
    global card
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x + 12, y + 30, x + image.width + 12, y + image.height + 30), radius, fill=(0, 0, 0, 190))
    card = Image.alpha_composite(card, shadow.filter(ImageFilter.GaussianBlur(32)))
    card.alpha_composite(image, (round(x), round(y)))


bar = shot("bar-titled.png", BAR_ZOOM)
icon_only = shot("bar-iconOnly.png", BAR_ZOOM)
panel = shot("settings.png", PANEL_ZOOM)
widget_x = layout["widgetX"] * BAR_ZOOM

# The titled bar across the top of the card strip, the panel hanging under
# its widget as it opens in the shell, and the icon-only mode to its left.
bar_x, bar_y = (W - bar.width) // 2 + 120, 390
panel_x = (bar_x + widget_x + bar_x + bar.width) / 2 - panel.width / 2
panel_y = bar_y + bar.height + 40
place(bar, bar_x, bar_y, 36)
place(icon_only, panel_x - icon_only.width - 110, 840, 36)
place(panel, panel_x, panel_y, 40)

card.convert("RGB").save(ROOT / "preview.png", optimize=True)
print("wrote", ROOT / "preview.png", card.size, file=sys.stderr)
