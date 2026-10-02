# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles: education batch (KDE Edu and science apps).
from apptiles.kit import *  # noqa: F401,F403
import math

# ---------------------------------------------------------------- local path helpers
# Layers g1 and x are filled with the nonzero rule, g2 and g3 with even-odd. The helpers below
# build clockwise outlines so that shapes unioned inside one nonzero layer never cancel out.


def _p(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def cw(*pts):
    """Closed polygon, always clockwise on screen."""
    pts = list(pts)
    a = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    if a < 0:
        pts.reverse()
    return "M" + "L".join(f"{_p(x)} {_p(y)}" for x, y in pts) + "z"


def C(cx, cy, r):
    """Clockwise circle (ci() from the kit runs counter-clockwise)."""
    return (f"M{_p(cx - r)} {_p(cy)}A{_p(r)} {_p(r)} 0 1 1 {_p(cx + r)} {_p(cy)}"
            f"A{_p(r)} {_p(r)} 0 1 1 {_p(cx - r)} {_p(cy)}z")


def line(pts, w):
    """Thick polyline with round caps and joins as a filled (nonzero) outline."""
    h = w / 2
    out = [C(pts[0][0], pts[0][1], h)]
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L * h, dx / L * h
        out.append(cw((x1 + nx, y1 + ny), (x2 + nx, y2 + ny), (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)))
        out.append(C(x2, y2, h))
    return "".join(out)


def bez(p0, p1, p2, p3, n=16):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        pts.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return pts


def arcpts(cx, cy, r, a0, a1, n=18):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def rot(pts, cx, cy, ang):
    a = math.radians(ang)
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def rrot(cx, cy, w, h, r, ang, n=5):
    """Rounded rectangle centred on (cx, cy), rotated by ang degrees (clockwise outline)."""
    pts = []
    for (qx, qy, a0) in ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0),
                         (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)):
        pts += arcpts(cx + qx, cy + qy, r, a0, a0 + 90, n)
    return cw(*rot(pts, cx, cy, ang))


def star4(cx, cy, R, r):
    """Four-point sparkle."""
    pts = []
    for k in range(8):
        a = math.radians(-90 + 45 * k)
        d = R if k % 2 == 0 else r
        pts.append((cx + d * math.cos(a), cy + d * math.sin(a)))
    return cw(*pts)


def qmark(cx, top, h, w):
    """Bold question mark (nonzero fill), h tall from y=top, stroke width w."""
    R = h * 0.25
    by = top + w / 2 + R
    pts = arcpts(cx, by, R, 165, 400, 20)
    stem_top = by + R + w * 0.35
    pts += [(cx, stem_top), (cx, top + h - w * 1.9)]
    return line(pts, w) + C(cx, top + h - w * 0.62, w * 0.62)


def gauss(x0, x1, base, peak, n=28):
    mu, s = (x0 + x1) / 2, (x1 - x0) / 6.2
    return [(x0 + (x1 - x0) * i / n,
             base - (base - peak) * math.exp(-((x0 + (x1 - x0) * i / n - mu) / s) ** 2 / 2)) for i in range(n + 1)]


# ---------------------------------------------------------------- shared constructions
def compass_globe(base, lip, label, sea, land, land_c, needle_up_right=True, tail='#ffffff'):
    """Marble family: white rim, sea disc, land in land_c, red and white compass needle."""
    cx, cy, L, hw = 32, 30, 14, 3.1
    d = 1 if needle_up_right else -1
    ux, uy = d * L / math.sqrt(2), -L / math.sqrt(2)          # red tip direction
    px, py = hw / math.sqrt(2), d * hw / math.sqrt(2)          # half-width, perpendicular
    red = cw((cx + ux, cy + uy), (cx + px, cy + py), (cx - px, cy - py))
    white = cw((cx - ux, cy - uy), (cx + px, cy + py), (cx - px, cy - py))
    return dict(label=label, base=base, lip=lip,
                g1=C(cx, cy, 15), c1=sea,
                g2=land, c2=land_c,
                s1=ci(cx, cy, 16.6), sc='#ffffff', sw=3.4,
                g3=red, c3='#e5484d',
                x=[(white + C(cx, cy, 2.6), tail)])


def sigma(cx, cy, s):
    """Bold sigma, about 18 x 24 units at s=1."""
    pts = [(-9, -12), (9, -12), (9, -7.5), (-2.2, -7.5), (5, 0), (-2.2, 7.5), (9, 7.5), (9, 12), (-9, 12),
           (-9, 8.6), (-0.6, 0), (-9, -8.6)]
    return cw(*[(cx + x * s, cy + y * s) for x, y in pts])


