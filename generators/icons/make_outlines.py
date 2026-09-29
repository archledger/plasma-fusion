#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Maintainer tool: turn the stroked symbolic glyphs into filled outlines (outlines.json).

GTK 4 recolours -symbolic icons by forcing `fill` on every rect, circle and path and has no
rule for strokes, so line art drawn with strokes turns into filled blobs (seen with Nautilus
on Fedora 44). The symbolic icons are therefore shipped as filled outlines, like Breeze's.
Qt's QPainterPathStroker (the code QtSvg uses to draw strokes) computes the outline of every
stroke layer: 1.75 wide, round caps, round joins. gen_icons.py reads the committed table.

    QT_QPA_PLATFORM=offscreen python3 generators/icons/make_outlines.py
"""
import json
import math
import os
import re
import sys

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QGuiApplication, QPainterPath, QPainterPathStroker

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

TOKEN = re.compile(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')


def parse(d):
    """SVG path data -> QPainterPath (all commands; elliptical arcs as cubic segments)."""
    toks = TOKEN.findall(d)
    p = QPainterPath()
    i = 0
    cmd = None
    cx = cy = sx = sy = 0.0
    last_c = None   # last cubic control point (for S)
    last_q = None   # last quadratic control point (for T)

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    def flag():
        # arc flags may be written without separators ("0 1 0" or "01"); handle both
        nonlocal i
        t = toks[i]
        if len(t) > 1 and t[0] in '01' and not t.startswith('0.'):
            toks[i] = t[1:]
            return float(t[0])
        i += 1
        return float(t)

    while i < len(toks):
        t = toks[i]
        if re.fullmatch(r'[A-Za-z]', t):
            cmd = t
            i += 1
            if cmd in 'Zz':
                p.closeSubpath()
                cx, cy = sx, sy
                last_c = last_q = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (cx, cy) if rel else (0.0, 0.0)
        if c == 'M':
            x, y = num() + ox, num() + oy
            p.moveTo(x, y)
            cx, cy, sx, sy = x, y, x, y
            cmd = 'l' if rel else 'L'
            last_c = last_q = None
        elif c == 'L':
            x, y = num() + ox, num() + oy
            p.lineTo(x, y)
            cx, cy = x, y
            last_c = last_q = None
        elif c == 'H':
            x = num() + (cx if rel else 0.0)
            p.lineTo(x, cy)
            cx = x
            last_c = last_q = None
        elif c == 'V':
            y = num() + (cy if rel else 0.0)
            p.lineTo(cx, y)
            cy = y
            last_c = last_q = None
        elif c == 'C':
            x1, y1, x2, y2, x, y = (num() + ox, num() + oy, num() + ox, num() + oy, num() + ox, num() + oy)
            p.cubicTo(x1, y1, x2, y2, x, y)
            last_c, last_q = (x2, y2), None
            cx, cy = x, y
        elif c == 'S':
            x1, y1 = (2 * cx - last_c[0], 2 * cy - last_c[1]) if last_c else (cx, cy)
            x2, y2, x, y = num() + ox, num() + oy, num() + ox, num() + oy
            p.cubicTo(x1, y1, x2, y2, x, y)
            last_c, last_q = (x2, y2), None
            cx, cy = x, y
        elif c == 'Q':
            x1, y1, x, y = num() + ox, num() + oy, num() + ox, num() + oy
            p.quadTo(x1, y1, x, y)
            last_q, last_c = (x1, y1), None
            cx, cy = x, y
        elif c == 'T':
            x1, y1 = (2 * cx - last_q[0], 2 * cy - last_q[1]) if last_q else (cx, cy)
            x, y = num() + ox, num() + oy
            p.quadTo(x1, y1, x, y)
            last_q, last_c = (x1, y1), None
            cx, cy = x, y
        elif c == 'A':
            rx, ry, rot = num(), num(), num()
            large, sweep = flag(), flag()
            x, y = num() + ox, num() + oy
            arc(p, cx, cy, rx, ry, rot, large, sweep, x, y)
            cx, cy = x, y
            last_c = last_q = None
        else:
            raise ValueError('unsupported path command ' + cmd)
    return p


def arc(p, x1, y1, rx, ry, phi_deg, fa, fs, x2, y2):
    """SVG endpoint arc -> cubic Béziers (SVG 1.1 implementation notes, F.6.5)."""
    if rx == 0 or ry == 0 or (x1 == x2 and y1 == y2):
        p.lineTo(x2, y2)
        return
    phi = math.radians(phi_deg)
    cos_p, sin_p = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cos_p * dx + sin_p * dy
    y1p = -sin_p * dx + cos_p * dy
    rx, ry = abs(rx), abs(ry)
    lam = (x1p ** 2) / (rx ** 2) + (y1p ** 2) / (ry ** 2)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    coef = math.sqrt(max(0.0, num / den)) if den else 0.0
    if fa == fs:
        coef = -coef
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cos_p * cxp - sin_p * cyp + (x1 + x2) / 2
    cy = sin_p * cxp + cos_p * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a
    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not fs and dt > 0:
        dt -= 2 * math.pi
    elif fs and dt < 0:
        dt += 2 * math.pi
    n = max(1, int(math.ceil(abs(dt) / (math.pi / 2) - 1e-9)))
    step = dt / n
    k = 4 / 3 * math.tan(step / 4)
    for s in range(n):
        a1 = t1 + s * step
        a2 = a1 + step
        e1 = (math.cos(a1), math.sin(a1))
        e2 = (math.cos(a2), math.sin(a2))
        q1 = (e1[0] - k * e1[1], e1[1] + k * e1[0])
        q2 = (e2[0] + k * e2[1], e2[1] - k * e2[0])

        def tr(pt):
            x, y = pt[0] * rx, pt[1] * ry
            return cos_p * x - sin_p * y + cx, sin_p * x + cos_p * y + cy
        c1, c2, end = tr(q1), tr(q2), tr(e2)
        p.cubicTo(c1[0], c1[1], c2[0], c2[1], end[0], end[1])


def fnum(v):
    s = ('%.3f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def to_d(p):
    out = []
    i = 0
    n = p.elementCount()
    while i < n:
        e = p.elementAt(i)
        t = e.type
        if t == QPainterPath.ElementType.MoveToElement:
            if out:
                out.append('Z')
            out.append(f'M{fnum(e.x)} {fnum(e.y)}')
        elif t == QPainterPath.ElementType.LineToElement:
            out.append(f'L{fnum(e.x)} {fnum(e.y)}')
        elif t == QPainterPath.ElementType.CurveToElement:
            c2 = p.elementAt(i + 1)
            ep = p.elementAt(i + 2)
            out.append(f'C{fnum(e.x)} {fnum(e.y)} {fnum(c2.x)} {fnum(c2.y)} {fnum(ep.x)} {fnum(ep.y)}')
            i += 2
        i += 1
    if out:
        out.append('Z')
    return ''.join(out)


def outline(d, width):
    path = parse(d)
    st = QPainterPathStroker()
    st.setWidth(width)
    st.setCapStyle(Qt.PenCapStyle.RoundCap)
    st.setJoinStyle(Qt.PenJoinStyle.RoundJoin)
    st.setCurveThreshold(0.02)
    return to_d(st.createStroke(path))


def stroke_layers():
    import gen_icons
    import art_symbolic as sym
    reg = gen_icons.build_registry()
    keys = set()
    for layers in reg.glyphs.values():
        for d, role, kind, opacity, width in layers:
            if d and kind == 'stroke':
                keys.add((width or sym.STROKE, d))
    return keys


def main():
    app = QGuiApplication(sys.argv[:1])  # noqa: F841
    table = {}
    for width, d in sorted(stroke_layers()):
        table[f'{width}|{d}'] = outline(d, width)
    out = os.path.join(HERE, 'outlines.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(table, f, sort_keys=True, indent=0)
        f.write('\n')
    print('wrote', out, len(table), 'outlines', os.path.getsize(out), 'bytes')


if __name__ == '__main__':
    main()
