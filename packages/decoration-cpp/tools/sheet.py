#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stacked title-bar crops for comparing the decoration with the boards (test tooling).

    sheet.py OUT.png [--scale 1|4-3] [--zoom 2] [--board RENDER.png] LABEL=IMAGE ...
    sheet.py OUT.png --preview DIR --scheme dark [--scale 1|4-3] [--board RENDER.png]

Every image is a 1440x900 (logical) screenshot with the window frame where the Main board has its
Appearance window (549,263 650x504): pfdeco-preview scenes and the virtual-session screenshots of
tests/vsession/scenario.sh both use that frame. The crop is the title bar with a margin
(530,240)-(1220,330); labels containing "maximized" are cropped from the top of the screen.
With --board the board render's own title bar comes first.
"""
import argparse
import glob
import os

from PIL import Image, ImageDraw

BOX = (530, 240, 1220, 330)
BOX_MAX = (0, 20, 1440, 90)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("items", nargs="*", help="LABEL=IMAGE")
    ap.add_argument("--preview")
    ap.add_argument("--scheme", default="dark")
    ap.add_argument("--scale", default="1")
    ap.add_argument("--zoom", type=int, default=2)
    ap.add_argument("--board")
    a = ap.parse_args()
    s = 4 / 3 if a.scale == "4-3" else 1.0
    items = [tuple(i.split("=", 1)) for i in a.items]
    if a.preview:
        for f in sorted(glob.glob(os.path.join(a.preview, f"{a.scheme}-*-s{a.scale}.png"))):
            items.append((os.path.basename(f)[len(a.scheme) + 1:-len(f"-s{a.scale}.png")], f))
    rows = []
    if a.board:
        b = Image.open(a.board).convert("RGB").crop(BOX)
        rows.append(("board", b.resize((round(b.width * s), round(b.height * s)), Image.LANCZOS)))
    for label, path in items:
        im = Image.open(path).convert("RGB")
        k = im.width / 1440.0
        box = BOX_MAX if "maximized" in label else BOX
        rows.append((label, im.crop(tuple(round(v * k) for v in box))))
    label_w = 170
    width = max(r[1].width for r in rows) * a.zoom + label_w
    height = sum(r[1].height * a.zoom + 4 for r in rows)
    sheet = Image.new("RGB", (width, height), (255, 0, 255))
    d = ImageDraw.Draw(sheet)
    y = 0
    for label, im in rows:
        z = im.resize((im.width * a.zoom, im.height * a.zoom), Image.NEAREST)
        sheet.paste((20, 20, 20), (0, y, label_w, y + z.height))
        d.text((6, y + 6), label, fill=(255, 255, 255))
        sheet.paste(z, (label_w, y))
        y += z.height + 4
    sheet.save(a.out)


if __name__ == "__main__":
    main()
