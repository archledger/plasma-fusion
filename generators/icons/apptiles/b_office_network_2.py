# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles: office-network-2 batch (build/kdeicons; not shipped).
import math

from apptiles.kit import *  # noqa: F401,F403  helpers and palette; the batch runs with build/kdeicons on sys.path


# ---- local path helpers -------------------------------------------------------------------------
def _p(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def capsule(x1, y1, x2, y2, r):
    """A bar with round ends from (x1, y1) to (x2, y2), as a fill path."""
    L = math.hypot(x2 - x1, y2 - y1)
    dx, dy = (x2 - x1) / L, (y2 - y1) / L
    nx, ny = dy * r, -dx * r
    return (f"M{_p(x1 + nx)} {_p(y1 + ny)}L{_p(x2 + nx)} {_p(y2 + ny)}"
            f"A{_p(r)} {_p(r)} 0 0 1 {_p(x2 - nx)} {_p(y2 - ny)}L{_p(x1 - nx)} {_p(y1 - ny)}"
            f"A{_p(r)} {_p(r)} 0 0 1 {_p(x1 + nx)} {_p(y1 + ny)}z")


def rpoly(pts, r):
    """Closed polygon with every corner rounded by r (quadratic corners)."""
    n = len(pts)
    out = []
    for i in range(n):
        px, py = pts[i - 1]
        x, y = pts[i]
        qx, qy = pts[(i + 1) % n]
        la, lb = math.hypot(px - x, py - y), math.hypot(qx - x, qy - y)
        ra, rb = min(r, la / 2), min(r, lb / 2)
        a = (x + (px - x) * ra / la, y + (py - y) * ra / la)
        b = (x + (qx - x) * rb / lb, y + (qy - y) * rb / lb)
        out.append(("M" if i == 0 else "L") + f"{_p(a[0])} {_p(a[1])}Q{_p(x)} {_p(y)} {_p(b[0])} {_p(b[1])}")
    return "".join(out) + "z"


def rot(pts, cx, cy, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def rrot(x, y, w, h, r, deg):
    """Rounded rectangle rotated by deg about its own centre."""
    cx, cy = x + w / 2, y + h / 2
    return rpoly(rot([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], cx, cy, deg), r)


def hole(x, y, w, h):
    """Counter-clockwise rectangle: a hole inside a clockwise rr() even under the nonzero rule."""
    return f"M{_p(x)} {_p(y)}V{_p(y + h)}H{_p(x + w)}V{_p(y)}z"


def star(cx, cy, ro, ri, n=5, start=-90):
    pts = []
    for k in range(2 * n):
        rr_ = ro if k % 2 == 0 else ri
        a = math.radians(start + k * 180 / n)
        pts.append((cx + rr_ * math.cos(a), cy + rr_ * math.sin(a)))
    return poly(*pts)


def arcpts(cx, cy, r, a0, a1, steps=24):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / steps)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / steps))) for k in range(steps + 1)]


def diamond(cx, cy, r):
    return rpoly([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], 1)


def gantt_summary(x, y, w):
    """Plan's summary bar: a bar with a downward tick under each end."""
    return (rr(x, y, w, 4.5, 1.5)
            + poly((x, y + 3), (x + 5, y + 3), (x, y + 8.5))
            + poly((x + w - 5, y + 3), (x + w, y + 3), (x + w, y + 8.5)))


def tear(cx, cy, r, ang, L):
    """Drop: a circle (cx, cy, r) with a pointed tail toward angle ang (degrees), tip at distance L."""
    a = math.radians(ang)
    tx, ty = cx + L * math.cos(a), cy + L * math.sin(a)
    ph = math.acos(r / L)
    p1 = (cx + r * math.cos(a + ph), cy + r * math.sin(a + ph))
    p2 = (cx + r * math.cos(a - ph), cy + r * math.sin(a - ph))
    return f"M{_p(tx)} {_p(ty)}L{_p(p1[0])} {_p(p1[1])}A{_p(r)} {_p(r)} 0 1 1 {_p(p2[0])} {_p(p2[1])}z"


