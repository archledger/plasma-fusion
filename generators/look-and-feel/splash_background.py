#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render the blurred wallpaper behind the Plasma Fusion splash screen.

Reproduces the background layer of design/boards/Splash.dc.html:

    <div style="background:#0b0e1b">
      <svg viewBox="0 0 1440 900" style="opacity:0.28; filter:blur(26px); transform:scale(1.08)">
        (Dusk Ridge wallpaper: #141a2e sky, sun and four ridges)

The element is blurred in its own coordinates with transparent surroundings (so the edges
soften the way the browser draws them), scaled by 1.08 about the centre, faded to 28 % and
laid over #0b0e1b. The result is written as an opaque PNG at the requested size; the splash
crops it to the screen with PreserveAspectCrop.

Usage: splash_background.py OUTPUT.png [WIDTHxHEIGHT]   (default 1920x1200, 16:10)
"""
import sys

from PIL import Image, ImageDraw, ImageFilter

BOARD_W, BOARD_H = 1440, 900
BASE = (0x0B, 0x0E, 0x1B)
OPACITY = 0.28
BLUR = 26.0
SCALE = 1.08

SKY = "#141a2e"
SUN = ("#f2a65a", (1010, 360), 150)
RIDGES = [
    ("#253058", "M0 560 L180 430 L330 505 L520 350 L700 485 L860 405 L1060 520 L1240 385 L1440 470 L1440 900 L0 900 Z"),
    ("#2e3d73", "M0 650 L220 545 L420 620 L640 505 L880 612 L1100 540 L1300 622 L1440 580 L1440 900 L0 900 Z"),
    ("#3b56a0", "M0 760 L260 662 L520 732 L780 642 L1040 722 L1280 662 L1440 702 L1440 900 L0 900 Z"),
    ("#5a7fd6", "M0 846 L300 786 L600 834 L900 774 L1200 824 L1440 792 L1440 900 L0 900 Z"),
]


def path_points(d, k, pad):
    """Points of an absolute M/L/Z polygon path, scaled by k and shifted by pad."""
    pts = []
    tokens = d.replace("M", " ").replace("L", " ").replace("Z", " ").split()
    for i in range(0, len(tokens), 2):
        pts.append((float(tokens[i]) * k + pad, float(tokens[i + 1]) * k + pad))
    return pts


def render(width, height):
    # Work in board units multiplied by k so the output keeps the board's proportions.
    k = max(width / BOARD_W, height / BOARD_H)
    pad = int(round(4 * BLUR * k))  # transparent margin so the blur fades at the edges
    lw, lh = int(round(BOARD_W * k)), int(round(BOARD_H * k))
    ss = 2  # supersampling for smooth polygon edges before the blur
    layer = Image.new("RGBA", ((lw + 2 * pad) * ss, (lh + 2 * pad) * ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rectangle([pad * ss, pad * ss, (pad + lw) * ss - 1, (pad + lh) * ss - 1], fill=SKY)
    colour, (cx, cy), r = SUN
    draw.ellipse([(pad + (cx - r) * k) * ss, (pad + (cy - r) * k) * ss,
                  (pad + (cx + r) * k) * ss, (pad + (cy + r) * k) * ss], fill=colour)
    for colour, d in RIDGES:
        draw.polygon(path_points(d, k * ss, pad * ss), fill=colour)
    layer = layer.resize((lw + 2 * pad, lh + 2 * pad), Image.LANCZOS)

    # Blur with premultiplied alpha, as a browser does.
    layer = layer.convert("RGBa").filter(ImageFilter.GaussianBlur(BLUR * k)).convert("RGBA")

    # scale(1.08) about the centre of the board area, then crop to the board area.
    ox, oy = pad + lw / 2.0, pad + lh / 2.0
    inv = 1.0 / SCALE
    # Output pixel (x, y) in board-area coordinates samples the layer at
    # ((x - lw/2) / SCALE + ox, (y - lh/2) / SCALE + oy).
    layer = layer.transform((lw, lh), Image.AFFINE,
                            (inv, 0, ox - (lw / 2.0) * inv, 0, inv, oy - (lh / 2.0) * inv),
                            resample=Image.BICUBIC)

    alpha = layer.getchannel("A").point(lambda a: int(round(a * OPACITY)))
    layer.putalpha(alpha)
    out = Image.new("RGBA", (lw, lh), BASE + (255,))
    out.alpha_composite(layer)
    out = out.convert("RGB")
    if (lw, lh) != (width, height):
        left, top = (lw - width) // 2, (lh - height) // 2
        out = out.crop((left, top, left + width, top + height))
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    size = sys.argv[2] if len(sys.argv) > 2 else "1920x1200"
    width, height = (int(v) for v in size.lower().split("x"))
    render(width, height).save(sys.argv[1], optimize=True)


if __name__ == "__main__":
    main()
