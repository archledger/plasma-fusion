# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, batch games-a (KDE board and arcade games, A to KSquares).
import math

from apptiles.kit import *  # noqa: F401,F403
from svgkit import transform_abs_path


def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pts(*p):
    return "M" + "L".join(f"{_f(x)} {_f(y)}" for x, y in p) + "z"


def rot(cx, cy, ang, p):
    """Rotate points p about (cx, cy) by ang degrees (clockwise on screen)."""
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in p]


def rbox(cx, cy, w, h, ang):
    """Rectangle centred on (cx, cy), rotated by ang degrees."""
    return pts(*rot(cx, cy, ang, [(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2),
                                  (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)]))


def star(cx, cy, ro, ri, n, a0=-90):
    p = []
    for k in range(2 * n):
        r = ro if k % 2 == 0 else ri
        a = math.radians(a0 + 180 * k / n)
        p.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts(*p)


def cross(cx, cy, arm, w):
    """X mark as two rotated bars (fill)."""
    return rbox(cx, cy, 2 * arm, w, 45) + rbox(cx, cy, 2 * arm, w, -45)


def yinyang(cx, cy, R, ang):
    """Two halves (a, b), the S curve between them, and the two eye centres (in a, in b)."""
    ux, uy = math.sin(math.radians(ang)), -math.cos(math.radians(ang))
    T = (cx + R * ux, cy + R * uy); B = (cx - R * ux, cy - R * uy); r = R / 2
    t, b, m = f"{_f(T[0])} {_f(T[1])}", f"{_f(B[0])} {_f(B[1])}", f"{_f(cx)} {_f(cy)}"
    half_a = f"M{t}A{_f(R)} {_f(R)} 0 0 0 {b}A{_f(r)} {_f(r)} 0 0 0 {m}A{_f(r)} {_f(r)} 0 0 1 {t}z"
    half_b = f"M{t}A{_f(R)} {_f(R)} 0 0 1 {b}A{_f(r)} {_f(r)} 0 0 0 {m}A{_f(r)} {_f(r)} 0 0 1 {t}z"
    s_curve = f"M{t}A{_f(r)} {_f(r)} 0 0 0 {m}A{_f(r)} {_f(r)} 0 0 1 {b}"
    eye_b = (cx + r * ux, cy + r * uy); eye_a = (cx - r * ux, cy - r * uy)
    return half_a, half_b, s_curve, eye_a, eye_b


# Kajongg: the green dragon character, traced from the original (0-64 units) and scaled onto the tile.
_FA = ("M24 3C18 10 10 16 2 19M10 9L21 9M13 11L21 15"
       "M33 7L40 3M31 9C40 16 50 22 60 25M33 13L52 12M40 4L31 17"
       "M10 23L22 23L22 35L5 35L5 45L19 45L19 55C19 58 17 58 13 58"
       "M30 25C30 33 28 37 24 40M30 24L38 24L38 32C38 36 44 37 51 36"
       "M26 44L50 44C45 52 35 57 22 60M30 48C40 54 50 58 58 60")
FA = transform_abs_path(_FA, 0.44, 18.3, 13.6)

# KNights: the knight, traced from the original (0-64 units).
_KNIGHT = ("M31 6C38 9 43 15 44 24C45 31 44 36 43 40L25 40C25 33 27 28 31 23"
           "C29 22 26 21 22 21C19 21 16 21 15 19C13 17 15 14 18 13C22 11 25 9 28 8L31 6Z")
_KBASE = "M27 45C27 50 23 52 22 54L46 54C45 52 41 50 41 45Z"


def _kn(d):
    return transform_abs_path(d, 0.8, 32 - 31 * 0.8 + 0.6, 9 - 6 * 0.8)


KNIGHT = _kn(_KNIGHT)
KBASE = _kn(_KBASE) + rr(16.6, 46.4, 30.8, 3.6, 1.8) + rr(19.4, 40.8, 25.2, 3.4, 1.7)

