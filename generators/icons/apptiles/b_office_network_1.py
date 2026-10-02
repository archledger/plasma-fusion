# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, batch office-network-1 (KDE office, PIM and network apps).
import math
import re

from apptiles.kit import *  # noqa: F401,F403  rr, ci, el, gear, ring, poly, f, ...


# ---- local helpers -------------------------------------------------------------------------
def _p(x, y):
    return f"{f(x)} {f(y)}"


def _on(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def arc(cx, cy, r, a0, a1):
    """Open arc for strokes; degrees, screen coordinates (0 = right, 90 = down)."""
    large = 1 if abs(a1 - a0) > 180 else 0
    sweep = 1 if a1 > a0 else 0
    return f"M{_p(*_on(cx, cy, r, a0))}A{f(r)} {f(r)} 0 {large} {sweep} {_p(*_on(cx, cy, r, a1))}"


def band(cx, cy, ri, ro, a0, a1):
    """Filled ring sector between radii ri and ro, angles a0 to a1 (degrees)."""
    large = 1 if abs(a1 - a0) > 180 else 0
    sw = 1 if a1 > a0 else 0
    return (f"M{_p(*_on(cx, cy, ro, a0))}A{f(ro)} {f(ro)} 0 {large} {sw} {_p(*_on(cx, cy, ro, a1))}"
            f"L{_p(*_on(cx, cy, ri, a1))}A{f(ri)} {f(ri)} 0 {large} {1 - sw} {_p(*_on(cx, cy, ri, a0))}z")


def cc(cx, cy, r):
    """Clockwise circle: unions with clockwise shapes in a nonzero layer (g1) leave no holes."""
    return f"M{f(cx - r)} {f(cy)}a{f(r)} {f(r)} 0 1 1 {f(2 * r)} 0a{f(r)} {f(r)} 0 1 1 {f(-2 * r)} 0z"


_NUM = re.compile(r'-?(?:\d+\.?\d*|\.\d+)')


def xf(d, ang=0, cx=0, cy=0, s=1):
    """Scale, rotate (degrees) and move a path drawn around (0, 0) with absolute M/L/C/Q/Z only."""
    a = math.radians(ang)
    c, sn = math.cos(a), math.sin(a)
    out = []
    for cmd, args in re.findall(r'([MLCQZz])([^MLCQZz]*)', d):
        if cmd in 'Zz':
            out.append('z')
            continue
        n = [float(v) for v in _NUM.findall(args)]
        pts = []
        for i in range(0, len(n), 2):
            x, y = n[i] * s, n[i + 1] * s
            pts.append(_p(cx + x * c - y * sn, cy + x * sn + y * c))
        out.append(cmd + ' '.join(pts))
    return ''.join(out)


def tpoly(pts, ang=0, cx=0, cy=0, s=1):
    a = math.radians(ang)
    c, sn = math.cos(a), math.sin(a)
    return poly(*[(cx + s * (x * c - y * sn), cy + s * (x * sn + y * c)) for x, y in pts])


# ---- shared motifs ---------------------------------------------------------------------------
# Calligra fountain-pen nib (from the Calligra / Calligra Words originals), tip up, around (0, 0).
NIB = 'M0 -12 C3 -6.5 8 -2.5 8 3 C8 5.5 6.8 7.5 5 9 L-5 9 C-6.8 7.5 -8 5.5 -8 3 C-8 -2.5 -3 -6.5 0 -12 z'
NIB_CUT = 'M-1.2 -9.5 L1.2 -9.5 L1.2 -1.4 L-1.2 -1.4 z'  # slit (evenodd hole)
NIB_BAND = 'M-7 9.5 L7 9.5 L7 14 L-7 14 z'
NIB_GRIP = 'M-5 14 L5 14 L5 20 L-5 20 z'


def nib(ang, cx, cy, s=1):
    """The nib turned by ang degrees around its centre, moved to (cx, cy): body (with slit and
    breather hole as even-odd cuts), band and grip paths."""
    a = math.radians(ang)
    hx, hy = -1.2 * math.sin(a), 1.2 * math.cos(a)  # breather hole at (0, 1.2), turned
    return dict(body=xf(NIB, ang, cx, cy, s) + xf(NIB_CUT, ang, cx, cy, s) + ci(cx + s * hx, cy + s * hy, 2.4 * s),
                band=xf(NIB_BAND, ang, cx, cy, s), grip=xf(NIB_GRIP, ang, cx, cy, s))


# Crow Translate feather, upright around (0, 0): vane with barb notches, green sheen.
CROW_VANE = ('M0 16 Q-6 12 -7.5 6.5 L-2.5 5.5 L-8.5 1.5 Q-9 -3 -8 -6 L-3 -6.5 L-7.5 -10.5 Q-5 -18 0 -23 '
             'Q4 -16 5.5 -8 L1.5 -6 L5.5 -3.5 Q5.5 8 0 16 z')
CROW_SHEEN = 'M0.8 -16.5 Q3.8 -12 4.8 -8.3 L1 -6.2 z'

# Blogilo's bold B, top-left corner at (0, 0), 25.7 x 32.
B_OUT = ('M0 0 L15 0 C20.5 0 24 3.3 24 8 C24 11.2 22.4 13.6 19.8 14.9 C23.4 16.1 25.7 18.9 25.7 23 '
         'C25.7 28.6 21.6 32 15.5 32 L0 32 z')
B_CUT = ('M6.5 5.5 L14 5.5 C16.2 5.5 17.6 6.8 17.6 8.8 C17.6 10.8 16.2 12.2 14 12.2 L6.5 12.2 z'
         'M6.5 17.5 L15.3 17.5 C18 17.5 19.6 19.3 19.6 22 C19.6 24.7 18 26.5 15.3 26.5 L6.5 26.5 z')


def kde_logo(cx, cy, s):
    """KDE logo: a C-shaped gear open to the right around a K."""
    pts = []
    teeth = [100, 140, 180, 220, 260]
    a = 60.0
    while a <= 300.001:
        r = 7.2
        for t in teeth:
            if abs(a - t) <= 9:
                r = 9.2
        pts.append(_on(0, 0, r, a))
        a += 1.5
    a = 300.0
    while a >= 60:
        pts.append(_on(0, 0, 5.0, a))
        a -= 3
    gear_c = poly(*[(cx + s * x, cy + s * y) for x, y in pts])
    k = (tpoly([(-2.6, -5.2), (0.6, -5.2), (0.6, 5.2), (-2.6, 5.2)], 0, cx, cy, s)
         + tpoly([(0.2, -0.8), (5.6, -8.6), (9.6, -8.6), (3.4, 0.6)], 0, cx, cy, s)
         + tpoly([(0.2, 0.8), (3.4, -0.6), (9.6, 8.6), (5.6, 8.6)], 0, cx, cy, s))
    return gear_c, k


# Itinerary airliner, side view, nose to the left, around (0, 0).
_FUSE = ([(-15 + 3.4 * math.cos(math.radians(a)), 3.4 * math.sin(math.radians(a))) for a in range(90, 271, 15)]
         + [(12, -3.4), (18.5, -3.4), (18.5, -1.8), (9, 3.4)])
_FIN = [(11, -3), (15.5, -12), (19, -12), (18.5, -3)]
_WING = [(-4, 1.5), (3, 1.5), (9.5, 10), (6, 10)]


# KMyMoney coin: the laurel as short arcs on the silver rim, open at top and bottom.
def laurel(cx, cy, r):
    d = ''
    for a in (120, 145, 170, 195, 220):
        d += arc(cx, cy, r, a, a + 13)
    for a in (60, 35, 10, -15, -40):
        d += arc(cx, cy, r, a, a - 13)
    return d


_kde = kde_logo(32, 31, 1.15)
_cw = nib(0, 32, 26.5)
_ww = nib(-135, 36.5, 30.5, 0.95)

TILES = {
    # RSS feed glyph, as the original.
    'akregator': dict(label='Akregator', base='#e8743b', lip='#b8552a',
                      g1=ci(20.5, 41.5, 4.6), c1='#ffffff',
                      s1='M20.5 28a13.5 13.5 0 0 1 13.5 13.5M20.5 17a24.5 24.5 0 0 1 24.5 24.5',
                      sc='#ffffff', sw=4.6),
    # Green alligator head whose open jaws hold the RSS arcs.
    'alligator': dict(label='Alligator', base='#ea8b25', lip='#b06819',
                      g1=(poly((12.5, 36), (21.5, 11), (30, 11.5), (21.5, 39))
                          + poly((14, 40), (49.5, 35), (53.5, 37.5), (52.5, 42), (18, 49))
                          + cc(19, 41, 8) + cc(26.2, 13, 3.8) + cc(16, 30.5, 6.2)),
                      c1='#3cc4b0',
                      g2=band(21.5, 39, 8, 12.5, -66, -12) + band(21.5, 39, 16.5, 21, -68, -9), c2='#ffffff',
                      x=[(ci(16, 30.5, 4.1), '#ffffff'), (ci(16.9, 30.7, 2.1), '#1b2031')]),
    # Angelfish: the fish whose body is a globe (yellow land), yellow tail.
    'angelfish': dict(label='Angelfish', base='#1d8fc0', lip='#156b90',
                      g1='M41 24 L52 15.5 C53.5 15 54 16 54 17.5 L54 33 C54 34.5 53 35 51.5 34.5 L42 31 z',
                      c1='#f7c948',
                      g2=('M12 33 C14 26 18 21.5 22.5 19.5 C27 15.5 32 13.5 37 13.5 C40 13.5 43 15 44.5 18 '
                          'C46 24 46 33 44 39.5 C42 43.5 38 45.5 33 45.5 C25 45.5 16 41 12 33 z'),
                      c2='#ffffff',
                      g3=('M23.5 20.5 C28 17 33 15 38.5 15.5 C40.5 18 40 21 37 22.5 C34.5 22.5 33 24.5 30.5 26 '
                          'C27.5 25.5 25 23.5 23.5 20.5 z'
                          'M25.5 29 C29.5 27.5 34 28.5 36.5 31.5 C37 35.5 34.5 40 31.5 44.5 C29.5 40.5 27.5 37 25.5 33 z'
                          'M39.5 26.5 C42 26 44 27.5 44.8 30 C44.5 34 43 36.5 40.5 38.5 C39.5 35 39 30.5 39.5 26.5 z'),
                      c3='#f7c948',
                      x=[(ci(17.5, 31.5, 2.4), '#1b2031')]),
    # Book with the sun-and-labyrinth cover.
    'arianna': dict(label='Arianna', base='#e99f2b', lip='#af771f',
                    g1=rr(16, 9.5, 32, 40, 3.5), c1='#ffffff',
                    g2='M19.5 9.5h3.5v40h-3.5a3.5 3.5 0 0 1-3.5-3.5v-33a3.5 3.5 0 0 1 3.5-3.5z', c2='#fbe0b5',
                    s1=(arc(23, 9.5, 13.5, 6, 84) + arc(23, 9.5, 20, 5, 85) + arc(23, 9.5, 26.5, 32, 87)
                        + 'M' + _p(*_on(23, 9.5, 9, 22)) + 'L' + _p(*_on(23, 9.5, 23.5, 22))
                        + 'M' + _p(*_on(23, 9.5, 9, 50)) + 'L' + _p(*_on(23, 9.5, 33, 50))
                        + 'M' + _p(*_on(23, 9.5, 9, 75)) + 'L' + _p(*_on(23, 9.5, 36.5, 75))),
                    sc='#e99f2b', sw=2.6,
                    g3='M23 9.5h7.5a7.5 7.5 0 0 1-7.5 7.5z', c3='#e99f2b'),
    # Bold B with a pen, on the blue of the original window.
    'blogilo': dict(label='Blogilo', base='#2e5fc0', lip='#22478f',
                    g2=xf(B_OUT, 0, 12.5, 15.5) + xf(B_CUT, 0, 12.5, 15.5), c2='#ffffff',
                    s1='M50 12.5L43.3 32', sc='#f2a65a', sw=5,
                    x=[(poly((45.8, 32.9), (40.8, 31.2), (40.4, 40.5)), '#ffffff')]),
    # Month grid under the board calendar's red header (KOrganizer keeps the date page).
    # review: a calendar page on teal; the full-bleed red header on the light base copied KOrganizer's
    # board:calendar tile almost exactly at 32 px
    'calindori': dict(label='Calindori', base='#1f9e8f', lip='#15756a',
                      g1=rr(12, 12.5, 40, 37, 5), c1='#ffffff',
                      g2='M17 12.5h30a5 5 0 0 1 5 5v5.5H12v-5.5a5 5 0 0 1 5-5z'
                         + rr(15.6 + 8.6 * 2, 27.2 + 7 * 1, 7, 5.2, 1.4), c2='#e5484d',
                      g3=''.join(rr(15.6 + 8.6 * c, 27.2 + 7 * r, 7, 5.2, 1.4)
                                 for r in range(3) for c in range(4) if (r, c) != (1, 2)), c3='#c7ccd8',
                      x=[(rr(20.5, 8.6, 4.4, 8.4, 2.2) + rr(39.1, 8.6, 4.4, 8.4, 2.2), '#ffffff')]),
    # Calligra: the nib on a framed board, as the original.
    'calligra': dict(label='Calligra', base='#f6f4ef', lip='#d6d0c2',
                     g2=_cw['body'], c2='#5b6478',
                     s1=rr(15, 11, 34, 37, 2), sc='#b7792f', sw=3.5,
                     g3=_cw['grip'], c3='#5b6478',
                     x=[(_cw['band'], '#f2a65a')]),
    # Calligra Sheets: bar and area chart above a table.
    'calligra-sheets': dict(label='Calligra Sheets', base='#2f9e6e', lip='#227650',
                            g1=(''.join(rr(13.8 + 7.6 * i, t, 6, 31.5 - t, 1.5)
                                        for i, t in enumerate((20, 13, 22, 11, 17)) if i % 2 == 0)
                                + rr(12, 33.5, 40, 15.5, 3)),
                            c1='#ffffff',
                            g2=''.join(rr(13.8 + 7.6 * i, t, 6, 31.5 - t, 1.5)
                                       for i, t in enumerate((20, 13, 22, 11, 17)) if i % 2 == 1),
                            c2='#e5484d',
                            g3=('M12.5 31.5 L12.5 27 C16 25 18 22 21 23 C24 24 25 28 28.5 27 C32 26 33 20.5 36.5 21 '
                                'C40 21.5 41 26.5 44.5 25.5 C47.5 24.5 49 22 51.5 22.5 L51.5 31.5 z'),
                            c3='#f2a65a',
                            x=[(rr(12, 40.4, 40, 2.4, 0) + rr(24.8, 33.5, 2.4, 15.5, 0) + rr(37.8, 33.5, 2.4, 15.5, 0),
                                '#2f9e6e')]),
    # Calligra Stage: slide box with a play mark, coloured slides stacked behind.
    'calligra-stage': dict(label='Calligra Stage', base='#2b8be6', lip='#1f68b3',
                           g1=rr(19, 11, 26, 7, 2), c1='#e5484d',
                           g2=rr(15.5, 15.5, 33, 7, 2), c2='#3cc4b0',
                           g3=rr(12, 20, 40, 28, 4) + poly((28, 27.5), (39.5, 34), (28, 40.5)), c3='#ffffff'),
    # Calligra Words: page of text written by the Calligra nib.
    'calligra-words': dict(label='Calligra Words', base='#3f7fe0', lip='#2b5db5',
                           g1=rr(11.5, 10, 29, 39.5, 3.5), c1='#ffffff',
                           s1='M17 18h17M17 24.5h14M17 31h9M17 37.5h6', sc='#3f7fe0', sw=2.6,
                           g2=_ww['body'], c2='#2c3348',
                           g3=_ww['grip'], c3='#2c3348',
                           x=[(_ww['band'], '#f2a65a')]),
    # Choqok: the round winking bird.
    'choqok': dict(label='Choqok', base='#78b82a', lip='#5a8a20',
                   g1=(cc(32, 32, 15.5) + 'M25.5 19 Q23 13 25 9.5 Q28 13 30 17 z'
                       'M29 18 Q30 11.5 33.5 9 Q34 14 34.5 18 z' 'M33.5 18 Q36.5 12.5 40.5 11.5 Q38.5 15.5 37.5 19 z'),
                   c1='#ffffff',
                   g2='M23.5 36 C27 34.5 31.5 34.5 34.5 36.5 C32 39.5 28.5 42.5 25 43 C25.5 40.5 25 38 23.5 36 z',
                   c2='#f2a65a',
                   s1='M20.5 29.5 Q24 25.5 27.5 29.5', sc='#1b2031', sw=2.6,
                   g3=ci(37.5, 28.5, 3.8), c3='#1b2031',
                   x=[(ci(38.8, 27.2, 1.4), '#ffffff')]),
    # Crow Translate: the black crow feather with its green sheen.
    'crow-translate': dict(label='Crow Translate', base='#f4f5f9', lip='#d5d9e3',
                           g1=xf(CROW_VANE, 40, 32.5, 29.8, 1.15), c1='#1b2031',
                           g2=xf(CROW_SHEEN, 40, 32.5, 29.8, 1.15), c2='#3cc4b0',
                           s1=xf('M0 21.5 L0 -21', 40, 32.5, 29.8, 1.15), sc='#8a93a8', sw=2.4),
    # Falkon: white falcon head with the golden streaks.
    'falkon': dict(label='Falkon', base='#5a5fd6', lip='#4347a0',
                   g1=xf('M16 50 C14 41 14 30 19 22 L17 14.5 L23 17.5 L26 12.5 C33 12 41 13.5 46 17.5 '
                       'C50 20.5 53.5 24 54 28 C54 31 52.5 33 50.5 34 C51 32 50.5 30.5 49 29.5 L44 30 '
                       'C38 31 32 35 29 40 C27 43 26 46.5 26 50 z', 0, -2, 0),
                   c1='#ffffff',
                   s1=xf('M19 46 C21.5 38 28 32.5 38 30.5M17.5 37 C19.5 30.5 25 26.5 33 25', 0, -2, 0), sc='#f2a65a', sw=3,
                   x=[(ci(38, 21, 2.4), '#1b2031')]),
    # ghostwriter: the ghost with the big eyes.
    'ghostwriter': dict(label='ghostwriter', base='#c93a42', lip='#992a31',
                        g1=('M16 30 C16 19 23 12 32 12 C41 12 48 19 48 30 L48 44 C48 47 46 48.5 43.5 47 '
                            'C41.5 45.8 40 45.8 38.5 47.5 C36.5 49.6 33.5 49.6 31.5 47.5 C30 45.8 28.5 45.8 26.5 47.3 '
                            'C24 49 21 48.5 19.5 46.8 C17 47 16 45 16 43 z'),
                        c1='#ffffff',
                        g2=ci(16, 32, 4.2) + ci(48, 32, 4.2), c2='#ffffff',
                        g3=el(26.5, 28.5, 3.6, 5) + el(37.5, 28.5, 3.6, 5), c3='#1b2031'),
    # KAddressBook: spiral pad with a contact.
    'kaddressbook': dict(label='KAddressBook', base='#b7792f', lip='#8a5a20',
                         g1=rr(15, 13, 34, 37, 4), c1='#ffffff',
                         g2=''.join(rr(18.7 + 6 * i, 9, 2.6, 8, 1.3) for i in range(5)), c2='#2c3348',
                         g3=ci(32, 27, 5.2) + 'M21.5 44 C21.5 37.5 26 34.5 32 34.5 C38 34.5 42.5 37.5 42.5 44 z',
                         c3='#b7792f'),
    # KAIChat: the glowing blue ring around a light bulb.
    'kaichat': dict(label='KAIChat', base='#262c42', lip='#131726',
                    g1=''.join(ci(*_on(32, 29.5, 17, a), 1.9) for a in range(0, 360, 24)), c1='#5b9dff',
                    g2=ring(32, 29.5, 12.5, 9.5), c2='#5b9dff',
                    g3=ci(32, 27.5, 4.6) + rr(29.8, 30.5, 4.4, 4.5, 1.2), c3='#ffffff'),
    # Karbon: disc with a filled path and its Bezier nodes.
    'karbon': dict(label='Karbon', base='#5a2ca0', lip='#3e1e70',
                   g1=ci(32, 30, 19), c1='#ffffff',
                   g2=('M16.4 19.1 A19 19 0 0 0 44.2 44.6 L40.4 36.8 C35 39 30 37 26.7 33 L30.1 23.5 '
                       'C27 20 22 18.5 16.4 19.1 z'),
                   c2='#3cc4b0',
                   s1='M16.4 19.1 C21 18.2 28 19.5 30.1 23.5 L26.7 33 C30 37 35 39 40.4 36.8', sc='#1b2031', sw=2.4,
                   g3=ci(16.4, 19.1, 3.8) + ci(30.1, 23.5, 3.8) + ci(26.7, 33, 3.8) + ci(40.4, 36.8, 5),
                   c3='#1b2031',
                   x=[(ci(16.4, 19.1, 2.2) + ci(30.1, 23.5, 2.2) + ci(26.7, 33, 2.2) + ci(40.4, 36.8, 3.2),
                       '#ffffff')]),
    # Karp: red PDF book with the pencil.
    'karp': dict(label='Karp', base='#dd3b2a', lip='#a62c20',
                 g1=rr(15, 9.5, 30, 40, 3.5), c1='#ffffff',
                 g2='M18.5 9.5h3.5v40h-3.5a3.5 3.5 0 0 1-3.5-3.5v-33a3.5 3.5 0 0 1 3.5-3.5z', c2='#f8cdc8',
                 g3='M22.5 11.5 C29 11.5 37 17 38.5 27.5 C33.5 27 28 23.5 25.5 19 C24 16.5 23 14 22.5 11.5 z', c3='#dd3b2a',
                 x=[(tpoly([(-2.8, -16), (2.8, -16), (2.8, 7), (0, 13), (-2.8, 7)], 28, 39, 30), '#2c3348')]),
    # Kasts: the broadcast tower.
    'kasts': dict(label='Kasts', base='#7b5cd6', lip='#5a40a8',
                  g2=(band(32, 17, 8, 10.5, 145, 215) + band(32, 17, 12.8, 15.3, 150, 210)
                      + band(32, 17, 8, 10.5, -35, 35) + band(32, 17, 12.8, 15.3, -30, 30)),
                  c2='#d9ccff',
                  s1='M24 48.5L32 19L40 48.5M28.8 31L38.1 42M35.2 31L25.9 42', sc='#ffffff', sw=3,
                  x=[(ci(32, 17, 3.8), '#ffffff')]),
    # KDE Connect: phone showing the KDE logo.
    'kdeconnect': dict(label='KDE Connect', base='#2b8be6', lip='#1f68b3',
                       g1=rr(18.5, 9, 27, 41, 5.5), c1='#ffffff',
                       g2=_kde[0], c2='#2b8be6',
                       x=[(_kde[1], '#2b8be6'), (rr(28, 12, 8, 2.6, 1.3), '#bcd4ff')]),
    # KDE Itinerary: airliner taking off past the control tower.
    'itinerary': dict(label='KDE Itinerary', base='#3d9ae2', lip='#2e74a9',
                      g1=(poly((34, 14), (48, 14), (46, 20.5), (36, 20.5)) + rr(37.5, 10.5, 7, 3.5, 1.2)
                          + rr(38.5, 20, 5, 25, 0)),
                      c1='#cfe6fb',
                      g2=rr(10, 44.5, 44, 4.5, 2.25), c2='#3cc4b0',
                      g3=tpoly(_FUSE, 17, 28, 30.5) + tpoly(_FIN, 17, 28, 30.5), c3='#ffffff',
                      x=[(tpoly(_WING, 17, 28, 30.5), '#ffffff')]),
    # KGet: download arrow into the tray.
    'kget': dict(label='KGet', base='#f4f5f9', lip='#d5d9e3',
                 g1=rr(28, 10, 8, 17, 2) + poly((18.5, 24.5), (45.5, 24.5), (32, 38)), c1='#2b8be6',
                 s1='M16.5 40l15.5 7.5 15.5-7.5', sc='#2b8be6', sw=4),
    # Kile: the blue book with the K.
    'kile': dict(label='Kile', base='#2a74c9', lip='#1f5797',
                 g1=(rr(22, 12, 7, 36, 1.5) + poly((28, 31), (41.5, 12), (49.5, 12), (33.5, 34.5))
                     + poly((32.5, 28.5), (50, 48), (41.5, 48), (28, 34))),
                 c1='#ffffff',
                 g2=''.join(rr(12, 13 + 6.2 * i, 6.5, 2.8, 1.4) for i in range(6)), c2='#bcd4ff'),
    # KleverNotes: light bulb with a pen nib inside.
    'klevernotes': dict(label='KleverNotes', base='#1aa391', lip='#127a6c',
                        g1=cc(32, 23, 13.5) + poly((24, 32), (40, 32), (37.5, 40), (26.5, 40)), c1='#ffffff',
                        g2=rr(26, 40.5, 12, 3.5, 1.5) + rr(27, 45, 10, 3.5, 1.5), c2='#bfeee6',
                        g3=('M32 34 C29.5 30 26 27.5 26 23 C26 20.5 27 18.5 29 17 L35 17 C37 18.5 38 20.5 38 23 '
                            'C38 27.5 34.5 30 32 34 z' + ci(32, 21.8, 2.1) + rr(30.8, 24.5, 2.4, 6.5, 1.2)),
                        c3='#1b2031'),
    # KMyMoney: silver coin with laurel, gold centre and the kip sign.
    'kmymoney': dict(label='KMyMoney', base='#5b6478', lip='#414859',
                     g1=ci(32, 30, 19), c1='#ffffff',
                     s1=laurel(32, 30, 15.8), sc='#5b6478', sw=2.4,
                     g2=ci(32, 30, 12.5), c2='#f7c948',
                     x=[(rr(27, 21.5, 3.8, 17, 0.8) + poly((30.4, 30.2), (36.4, 21.5), (40.6, 21.5), (33.2, 31.6))
                         + poly((33.2, 28.4), (40.6, 38.5), (36.4, 38.5), (30.4, 29.8))
                         + rr(23.5, 28.6, 17, 2.8, 1), '#ffffff')]),
    # Kongress: speaker at the podium.
    'kongress': dict(label='Kongress', base='#475069', lip='#323950',
                     g1=ci(32, 16.5, 5.5) + 'M20 37 C20 28.5 25 24.5 32 24.5 C39 24.5 44 28.5 44 37 z',
                     c1='#ffffff',
                     g2=rr(17, 32, 30, 5, 1.5) + poly((20.5, 37), (43.5, 37), (41, 49), (23, 49)), c2='#f2a65a',
                     s1='M27.5 31.5L25.5 27', sc='#1b2031', sw=2.4,
                     x=[(ci(25.3, 26.2, 2.2), '#1b2031')]),
}

APPS = {
    'org.kde.akregator': 'akregator',
    'org.kde.alligator': 'alligator',
    'org.kde.angelfish': 'angelfish',
    'org.kde.arianna': 'arianna',
    'org.kde.blogilo': 'blogilo',
    'org.kde.calindori': 'calindori',
    'org.kde.calligra': 'calligra',
    'org.kde.calligra.sheets': 'calligra-sheets',
    'org.kde.calligra.stage': 'calligra-stage',
    'org.kde.calligra.words': 'calligra-words',
    'org.kde.choqok': 'choqok',
    'org.kde.CrowTranslate': 'crow-translate',
    'org.kde.falkon': 'falkon',
    'org.kde.ghostwriter': 'ghostwriter',
    'org.kde.gwenview': 'round1:gwenview',
    'org.kde.kaddressbook': 'kaddressbook',
    'org.kde.kaichat': 'kaichat',
    'org.kde.calligra.karbon': 'karbon',
    'org.kde.karp': 'karp',
    'org.kde.kasts': 'kasts',
    'org.kde.kdeconnect': 'kdeconnect',
    'org.kde.itinerary': 'itinerary',
    'org.kde.kget': 'kget',
    'org.kde.kile': 'kile',
    'org.kde.klevernotes': 'klevernotes',
    'org.kde.kmail2': 'round1:kmail',
    'org.kde.kmymoney': 'kmymoney',
    'org.kde.kongress': 'kongress',
}
