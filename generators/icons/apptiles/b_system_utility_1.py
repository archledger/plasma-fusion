# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, batch system-utility-1 (KDE system tools and utilities).
import math

from apptiles.kit import *  # noqa: F401,F403
from textoutline import text_in_box


def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pt(cx, cy, r, a):
    """Point on a circle; a in degrees, 0 = +x, positive = clockwise on screen."""
    t = math.radians(a)
    return cx + r * math.cos(t), cy + r * math.sin(t)


def band(cx, cy, ro, ri, a0, a1):
    """Annular sector from a0 to a1 (clockwise)."""
    p0 = pt(cx, cy, ro, a0); p1 = pt(cx, cy, ro, a1)
    q1 = pt(cx, cy, ri, a1); q0 = pt(cx, cy, ri, a0)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{_f(p0[0])} {_f(p0[1])}A{_f(ro)} {_f(ro)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}"
            f"L{_f(q1[0])} {_f(q1[1])}A{_f(ri)} {_f(ri)} 0 {large} 0 {_f(q0[0])} {_f(q0[1])}z")


def wedge(cx, cy, r, a0, a1):
    p0 = pt(cx, cy, r, a0); p1 = pt(cx, cy, r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{_f(cx)} {_f(cy)}L{_f(p0[0])} {_f(p0[1])}"
            f"A{_f(r)} {_f(r)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}z")


def half_disc(cx, cy, r, a0):
    """Half disc from angle a0 clockwise to a0 + 180, closed by the chord."""
    p0 = pt(cx, cy, r, a0); p1 = pt(cx, cy, r, a0 + 180)
    return f"M{_f(p0[0])} {_f(p0[1])}A{_f(r)} {_f(r)} 0 0 1 {_f(p1[0])} {_f(p1[1])}z"


def ci_cw(cx, cy, r):
    """Circle drawn clockwise, so it unions with rr() shapes in a nonzero layer (ci() runs the other way)."""
    return (f"M{_f(cx - r)} {_f(cy)}a{_f(r)} {_f(r)} 0 1 1 {_f(2 * r)} 0"
            f"a{_f(r)} {_f(r)} 0 1 1 {_f(-2 * r)} 0z")


def xform(pts, ang, tx, ty):
    """Rotate points by ang degrees about the origin, then translate."""
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(x * c - y * s + tx, x * s + y * c + ty) for x, y in pts]


def cw(pts):
    """Clockwise (on screen) orientation, so nonzero unions never cancel."""
    a = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]))
    return pts if a > 0 else pts[::-1]