def ell_ring(cx, cy, rx, ry, w, deg, n=72):
    """Rotated elliptical annulus (outer clockwise, inner counter-clockwise: works under nonzero)."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)

    def pts(rx_, ry_):
        out = []
        for k in range(n):
            t = 2 * math.pi * k / n
            x, y = rx_ * math.cos(t), ry_ * math.sin(t)
            out.append((cx + x * c - y * s, cy + x * s + y * c))
        return out
    return poly(*pts(rx + w / 2, ry + w / 2)) + poly(*pts(rx - w / 2, ry - w / 2)[::-1])


def book(x, y, w, h, deg=0):
    """Book seen from the fore-edge: (cover with spine on the left, page block open to the right)."""
    cx, cy = x + w / 2, y + h / 2
    pages = rot([(x + 6, y + 3), (x + w + 0.5, y + 3), (x + w + 0.5, y + h - 3), (x + 6, y + h - 3)], cx, cy, deg)
    return rrot(x, y, w, h, 3, deg), rpoly(pages, 1)


def pencil(x1, y1, x2, y2, r, tip):
    """Pencil from its back end (x1, y1) to the start of the point (x2, y2): (body, point)."""
    L = math.hypot(x2 - x1, y2 - y1)
    dx, dy = (x2 - x1) / L, (y2 - y1) / L
    nx, ny = -dy * r, dx * r
    body = rpoly([(x1 + nx, y1 + ny), (x2 + nx, y2 + ny), (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)], 1.4)
    point = rpoly([(x2 + nx, y2 + ny), (x2 + dx * tip, y2 + dy * tip), (x2 - nx, y2 - ny)], 0.8)
    return body, point


# Pix: a 4 x 4 pixel grid shading from peach (top left) to dark purple (bottom right).
PIX_PATTERN = ["OOOL", "OOLL", "LLPP", "PPDD"]


def pix_cells(colour):
    """The cells of Pix's pixel grid that carry one colour key of PIX_PATTERN."""
    ys, hs = [12.5, 21.3, 30.1, 38.9], [8.2, 8.2, 8.2, 8.6]
    return ''.join(rr(16 + c * 8.15, ys[r], 7.55, hs[r], 0.8)
                   for r, row in enumerate(PIX_PATTERN) for c, ch in enumerate(row) if ch == colour)


# ---- shared shapes ------------------------------------------------------------------------------
# Plan family (Plan, Plan Portfolio, Plan Work): the same Gantt layout, each on its own base.
PLAN_GRID = rr(20, 10, 2.4, 40, 1.2) + rr(31, 10, 2.4, 40, 1.2) + rr(42, 10, 2.4, 40, 1.2)
PLAN_SUM = gantt_summary(11, 13, 28) + gantt_summary(25, 38, 28)
PLAN_TASK = rr(19, 26, 20, 5, 2.5)
PLAN_MILE = diamond(47.5, 28.5, 5)


def _handset():
    """Phone handset: a curved band with a thicker pad at each end (outline, rounded later)."""
    cx, cy = 49.2, 12.5
    out = arcpts(cx, cy, 32, 172, 98, 20)            # outer edge, ear end -> mouth end
    pad = 21
    inner = []
    inner += arcpts(cx, cy, pad, 98, 120, 6)          # mouth pad
    inner += arcpts(cx, cy, 25, 121, 149, 8)          # band
    inner += arcpts(cx, cy, pad, 150, 172, 6)         # ear pad
    return poly(*(out + inner))


HANDSET = _handset()

# Tellico: three stacked books, the top one tilted (as on the original).
BOOK_G = book(14, 37, 37, 11.5)
BOOK_B = book(11, 25, 36, 11.5)
BOOK_R = book(18.5, 12.5, 34, 11.5, -6)

# Online Quotes Editor: the pencil drawing the price line.
QUOTE_PENCIL = pencil(51, 13, 42, 23.5, 3.2, 6.5)

