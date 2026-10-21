#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A screenshot of SDDM's greeter against the Login board, where the board shows its background
only (no clock, card, user row, session pill or power buttons on any screen size the theme lays
out): the mean colour of each region, the board scaled and cropped to the screenshot as the theme
fills the screen (Image.PreserveAspectCrop). Needs Pillow (on NixOS:
nix-shell -p python3Packages.pillow).

  greeter-compare.py SHOT.png [--board design/previews/Login.webp] [--expect match|differ]

match (default): every region within --tol (per channel, of 255) of the board - the Plasma Fusion
theme was drawn; differ: some region more than three times --tol off - another theme was (the
stock greeter after a restore). One line per region, then the verdict; exit 1 when it fails.
"""

import argparse
import pathlib
import sys

from PIL import Image, ImageStat

# Fractions of the width and height: x0, y0, x1, y1
REGIONS = {
    "mid-left": (0.05, 0.25, 0.30, 0.55),
    "sun": (0.68, 0.30, 0.78, 0.42),
    "far-right": (0.85, 0.55, 0.97, 0.80),
    "hills": (0.25, 0.82, 0.75, 0.97),
}


def fill(image, size):
    """IMAGE scaled to cover SIZE and cropped to it around the centre."""
    w, h = size
    scale = max(w / image.width, h / image.height)
    size = (round(image.width * scale), round(image.height * scale))
    scaled = image.resize(size, Image.LANCZOS)
    left, top = (scaled.width - w) // 2, (scaled.height - h) // 2
    return scaled.crop((left, top, left + w, top + h))


def mean(image, box):
    w, h = image.size
    x0, y0, x1, y1 = box
    region = image.crop((round(x0 * w), round(y0 * h), round(x1 * w), round(y1 * h)))
    return tuple(ImageStat.Stat(region).mean)


def main():
    here = pathlib.Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("shot")
    ap.add_argument("--board", default=str(here.parents[2] / "design/previews/Login.webp"))
    ap.add_argument("--expect", choices=("match", "differ"), default="match")
    ap.add_argument("--tol", type=float, default=4.0)
    args = ap.parse_args()
    shot = Image.open(args.shot).convert("RGB")
    board = fill(Image.open(args.board).convert("RGB"), shot.size)
    worst = 0.0
    for name, box in REGIONS.items():
        s, b = mean(shot, box), mean(board, box)
        delta = max(abs(x - y) for x, y in zip(s, b))
        worst = max(worst, delta)
        print(f"{name:10} shot {s[0]:6.1f} {s[1]:6.1f} {s[2]:6.1f}"
              f"  board {b[0]:6.1f} {b[1]:6.1f} {b[2]:6.1f}  delta {delta:5.1f}")
    if args.expect == "match":
        ok = worst <= args.tol
        print(f"{'match' if ok else 'NO MATCH'}: largest delta {worst:.1f}"
              f" (tolerance {args.tol:g})")
    else:
        ok = worst > 3 * args.tol
        print(f"{'differs' if ok else 'TOO CLOSE'}: largest delta {worst:.1f}"
              f" (needs more than {3 * args.tol:g})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