def rr_pts(w, h, r, n=5):
    """Rounded rectangle centred on the origin, as a point list (for rotated cards)."""
    pts = []
    for (cx, cy, a0) in ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0),
                         (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def rot_rr(cx, cy, w, h, r, ang):
    return poly(*xform(rr_pts(w, h, r), ang, cx, cy))


def rot_poly(pts, ang, cx, cy):
    return poly(*xform(pts, ang, cx, cy))


def inset(pts, d):
    """Inset a convex polygon (clockwise on screen) by d units."""
    pts = cw(pts)
    n = len(pts)
    lines = []
    for i in range(n):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
        ex, ey = x1 - x0, y1 - y0
        L = math.hypot(ex, ey)
        nx, ny = -ey / L, ex / L          # inward normal for a clockwise (screen) polygon
        lines.append(((x0 + nx * d, y0 + ny * d), (ex, ey)))
    out = []
    for i in range(n):
        (p, e), (q, g) = lines[i - 1], lines[i]
        den = e[0] * g[1] - e[1] * g[0]
        t = ((q[0] - p[0]) * g[1] - (q[1] - p[1]) * g[0]) / den
        out.append((p[0] + t * e[0], p[1] + t * e[1]))
    return out


def cube(cx, cy, s, gap=0.9):
    """Flat isometric cube: three faces with small gaps between them."""
    w = s * math.cos(math.radians(30))
    T, UR, LR = (cx, cy - s), (cx + w, cy - s / 2), (cx + w, cy + s / 2)
    B, LL, UL, C = (cx, cy + s), (cx - w, cy + s / 2), (cx - w, cy - s / 2), (cx, cy)
    faces = [[T, UR, C, UL], [UL, C, B, LL], [C, UR, LR, B]]
    return ''.join(poly(*inset(fc, gap)) for fc in faces)


def wrench(hx, hy, ang, r=6.5, slot=2.4, depth=-0.5, hw=2.8, length=22.0):
    """Open-end wrench: head centred on (hx, hy), jaw opening away from the handle, handle along ang."""
    a0 = math.degrees(math.asin(slot / r))
    head = [(depth, -slot)]
    for k in range(41):
        a = 180 + a0 + (360 - 2 * a0) * k / 40
        head.append((r * math.cos(math.radians(a)), r * math.sin(math.radians(a))))
    head.append((depth, slot))
    handle = rr_pts(length, 2 * hw, hw - 0.01, 6)
    handle = [(x + length / 2 + r * 0.4, y) for x, y in handle]
    return (poly(*cw(xform(head, ang, hx, hy))) + poly(*cw(xform(handle, ang, hx, hy))))


# ---------------------------------------------------------------------------------------------
# KCharSelect: the letter a with a grave accent (the app's own mark).
_A = text_in_box('a', 'manrope-800', 48, (0, 3, 64, 54))
_GRAVE = poly((23.5, 11.5), (28.5, 9), (35, 17.5), (31.5, 19.5))

# KDiskFree: three cubes stacked as a pyramid.
_CS = 10.5
_CW = _CS * math.cos(math.radians(30))
_CUBE_TOP = cube(32, 21, _CS)
_CUBE_L = cube(32 - _CW - 1.2, 39, _CS)
_CUBE_R = cube(32 + _CW + 1.2, 39, _CS)

# KeepSecret: two tilted cards.
_CARD_BACK = rot_rr(29, 25, 34, 22, 3.5, -24)
_CARD_FRONT = rot_rr(33, 33, 38, 25, 3.5, -10)
_PHOTO = rot_rr(25.5, 34.5, 11, 13, 2, -10)
_PERSON = (poly(*xform([(x - 0.0, y) for x, y in [(-3.8, 6.5), (3.8, 6.5), (3.8, 4.5), (2.2, 2.2), (-2.2, 2.2), (-3.8, 4.5)]], -10, 25.5, 34.5))
           + ci(*xform([(0, -1.5)], -10, 25.5, 34.5)[0], 2.8))
_CARD_LINES = ''.join("M{} {}L{} {}".format(*map(_f, (*a, *b))) for a, b in (
    (xform([(-1, -7)], -10, 37, 33)[0], xform([(9, -7)], -10, 37, 33)[0]),
    (xform([(-1, -1.5)], -10, 37, 33)[0], xform([(7, -1.5)], -10, 37, 33)[0]),
    (xform([(-1, 4)], -10, 37, 33)[0], xform([(9, 4)], -10, 37, 33)[0])))

# KFind: binoculars in front of a gear.
_BINO = (ci_cw(22, 39, 9) + ci_cw(42, 39, 9) + rr(26, 27.5, 12, 8, 2)
         + 'M16 39V28a3.5 3.5 0 0 1 3.5-3.5h5A3.5 3.5 0 0 1 28 28v11z'
         + 'M36 39V28a3.5 3.5 0 0 1 3.5-3.5h5A3.5 3.5 0 0 1 48 28v11z')
_LENS = ci(22, 39, 5.6) + ci(42, 39, 5.6)

# KFloppy: floppy disk with a wrench across it.
_WRENCH = wrench(21, 21.5, 45, r=6.8, slot=2.5, depth=0.0, hw=3.0, length=24)


TILES = {
    # review: green-2 instead of purple; on purple it was a second Evolution (white envelope with a badge),
    # and teal would copy board:mail (the generic mail tile)
    'accountwizard': dict(label='Account Wizard', base='#2f9e6e', lip='#227650',
                          g1=rr(19, 9, 26, 26, 3), c1='#b3e3cc',
                          g2=rr(12, 25, 40, 22, 4), c2='#ffffff',
                          s1='M14.5 27.5 32 39l17.5-11.5M33.5 12.5l4.5 4-4.5 4', sc='#2f9e6e', sw=3,
                          g3=ci(24, 20.5, 1.7) + ci(28.5, 16.5, 1.7), c3='#2f9e6e',
                          x=[('M47.5 9.5l1.4 3.6 3.6 1.4-3.6 1.4-1.4 3.6-1.4-3.6-3.6-1.4 3.6-1.4z', '#f7c948')]),
    # review: purple instead of amber; a cream box on amber was board:archive (File Roller, Engrampa) at 32 px
    'arca': dict(label='Arca', base='#7b5cd6', lip='#5a40a8',
                 g1=rr(23, 10, 18, 18, 2.5), c1='#f7c948',
                 g2=rr(14, 15.5, 15, 14, 2.5) + rr(36, 14.5, 14, 14, 2.5), c2='#3cc4b0',
                 g3=rr(12, 23, 40, 26, 3.5), c3='#fbe7c6',
                 x=[(rr(30.6, 23, 2.8, 12, 0.5) + ''.join(rr(28.2, y, 3.6, 2.4, 1.1) + rr(32.2, y + 2.2, 3.6, 2.4, 1.1) for y in (24, 28.4))
                     + rr(28.5, 33.5, 7, 4.5, 1.5) + rr(29.5, 36, 5, 9.5, 2.5), '#8a5a20')]),
    'ark': dict(label='Ark', base='#5b6478', lip='#414859',
                g1=rr(15, 9, 34, 41, 4), c1='#ffffff',
                x=[(rr(29.5, 9, 5, 26, 0.5)
                    + ''.join(rr(26, y, 5, 2.6, 1.2) for y in (11, 16.5, 22, 27.5))
                    + ''.join(rr(33, y + 2.75, 5, 2.6, 1.2) for y in (11, 16.5, 22, 27.5))
                    + rr(27.5, 33, 9, 6.5, 2) + rr(29, 38, 6, 9, 3), '#1b2031'),
                   (rr(30.75, 41, 2.5, 3.5, 1.25), '#ffffff')]),
    'kalk': dict(label='Calculator', base='#e8743b', lip='#b8552a',
                 g1=rr(12.5, 11, 18, 18, 4.5) + rr(12.5, 31, 18, 18, 4.5) + rr(33.5, 11, 18, 38, 4.5), c1='#ffffff',
                 s1='M21.5 15.5v9M17 20h9M17 40h9M38 26.5h9M38 33.5h9', sc='#e8743b', sw=3.2),
    'kclock': dict(label='Clock', base='#2b8be6', lip='#1f68b3',
                   g1=ci(32, 30, 18.5), c1='#ffffff',
                   g2=ci(32, 30, 15), c2='#2b8be6',
                   s1='M32 30 24.5 22.5M32 30 41 25', sc='#ffffff', sw=3.2,
                   x=[(poly(*xform([(-1.25, 0), (1.25, 0), (1.25, 13), (-1.25, 13)], -22, 32, 30)), '#e5484d'),
                      (ci(32, 30, 2.6), '#ffffff')]),
    'filelight': dict(label='Filelight', base='#2f9e6e', lip='#227650',
                      g1=band(32, 30, 15.5, 11, 280, 520) + band(32, 30, 15.5, 11, 175, 265), c1='#bfeccf',
                      g2=band(32, 30, 20, 16.6, 180, 265) + band(32, 30, 20, 16.6, 0, 95), c2='#1b2031',
                      g3=ring(32, 30, 9, 4.2), c3='#ffffff'),
    'francis': dict(label='Francis', base='#3a7bd5', lip='#2a5ea8',
                    g1=ci(32, 30, 18), c1='#fbe9c8',
                    g2='M17.5 30A14.5 14.5 0 0 0 46.5 30z', c2='#a8682a',
                    g3=ci(37.5, 23.5, 7), c3='#e5484d'),
    'hashomatic': dict(label='Hash-o-matic', base='#9b3fb5', lip='#742d88',
                       s1='M28.5 12.5 23.5 47.5M41.5 12.5 36.5 47.5M14.5 23.5h35M14.5 36.5h35', sc='#ffffff', sw=4.8),
    'khelpcenter': dict(label='Help Center', base='#2b8be6', lip='#1f68b3',
                        g2=ring(32, 30, 18.5, 9), c2='#ffffff',
                        g3=''.join(band(32, 30, 18.5, 9, a - 20, a + 20) for a in (45, 135, 225, 315)), c3='#e5484d'),
    'index': dict(label='Index', base='#f5c84c', lip='#c99a22',
                  g1='M13 19a4 4 0 0 1 4-4h9l4 4h17a4 4 0 0 1 4 4v19H13z', c1='#fff1c9',
                  g2=rr(13, 24, 38, 22, 4), c2='#ffffff',
                  g3=''.join(rr(x, y, 7, 6, 1.6) for x in (18, 28.5, 39) for y in (28.5, 37)), c3='#e9a92a'),
    # review: blue base and an ink chip; on green it was Okteta's twin (green board, chip with pins)
    'kinfocenter': dict(label='Info Center', base='#2b8be6', lip='#1f68b3',
                        g1=''.join(rr(c - 1.5, 11, 3, 6, 1.2) + rr(c - 1.5, 43, 3, 6, 1.2)
                                   + rr(12, c - 1.5, 6, 3, 1.2) + rr(46, c - 1.5, 6, 3, 1.2) for c in (23, 32, 41))
                        , c1='#bcd4ff',
                        g2=rr(16, 14, 32, 32, 5), c2='#1b2031',
                        g3=ring(32, 30, 11.5, 9), c3='#ffffff',
                        x=[(ci(32, 24.5, 2.3) + rr(30, 28, 4, 9.5, 1.5), '#ffffff')]),
    'isoimagewriter': dict(label='ISO Image Writer', base='#3f7fe0', lip='#2b5db5',
                           g1=rr(22.5, 9, 19, 19, 2.5), c1='#bcd4ff',
                           g2=rr(19, 24, 26, 26, 4.5), c2='#ffffff',
                           g3=ring(32, 37, 8, 2.6), c3='#3f7fe0',
                           x=[(rr(26, 13, 4.5, 5, 1) + rr(33.5, 13, 4.5, 5, 1), '#f2a65a')]),
    'kjournaldbrowser': dict(label='Journald Browser', base='#262c42', lip='#131726',
                             g1='M17 14l4.2 1.6v3.2c0 3-1.8 4.9-4.2 5.8c-2.4-.9-4.2-2.8-4.2-5.8v-3.2z', c1='#e5484d',
                             g2=ci(17, 31, 3.8) + ci(17, 42, 3.8), c2='#5b9dff',
                             g3=rr(25, 17.4, 10, 3.2, 1.6) + rr(25, 29.4, 15, 3.2, 1.6) + rr(25, 40.4, 8, 3.2, 1.6), c3='#ffffff',
                             x=[(rr(37.5, 17.4, 12, 3.2, 1.6) + rr(42.5, 29.4, 7, 3.2, 1.6) + rr(35.5, 40.4, 14, 3.2, 1.6),
                                 '#7c86a3')]),
    'kalarm': dict(label='KAlarm', base='#c93a42', lip='#992a31',
                   g1=half_disc(19.5, 19, 6.8, 135) + half_disc(44.5, 19, 6.8, 225), c1='#ffffff',
                   g2=ci(32, 31.5, 17), c2='#c93a42',
                   s1=ci(32, 31.5, 13) + 'M32 31.5V22.5M32 31.5 26.5 37M23.5 41.5l-3 4M40.5 41.5l3 4',
                   sc='#ffffff', sw=3.2,
                   x=[(ci(32, 31.5, 2.6), '#ffffff')]),
    'kalm': dict(label='Kalm', base='#1f9e8f', lip='#15756a',
                 g1=poly((14.5, 18.5), (23.5, 22.5), (24.5, 31), (17, 27.5)) + poly((49.5, 18.5), (40.5, 22.5), (39.5, 31), (47, 27.5)),
                 c1='#9fe3d6',
                 g2='M32 10C40.5 17.5 40.5 34.5 32 45C23.5 34.5 23.5 17.5 32 10z', c2='#1b2031',
                 g3='M29.5 47.5C19.5 47 11.5 40 10 28.5C17.5 29.5 24.5 34 29 41.5z'
                    'M34.5 47.5C44.5 47 52.5 40 54 28.5C46.5 29.5 39.5 34 35 41.5z', c3='#ffffff'),
    'kbackup': dict(label='KBackup', base='#c2410c', lip='#922f08',
                    g1='M28.5 10h14l9 9v26a3 3 0 0 1-3 3H28.5a3 3 0 0 1-3-3V13a3 3 0 0 1 3-3z', c1='#ffffff',
                    g2='M15.5 24h18l4 4v17a3 3 0 0 1-3 3H15.5a3 3 0 0 1-3-3V27a3 3 0 0 1 3-3z', c2='#1b2031',
                    s1='M30.5 16h8M30.5 21h12M41.5 27h6M41.5 33h6M41.5 39h6', sc='#c2410c', sw=2.6,
                    x=[(rr(18.5, 24, 12, 7.5, 1.2), '#cfd5e4'), (rr(16.5, 35, 17, 10, 1.6), '#ffffff')]),
    'kcharselect': dict(label='KCharSelect', base='#3b4255', lip='#262b38',
                        g1=_A, c1='#ffffff',
                        g3=_GRAVE, c3='#f2a65a'),
    'partitionmanager': dict(label='KDE Partition Manager', base='#f4f5f9', lip='#d5d9e3',
                             g1=wedge(32, 27, 15, 180, 270), c1='#3cc4b0',
                             g2=wedge(32, 27, 15, 270, 360), c2='#5b9dff',
                             g3=wedge(32, 27, 15, 90, 180), c3='#f7c948',
                             x=[(wedge(32, 27, 15, 0, 90), '#7b5cd6'), (ci(32, 27, 4.5), '#f4f5f9'),
                                (rr(19, 45, 26, 4, 2), '#1b2031'), (rr(36, 46, 6, 2, 1), '#f2a65a')]),
    'kdebugsettings': dict(label='KDebugSettings', base='#d6457a', lip='#a8325d',
                           g1=el(32, 35.5, 9.5, 12) + ci(32, 21, 5.5), c1='#ffffff',
                           s1='M23 30 15.5 26.5M22.5 36.5H14.5M23.5 42.5 16.5 47M41 30l7.5-3.5M41.5 36.5h8M40.5 42.5l7 4.5'
                              'M29 17 26 12.5M35 17l3-4.5', sc='#ffffff', sw=2.6,
                           g3=rr(30.8, 26.5, 2.4, 20, 1.2), c3='#d6457a'),
    'kdf': dict(label='KDiskFree', base='#2c3348', lip='#1a1f2e',
                g1=_CUBE_TOP, c1='#5b9dff',
                g2=_CUBE_L, c2='#f2a65a',
                g3=_CUBE_R, c3='#3cc4b0'),
    'keepsecret': dict(label='KeepSecret', base='#475069', lip='#323950',
                       g1=_CARD_BACK, c1='#5b9dff',
                       g2=_CARD_FRONT, c2='#ffffff',
                       s1=_CARD_LINES, sc='#475069', sw=2.6,
                       g3=_PHOTO, c3='#f2a65a',
                       x=[(_PERSON, '#ffffff')]),
    'keysmith': dict(label='Keysmith', base='#1aa391', lip='#127a6c',
                     s1='M23.5 27V22a8.5 8.5 0 0 1 17 0v5', sc='#ffffff', sw=4.5,
                     g1=ci(32, 35, 13.5), c1='#ffffff',
                     g3=ring(32, 35, 8, 4.5), c3='#1aa391',
                     x=[(''.join(ci(*pt(32, 35, 10.8, a), 1.3) for a in (0, 45, 90, 135, 180, 225, 315)), '#1aa391'),
                        (rr(30.6, 22, 2.8, 4, 1.2), '#e5484d')]),
    'kfind': dict(label='KFind', base='#e8743b', lip='#b8552a',
                  g1=gear(32, 22.5, 12.5, 9.7, 8), c1='#ffd3b8',
                  g2=ci(32, 22.5, 4.2), c2='#e8743b',
                  x=[(_BINO, '#1b2031'), (_LENS, '#f2a65a')]),
    'kfloppy': dict(label='KFloppy', base='#3d4db7', lip='#2c388a',
                    g1='M18 11h24l9 9v25a3 3 0 0 1-3 3H18a3 3 0 0 1-3-3V14a3 3 0 0 1 3-3z', c1='#ffffff',
                    g2=rr(23, 11, 17, 11, 1.5) + rr(20, 30, 26, 18, 2), c2='#c6ccf2',
                    s1=_WRENCH, sc='#3d4db7', sw=3,
                    g3=_WRENCH, c3='#f7c948'),
    'kgpg': dict(label='KGpg', base='#5a2ca0', lip='#3e1e70',
                 s1='M23.5 27v-6a8.5 8.5 0 0 1 17 0v6', sc='#d9ccff', sw=4.5,
                 g1=rr(16, 26, 32, 23, 5), c1='#ffffff',
                 g3=ci(32, 35, 3.4) + poly((30.3, 36), (33.7, 36), (34.6, 43), (29.4, 43)), c3='#5a2ca0'),
}

APPS = {
    'org.kde.accountwizard': 'accountwizard',
    'org.kde.arca': 'arca',
    'org.kde.ark': 'ark',
    'org.kde.kalk': 'kalk',
    'org.kde.kclock': 'kclock',
    'org.kde.discover': 'board:software',
    'org.kde.dolphin': 'round1:dolphin',
    'org.kde.filelight': 'filelight',
    'org.kde.francis': 'francis',
    'org.kde.hashomatic': 'hashomatic',
    'org.kde.khelpcenter': 'khelpcenter',
    'org.kde.index': 'index',
    'org.kde.kinfocenter': 'kinfocenter',
    'org.kde.isoimagewriter': 'isoimagewriter',
    'org.kde.kjournaldbrowser': 'kjournaldbrowser',
    'org.kde.kalarm': 'kalarm',
    'org.kde.kalm': 'kalm',
    'org.kde.kbackup': 'kbackup',
    'org.kde.kcalc': 'board:calculator',
    'org.kde.kcharselect': 'kcharselect',
    'org.kde.partitionmanager': 'partitionmanager',
    'org.kde.kdebugsettings': 'kdebugsettings',
    'org.kde.kdf': 'kdf',
    'org.kde.keepsecret': 'keepsecret',
    'org.kde.keysmith': 'keysmith',
    'org.kde.kfind': 'kfind',
    'org.kde.kfloppy': 'kfloppy',
    'org.kde.kgpg': 'kgpg',
}
