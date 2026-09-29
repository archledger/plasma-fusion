#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline preview of a generated Aurorae theme (test tooling, not installed).

    preview.py THEME_DIR OUT.png [--state active|inactive|hover|maximized] [--scale S]
               [--size WxH] [--bg #rrggbb] [--title TEXT] [--board-crop RENDER x,y,w,h]

Re-implements what Aurorae v2 and KSvg FrameSvg do in KWin 6.7 (nine-slice frame at window size
plus padding, painted at -padding; buttons from the button SVGs at the rc metrics; caption in the
title font, Manrope 14 px ExtraBold) and draws one window on a plain background, like the Anatomy
panel of Windows.dc.html (window at 52,42, 700x250 including the 1 px edge). With --board-crop
the board render crop is placed on the left for a side-by-side.
"""
import argparse
import configparser
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QRectF, Qt  # noqa: E402
from PySide6.QtGui import (QColor, QFont, QFontDatabase, QGuiApplication, QImage, QPainter,  # noqa: E402
                           QPainterPath)
from PySide6.QtSvg import QSvgRenderer  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def read_rc(path):
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str
    with open(path, encoding="utf-8") as f:
        cp.read_string("".join(line for line in f if not line.startswith("#")))
    return cp


def bounds(r, eid):
    return r.transformForElement(eid).mapRect(r.boundsOnElement(eid))


def paint_frame(p, r, prefix, x, y, fw, fh, maximized=False):
    """FrameSvg::paintFrame for size fw x fh at (x, y)."""
    if maximized:
        r.render(p, prefix + "-center", QRectF(x, y, fw, fh))
        return
    b = {e: bounds(r, prefix + "-" + e) for e in
         ("topleft", "top", "topright", "left", "right", "bottomleft", "bottom", "bottomright", "center")}
    L, T = b["left"].width(), b["top"].height()
    R, B = b["right"].width(), b["bottom"].height()
    cw, ch = fw - L - R, fh - T - B
    if cw > 0 and ch > 0:
        r.render(p, prefix + "-center", QRectF(x + L, y + T, cw, ch))
    for e, rect in (("topleft", (0, 0, L, T)), ("topright", (fw - R, 0, R, T)),
                    ("bottomleft", (0, fh - B, L, B)), ("bottomright", (fw - R, fh - B, R, B))):
        r.render(p, prefix + "-" + e, QRectF(x + rect[0], y + rect[1], rect[2], rect[3]))
    for e, rect in (("left", (0, T, L, ch)), ("right", (fw - R, T, R, ch)),
                    ("top", (L, 0, cw, T)), ("bottom", (L, fh - B, cw, B))):
        if rect[2] > 0 and rect[3] > 0:
            r.render(p, prefix + "-" + e, QRectF(x + rect[0], y + rect[1], rect[2], rect[3]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("theme_dir")
    ap.add_argument("out")
    ap.add_argument("--state", default="active", choices=["active", "inactive", "hover", "maximized"])
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--size", default="804x440")
    ap.add_argument("--bg", default="#1f2644")
    ap.add_argument("--client", default=None)
    ap.add_argument("--title", default="Appearance")
    ap.add_argument("--board-crop", nargs=2, metavar=("RENDER", "X,Y,W,H"))
    a = ap.parse_args()
    app = QGuiApplication(sys.argv[:1])  # noqa: F841
    fid = QFontDatabase.addApplicationFont(os.path.join(ROOT, "fonts", "manrope", "Manrope[wght].ttf"))
    family = QFontDatabase.applicationFontFamilies(fid)[0]

    name = os.path.basename(a.theme_dir.rstrip("/"))
    rc = read_rc(os.path.join(a.theme_dir, name + "rc"))
    lay = {k: int(v) for k, v in rc["Layout"].items()}
    gen = rc["General"]
    light = "Light" in name
    client = QColor(a.client or ("#ffffff" if light else "#1b2031"))
    active = a.state in ("active", "hover", "maximized")
    maximized = a.state == "maximized"

    sw, sh = (int(v) for v in a.size.split("x"))
    img = QImage(int(sw * a.scale), int(sh * a.scale), QImage.Format_ARGB32_Premultiplied)
    img.fill(QColor(a.bg))
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    p.setRenderHint(QPainter.SmoothPixmapTransform)
    p.scale(a.scale, a.scale)

    deco = QSvgRenderer(os.path.join(a.theme_dir, "decoration.svg"))
    if maximized:
        wx, wy, W, H = 0, 0, sw, sh
        title_h = lay["TitleHeight"] + lay["TitleEdgeTopMaximized"] + lay["TitleEdgeBottomMaximized"]
        paint_frame(p, deco, "decoration-maximized", wx, wy, W, H, maximized=True)
        edges = (lay["TitleEdgeLeftMaximized"], lay["TitleEdgeTopMaximized"], lay["TitleEdgeRightMaximized"])
        margin = lay.get("ButtonMarginTopMaximized", 0)
    else:
        # the board window is 700x250 including the 1 px edge
        wx, wy, W, H = 53, 43, 698, 248
        title_h = lay["TitleHeight"] + lay["TitleEdgeTop"] + lay["TitleEdgeBottom"]
        pl, pt, pr, pb = lay["PaddingLeft"], lay["PaddingTop"], lay["PaddingRight"], lay["PaddingBottom"]
        paint_frame(p, deco, "decoration" if active else "decoration-inactive",
                    wx - pl, wy - pt, W + pl + pr, H + pt + pb)
        edges = (lay["TitleEdgeLeft"], lay["TitleEdgeTop"], lay["TitleEdgeRight"])
        margin = lay.get("ButtonMarginTop", 0)
    p.fillRect(QRectF(wx, wy + title_h, W, H - title_h), client)

    # buttons: left group M (icon) for the right layout, X I A for the left layout
    left_layout = gen.get("TitleAlignment") == "Center"
    bw, bh = lay["ButtonWidth"], lay["ButtonHeight"]
    by = wy + edges[1] + margin
    st = "active" if active else "inactive"
    hover_btn = "maximize" if a.state == "hover" else None
    if left_layout:
        left = ["close", "minimize", "maximize"]
        right = []
        right_w = lay["ExplicitButtonSpacer"]
    else:
        left = ["menu"]
        right = ["minimize", "maximize", "close"]
        right_w = bw * 3
    x = wx + edges[0]
    for b in left:
        if b == "menu":
            iw = lay["ButtonWidthMenu"]
            icon = QSvgRenderer("/usr/share/icons/breeze/apps/48/systemsettings.svg")
            s = min(iw, bh)
            if icon.isValid():
                icon.render(p, QRectF(x + (iw - s) / 2, by + (bh - s) / 2, s, s))
            x += iw
            continue
        br = QSvgRenderer(os.path.join(a.theme_dir, ("restore" if (maximized and b == "maximize") else b) + ".svg"))
        state = ("hover" if active else "hover-inactive") if (a.state == "hover" and left_layout) else st
        br.render(p, state + "-center", QRectF(x, by, bw, bh))
        x += bw
    cap_left = x + lay["TitleBorderLeft"]
    rx = wx + W - edges[2] - right_w
    cap_right = rx - lay["TitleBorderRight"]
    for b in right:
        br = QSvgRenderer(os.path.join(a.theme_dir, ("restore" if (maximized and b == "maximize") else b) + ".svg"))
        state = "hover" if b == hover_btn else st
        br.render(p, state + "-center", QRectF(rx, by, bw, bh))
        rx += bw
    f = QFont(family)
    f.setPixelSize(14)
    f.setWeight(QFont.Weight.ExtraBold)
    f.setVariableAxis(QFont.Tag("wght"), 800)
    p.setFont(f)
    col = [int(v) for v in gen["ActiveTextColor" if active else "InactiveTextColor"].split(",")]
    p.setPen(QColor(*col[:3]))
    align = (Qt.AlignHCenter if left_layout else Qt.AlignLeft) | Qt.AlignVCenter
    p.drawText(QRectF(cap_left, wy + edges[1], cap_right - cap_left, max(lay["TitleHeight"], bh)), align, a.title)
    p.end()

    if a.board_crop:
        from PIL import Image
        ours = Image.frombuffer("RGBA", (img.width(), img.height()), bytes(img.constBits()), "raw", "BGRA", 0, 1)
        bx, by_, bw_, bh_ = (int(v) for v in a.board_crop[1].split(","))
        board = Image.open(a.board_crop[0]).convert("RGBA").crop((bx, by_, bx + bw_, by_ + bh_))
        if a.scale != 1:
            board = board.resize((int(bw_ * a.scale), int(bh_ * a.scale)), Image.LANCZOS)
        out = Image.new("RGBA", (board.width + ours.width + 8, max(board.height, ours.height)), (0, 0, 0, 255))
        out.paste(board, (0, 0))
        out.paste(ours, (board.width + 8, 0))
        out.save(a.out)
    else:
        img.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
