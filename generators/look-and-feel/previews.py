#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Make the Global Theme preview images from full-screen captures.

    previews.py DESKTOP.png SPLASH.png OUTDIR

DESKTOP.png is a 16:10 capture of the desktop (a board render or a screenshot of a session
using the theme); SPLASH.png a capture of the splash screen. Writes, as System Settings'
Global Theme page expects them:

    OUTDIR/preview.png             600 x 375   grid thumbnail
    OUTDIR/fullscreenpreview.jpg   1440 x 900  full-screen preview
    OUTDIR/splash.png              300 x 188   splash thumbnail

This is run by hand when the look changes; the results are committed in
packages/look-and-feel/<id>/contents/previews/ so the build needs no captures.
"""
import os
import sys

from PIL import Image


def fit(img, size):
    """Scale and centre-crop to exactly `size`."""
    w, h = size
    scale = max(w / img.width, h / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left, top = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((left, top, left + w, top + h))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    desktop = Image.open(sys.argv[1]).convert("RGB")
    splash = Image.open(sys.argv[2]).convert("RGB")
    out = sys.argv[3]
    os.makedirs(out, exist_ok=True)
    fit(desktop, (600, 375)).save(os.path.join(out, "preview.png"), optimize=True)
    fit(desktop, (1440, 900)).save(os.path.join(out, "fullscreenpreview.jpg"), quality=90, optimize=True)
    fit(splash, (300, 188)).save(os.path.join(out, "splash.png"), optimize=True)


if __name__ == "__main__":
    main()