# Granatier: bomb with its cap and fuse.
_bc, _br = (29.0, 33.0), 14.0
_d = (math.cos(math.radians(-45)), math.sin(math.radians(-45)))
_cap = (_bc[0] + 13.2 * _d[0], _bc[1] + 13.2 * _d[1])

# Bovo: red pencil from the top right, its tip on the bottom-middle O.
def _pencil(tip, end, w, cone):
    dx, dy = end[0] - tip[0], end[1] - tip[1]; L = math.hypot(dx, dy); ux, uy = dx / L, dy / L
    nx, ny = -uy * w / 2, ux * w / 2
    cb = (tip[0] + ux * cone, tip[1] + uy * cone)
    body = pts((cb[0] + nx, cb[1] + ny), (end[0] + nx, end[1] + ny), (end[0] - nx, end[1] - ny),
               (cb[0] - nx, cb[1] - ny))
    return body, pts(tip, (cb[0] + nx, cb[1] + ny), (cb[0] - nx, cb[1] - ny))


PENCIL = _pencil((35, 44.5), (50.8, 12.2), 6.4, 7.5)

# KReversi
_ya, _yb, _ys, _yea, _yeb = yinyang(32, 30, 18, 40)

# Kolf: round badge as in the original; the grass is the lower segment of the badge, cut by a soft curve.
_hx = math.sqrt(19 ** 2 - 5 ** 2)

