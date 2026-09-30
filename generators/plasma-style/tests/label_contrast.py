#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Contrast of the desktop icon labels in a screenshot (BACKLOG S6 review; test use only).

    label_contrast.py SHOT.png SCALE X0 Y0 PITCH ROWS

Folder View draws desktop labels white with a black drop shadow (PlasmaExtras.ShadowedLabel), so
what makes them readable is the halo, not the wallpaper. For each label under the icon cells of
the left column (icon centre at logical X0, Y0 + k * PITCH) it measures, in device pixels, the
median luminance of the glyph pixels (near white) and of the halo (pixels up to 2 px from a glyph
that are not glyph), and prints the WCAG ratio of the two, plus the ratio white would have on the
wallpaper next to the label without any shadow.
"""
import sys

from PIL import Image


def lum(rgb):
    def lin(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb[:3]
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def ratio(a, b):
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def main():
    path, scale, x0, y0, pitch, rows = sys.argv[1], float(sys.argv[2]), *map(float, sys.argv[3:6]), int(sys.argv[6])
    im = Image.open(path).convert('RGB')
    px = im.load()
    worst = None
    for k in range(rows):
        cy = y0 + k * pitch
        box = (int((x0 - 44) * scale), int((cy + 28) * scale), int((x0 + 44) * scale), int((cy + 50) * scale))
        vals = sorted(lum(px[x, y]) for y in range(box[1], box[3]) for x in range(box[0], box[2]))
        glyph, shadow = vals[int(0.995 * (len(vals) - 1))], vals[int(0.05 * (len(vals) - 1))]
        # the wallpaper right of the label (same row), where no text or shadow is drawn
        bg = lum(px[min(im.width - 1, box[2] + int(10 * scale)), (box[1] + box[3]) // 2])
        bare = ratio(1.0, bg)
        worst = bare if worst is None else min(worst, bare)
        print('row %d: white on the bare wallpaper %.1f:1; brightest glyph pixel against the shadow core %.1f:1'
              % (k, bare, ratio(glyph, shadow)))
    print('worst: white label on the bare wallpaper %.1f:1 (4.5:1 wanted; Folder View draws the label white '
          'with a black drop shadow, which is what carries it on light wallpapers)' % (worst or 0))
    return 0 if worst and worst >= 4.5 else 1


if __name__ == '__main__':
    sys.exit(main())
