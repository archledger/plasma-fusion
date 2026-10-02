# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, batch common-c: common third-party developer and gaming apps.
# Same construction as generators/icons/art_tiles.py (see build/kdeicons/STYLE.md).
import math

from apptiles.kit import *  # noqa: F401,F403  rr, ci, el, gear, ring, poly, PALETTE


# ---------------------------------------------------------------- geometry helpers

def _p(pts):
    """Closed polygon from (x, y) points, normalised to run counter-clockwise on screen like ci() and el(),
    so that unions of these shapes in a nonzero layer (g1, x) never cancel where they overlap."""
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    if area > 0:
        pts = list(reversed(pts))
    return poly(*pts)


def rrp(x, y, w, h, r, n=6):
    """Rounded rectangle as a counter-clockwise polygon (rr() runs clockwise), safe in nonzero unions."""
    return _p(rr_pts(x, y, w, h, (r, r, r, r), n))


def band(p, q, w):
    """Straight band of width w from point p to point q, ends cut square."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    n = math.hypot(dx, dy)
    ox, oy = -dy / n * w / 2, dx / n * w / 2
    return _p([(p[0] + ox, p[1] + oy), (q[0] + ox, q[1] + oy), (q[0] - ox, q[1] - oy), (p[0] - ox, p[1] - oy)])


def rot(pts, deg, c):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(c[0] + (x - c[0]) * ca - (y - c[1]) * sa, c[1] + (x - c[0]) * sa + (y - c[1]) * ca) for x, y in pts]


def mirror(pts, cx=32):
    """Mirror image of a point list about the vertical line x = cx (reversed so winding matches)."""
    return [(2 * cx - x, y) for x, y in reversed(pts)]


def cubic(p0, p1, p2, p3, n=10):
    out = []
    for k in range(1, n + 1):
        t = k / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def arc_pts(cx, cy, r, a0, a1, n=24):
    """Points on a circle from angle a0 to a1 (degrees, screen orientation: 90 = down)."""
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]


def rel(cx, cy, rx, ry, deg, n=36):
    """Ellipse rotated by deg degrees, as a counter-clockwise polygon."""
    pts = [(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n)) for k in range(n)]
    return _p(rot(pts, deg, (cx, cy)))


def sector(cx, cy, ro, ri, a0, a1, n=32):
    """Annulus sector from angle a0 to a1 (degrees)."""
    return _p(arc_pts(cx, cy, ro, a0, a1, n) + arc_pts(cx, cy, ri, a1, a0, n))


def clip_convex(subject, clip):
    """Sutherland-Hodgman: clip any polygon against a convex polygon (both counter-clockwise or both clockwise)."""
    def inside(p, a, b):
        return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0

    def cross(p1, p2, a, b):
        x1, y1 = p1; x2, y2 = p2; x3, y3 = a; x4, y4 = b
        d = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / d
        return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))

    out = subject
    for i in range(len(clip)):
        a, b = clip[i], clip[(i + 1) % len(clip)]
        inp, out = out, []
        if not inp:
            break
        s = inp[-1]
        for e in inp:
            if inside(e, a, b):
                if not inside(s, a, b):
                    out.append(cross(s, e, a, b))
                out.append(e)
            elif inside(s, a, b):
                out.append(cross(s, e, a, b))
            s = e
    return out


def rr_pts(x, y, w, h, radii, n=8):
    """Rounded rectangle as points, clockwise on screen; radii = (top-left, top-right, bottom-right, bottom-left)."""
    tl, tr, br, bl = radii
    pts = []
    pts += arc_pts(x + tl, y + tl, tl, 180, 270, n)
    pts += arc_pts(x + w - tr, y + tr, tr, 270, 360, n)
    pts += arc_pts(x + w - br, y + h - br, br, 0, 90, n)
    pts += arc_pts(x + bl, y + h - bl, bl, 90, 180, n)
    return pts


# ---------------------------------------------------------------- shared motifs

def jb_letters_ij(x, y):
    """JetBrains-style 'IJ' monogram, cap height 12.5, top-left at (x, y)."""
    return (f"M{x} {y}h3.4v12.5H{x}z"
            f"M{x + 8.6} {y}H{x + 12}v8.6a4 4 0 0 1-4 4h-2.6v-3.3h2.4a.8.8 0 0 0 .8-.8z")


def jb_letters_pc(x, y):
    """JetBrains-style 'PC' monogram, cap height 12.5, top-left at (x, y)."""
    p = (f"M{x} {y}h6.2a4.3 4.3 0 0 1 0 8.6h-2.9v3.9H{x}z"
         f"M{x + 3.3} {y + 3}v2.6h2.8a1.3 1.3 0 0 0 0-2.6z")
    cx, cy = x + 15.4, y + 6.25
    c = _p(arc_pts(cx, cy, 6.25, 42, 318, 28) + arc_pts(cx, cy, 3.05, 318, 42, 28))
    return p + c


def jetbrains(label, base, lip, accent, shard, letters):
    return dict(label=label, base=base, lip=lip,
                g1=shard, c1=accent,                                # coloured shard behind the square
                g2=rr(17, 12, 30, 30, 1.5), c2='#1b2031',           # the black JetBrains square
                g3=letters + rr(20.5, 35.5, 11, 3, 0.4), c3='#ffffff')  # monogram + bar


# ---------------------------------------------------------------- tiles

# VS Code: the folded ribbon (right panel + two crossing bands, '<' notch).
_vsc_panel = _p([(40.5, 12.5), (46.5, 9.2), (52, 11.8), (52, 48.2), (46.5, 50.8), (40.5, 47.5)])
_vsc_bands = band((44, 12.5), (13, 37), 6.4) + band((44, 47.5), (13, 23), 6.4)

# VSCodium: the same ribbon family drawn soft: curved round-capped bands and a crescent panel.
_vscod_bands = 'M40.5 15.5C31 19.5 21 26.5 15 35.5M40.5 44.5C31 40.5 21 33.5 15 24.5'
_vscod_panel = 'M38.5 12.2c7-3.4 12.8-.6 13.5 4.8v26c-.7 5.4-6.5 8.2-13.5 4.8 3.2-5 4.8-11 4.8-17.8s-1.6-12.8-4.8-17.8z'

# Sublime Text: two rising planes with the darker, reversed middle plane between them.
_subl_top = _p([(14.5, 21), (49.5, 10.5), (49.5, 19), (14.5, 29.5)])
_subl_mid = _p([(14.5, 29.5), (32.4, 35.1), (14.5, 40.5)])   # visible part of the reversed plane
_subl_bot = _p([(14.5, 40.5), (49.5, 30), (49.5, 38.5), (14.5, 49)])

# Postman: a rocket heading up-right inside the orbit ring.
_rk = [(0, -14)] + cubic((0, -14), (4.6, -10), (5.4, -3), (4.6, 6), 10) + [(-4.6, 6)] + cubic((-4.6, 6), (-5.4, -3), (-4.6, -10), (0, -14), 10)[:-1]
_rk = [(32 + x, 30 + y) for x, y in _rk]
_fins = [[(27.4, 31), (23.5, 38.5), (27.4, 36.5)], [(36.6, 31), (40.5, 38.5), (36.6, 36.5)]]
_postman_rocket = _p(rot(_rk, 45, (32, 30))) + ''.join(_p(rot(fp, 45, (32, 30))) for fp in _fins)
_postman_window = ci(*rot([(32, 25)], 45, (32, 30))[0], 2.6)

# Meld: two interlocking spiral arms clipped to the rounded square of the original.
def _meld_arm(rot_deg):
    a = 18.5 / (2.25 * math.pi)
    T = 2.25 * math.pi + 1.6
    pts = []
    for k in range(0, 121):
        t = T * k / 120
        pts.append((a * t * math.cos(t), a * t * math.sin(t)))
    pts2 = []
    for k in range(120, -1, -1):
        t = math.pi + T * k / 120
        r = a * (t - math.pi)
        pts2.append((r * math.cos(t), r * math.sin(t)))
    # outer closing arc well outside the clip square
    big = [(30 * math.cos(T + s * math.pi / 16), 30 * math.sin(T + s * math.pi / 16)) for s in range(0, 17)]
    shape = pts + big + pts2
    a0 = math.radians(rot_deg)
    shape = [(32 + x * math.cos(a0) - y * math.sin(a0), 30 + x * math.sin(a0) + y * math.cos(a0)) for x, y in shape]
    sq = rr_pts(14, 12, 36, 36, (4, 12, 4, 12))
    return _p(clip_convex(shape, sq))


# Godot: the gear-topped robot head.
def _godot_head():
    s = rrp(13.5, 18, 37, 30, 12)
    s += rrp(23, 11.5, 6.5, 9, 1.6) + rrp(34.5, 11.5, 6.5, 9, 1.6)
    s += _p(rot([(13, 14), (19.5, 14), (19.5, 23), (13, 23)], -40, (16.25, 18.5)))
    s += _p(rot([(44.5, 14), (51, 14), (51, 23), (44.5, 23)], 40, (47.75, 18.5)))
    return s


# RetroArch: the invader-controller mark, traced from the original on a 64 grid, then scaled.
def _retro():
    S, CY = 0.7, 30.8

    def T(pts):
        return [(32 + (x - 32) * S, 30 + (y - CY) * S) for x, y in pts]
    left = [(32, 20.8), (15.2, 20.8), (14.4, 28), (8, 28), (8.8, 20.8), (4.6, 20.8), (1.6, 34), (11.6, 34),
            (12.2, 39.4), (19, 39.4), (13.6, 46.6), (19.2, 46.6), (25.4, 39.4), (32, 39.4)]
    outline = left + [(64 - x, y) for x, y in reversed(left[1:-1])]
    horn = [(19.4, 14.8), (25, 14.8), (30.6, 21.4), (25, 21.4)]
    shape = _p(T(outline)) + _p(T(horn)) + _p(T(mirror(horn)))
    eyes = _p(T([(18.4, 23.8), (24.8, 23.8), (24.8, 30.4), (18.4, 30.4)])) + _p(T(mirror([(18.4, 23.8), (24.8, 23.8), (24.8, 30.4), (18.4, 30.4)])))
    return shape, eyes


_retro_shape, _retro_eyes = _retro()

# Bottles: three bottles of different heights.
_bottle_l = 'M16 19h5v3.5c2.2 1.5 3.4 3.6 3.4 6.2V45.5a2.5 2.5 0 0 1-2.5 2.5h-6.8a2.5 2.5 0 0 1-2.5-2.5V28.7c0-2.6 1.2-4.7 3.4-6.2z'
_bottle_m = 'M29.5 12h5v4.5c2.3 1.2 3.5 3.3 3.5 5.8v23.2a2.5 2.5 0 0 1-2.5 2.5h-7a2.5 2.5 0 0 1-2.5-2.5V22.3c0-2.5 1.2-4.6 3.5-5.8z'
_bottle_r = rrp(40, 21, 11, 27, 3) + rrp(42, 16.5, 7, 5.5, 1.5)

# Prism Launcher: the isometric prism cube, three facets.
_pc, _pr = (32, 30), 18
_hx = [(32 + _pr * math.cos(math.radians(-90 + 60 * k)), 30 + _pr * math.sin(math.radians(-90 + 60 * k))) for k in range(6)]
_prism_top = _p([_hx[0], _hx[1], _pc, _hx[5]])
_prism_left = _p([_hx[5], _pc, _hx[3], _hx[4]])
_prism_right = _p([_pc, _hx[1], _hx[2], _hx[3]])

TILES = {
    'vscode': dict(label='Visual Studio Code', base='#2b8be6', lip='#1f68b3',
                   g1=_vsc_bands, c1='#bfe0ff',
                   g3=_vsc_panel, c3='#ffffff'),
    # Review: VSCodium's own mark is the branching coral, not the VS Code ribbon (that read as VS Code at 32 px).
    'vscodium': dict(label='VSCodium', base='#1d8fb3', lip='#156b87',
                     s1=('M32 48.5C32 43 31.5 39 32 34M32 34C32 27 30.5 22 31.2 15'
                         'M31.8 38.5C25 38 20.5 34 19 26.5M19 26.5C18.6 22.5 19.6 19 21.4 15.6'
                         'M20.4 31.6C17.4 31.2 15 29.6 13.8 26.4'
                         'M32 31.5C38.5 31 43 27.5 44.6 21.5M44.6 21.5C45 18 44.4 15.6 42.6 13'
                         'M43.4 26.4C46.6 26.4 48.8 24.8 50.2 22'), sc='#ffffff', sw=5,
                     g3=ci(31.2, 14.4, 3.3) + ci(21.6, 14.8, 3.3) + ci(13.6, 25.6, 3.3) + ci(42.2, 12.4, 3.3)
                        + ci(50.4, 21.2, 3.3), c3='#ffffff'),
    'sublime-text': dict(label='Sublime Text', base='#ef8f22', lip='#b86a14',
                         g1=_subl_mid, c1='#ffd9a8',
                         g2=_subl_top + _subl_bot, c2='#ffffff'),
    'intellij-idea': jetbrains('IntelliJ IDEA', '#e0386a', '#ad2750', '#f2a65a',
                               _p([(11, 41), (40, 9.5), (53, 9.5), (53, 16), (24, 49.5), (11, 49.5)]),
                               jb_letters_ij(20.5, 16)),
    'pycharm': jetbrains('PyCharm', '#22a86c', '#187e51', '#f7c948',
                         _p([(11, 9.5), (24, 9.5), (53, 41), (53, 49.5), (40, 49.5), (11, 16)]),
                         jb_letters_pc(20.5, 16)),
    'android-studio': dict(label='Android Studio', base='#1f5a70', lip='#153f4f',
                           g1='M21 24.5a11 11 0 0 1 22 0z', c1='#3ddc84',                 # the Android head
                           s1='M25.5 15.5l-2.6-4.4M38.5 15.5l2.6-4.4', sc='#3ddc84', sw=2.4,
                           x=[(ci(27.5, 20, 1.7) + ci(36.5, 20, 1.7), '#1f5a70'),
                              (band((30.6, 28), (20.5, 48.5), 5) + band((33.4, 28), (43.5, 48.5), 5) + ci(32, 27.5, 5),
                               '#ffffff'),                                            # drafting compass
                              (ci(32, 27.5, 1.8), '#1f5a70')]),
    'github-desktop': dict(label='GitHub Desktop', base='#7b5cd6', lip='#5a40a8',
                           g1=ci(32, 30, 18.5), c1='#ffffff',
                           s1='M28.6 41.5c-3.2.6-5.4-.6-7-3.4', sc='#7b5cd6', sw=2.6,
                           x=[(el(32, 28.5, 10.2, 8.2)
                               + _p([(22.6, 26), (23.6, 16.6), (29.5, 21)]) + _p([(41.4, 26), (40.4, 16.6), (34.5, 21)])
                               + _p([(28.2, 34), (35.8, 34), (35.8, 49.5), (28.2, 49.5)]), '#7b5cd6')]),
    'postman': dict(label='Postman', base='#ef5b25', lip='#b8431a',
                    g2=ring(32, 30, 18, 15.2), c2='#ffc9b2',
                    g3=_postman_rocket, c3='#ffffff',
                    x=[(_postman_window, '#ef5b25')]),
    'dbeaver': dict(label='DBeaver', base='#475069', lip='#323950',
                    g1=ci(19.5, 20, 3.6) + ci(44.5, 20, 3.6) + el(32, 29.5, 16, 13), c1='#f2a65a',
                    g2=el(32, 35.5, 8.5, 5.8), c2='#ffffff',
                    g3=ci(25, 25.5, 2.3) + ci(39, 25.5, 2.3) + el(32, 32.6, 3.6, 2.5), c3='#1b2031',
                    x=[(rr(28.4, 37, 3.4, 10, 1.3) + rr(32.2, 37, 3.4, 10, 1.3), '#ffffff')]),
    'meld': dict(label='Meld', base='#3f7fe0', lip='#2b5db5',
                 g1=rr(14, 12, 36, 36, 6), c1='#5b9dff',
                 g2=_meld_arm(200), c2='#f2a65a'),
    'godot': dict(label='Godot', base='#478cbf', lip='#336a92',
                  g1=_godot_head(), c1='#ffffff',
                  g2=ci(23.5, 31, 5.6) + ci(40.5, 31, 5.6), c2='#478cbf',
                  s1='M12.5 40h6.5v3.4h7.5V40h11v3.4H45V40h6.5', sc='#478cbf', sw=2.5,
                  g3=ci(23.5, 31, 3.4) + ci(40.5, 31, 3.4), c3='#1b2031',
                  x=[(rr(30.8, 28, 2.4, 6.5, 1.2), '#478cbf')]),
    # Review: the real Podman Desktop mark is a container inside a hexagon on deep purple (no seal).
    'podman-desktop': dict(label='Podman Desktop', base='#5a2ca0', lip='#3e1e70',
                           g2=_p([(32 + 19 * math.cos(math.radians(a)), 30 + 19 * math.sin(math.radians(a)))
                                  for a in range(-90, 270, 60)])
                              + _p([(32 + 15.4 * math.cos(math.radians(a)), 30 + 15.4 * math.sin(math.radians(a)))
                                    for a in range(-90, 270, 60)]), c2='#d9ccff',
                           g3=rr(19.5, 22.5, 25, 15, 3), c3='#ffffff',
                           x=[(''.join(rr(x, 26, 2.6, 8, 1.3) for x in (23.6, 28.6, 33.6, 38.6)), '#5a2ca0')]),
    'alacritty': dict(label='Alacritty', base='#262c42', lip='#131726',
                      g1=_p([(32, 10), (52, 49.5), (43.5, 49.5), (32, 25), (20.5, 49.5), (12, 49.5)]), c1='#f2a65a',
                      g2=_p([(32, 27.5), (35.8, 36.5), (32, 47.5), (28.2, 36.5)]), c2='#5b9dff',
                      g3=_p([(32, 27.5), (35.8, 36.5), (32, 47.5)]), c3='#ffffff'),
    'kitty': dict(label='kitty', base='#a0602f', lip='#784823',  # review: nudged into HSL 40-60 % / 50-85 %
                  g1=el(32, 24, 13, 10) + _p([(19.5, 22), (20, 9.5), (28.5, 15.5)]) + _p([(44.5, 22), (44, 9.5), (35.5, 15.5)]),
                  c1='#f2a65a',
                  g2=rr(13, 27, 38, 22, 4), c2='#1b2031',
                  s1='M20 33.5l5 4-5 4', sc='#ffffff', sw=2.6,
                  g3=ci(27, 20, 2) + ci(37, 20, 2), c3='#1b2031',
                  x=[(rr(28.5, 40.2, 9, 2.6, 1.3), '#ffffff'), (el(22, 27, 3.6, 2.3) + el(42, 27, 3.6, 2.3), '#f2a65a')]),
    'steam': dict(label='Steam', base='#1f4f87', lip='#163a66',
                  g1=band((21, 38.5), (35, 28), 6.5) + ci(21, 38.5, 6.5), c1='#ffffff',
                  g2=ci(21, 38.5, 3.3) + ring(39, 23, 9.8, 6.4), c2='#ffffff',
                  g3=ci(39, 23, 4.4), c3='#ffffff',
                  x=[(ci(21, 38.5, 3.3), '#1f4f87')]),
    'lutris': dict(label='Lutris', base='#b7792f', lip='#8a5a20',
                   g1=ci(35, 33, 11.5), c1='#f7c948',
                   g2=sector(32, 31, 18.5, 13.5, -38, -320), c2='#ffffff',
                   x=[(rel(46, 19.8, 7.6, 5, 22), '#ffffff'),
                      (ci(45.6, 17.6, 1.7) + ci(52.2, 22.4, 1.6), '#1b2031')]),
    # Review: Heroic's real mark is a blue shield with a dark upright sword (the domino mask was a stand-in).
    'heroic': dict(label='Heroic', base='#262c42', lip='#131726',
                   g1=_p([(20.5, 10), (43.5, 10), (47, 20), (32, 50), (17, 20)]), c1='#5bb8ff',
                   g3=(_p([(32, 13), (34.7, 16.6), (34.7, 33), (29.3, 33), (29.3, 16.6)]) + rr(25, 33, 14, 3, 1.5)
                       + rr(30.6, 35.5, 2.8, 4.5, 0) + _p([(32, 39.8), (34.3, 42.2), (32, 44.6), (29.7, 42.2)])),
                   c3='#262c42'),
    'bottles': dict(label='Bottles', base='#1f9e8f', lip='#15756a',
                    g1=_bottle_l, c1='#f2a65a',
                    g2=_bottle_m, c2='#ffffff',
                    x=[(_bottle_r, '#e5484d'), (rr(26, 30, 12, 7, 0), '#1f9e8f'), (ci(18.4, 35, 2.6), '#ffffff')]),
    'prism-launcher': dict(label='Prism Launcher', base='#f4f5f9', lip='#d5d9e3',
                           g1=_prism_top, c1='#3cc4b0',
                           g2=_prism_left, c2='#f2a65a',
                           g3=_prism_right, c3='#5b9dff'),
    'retroarch': dict(label='RetroArch', base='#2c3348', lip='#1a1f2e',
                      g1=_retro_shape, c1='#ffffff',
                      x=[(_retro_eyes, '#2c3348')]),
    'moonlight': dict(label='Moonlight', base='#5b6478', lip='#414859',
                      g1=ci(32, 30, 18), c1='#ffffff',
                      g2=ci(32, 30, 13.5), c2='#5b6478',
                      s1='M32 17v26M19 30h26M22.8 20.8l18.4 18.4M41.2 20.8 22.8 39.2', sc='#ffffff', sw=2.6),
    # Review: the real ProtonUp-Qt mark is a green up arrow (outlined, pale inside) on white.
    'protonup-qt': dict(label='ProtonUp-Qt', base='#f4f5f9', lip='#d5d9e3',
                        g1=_p([(32, 9.5), (47, 25.5), (38.5, 25.5), (38.5, 49), (25.5, 49), (25.5, 25.5), (17, 25.5)]),
                        c1='#3aa65b',
                        g3=_p([(32, 15.5), (40.2, 24.2), (35.5, 24.2), (35.5, 46), (28.5, 46), (28.5, 24.2), (23.8, 24.2)]),
                        c3='#bdebc8'),
}

APPS = {
    'com.visualstudio.code': 'vscode',
    'com.vscodium.codium': 'vscodium',
    'com.sublimetext.three': 'sublime-text',
    'com.jetbrains.IntelliJ-IDEA-Community': 'intellij-idea',
    'com.jetbrains.PyCharm-Community': 'pycharm',
    'com.google.AndroidStudio': 'android-studio',
    'io.github.shiftey.Desktop': 'github-desktop',
    'com.getpostman.Postman': 'postman',
    'io.dbeaver.DBeaverCommunity': 'dbeaver',
    'org.gnome.Meld': 'meld',
    'org.godotengine.Godot': 'godot',
    'io.podman_desktop.PodmanDesktop': 'podman-desktop',
    'org.alacritty.Alacritty': 'alacritty',
    'kitty': 'kitty',
    'com.valvesoftware.Steam': 'steam',
    'net.lutris.Lutris': 'lutris',
    'com.heroicgameslauncher.hgl': 'heroic',
    'com.usebottles.bottles': 'bottles',
    'org.prismlauncher.PrismLauncher': 'prism-launcher',
    'org.libretro.RetroArch': 'retroarch',
    'com.moonlight_stream.Moonlight': 'moonlight',
    'net.davidotek.pupgui2': 'protonup-qt',
}
