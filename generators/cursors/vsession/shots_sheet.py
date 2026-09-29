#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Sheet of the pointers KWin drew into virtual-session screenshots (laptop side, Pillow).

    shots_sheet.py RESULTS_DIR PREFIX OUT.png [TITLE]

Reads RESULTS_DIR/PREFIX-positions.json and RESULTS_DIR/PREFIX-NAME.png (from eipointer.py),
crops 56x56 px around each pointer position, zooms 3x and marks the pointer position (where the
hotspot must be) with a thin amber ring.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def main():
    d, prefix, out = sys.argv[1:4]
    title = sys.argv[4] if len(sys.argv) > 4 else prefix
    pos = json.load(open(os.path.join(d, f'{prefix}-positions.json')))
    try:
        f1 = ImageFont.truetype(os.path.join(ROOT, 'fonts/manrope/Manrope[wght].ttf'), 13)
        f2 = ImageFont.truetype(os.path.join(ROOT, 'fonts/manrope/Manrope[wght].ttf'), 20)
    except OSError:
        f1 = f2 = ImageFont.load_default()
    C, Z, pad = 56, 3, 14
    cols = 7
    n = len(pos)
    rows = (n + cols - 1) // cols
    cw, ch = C * Z + pad, C * Z + 28 + pad
    sheet = Image.new('RGB', (cols * cw + pad, rows * ch + 50), '#10142a')
    dr = ImageDraw.Draw(sheet)
    dr.text((pad, 14), title, fill='#e8ebf4', font=f2)
    for i, (name, (x, y)) in enumerate(pos.items()):
        im = Image.open(os.path.join(d, f'{prefix}-{name}.png')).convert('RGB')
        x0, y0 = int(x) - 16, int(y) - 16
        crop = im.crop((x0, y0, x0 + C, y0 + C)).resize((C * Z, C * Z), Image.NEAREST)
        cd = ImageDraw.Draw(crop)
        hx, hy = (x - x0) * Z, (y - y0) * Z
        cd.ellipse((hx - 4, hy - 4, hx + 4, hy + 4), outline='#f2a65a', width=1)
        px, py = pad + (i % cols) * cw, 50 + (i // cols) * ch
        sheet.paste(crop, (px, py))
        dr.text((px, py + C * Z + 6), name, fill='#e8ebf4', font=f1)
    sheet.save(out)


if __name__ == '__main__':
    main()