TILES = {
    'atlantik': dict(
        label='Atlantik', base='#3f8f5a', lip='#2d6b42',
        g2=rr(20, 9, 32, 32, 4) + 'M' + rr(27, 16, 18, 18, 2)[1:], c2='#d6efd9',
        g3=pts((36, 19.5), (41.5, 25), (36, 30.5), (30.5, 25)), c3='#d6efd9',
        x=[(rr(28.5, 10.4, 6, 4, 1.2) + rr(37.5, 10.4, 6, 4, 1.2) + rr(46.6, 27.5, 4, 6, 1.2), '#e5484d'),
           (rr(8.5, 23.5, 27, 27, 7), '#3f8f5a'),
           (rr(11, 26, 22, 22, 5.5), '#ffffff'),
           (ci(16.6, 31.6, 2.4) + ci(27.4, 31.6, 2.4) + ci(16.6, 42.4, 2.4) + ci(27.4, 42.4, 2.4), '#3f8f5a')]),
    'bomber': dict(
        # review: orange base and yellow fire; the white jet on sky blue matched KDE Itinerary's airliner at 32 px
        label='Bomber', base='#e8743b', lip='#b8552a',
        g1='M18 22C18 18.6 21 17 25 17H41C47.5 17 52 19.4 53.5 22C52 24.6 47.5 27 41 27H25C21 27 18 25.4 18 22Z'
           'M19.5 19.5L16.5 10H21.5L29 17.5Z' + 'M31 23.5H41.5L28.5 34.5H22.5Z', c1='#ffffff',
        g2=el(34.5, 37, 3.8, 5.2) + pts((32, 32.2), (37, 32.2), (36.2, 30.4), (32.8, 30.4)), c2='#1b2031',
        g3=star(34.5, 45.4, 4.6, 2.1, 7) + 'M18 19.8C14.5 19.8 12 21 10.5 22C12 23 14.5 24.2 18 24.2Z',
        c3='#f7c948'),
    'bovo': dict(
        label='Bovo', base='#f6f4ef', lip='#d6d0c2',
        g1=cross(32, 17, 5, 3.2) + cross(32, 30, 5, 3.2), c1='#3f7fe0',
        s1='M25.5 11V49M38.5 11V49M12 23.5H52M12 36.5H52', sc='#c4bdac', sw=2.4,
        g3=ring(19, 43, 5.2, 2.6) + ring(32, 43, 5.2, 2.6), c3='#e5484d',
        x=[(PENCIL[0], '#e5484d'), (PENCIL[1], '#c4bdac')]),
    'granatier': dict(
        label='Granatier', base='#f5c84c', lip='#c99a22',
        g1=ci(_bc[0], _bc[1], _br) + rbox(_cap[0], _cap[1], 9, 6, -45), c1='#1b2031',
        s1=f'M{_f(_cap[0] + 2.6)} {_f(_cap[1] - 2.6)}C42 19 44 18 45.5 15', sc='#1b2031', sw=2.6,
        g3=star(45.5, 15, 5.8, 2.3, 6), c3='#e5484d',
        x=[(el(23, 27.5, 3.2, 4.2), '#ffffff')]),
    'kajongg': dict(
        label='Kajongg', base='#2f9e6e', lip='#227650',
        g1=rr(14, 12.5, 36, 37.5, 5), c1='#bfe6d2',
        g2=rr(14, 9, 36, 37, 5), c2='#ffffff',
        s1=FA, sc='#1d7a52', sw=2.5),
    'kapman': dict(
        label='Kapman', base='#262c42', lip='#131726',
        g1=el(20, 45.5, 5.5, 3.4) + el(33, 45.5, 5.5, 3.4), c1='#ffffff',
        g2=f'M27 28L{_f(27 + 15 * math.cos(math.radians(38)))} {_f(28 - 15 * math.sin(math.radians(38)))}'
           f'A15 15 0 1 0 {_f(27 + 15 * math.cos(math.radians(38)))} {_f(28 + 15 * math.sin(math.radians(38)))}z',
        c2='#f7c948',
        g3=ci(25.5, 19.5, 2.4), c3='#1b2031',
        x=[(ci(46, 28, 3), '#ffffff')]),
    'kblackbox': dict(
        label='KBlackbox', base='#5b6478', lip='#414859',
        g1=pts((12, 20), (22, 10), (52, 10), (42, 20)), c1='#b4bbcd',
        g2=pts((12, 20), (42, 20), (52, 10), (52, 40), (42, 50), (12, 50)), c2='#1b2031',
        s1='M21.6 31.2a5.6 5.6 0 1 1 8 5.1c-1.7.8-2.6 1.8-2.6 3.9', sc='#ffffff', sw=3.6,
        g3=ci(27, 45.3, 2.2), c3='#ffffff',
        x=[(rr(41.3, 20, 1.4, 30, 0.7), '#5b6478')]),
    'kblocks': dict(
        label='KBlocks', base='#f4f5f9', lip='#d5d9e3',
        g1=rr(12, 10, 12, 12, 2.5) + rr(12, 24, 12, 12, 2.5) + rr(26, 38, 12, 12, 2.5), c1='#3f7fe0',
        g2=rr(26, 10, 12, 12, 2.5) + rr(40, 24, 12, 12, 2.5) + rr(12, 38, 12, 12, 2.5), c2='#e5484d',
        g3=rr(40, 10, 12, 12, 2.5) + rr(26, 24, 12, 12, 2.5) + rr(40, 38, 12, 12, 2.5), c3='#f2a65a'),
    'kbounce': dict(
        label='KBounce', base='#5a2ca0', lip='#3e1e70',
        s1='M17 23L16 47M23.5 29.5L16 47M30.5 24.5L16 47L50 33', sc='#cbb8f0', sw=2.6,
        g2=ci(24, 20.5, 9.5), c2='#5b9dff',
        g3=ci(20.8, 17.3, 3), c3='#ffffff'),
    'kbrickbuster': dict(
        label='KBrickbuster', base='#1f9e8f', lip='#15756a',
        g1=rr(11, 11, 13, 6, 1.8) + rr(39.5, 11, 13, 6, 1.8) + rr(25.25, 19, 13, 6, 1.8), c1='#e5484d',
        g2=rr(25.25, 11, 13, 6, 1.8) + rr(39.5, 19, 13, 6, 1.8), c2='#f7c948',
        g3=ci(36, 34, 3.4) + rr(20, 43, 24, 5, 2.5), c3='#ffffff'),
    'kfourinline': dict(
        label='KFourInLine', base='#2f6fdf', lip='#2152ad',
        g1=ci(19, 17, 5.4) + ci(45, 17, 5.4) + ci(19, 30, 5.4), c1='#1d4fa6',
        g2=ci(32, 17, 5.4) + ci(32, 30, 5.4) + ci(32, 43, 5.4), c2='#e5484d',
        g3=ci(45, 30, 5.4) + ci(19, 43, 5.4) + ci(45, 43, 5.4), c3='#ffffff'),
    'kgoldrunner': dict(
        label='KGoldrunner', base='#b7792f', lip='#8a5a20',
        g1=ci(38, 13.5, 4.4), c1='#ffffff',
        s1='M35.5 20L30.5 31M34.5 22L27 25L22.5 21.5M34.5 22L41.5 26.5L46.5 23'
           'M30.5 31L38.5 37L36.5 46M30.5 31L24 39L15 39.5', sc='#ffffff', sw=4.4,
        g3=pts((40.5, 48.5), (53.5, 48.5), (51, 42.5), (43, 42.5)), c3='#f7c948'),
    'kigo': dict(
        label='Kigo', base='#6a9f2e', lip='#4f7722',
        g1=rr(10, 16, 44, 30, 6), c1='#4f7722',
        g2=rr(10, 13, 44, 30, 6), c2='#8fc152',
        s1='M19 17V39M32 17V39M45 17V39M14 21H50M14 33H50', sc='#6a9f2e', sw=2.4,
        g3=ci(32, 21, 6.6) + ci(19, 33, 6.6), c3='#1b2031',
        x=[(ci(32, 33, 6.6) + ci(45, 33, 6.6), '#ffffff')]),
    'kiriki': dict(
        label='Kiriki', base='#c93a42', lip='#992a31',
        g1=rr(13, 11, 38, 38, 9), c1='#ffffff',
        g3=ci(22.5, 20.5, 4.2) + ci(32, 30, 4.2) + ci(41.5, 39.5, 4.2), c3='#c93a42'),
    'kmahjongg': dict(
        label='KMahjongg', base='#a52a37', lip='#7c1f29',
        g1=rr(16, 12.5, 32, 37.5, 5), c1='#f4c7ca',
        g2=rr(16, 9, 32, 37, 5), c2='#ffffff',
        s1='M23 21H41V32H23ZM32 13.5V40', sc='#c93a42', sw=3.4),
    'knights': dict(
        label='KNights', base='#c2410c', lip='#922f08',
        g1=KNIGHT + KBASE, c1='#ffffff',
        g3=el(29.6, 15.4, 1.8, 1.5), c3='#c2410c'),
    'kolf': dict(
        # review: ball, green and red flag; the ball on its tee over a green hill read as a user-account avatar
        label='Kolf', base='#2b8be6', lip='#1f68b3',
        g1='M11 46C15.5 37.5 48.5 37.5 53 46A3.5 3.5 0 0 1 49.5 49.5H14.5A3.5 3.5 0 0 1 11 46Z', c1='#3aa65b',
        s1='M40 13.2V41', sc='#ffffff', sw=2.6,
        g3=pts((41.2, 11.5), (51.5, 16.2), (41.2, 21)), c3='#e5484d',
        x=[(ci(24.5, 34, 6), '#ffffff')]),
    'kollision': dict(
        label='Kollision', base='#9b3fb5', lip='#742d88',
        g1=ci(22.5, 21.5, 10.5), c1='#3cc4b0',
        g2=ci(41.5, 38.5, 9.5), c2='#3e1e70',
        g3=star(32.3, 30.3, 10.5, 3, 8, -67.5), c3='#f7c948'),
    'kreversi': dict(
        label='KReversi', base='#7b5cd6', lip='#5a40a8',
        g1=_ya, c1='#ffffff',
        g2=_yb, c2='#e5484d',
        s1=_ys, sc='#7b5cd6', sw=2.4,  # review: separator to the 2.4 minimum
        g3=ci(_yeb[0], _yeb[1], 3), c3='#ffffff',
        x=[(ci(_yea[0], _yea[1], 3), '#e5484d')]),
    'kshisen': dict(
        label='KShisen', base='#e8743b', lip='#b8552a',
        g1=rr(11, 13, 20, 34, 4) + rr(33, 13, 20, 34, 4), c1='#b8552a',
        g2=rr(11, 10, 20, 34, 4) + rr(33, 10, 20, 34, 4), c2='#ffffff',
        g3=ring(21, 27, 6.2, 3.4) + ci(21, 27, 1.6), c3='#e5484d',
        x=[(rr(37.5, 15, 3.8, 10, 1.9) + rr(44.7, 15, 3.8, 10, 1.9)
            + rr(37.5, 29, 3.8, 10, 1.9) + rr(44.7, 29, 3.8, 10, 1.9), '#1f9e8f')]),
    'ksnakeduel': dict(
        label='KSnakeDuel', base='#3aa65b', lip='#2a7e44',
        s1='M31 17C22 18 19 25 25 29C31 33 44 30 45 38C46 46 36 49 27 47C18 45 15 39 20 35C24 32 31 34 31 40',
        sc='#f7c948', sw=5,
        g2=el(35, 16, 7.5, 5.2), c2='#f7c948',
        g3=ci(37.6, 14.6, 1.8), c3='#1b2031',
        x=[(star(47, 13.2, 4.2, 1.9, 5), '#f2a65a')]),
    'kspaceduel': dict(
        label='KSpaceDuel', base='#2c3348', lip='#1a1f2e',
        g1='M32 16C35 16 37 20 37 26L37 32L49 39L49 44L37 42L36 48L28 48L27 42L15 44L15 39L27 32L27 26'
           'C27 20 29 16 32 16Z' + rr(46, 33, 4.4, 13, 2.2) + rr(13.6, 33, 4.4, 13, 2.2), c1='#e8ebf4',
        g2=el(32, 32, 2.8, 8), c2='#5b9dff',
        g3='M32 9C34.6 12 35.4 14.2 34.4 16.8H29.6C28.6 14.2 29.4 12 32 9Z', c3='#f2a65a'),
    'ksquares': dict(
        label='KSquares', base='#475069', lip='#323950',
        g1=rr(15, 13, 17, 17, 1.5), c1='#5b9dff',
        g2=rr(32, 30, 17, 17, 1.5), c2='#3cc4b0',
        s1='M15 13H32V30H15ZM32 30H49V47H32ZM32 13H49M15 30V47', sc='#ffffff', sw=2.6,
        g3=''.join(ci(x, y, 3.1) for x in (15, 32, 49) for y in (13, 30, 47)), c3='#ffffff'),
}

APPS = {
    'org.kde.atlantik': 'atlantik',
    'org.kde.bomber': 'bomber',
    'org.kde.bovo': 'bovo',
    'org.kde.granatier': 'granatier',
    'org.kde.kajongg': 'kajongg',
    'org.kde.kapman': 'kapman',
    'org.kde.kblackbox': 'kblackbox',
    'org.kde.kblocks': 'kblocks',
    'org.kde.kbounce': 'kbounce',
    'org.kde.kbrickbuster': 'kbrickbuster',
    'org.kde.kfourinline': 'kfourinline',
    'org.kde.kgoldrunner': 'kgoldrunner',
    'org.kde.kigo': 'kigo',
    'org.kde.kiriki': 'kiriki',
    'org.kde.kmahjongg': 'kmahjongg',
    'org.kde.knights': 'knights',
    'org.kde.kolf': 'kolf',
    'org.kde.kollision': 'kollision',
    'org.kde.kreversi': 'kreversi',
    'org.kde.kshisen': 'kshisen',
    'org.kde.ksnakeduel': 'ksnakeduel',
    'org.kde.kspaceduel': 'kspaceduel',
    'org.kde.ksquares': 'ksquares',
}
