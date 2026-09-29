#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Board-versus-build comparison images (test use only).

    compare.py BOARD.png BUILD.png OUT.png [x,y,w,h] [--stack] [--scale S]

Without a box: the two full images side by side. With a box: that crop of both, side by side
(or stacked with --stack), optionally scaled. Labels "board" and "build" are drawn on top.
"""
import sys
from PIL import Image, ImageDraw

args = [a for a in sys.argv[1:] if not a.startswith("--")]
flags = [a for a in sys.argv[1:] if a.startswith("--")]
board, build, out = Image.open(args[0]).convert("RGB"), Image.open(args[1]).convert("RGB"), args[2]
scale = 1.0
for f in flags:
    if f.startswith("--scale="):
        scale = float(f.split("=", 1)[1])
if len(args) > 3:
    x, y, w, h = (int(v) for v in args[3].split(","))
    board = board.crop((x, y, x + w, y + h))
    build = build.crop((x, y, x + w, y + h))
if scale != 1.0:
    board = board.resize((int(board.width * scale), int(board.height * scale)), Image.LANCZOS)
    build = build.resize((int(build.width * scale), int(build.height * scale)), Image.LANCZOS)
stack = "--stack" in flags
W = board.width if stack else board.width * 2 + 12
H = board.height * 2 + 12 if stack else board.height
img = Image.new("RGB", (W, H), (255, 0, 255))
img.paste(board, (0, 0))
img.paste(build, (0, board.height + 12) if stack else (board.width + 12, 0))
d = ImageDraw.Draw(img)
for label, pos in (("board", (6, 4)), ("build", (6, board.height + 16) if stack else (board.width + 18, 4))):
    d.rectangle((pos[0] - 2, pos[1] - 2, pos[0] + 40, pos[1] + 12), fill=(255, 0, 255))
    d.text(pos, label, fill=(255, 255, 255))
img.save(out)
