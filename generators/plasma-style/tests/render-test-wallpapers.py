#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render the Dusk Ridge wallpaper drawn inline in Main.dc.html / MainLight.dc.html (test use only).

    render-test-wallpapers.py OUTDIR   -> OUTDIR/wall-Main.png, OUTDIR/wall-MainLight.png (1440x900)
"""
import os
import re
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QByteArray  # noqa: E402
from PySide6.QtGui import QGuiApplication, QImage, QPainter  # noqa: E402
from PySide6.QtSvg import QSvgRenderer  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
app = QGuiApplication([])
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for name in ("Main", "MainLight"):
    html = open(os.path.join(ROOT, "design", "boards", f"{name}.dc.html"), encoding="utf-8").read()
    svg = re.search(r'<svg width="1440" height="900".*?</svg>', html, re.S).group(0)
    svg = svg.replace('aria-hidden="true" style="position:absolute;left:0;top:0"', 'xmlns="http://www.w3.org/2000/svg"')
    img = QImage(1440, 900, QImage.Format_RGB32)
    p = QPainter(img)
    QSvgRenderer(QByteArray(svg.encode())).render(p)
    p.end()
    img.save(os.path.join(out, f"wall-{name}.png"))
