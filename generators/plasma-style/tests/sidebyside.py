#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Side-by-side crops for board vs screenshot comparisons.

    sidebyside.py OUT.png ZOOM  IMG x0 y0 x1 y1  [IMG x0 y0 x1 y1 ...] [LABEL ...]
"""

import sys
from PIL import Image, ImageDraw
out, zoom = sys.argv[1], float(sys.argv[2])
args = sys.argv[3:]
crops = []
while len(args) >= 5:
    f, x0, y0, x1, y1 = args[:5]; args = args[5:]
    im = Image.open(f).convert("RGB").crop((int(x0), int(y0), int(x1), int(y1)))
    crops.append(im.resize((int(im.width * zoom), int(im.height * zoom)), Image.NEAREST if zoom >= 2 else Image.LANCZOS))
labels = args
W = sum(c.width for c in crops) + 12 * (len(crops) + 1)
H = max(c.height for c in crops) + 36
canvas = Image.new("RGB", (W, H), (40, 40, 40))
d = ImageDraw.Draw(canvas)
x = 12
for i, c in enumerate(crops):
    canvas.paste(c, (x, 30))
    if i < len(labels):
        d.text((x, 8), labels[i], fill=(230, 230, 230))
    x += c.width + 12
canvas.save(out)
print(out, canvas.size)