def k_mark(x, y, h, t, wr=0.62):
    """Bold sans K, top-left (x, y), height h, stroke t; the arms reach x + h * wr + 1.25 t."""
    mid = y + h * 0.56
    stem = cw((x, y), (x + t, y), (x + t, y + h), (x, y + h))
    arm_up = cw((x + t - 0.5, mid - t * 0.9), (x + h * wr, y), (x + h * wr + t * 1.25, y), (x + t + 0.6, mid + t * 0.45))
    arm_dn = cw((x + t * 1.6, mid - t * 0.75), (x + h * (wr + 0.06) + t * 1.25, y + h), (x + h * (wr + 0.06), y + h),
                (x + t - 0.4, mid + t * 0.4))
    return stem + arm_up + arm_dn


# ---------------------------------------------------------------- tiles
ART_BUB_A = rr(10, 9, 19, 14.5, 4.5) + cw((18.5, 22), (25, 22), (25.5, 27.5))
ART_BUB_B = rr(35, 35.5, 19, 14.5, 4.5) + cw((38, 37), (44.5, 37), (38.5, 31.5))

TILES = {
    'artikulate': dict(
        label='Artikulate', base='#3a7bd5', lip='#2a5ea8',
        g1=C(32.5, 30, 14.5), c1='#ffffff',
        g2='M23.5 27.5c1-2.6 3.4-4.2 6-4 1.4 1 .8 2.8 2 3.8 1.4 1.2 1 3.2-.6 4-1.4.8-1.8 2.6-1.6 4.2.2 1.4-.6 2.4-1.8 2.6-1.8-1.6-3-3.6-3.6-5.8-.4-1.6-.8-3.2-.4-4.8z'
           'M36.5 19.5c2.6-.2 5 1 6.4 3 .2 1.4-.8 2.2-2.2 2.2-1.4 0-2 1.4-1.4 2.6.8 1.6 2.6 2.2 2.6 4 0 2-1.6 3.4-3.4 4-.6-1.8-.4-3.6-1.4-5.2-.8-1.4-2.4-1.8-2.6-3.6-.2-1.6.8-3.4 2-5z',
        c2='#3a7bd5',
        s1=ART_BUB_A + ART_BUB_B, sc='#3a7bd5', sw=2.8,
        x=[(ART_BUB_A, '#3cc4b0'), (qmark(19.5, 10.6, 11.6, 2.8), '#ffffff'),
           (ART_BUB_B, '#d9ccff'), (rr(43, 38.2, 3, 6.8, 1.5) + C(44.5, 46.8, 1.6), '#3a7bd5')]),

    'marble-behaim': compass_globe(
        '#c2410c', '#922f08', 'Behaim Globe', '#5b9dff',
        'M17.5 25c1.5-3.5 4.5-6.5 8-8 1.8.6 1.6 2.6 3.2 3.4 1.8.8 3.8-.8 5.6.2-.4 2-2.6 3-3 5-.3 1.8 1.6 3 1.2 4.8-.6 2.2-3.4 2.6-4.4 4.6-1 2.2.4 5-1 7-2.6-1.2-4.4-3.8-5.6-6.6-.8-2-.6-4.2-2-5.8-1-1.2-2.4-2.6-2-4.6z'
        'M38 31c2-1 4.6-.4 6.4.8.4 2.2-.2 4.6-1.4 6.6-1 1.6-2.6 3-4.4 3.6-.6-1.8.2-3.6-.4-5.4-.5-1.8-1.6-3.6-.2-5.6z',
        '#c2410c', needle_up_right=True),

    'cantor': dict(
        label='Cantor', base='#b7792f', lip='#8a5a20',
        g1=rr(11, 12, 42, 35, 3.5), c1='#1b2031',
        s1='M17.5 29.5h3.5l4 8.5 5.5-18h13.5'
           'M34 30.5a3.6 3.6 0 1 0 7.2 0a3.6 3.6 0 1 0-7.2 0M41.2 26.9v7.5', sc='#ffffff', sw=2.6,
        x=[(rr(34, 41.5, 7, 2.6, 1.3), '#5b9dff'), (rr(43, 41.5, 6, 2.6, 1.3), '#ffffff')]),

    'kalgebra': dict(
        label='KAlgebra', base='#f6f4ef', lip='#d6d0c2',
        g1=rr(0, 14, 64, 2.6, 0), c1='#5b9dff',
        g2=rr(17.5, 0, 2.6, 60, 0), c2='#e5484d',
        g3=sigma(35, 33, 0.95), c3='#3b4255'),

    'kalgebra-mobile': dict(
        label='KAlgebra Mobile', base='#3b4255', lip='#262b38',
        g1=rr(18, 9.5, 28, 40.5, 6), c1='#f6f4ef',
        g2=rr(22.5, 9.5, 2.4, 40.5, 0), c2='#e5484d',
        g3=sigma(34.5, 28.5, 0.68), c3='#3b4255',
        x=[(rr(28, 45, 10, 2.4, 1.2), '#9aa2b8')]),

    'kalzium': dict(
        label='Kalzium', base='#f4f5f9', lip='#d5d9e3',
        s1='M20 31L41 17.5M20 31l21 11.5M41 17.5v24.5', sc='#1b2031', sw=4.2,
        g1=C(19.5, 31, 8.5), c1='#1b2031',
        g3=ci(41, 17.5, 7.5), c3='#5b9dff',
        x=[(C(41, 42, 7.5), '#e5484d')]),

    'kbibtex': dict(
        label='KBibTeX', base='#2f9e6e', lip='#227650',
        g1=rr(21, 9, 30, 37, 4), c1='#bfe6d3',
        g2=rr(13, 14, 31, 36, 4), c2='#ffffff',
        s1='M18.5 16v32', sc='#bfe6d3', sw=2.6,
        x=[(k_mark(24.5, 22.5, 20, 4.4), '#2f9e6e')]),

    'kbruch': dict(
        label='KBruch', base='#475069', lip='#323950',
        g1=rr(10.5, 11, 43, 36, 3.5), c1='#1b2031',
        s1='M24.5 14.5c-3.6 0-6.3 3-6.3 7.6M18.2 22.4a3.2 3.2 0 1 0 6.4 0a3.2 3.2 0 1 0-6.4 0'
           'M15.5 29h12'
           'M18 33h6l-3.4 3.6c2.4 0 3.9 1.3 3.9 3.3s-1.7 3.4-3.8 3.4c-1.5 0-2.7-.6-3.3-1.7'
           'M31 26.5h6M31 31.5h6'
           'M40.5 23c0-2 1.6-3.5 3.7-3.5s3.7 1.5 3.7 3.4c0 3.3-7.4 6.9-7.4 11.6h7.8', sc='#ffffff', sw=2.4,
        x=[(rr(14, 47, 36, 2.5, 1.25), '#c5cbe0')]),

    'kgeography': dict(
        label='KGeography', base='#f5c84c', lip='#c99a22',
        g1=rr(12.5, 12.5, 39, 34, 2.5), c1='#3f7fe0',
        g2='M24 8c1.6 2.8 4.6 3.6 6.8 5.8 1.8 1.8 1.2 4.4 3 6 1.8 1.6 4.6.8 6 2.8 1.4 2-.6 4.6.4 6.8 1 2.2 3.8 2.4 5.2 4.4 1.2 1.8.4 4.2 1.6 5.8 1.2 1.4 3.4 1.6 5 2.6V8z',
        c2='#f5c84c',
        s1=rr(12.5, 12.5, 39, 34, 2.5), sc='#ffffff', sw=3,
        g3=star4(23, 36, 13, 3.6), c3='#ffffff',
        x=[(cw((23, 23), (26.6, 36), (23, 36)) + cw((23, 49), (19.4, 36), (23, 36))
            + cw((10, 36), (23, 32.4), (23, 36)) + cw((36, 36), (23, 39.6), (23, 36)), '#c9d6ee')]),

    'kig': dict(
        label='Kig', base='#f4f5f9', lip='#d5d9e3',
        g2=rr(29, 30, 19, 19, 2) + rr(32, 33, 13, 13, 0.5), c2='#e5484d',
        s1=ci(25, 31, 12), sc='#5b9dff', sw=3.4,
        g3=poly((22, 9), (53, 9), (53, 40)) + poly((31, 13), (49, 13), (49, 31)), c3='#f2a65a'),

    'kiten': dict(
        label='Kiten', base='#c93a42', lip='#992a31',
        s1='M13.7 45L22.7 16.5L31.7 45M16.8 35.5h11.8'
           'M37.4 30.5c1.4-2.6 3.8-3.6 6.4-3.6 3.6 0 5.9 2 5.9 5.6V45'
           'M49.7 36.4c-1.6-.8-4-1.2-6.4-1.2-3.8 0-6.8 1.8-6.8 4.9 0 2.7 2 4.6 4.9 4.6 3.6 0 6.6-2.6 8.3-5.2',
        sc='#ffffff', sw=3.4),

    'klettres': dict(
        label='KLettres', base='#2b8be6', lip='#1f68b3',
        g1='M19 13.5c6-3.4 11.4 1.4 17.2-.4 5-1.6 9.6-3.4 14.8-.8v22.6c-5.2-2.6-9.8-.8-14.8.8-5.8 1.8-11.2-3-17.2.4z', c1='#ffffff',
        s1='M16.5 14v34.5', sc='#1b2031', sw=3.6,
        x=[(C(16.5, 11.5, 2.8), '#1b2031'),
           (C(35, 23, 3.8) + line(arcpts(35, 23.5, 7.2, 102, 222, 12), 2.4)
            + line(arcpts(35, 23.5, 7.2, -42, 78, 12), 2.4), '#2b8be6')]),

    'kmplot': dict(
        label='KmPlot', base='#2f6fdf', lip='#2152ad',
        g1=rr(11, 11, 42, 38, 4), c1='#ffffff',
        g2=poly((11, 31), (53, 31), (53, 33.4), (11, 33.4)) + poly((25, 11), (27.4, 11), (27.4, 49), (25, 49)), c2='#bcd4ff',
        s1='M15 45c8-.5 9.8-5 11.2-12.8 1.4-7.8 4.6-15.2 22.8-15.6', sc='#2f6fdf', sw=3.2),

    'kstars': dict(
        label='KStars', base='#262c42', lip='#131726',
        s1='M29.5 30.5L20.5 48.5M29.5 30.5v18M29.5 30.5l9 18', sc='#c5cbe0', sw=2.6,
        g1=cw((16.84, 11.72), (41.66, 27.92), (38.34, 34.08), (11.16, 22.28)), c1='#ffffff',
        g3=cw((19.2, 13.0), (21.8, 14.4), (15.6, 25.9), (13.0, 24.5)) + C(29.5, 30, 2.8), c3='#c5cbe0',
        x=[(star4(47, 14.5, 6, 1.7) + star4(50.2, 26.5, 3.6, 1.1), '#f7c948')]),

    'ktechlab': dict(
        label='KTechlab', base='#7b5cd6', lip='#5a40a8',
        g1=rr(17, 14, 30, 32, 4) + ''.join(rr(11, y, 7.5, 3.6, 1.6) + rr(46, y, 7.5, 3.6, 1.6) for y in (18, 25, 32, 39)),
        c1='#ffffff',
        g2=rr(20.5, 17.5, 11, 11.5, 2.5), c2='#f2a65a',
        g3=rr(32.5, 17.5, 11, 11.5, 2.5) + rr(20.5, 31, 11, 11.5, 2.5), c3='#7b5cd6',
        x=[(rr(32.5, 31, 11, 11.5, 2.5), '#3cc4b0')]),

    'ktouch': dict(
        label='KTouch', base='#1f9e8f', lip='#15756a',
        g1=rr(10.5, 23, 13, 12, 3) + rr(25.5, 23, 13, 12, 3) + rr(40.5, 23, 13, 12, 3)
           + rr(16, 38, 13, 12, 3) + rr(31, 38, 13, 12, 3), c1='#ffffff',
        s1=rr(25.5, 23, 13, 12, 3), sc='#e5484d', sw=2.6,
        g3=poly((28.8, 8.5), (35.2, 8.5), (35.2, 12.5), (40, 12.5), (32, 20.5), (24, 12.5), (28.8, 12.5)), c3='#ffffff'),

    'kturtle': dict(
        label='KTurtle', base='#3aa65b', lip='#2a7e44',
        g1=rr(26, 9, 12, 4, 0.6) + rr(22, 13, 20, 4, 0.6) + rr(26, 16, 12, 6, 0.6)
           + rr(10, 21, 8, 4, 0.6) + rr(22, 21, 20, 4, 0.6) + rr(46, 21, 8, 4, 0.6)
           + rr(14, 24.5, 36, 4.5, 0.6) + rr(18, 28, 28, 14, 0.6) + rr(14, 41, 36, 4, 0.6)
           + rr(10, 44.5, 8, 4.5, 0.6) + rr(46, 44.5, 8, 4.5, 0.6), c1='#ffffff',
        g2=rr(25, 27, 14, 15, 0.6) + rr(22, 30, 3, 9, 0.6) + rr(39, 30, 3, 9, 0.6), c2='#8fd3a2'),

    'labplot': dict(
        label='LabPlot', base='#2c3348', lip='#1a1f2e',
        g1=rr(11, 29.3, 42, 2.4, 1.2) + rr(13, 11, 2.4, 38, 1.2)
           + rr(21.3, 27.5, 2.4, 6, 1.2) + rr(32.3, 27.5, 2.4, 6, 1.2) + rr(43.3, 27.5, 2.4, 6, 1.2), c1='#8a93ab',
        x=[(line(gauss(17, 51, 30.5, 44), 2.6), '#8a93ab'),
           (line(gauss(17, 51, 30.5, 12.5), 3.2), '#ffffff'),
           (line(gauss(20.5, 47.5, 30.5, 19.5), 3.2), '#5b9dff')]),

    'marble': compass_globe(
        '#2b8be6', '#1f68b3', 'Marble', '#bcd4ff',
        'M18 26c1.6-3.2 4.2-5.8 7.6-7.4 2.2.6 1.6 3 3.4 3.8 2 .8 4-1 6 .2-.6 2.2-3 2.8-3.6 4.8-.4 1.6 1.4 2.8.6 4.6-1.2 2.2-4.4 1.6-5.6 3.6-1 1.8.2 4.4-1.4 6.2-2.6-1.6-4.2-4.4-5.2-7.2-.6-1.8-.6-3.6-1.6-5.2-.4-1-.6-2-.2-3.4z'
        'M40 30c2.2-.8 4.6 0 6 1.4-.2 2.6-1.2 5.2-3 7.2-1.2 1.2-2.6 2.2-4.2 2.6-.4-2 .6-3.6.2-5.4-.4-2-1.4-3.6-.2-5.8z',
        '#ffffff', needle_up_right=False, tail='#2b8be6'),

    'marble-maps': compass_globe(
        '#3f8f5a', '#2d6b42', 'Marble Maps', '#5b9dff',
        'M17 27.5c.6-4 3.2-7.6 6.6-9.8 2.6-.2 4.6 1.6 4.4 3.8-.2 2-2.4 2.6-2.4 4.6 0 2.4 3.2 3 3.4 5.4.2 2.6-2.6 4-3.2 6.4-.4 1.8.4 3.6-.6 5-3-1.2-5.6-3.6-6.8-6.6-.8-2.2-.4-4.6-1.4-6.6z'
        'M36.6 16.4c3.4.8 6.4 2.8 8.4 5.6-1.6.8-3.6.2-5 1.4-1.2 1 0 2.8-.8 4.2-1 1.6-3.4 1.4-4.4 3-.8 1.4.2 3.4-.8 4.6-1.4-1.6-1.2-4-2-5.8-.8-1.6-2.6-2.4-2.4-4.4.2-2.4 3-3.2 4.4-5 .8-1.2.4-2.4 2.6-3.6z',
        '#3f8f5a', needle_up_right=True),

    'minuet': dict(
        label='Minuet', base='#5a2ca0', lip='#3e1e70',
        g1=rr(11, 11, 14, 38, 4), c1='#e5484d',
        g2=rr(37, 11, 16, 38, 4), c2='#5b9dff',
        x=[(poly((19.4, 11), (28.4, 11), (28.4, 49), (19.4, 49)), '#f2a65a'),
           (poly((27.8, 11), (36.8, 11), (36.8, 49), (27.8, 49)), '#f7c948'),
           (poly((36.2, 11), (45.2, 11), (45.2, 49), (36.2, 49)), '#3cc4b0'),
           (rr(16.8, 11, 5.2, 21, 1.6) + rr(25.2, 11, 5.2, 21, 1.6) + rr(42.6, 11, 5.2, 21, 1.6)
            + poly((16.8, 11), (22, 11), (22, 14), (16.8, 14)) + poly((25.2, 11), (30.4, 11), (30.4, 14), (25.2, 14))
            + poly((42.6, 11), (47.8, 11), (47.8, 14), (42.6, 14)), '#1b2031')]),

    'parley': dict(
        label='Parley', base='#2b6fd6', lip='#1f52a3',
        g1=rr(18, 10, 36, 27, 3.5), c1='#bcd4ff',
        g2=rr(10, 18, 38, 30, 3.5), c2='#ffffff',
        s1='M23.5 28.5c3.6-3.2 10.4-4.6 14.4-2.8 3.6 1.6 2.4 6.2-2.2 7.6-3 .9-6.2.6-8-.4'
           'M33.6 26.4c-1.6 6-4.4 12.6-9 17.6', sc='#2b6fd6', sw=3.8,
        x=[(rr(10, 22.4, 38, 2.4, 0), '#e5484d')]),

    # review: light base with the original's black K and blue ring; on steel it was Kwave's twin (white K
    # on steel), and on blue it would be Kile's (white K on blue)
    'rkward': dict(
        label='RKWard', base='#f4f5f9', lip='#d5d9e3',
        g2=el(25, 37, 14.5, 8.8) + el(25, 37, 7.6, 3.6), c2='#3f7fe0',
        x=[(k_mark(28.5, 10, 36, 6.2, 0.46), '#1b2031'),
           ('M8.9 37A16.1 10.4 0 0 0 41.1 37H34.1A9.1 2.1 0 0 1 15.9 37z', '#f4f5f9'),
           ('M10.5 37A14.5 8.8 0 0 0 39.5 37H32.6A7.6 3.6 0 0 1 17.4 37z', '#3f7fe0')]),

    'rocs': dict(
        label='Rocs', base='#1aa391', lip='#127a6c',
        g2=gear(25, 33, 15.5, 12, 9) + ci(25, 33, 6.5), c2='#ffffff',
        s1='M36 14L42.5 27.5M49 16L42.5 27.5M42.5 27.5L50 36.5M42.5 27.5L40 44M50 36.5L40 44M36 14L49 16',
        sc='#1b2031', sw=2.4,
        x=[(C(36, 14, 3.6) + C(42.5, 27.5, 3.6) + C(40, 44, 3.6), '#5b9dff'),
           (C(49, 16, 3.3) + C(50, 36.5, 3.3), '#ffffff')]),

    'step': dict(
        label='Step', base='#5b6478', lip='#414859',
        g1=line([(11.5, 48.8)] + arcpts(17, 17.5, 5.5, 180, 270, 6) + arcpts(47, 17.5, 5.5, 270, 360, 6) + [(52.5, 48.8)], 3),
        c1='#ffffff',
        s1='M20 15v20M29 15v20M38 15v20M45 15l4.6 14', sc='#c5cbe0', sw=2.4,
        x=[(C(20, 39, 6.4) + C(29, 39, 6.4) + C(38, 39, 6.4) + C(50.4, 32.4, 5.8), '#5b6478'),
           (C(20, 39, 4.6) + C(29, 39, 4.6) + C(38, 39, 4.6) + C(50.4, 32.4, 4.1), '#ffffff'),
           (C(18.5, 37.5, 1.4) + C(27.5, 37.5, 1.4) + C(36.5, 37.5, 1.4) + C(49.1, 31.1, 1.25), '#c5cbe0')]),

    'kwordquiz': dict(
        label='WordQuiz', base='#e8743b', lip='#b8552a',
        g1=rrot(25.5, 29, 22, 30, 3.5, -12), c1='#ffd6bd',
        g2=rrot(38, 30, 23, 32, 3.5, 10), c2='#5b9dff',
        x=[(qmark(38, 19.5, 21, 4.4), '#ffffff')]),
}

