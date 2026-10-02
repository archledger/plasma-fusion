#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Draw the boot splash greeting ("Welcome back, <name>") as one PNG per scale factor.

    greeting.py LAYOUT_JSON OUTDIR [--name NAME]...

The boot splash cannot draw this line itself: early boot has no fonts to speak of, and the name
is only known on the machine. gen_plymouth.py writes LAYOUT_JSON (font file, size, colour, the
box and pen position of every scale factor, the font's character coverage) next to a copy of
this file and of the font, and draws the generic "Welcome back" with it at build time;
tools/system/plymouth-install.sh runs it again as root on the target machine with the owner's
name, over the copies of NNN-greeting.png in the theme it installs.

Each --name is a candidate (for example the first word of the account's full name, then the
login name); the first one the font can draw is used. Without a usable candidate the line is
"Welcome back". A name wider than the column ends with an ellipsis. Prints the text drawn.

Needs only Pillow (with libraqm for HarfBuzz shaping, as Fedora's python3-pillow has it).
"""
import argparse
import json
import os
import sys
import unicodedata

from PIL import Image, ImageDraw, ImageFont, features


def covered(text, ranges):
    for ch in text:
        c = ord(ch)
        if not any(lo <= c <= hi for lo, hi in ranges):
            return False
    return True


def clean(name):
    """Printable characters only, inner whitespace collapsed."""
    name = "".join(ch if unicodedata.category(ch)[0] not in "CZ" or ch == " " else " " for ch in name)
    return " ".join(name.split())


def choose(layout, candidates):
    for name in candidates:
        name = clean(name)
        if name and covered(name, layout["coverage"]):
            return name
    return ""


def load_font(path, px):
    engine = ImageFont.Layout.RAQM if features.check("raqm") else ImageFont.Layout.BASIC
    return ImageFont.truetype(path, size=px, layout_engine=engine)


def fit(font, layout, name, maxw):
    """The greeting text for `name`, the name shortened with an ellipsis to fit maxw px."""
    if not name:
        return layout["text"]
    text = layout["with_name"].format(name=name)
    if font.getlength(text) <= maxw:
        return text
    while name:
        name = name[:-1].rstrip()
        text = layout["with_name"].format(name=name + "…")
        if font.getlength(text) <= maxw:
            return text
    return layout["text"]


def render(layout, font_path, entry, name):
    """One scale: an RGBA image of the box with the text centred on the pen centre."""
    font = load_font(font_path, layout["size"] * entry["s"])
    text = fit(font, layout, name, entry["maxw"])
    width = font.getlength(text)
    mask = Image.new("L", (entry["w"], entry["h"]), 0)
    ImageDraw.Draw(mask).text((entry["cx"] - width / 2, entry["base"]), text, fill=255, font=font,
                              anchor="ls")
    colour = layout["colour"].lstrip("#")
    rgb = tuple(int(colour[i:i + 2], 16) for i in (0, 2, 4))
    img = Image.new("RGBA", mask.size, rgb + (0,))
    img.putalpha(mask)
    return img, text


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("layout")
    ap.add_argument("outdir")
    ap.add_argument("--name", action="append", default=[],
                    help="a name to greet; several are tried in order")
    a = ap.parse_args()
    with open(a.layout, encoding="utf-8") as f:
        layout = json.load(f)
    font_path = os.path.join(os.path.dirname(os.path.abspath(a.layout)), layout["font"])
    if not features.check("raqm"):
        print("greeting: Pillow has no libraqm; drawing without kerning", file=sys.stderr)
    name = choose(layout, a.name)
    # Draw every scale first, then write them, so a failure leaves the old images in place.
    images = [(entry, *render(layout, font_path, entry, name)) for entry in layout["scales"]]
    for entry, img, _ in images:
        img.save(os.path.join(a.outdir, entry["file"]), "PNG", optimize=True)
    print(images[0][2])


if __name__ == "__main__":
    main()
