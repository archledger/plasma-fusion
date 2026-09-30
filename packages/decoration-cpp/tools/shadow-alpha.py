#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The window shadow as a screen shows it, against the CSS model (test tooling).

    shadow-alpha.py WITH.png WITHOUT.png --frame X,Y,W,H --scale 2 [--color 20,24,39]
                    [--opacity 0.22] [--blur 90] [--dy 34] [--out DIR]

WITH and WITHOUT are screenshots (device pixels) of the same desktop with the active window and
with it minimized (tests/vsession/scenario-hidpi.sh). Where the shadow lies over the backdrop,
with = without * (1 - a) + colour * a, so a = (without - with) / (without - colour), averaged
over the channels that have enough contrast. The script compares a with the CSS box-shadow model
of the board (Gaussian of sigma = blur / 2 around the frame grown by the 1 px outline, rounded
14 px, moved down by dy) along the column under the window's middle and over the bottom-left
corner, in device pixels, and writes a 3x zoom of the corner (screen / model / |difference| x 20).
"""
import argparse
import math
import os

import numpy as np
from PIL import Image


def model_alpha(x, y, frame, opacity, sigma, dy, radius=14.0, step=0.5):
    """CSS box-shadow alpha at logical points x, y (numpy arrays): the Gaussian-blurred rectangle
    (exact, separable erf) minus the four corner pieces outside the rounded shape (square radius x
    radius without the quarter disc), integrated numerically; the corner term is below 0.001."""
    fx, fy, fw, fh = frame
    left, top, right, bottom = fx - 1, fy - 1 + dy, fx + fw + 1, fy + fh + 1 + dy
    k = 1.0 / (sigma * math.sqrt(2))
    erf = np.vectorize(math.erf)
    ax = 0.5 * (erf((right - x) * k) - erf((left - x) * k))
    ay = 0.5 * (erf((bottom - y) * k) - erf((top - y) * k))
    a = ax * ay
    g = (np.arange(int(radius / step)) + 0.5) * step
    u, v = np.meshgrid(g, g)
    outside = (radius - u) ** 2 + (radius - v) ** 2 > radius * radius
    u, v = u[outside], v[outside]
    norm = step * step / (2 * math.pi * sigma * sigma)
    for cx, cy, sx, sy in ((left, top, 1, 1), (right, top, -1, 1), (left, bottom, 1, -1), (right, bottom, -1, -1)):
        px, py = cx + sx * u, cy + sy * v
        d2 = (px[None, :] - x.reshape(-1)[:, None]) ** 2 + (py[None, :] - y.reshape(-1)[:, None]) ** 2
        a = a - (np.exp(-d2 / (2 * sigma * sigma)).sum(axis=1) * norm).reshape(a.shape)
    return opacity * np.clip(a, 0, None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("with_png")
    ap.add_argument("without_png")
    ap.add_argument("--frame", required=True, help="logical X,Y,W,H of the window frame")
    ap.add_argument("--scale", type=float, default=2.0)
    ap.add_argument("--color", default="20,24,39")
    ap.add_argument("--opacity", type=float, default=0.22)
    ap.add_argument("--blur", type=float, default=90)
    ap.add_argument("--dy", type=float, default=34)
    ap.add_argument("--out", default=".")
    args = ap.parse_args()
    s = args.scale
    frame = [float(v) for v in args.frame.split(",")]
    col = [float(v) for v in args.color.split(",")]
    sigma = args.blur / 2
    w = np.asarray(Image.open(args.with_png).convert("RGB"), dtype=float)
    b = np.asarray(Image.open(args.without_png).convert("RGB"), dtype=float)
    H, W = w.shape[:2]
    # a = (without - with) / (without - colour), least squares over the channels with contrast
    d = b - np.array(col)[None, None, :]
    use = d > 60
    num = ((b - w) * d * use).sum(axis=2)
    den = (d * d * use).sum(axis=2)
    alpha = np.where(den > 0, num / np.maximum(den, 1e-9), np.nan)

    fx, fy, fw, fh = frame
    ys, xs = np.mgrid[0:H, 0:W]
    lx, ly = (xs + 0.5) / s, (ys + 0.5) / s
    grown = (lx >= fx - 1) & (lx <= fx + fw + 1) & (ly >= fy - 1) & (ly <= fy + fh + 1)

    # column under the middle of the window, from 2 logical px below the frame down to 3 sigma
    X = int((fx + fw / 2) * s)
    Y0 = int((fy + fh + 2) * s)
    Y1 = min(H - 1, int((fy + fh + args.dy + 3 * sigma) * s))
    Ys = np.arange(Y0, Y1)
    col_a = alpha[Ys, X]
    col_m = model_alpha(lx[Ys, X], ly[Ys, X], frame, args.opacity, sigma, args.dy)
    ok = ~np.isnan(col_a)
    worst_col = float(np.max(np.abs(col_a[ok] - col_m[ok]))) if ok.any() else float("nan")

    # bottom-left corner region outside the frame
    cx0, cx1 = int((fx - 60) * s), int((fx + 40) * s)
    cy0, cy1 = int((fy + fh - 40) * s), min(H, int((fy + fh + 90) * s))
    ra = alpha[cy0:cy1, cx0:cx1]
    rm = model_alpha(lx[cy0:cy1, cx0:cx1], ly[cy0:cy1, cx0:cx1], frame, args.opacity, sigma, args.dy)
    mask = ~grown[cy0:cy1, cx0:cx1] & ~np.isnan(ra)
    worst_corner = float(np.max(np.abs(ra[mask] - rm[mask]))) if mask.any() else float("nan")

    def grey(v):
        return np.clip(np.round(255 * (1 - v / max(args.opacity, 1e-6))), 0, 255)

    panel_w = cx1 - cx0
    sheet = np.full((cy1 - cy0, panel_w * 3), 255.0)
    sheet[:, :panel_w] = np.where(mask, grey(np.nan_to_num(ra)), 90)
    sheet[:, panel_w:2 * panel_w] = np.where(mask, grey(rm), 90)
    sheet[:, 2 * panel_w:] = np.where(mask, np.clip(np.round(255 * (1 - 20 * np.abs(np.nan_to_num(ra) - rm))), 0, 255), 90)
    os.makedirs(args.out, exist_ok=True)
    img = Image.fromarray(sheet.astype(np.uint8), "L")
    img.resize((img.width * 3, img.height * 3), Image.NEAREST).save(os.path.join(args.out, "shadow-corner-screen-model-diff-3x.png"))
    with open(os.path.join(args.out, "shadow-profile.csv"), "w") as f:
        f.write("device_y,screen_alpha,model_alpha\n")
        for Y, a, m in zip(Ys, col_a, col_m):
            f.write("%d,%.4f,%.4f\n" % (Y, a, m))
    print("scale %.3f: column under the window (%d samples): max |screen - model| = %.4f alpha (%.2f/255)"
          % (s, int(ok.sum()), worst_col, worst_col * 255))
    print("scale %.3f: bottom-left corner region (%d px): max |screen - model| = %.4f alpha (%.2f/255)"
          % (s, int(mask.sum()), worst_corner, worst_corner * 255))


if __name__ == "__main__":
    main()