TILES = {
    'konqueror': dict(label='Konqueror', base='#3f7fe0', lip='#2b5db5',
                      g1=gear(32, 30, 20.5, 16, 8), c1='#ffffff',
                      g2=ci(32, 30, 12.5), c2='#1f56b8',
                      g3=('M21.5 25.5c1.5-3 4.5-5.5 7.5-5.5 1.5 1 .5 3-1 3.5-1.5.5-1 2.5.5 3 2 .5 2 3 .5 4.5'
                          '-1.5 1.5-1 4 0 5.5.5 1.5-.5 3.5-2 4-2.5-1.5-4.5-4-5.3-7-.6-2.5-.6-5.5-.2-8z'
                          'M34 20.5c3 0 6 1.5 8 4-1 1-2.5.5-3.5 1.5s0 2.5 1.5 3c1.5.5 2.5 2 2 3.5-.8 2.5-2.5 4.5-4.5'
                          ' 6-1-1.5-.5-3.5-1.5-5-1-1.5-3-1.5-3.5-3.5-.5-1.5 1-2.5 2-3.5-1-1.5-2.5-2.5-2-4.5.5-1 1.5-1.5 2.5-1.5z'),
                      c3='#9cc5ff'),
    # review: orange (the original's folder) instead of amber, apart from KAddressBook's amber notebook
    'kontact': dict(label='Kontact', base='#e8743b', lip='#b8552a',
                    g1=rr(17, 12, 30, 26, 3) + ci(32, 18.5, 3.4) + el(32, 27, 6.5, 3.6), c1='#fbd3bd',
                    g2=rr(11, 25, 42, 25, 4), c2='#ffffff',
                    s1='M14 28.5 32 40.5l18-12', sc='#e8743b', sw=3,
                    x=[(rr(21.5, 9, 3, 7, 1.5) + rr(27.5, 9, 3, 7, 1.5) + rr(33.5, 9, 3, 7, 1.5)
                        + rr(39.5, 9, 3, 7, 1.5), '#ffffff')]),
    'konversation': dict(label='Konversation', base='#2b8be6', lip='#1f68b3',
                         g1='M16 11h32a4 4 0 0 1 4 4v22a4 4 0 0 1-4 4H25l-9 8v-8a4 4 0 0 1-4-4V15a4 4 0 0 1 4-4z',
                         c1='#ffffff',
                         g2=(rr(17, 20.5, 4, 11, 1.2) + rpoly([(23, 22.5), (40.5, 15.5), (40.5, 36.5), (23, 29.5)], 1.5)
                             + rr(24, 29.5, 4, 6.5, 1.2) + rr(44, 20, 3.2, 12, 1.4)),
                         c2='#2b8be6'),
    'kopete': dict(label='Kopete', base='#2a9fd6', lip='#1f78a3',
                   g1=el(32, 27, 20.5, 16.5) + 'M18 36C18 42 16 46 12 49.5 18.5 49 23.5 45.5 27 41z', c1='#ffffff',
                   g2=ci(23, 19.5, 2.3) + ci(23, 30, 2.3) + capsule(28, 25.2, 34, 24.8, 1.5), c2='#2a9fd6',
                   s1='M38.5 14C46 19.5 46.5 32.5 39 39.5', sc='#2a9fd6', sw=3.6,
                   g3=capsule(23.9, 30.6, 22, 34.5, 1.25), c3='#2a9fd6'),
    'krdc': dict(label='KRDC', base='#475069', lip='#323950',
                 g1=rr(10, 10, 28, 21, 3), c1='#ffffff',
                 g2=rr(12.75, 12.75, 22.5, 15.5, 1.5), c2='#5b9dff',
                 # review: the base-coloured gap is limited to where it overlaps the back monitor, so it no
                 # longer cuts a dark patch out of the sheen right of it
                 x=[('M27 18.5H38V31.5H22V23.5A5 5 0 0 1 27 18.5Z', '#475069'),
                    (rr(24.5, 21, 29.5, 21.5, 3) + rr(36.5, 41, 5, 5, 0.5) + rr(31, 45, 16, 3.6, 1.8), '#ffffff'),
                    (rr(27.25, 23.75, 24, 16, 1.5), '#5b9dff')]),
    'krfb': dict(label='Krfb', base='#3a7bd5', lip='#2a5ea8',
                 g1=rr(10, 11, 44, 31, 4) + rr(29, 41, 6, 5, 0.5) + rr(22.5, 45, 19, 3.6, 1.8), c1='#1b2031',
                 g2=rr(13.5, 14.5, 37, 24, 2), c2='#5b9dff',
                 s1='M40 20.5 26 26.5 40 32.5', sc='#ffffff', sw=2.6,
                 g3=ci(25.5, 26.5, 3.6) + ci(40, 20.5, 3.1) + ci(40, 32.5, 3.1), c3='#ffffff'),
    'ktorrent': dict(label='KTorrent', base='#2f6fdf', lip='#2152ad',
                     g1=rr(26.5, 11.5, 11, 20, 2.5) + rpoly([(13, 28.5), (51, 28.5), (32, 49.5)], 3), c1='#ffffff',
                     g2=(tear(12.5, 21, 2.5, 40, 7) + tear(18, 15.5, 2.7, 75, 7.5) + tear(23.2, 20, 1.9, 100, 5.5)
                         + tear(51.5, 21, 2.5, 140, 7) + tear(46, 15.5, 2.7, 105, 7.5) + tear(40.8, 20, 1.9, 80, 5.5)),
                     c2='#ffffff'),
    'ktrip': dict(label='KTrip', base='#3aa65b', lip='#2a7e44',
                  g1=('M53 18H31C21 18 14 24 11 33L10.5 36.5a3 3 0 0 0 3 3.5H53a1.5 1.5 0 0 0 1.5-1.5V19.5'
                      'A1.5 1.5 0 0 0 53 18z'), c1='#ffffff',
                  g2='M33 21.5V28.5H14.5C17 24 22 21.5 29 21.5z' + rr(36.5, 21.5, 18, 7, 2), c2='#1b2031',
                  s1='M33 18l-3.2-3.2 3.2-3.2 3.2 3.2zM27.5 11.6h11M11.2 47.5h41.6', sc='#1b2031', sw=2.4,
                  g3=rr(11.8, 32, 42.7, 3.2, 0), c3='#e5484d',
                  x=[(ci(19, 42.5, 3.2) + ci(26.5, 42.5, 3.2) + ci(41, 42.5, 3.2) + ci(48.5, 42.5, 3.2), '#1b2031')]),
    'merkuro': dict(label='Merkuro', base='#7b5cd6', lip='#5a40a8',
                    g1=rr(12, 14, 40, 35, 5), c1='#ffffff',
                    g2='M12 25H52V44a5 5 0 0 1-5 5H17a5 5 0 0 1-5-5z', c2='#d9ccff',
                    g3='M12 37H52V44a5 5 0 0 1-5 5H17a5 5 0 0 1-5-5z', c3='#b8a4f4',
                    x=[(rr(21.3, 25, 2.4, 24, 0) + rr(30.8, 25, 2.4, 24, 0) + rr(40.3, 25, 2.4, 24, 0), '#7b5cd6'),
                       (rr(19.5, 9.5, 5, 9, 2.5) + rr(39.5, 9.5, 5, 9, 2.5), '#d9ccff')]),
    'onlinequoteseditor': dict(label='Online Quotes Editor', base='#1f9e8f', lip='#15756a',
                               g1=rpoly([(11, 49), (11, 41), (18, 34), (23, 38), (30, 29), (35, 33), (41, 24.5),
                                         (46, 28.5), (53, 18.5), (53, 49)], 1.2), c1='#ffffff',
                               s1='M11.5 31.5h4M20 31.5h4.5M29 31.5h4.5M38 31.5h4.5M47 31.5h5.5', sc='#e5484d', sw=2.6,
                               g3=QUOTE_PENCIL[0], c3='#f7c948',
                               x=[(QUOTE_PENCIL[1], '#15756a')]),
    'plasma-dialer': dict(label='Phone', base='#2b8be6', lip='#1f68b3',
                          g1=HANDSET, c1='#ffffff',
                          s1=HANDSET, sc='#ffffff', sw=3),
    # review: green instead of orange-amber; it was a white book with a person on the same amber as
    # KAddressBook and on the same orange as Arianna's white book (tabs now red, yellow, blue)
    'phonebook': dict(label='Phonebook', base='#3aa65b', lip='#2a7e44',
                      g1=rr(17, 10, 30, 40, 4) + capsule(13.5, 16, 20, 16, 1.4) + capsule(13.5, 24, 20, 24, 1.4)
                      + capsule(13.5, 32, 20, 32, 1.4) + capsule(13.5, 40, 20, 40, 1.4), c1='#ffffff',
                      g2=ci(21.5, 16, 1.5) + ci(21.5, 24, 1.5) + ci(21.5, 32, 1.5) + ci(21.5, 40, 1.5), c2='#3aa65b',
                      s1=ci(33, 23, 5) + 'M24.5 40c0-5.5 3.8-9 8.5-9s8.5 3.5 8.5 9', sc='#3aa65b', sw=3,
                      x=[(rr(45, 13, 6, 7, 1.5), '#e5484d'), (rr(45, 22, 6, 7, 1.5), '#f7c948'),
                         (rr(45, 31, 6, 7, 1.5), '#5b9dff')]),
    'koko': dict(label='Photos', base='#e05a52', lip='#ae3f39',
                 g1=ci(29, 33, 7), c1='#f7c948',
                 g2=poly((14, 47), (14, 40), (21, 34), (26, 38), (33, 31), (37, 34), (43, 25), (50, 20), (50, 47)),
                 c2='#2c3348',
                 g3=rr(11, 11, 42, 39, 6) + rr(15, 15, 34, 31, 3), c3='#ffffff'),
    'pix': dict(label='Pix', base='#5a2ca0', lip='#3e1e70',
                g1=rr(13, 9.5, 38, 41, 4.5), c1='#ffffff',
                g2=pix_cells('O'), c2='#f2a65a',
                g3=pix_cells('L'), c3='#c59be8',
                x=[(pix_cells('P'), '#5a2ca0'), (pix_cells('D'), '#3e1e70')]),
    'calligraplan': dict(label='Plan', base='#f4f5f9', lip='#d5d9e3',
                         g1=PLAN_GRID, c1='#dde1ea',
                         g2=PLAN_SUM, c2='#2f6fdf',
                         g3=PLAN_TASK, c3='#3aa65b',
                         x=[(PLAN_MILE, '#e5484d')]),
    'calligraplanportfolio': dict(label='Plan Portfolio', base='#2c3348', lip='#1a1f2e',
                                  g1=PLAN_GRID, c1='#3e4660',
                                  g2=PLAN_SUM, c2='#ffffff',
                                  g3=PLAN_TASK, c3='#3aa65b',
                                  x=[(PLAN_MILE, '#e5484d')]),
    'calligraplanwork': dict(label='Plan Work', base='#3aa65b', lip='#2a7e44',
                             g1=PLAN_GRID, c1='#5dbb79',
                             g2=gantt_summary(11, 13, 28), c2='#ffffff',
                             g3=rr(19, 26, 20, 5, 2.5), c3='#c9ecd2',
                             s1='M29.5 38.5l6 6 14.5-15', sc='#3aa65b', sw=9,
                             x=[(capsule(29.5, 38.5, 35.5, 44.5, 2.3) + capsule(35.5, 44.5, 50, 29.5, 2.3), '#ffffff')]),
    'ruqola': dict(label='Ruqola', base='#3f8f5a', lip='#2d6b42',
                   g1='M13.5 49C12.5 37 17.5 24 29.5 17c6-3.5 13-5.5 21-6-1 8-3.5 15-7.5 21-7 10-17 15.5-29.5 17z',
                   c1='#ffffff',
                   s1='M15 47.5C23.5 40 32.5 31 44.5 17', sc='#3f8f5a', sw=2.4,
                   g3=(poly((21.5, 26), (27, 25), (24.5, 20.5)) + poly((32.5, 17.5), (37, 17), (35.5, 13))
                       + poly((40.5, 32), (36.5, 36.5), (42, 37)) + poly((30.5, 40.5), (25.5, 43.5), (30.5, 45.5))),
                   c3='#3f8f5a'),
    'sieveeditor': dict(label='SieveEditor', base='#262c42', lip='#131726',
                        g1=rr(11, 25, 42, 23.5, 3.5) + poly((11, 28), (32, 13), (53, 28)), c1='#bcd4ff',
                        g2='M21 10H38L45 17V36H19V12a2 2 0 0 1 2-2z', c2='#5b9dff',
                        s1='M30 21.5l5 4-5 4', sc='#ffffff', sw=3,
                        g3='M11 30L32 41L53 30V45a3.5 3.5 0 0 1-3.5 3.5H14.5A3.5 3.5 0 0 1 11 45z', c3='#ffffff',
                        x=[('M38 10V15a2 2 0 0 0 2 2H45z', '#bcd4ff'),
                           (ci(24.5, 18, 1.7) + ci(24.5, 27, 2.6), '#ffffff')]),
    'skrooge': dict(label='Skrooge', base='#c2410c', lip='#922f08',
                    g1=(rr(10, 24, 10, 4.2, 2.1) + rr(10, 31.8, 10, 4.2, 2.1)
                        + rr(44, 24, 10, 4.2, 2.1) + rr(44, 31.8, 10, 4.2, 2.1)), c1='#ffffff',
                    g2=ring(32, 30, 15, 12.4), c2='#ffffff',
                    g3=ci(32, 30, 12.4), c3='#f2a65a',
                    x=[(capsule(25, 22.5, 32, 39, 1.8) + capsule(39, 22.5, 32, 39, 1.8)
                        + capsule(32, 26, 32, 33, 1.5), '#ffffff')]),
    'spacebar': dict(label='Spacebar', base='#3f7fe0', lip='#2b5db5',
                     g1=ell_ring(32, 28, 21, 12.5, 3, -32), c1='#bcd4ff',
                     g2=rr(14, 13, 36, 27, 5) + 'M19 40H28L17 48.5z', c2='#ffffff',
                     g3=star(35.5, 27.5, 9, 3.9) + star(22.5, 20, 3.8, 1.7), c3='#3f7fe0'),
    'tellico': dict(label='Tellico', base='#3b4255', lip='#262b38',
                    g1=BOOK_G[0], c1='#3aa65b',
                    g2=BOOK_B[0], c2='#3f7fe0',
                    g3=BOOK_R[0], c3='#e5484d',
                    x=[(BOOK_G[1] + BOOK_B[1] + BOOK_R[1], '#ffffff')]),
    'tokodon': dict(label='Tokodon', base='#3b9ad9', lip='#2a74a8',
                    g1=ci(32, 30, 19.5), c1='#cfe7f8',
                    g2=('M24 15H40A4 4 0 0 1 44 19V26C44 30.5 40.5 33.5 35.5 34.5V40.5C35.5 42 36.5 43 38 43'
                        'C39.5 43 40.5 42 40.5 40.5L44 40.5C44 44.5 41.5 46.8 38 46.8C32.5 46.8 28.5 44 28.5 39'
                        'V34.5C23.5 33.5 20 30.5 20 26V19A4 4 0 0 1 24 15Z'), c2='#2c3348',
                    g3=('M25.5 31.5C25.5 35.5 24 39 20.5 41.5 21.5 38 22 35 22 31z'
                        'M38.5 31.5C38.5 35.5 40 39 43.5 41.5 42.5 38 42 35 42 31z'),
                    c3='#ffffff',
                    x=[(el(26.5, 22.5, 1.8, 2.4) + el(37.5, 22.5, 1.8, 2.4), '#ffffff')]),
    'trojita': dict(label='Trojitá', base='#5b6478', lip='#414859',
                    g1=rr(10, 14, 44, 31, 4), c1='#ffffff',
                    g2=capsule(13, 17, 32, 31, 1.3) + capsule(51, 17, 32, 31, 1.3), c2='#c9cfdd',
                    s1='M20 27C30 22 46 18 49 23.5 51.5 28 45 31 39 31.5 47 31.5 53 34 51 39 48.5 45 32 45 17 40',
                    sc='#2f6fdf', sw=4),
}