APPS = {
    'org.kde.artikulate': 'artikulate',
    'org.kde.marble.behaim': 'marble-behaim',
    'org.kde.cantor': 'cantor',
    'org.kde.kalgebra': 'kalgebra',
    'org.kde.kalgebramobile': 'kalgebra-mobile',
    'org.kde.kalzium': 'kalzium',
    'org.kde.kbibtex': 'kbibtex',
    'org.kde.kbruch': 'kbruch',
    'org.kde.kgeography': 'kgeography',
    'org.kde.kig': 'kig',
    'org.kde.kiten': 'kiten',
    'org.kde.klettres': 'klettres',
    'org.kde.kmplot': 'kmplot',
    'org.kde.kstars': 'kstars',
    'org.kde.ktechlab': 'ktechlab',
    'org.kde.ktouch': 'ktouch',
    'org.kde.kturtle': 'kturtle',
    'org.kde.labplot': 'labplot',
    'org.kde.marble': 'marble',
    'org.kde.marble.maps': 'marble-maps',
    'org.kde.minuet': 'minuet',
    'org.kde.parley': 'parley',
    'org.kde.rkward': 'rkward',
    'org.kde.rocs': 'rocs',
    'org.kde.step': 'step',
    'org.kde.kwordquiz': 'kwordquiz',
}