APPS = {
    'org.kde.konqueror': 'konqueror',
    'org.kde.kontact': 'kontact',
    'org.kde.konversation': 'konversation',
    'org.kde.kopete': 'kopete',
    'org.kde.korganizer': 'board:calendar',
    'org.kde.krdc': 'krdc',
    'org.kde.krfb': 'krfb',
    'org.kde.ktorrent': 'ktorrent',
    'org.kde.ktrip': 'ktrip',
    'org.kde.marknote': 'round1:marknote',
    'org.kde.merkuro': 'merkuro',
    'org.kde.neochat': 'board:chat',
    'org.kde.okular': 'round1:okular',
    'org.kde.onlinequoteseditor6': 'onlinequoteseditor',
    'org.kde.plasma.dialer': 'plasma-dialer',
    'org.kde.phonebook': 'phonebook',
    'org.kde.koko': 'koko',
    'org.kde.pix': 'pix',
    'org.kde.calligraplan': 'calligraplan',
    'org.kde.calligraplanportfolio': 'calligraplanportfolio',
    'org.kde.calligraplanwork': 'calligraplanwork',
    'org.kde.ruqola': 'ruqola',
    'org.kde.sieveeditor': 'sieveeditor',
    'org.kde.skrooge': 'skrooge',
    'org.kde.spacebar': 'spacebar',
    'org.kde.tellico': 'tellico',
    'org.kde.tokodon': 'tokodon',
    'org.kde.trojita': 'trojita',
}
