# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, batch games-b (KDE games and kids' games).
import math
import re

from apptiles.kit import *  # noqa: F401,F403


def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pt(cx, cy, r, a):
    """Point on a circle; a in degrees, 0 = +x, positive = clockwise on screen."""
    t = math.radians(a)
    return cx + r * math.cos(t), cy + r * math.sin(t)


def P(pts):
    """Closed polygon path from a list of (x, y)."""
    return "M" + "L".join(f"{_f(x)} {_f(y)}" for x, y in pts) + "z"


def rot(pts, ang, cx, cy):
    """Rotate points by ang degrees (clockwise on screen) about (cx, cy)."""
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


def rrpts(cx, cy, w, h, r, ang=0.0, seg=6):
    """Rounded rectangle centred on (cx, cy), rotated by ang degrees, as points."""
    pts = []
    corners = [(cx + w / 2 - r, cy - h / 2 + r, -90), (cx + w / 2 - r, cy + h / 2 - r, 0),
               (cx - w / 2 + r, cy + h / 2 - r, 90), (cx - w / 2 + r, cy - h / 2 + r, 180)]
    for ox, oy, a0 in corners:
        for k in range(seg + 1):
            pts.append(pt(ox, oy, r, a0 + 90 * k / seg))
    return rot(pts, ang, cx, cy)


def rrr(cx, cy, w, h, r, ang=0.0):
    return P(rrpts(cx, cy, w, h, r, ang))


def band(cx, cy, ro, ri, a0, a1):
    """Annular sector from a0 to a1 (clockwise on screen)."""
    p0 = pt(cx, cy, ro, a0); p1 = pt(cx, cy, ro, a1)
    q1 = pt(cx, cy, ri, a1); q0 = pt(cx, cy, ri, a0)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{_f(p0[0])} {_f(p0[1])}A{_f(ro)} {_f(ro)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}"
            f"L{_f(q1[0])} {_f(q1[1])}A{_f(ri)} {_f(ri)} 0 {large} 0 {_f(q0[0])} {_f(q0[1])}z")


def ept(cx, cy, a, b, phi, t):
    """Point on an ellipse (semi-axes a, b) rotated by phi degrees, parameter t in degrees."""
    t = math.radians(t); p = math.radians(phi)
    x, y = a * math.cos(t), b * math.sin(t)
    return cx + x * math.cos(p) - y * math.sin(p), cy + x * math.sin(p) + y * math.cos(p)


def earc(cx, cy, a, b, phi, t0, t1, n=40):
    return [ept(cx, cy, a, b, phi, t0 + (t1 - t0) * k / n) for k in range(n + 1)]


def xpath(d, fn):
    """Map every point of an absolute M/L/C/Q/Z path through fn((x, y)) -> (x, y)."""
    out = []
    for cmd, args in re.findall(r'([MLCQZ])([^MLCQZ]*)', d):
        if cmd == 'Z':
            out.append('z')
            continue
        nums = [float(n) for n in re.findall(r'-?(?:\d+\.?\d*|\.\d+)', args)]
        pairs = []
        for i in range(0, len(nums), 2):
            x, y = fn((nums[i], nums[i + 1]))
            pairs.append(f"{_f(x)} {_f(y)}")
        out.append(cmd + ' '.join(pairs))
    return ''.join(out)


def inset(poly, d):
    """Inset a convex polygon by d units (works for either orientation)."""
    n = len(poly)
    area = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
    sgn = 1 if area > 0 else -1
    lines = []
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        ex, ey = x1 - x0, y1 - y0
        L = math.hypot(ex, ey)
        nx, ny = -ey / L * sgn, ex / L * sgn          # inward normal
        lines.append(((x0 + nx * d, y0 + ny * d), (ex, ey)))
    out = []
    for i in range(n):
        (p, r), (q, s) = lines[i - 1], lines[i]
        den = r[0] * s[1] - r[1] * s[0]
        t = ((q[0] - p[0]) * s[1] - (q[1] - p[1]) * s[0]) / den
        out.append((p[0] + t * r[0], p[1] + t * r[1]))
    return out


def sparkle(cx, cy, ro, ri):
    pts = []
    for k in range(8):
        pts.append(pt(cx, cy, ro if k % 2 == 0 else ri, -90 + 45 * k))
    return P(pts)


WHITE, INK = '#ffffff', '#1b2031'
ORANGE, TEAL, BLUE, RED, YELLOW, GREEN = '#f2a65a', '#3cc4b0', '#5b9dff', '#e5484d', '#f7c948', '#3aa65b'

# ---------------------------------------------------------------- Blinken: the four-colour oval
_bk_c, _bk_a, _bk_b, _bk_phi = (32, 30), 22.3, 16.2, -18
_bk = {}
for name, t0 in (('top', 225), ('right', 315), ('bottom', 45), ('left', 135)):
    _bk[name] = P([_bk_c] + earc(*_bk_c, _bk_a, _bk_b, _bk_phi, t0, t0 + 90))
_bk_sep = {}
for tb in (45, 135, 225, 315):
    ex, ey = ept(*_bk_c, _bk_a, _bk_b, _bk_phi, tb)
    a = math.degrees(math.atan2(ey - _bk_c[1], ex - _bk_c[0]))
    L = math.hypot(ex - _bk_c[0], ey - _bk_c[1]) + 1.2
    ux, uy = math.cos(math.radians(a)), math.sin(math.radians(a))
    _bk_sep[tb] = rrr(_bk_c[0] + ux * L / 2, _bk_c[1] + uy * L / 2, L, 3, 0.01, a)
# The separators are drawn in the tile colour; the upper two lie under the 9 % white sheen.
_bk_sheen = '#3f4558'

# ---------------------------------------------------------------- GCompris: globe stand with G + die
_gc_die = 46 - 2, 41
_gc_pips = rot([(_gc_die[0] - 3.4, _gc_die[1] - 3.4), _gc_die, (_gc_die[0] + 3.4, _gc_die[1] + 3.4)], -15, *_gc_die)

# ---------------------------------------------------------------- KHangMan pencil
_hm_T, _hm_E = (35.5, 45.5), (51, 16)
_hm_len = math.hypot(_hm_E[0] - _hm_T[0], _hm_E[1] - _hm_T[1])
_hm_d = ((_hm_E[0] - _hm_T[0]) / _hm_len, (_hm_E[1] - _hm_T[1]) / _hm_len)
_hm_n = (-_hm_d[1], _hm_d[0])


def _hm(a, b):
    """Point a units along the pencil from the tip and b units across."""
    return (_hm_T[0] + a * _hm_d[0] + b * _hm_n[0], _hm_T[1] + a * _hm_d[1] + b * _hm_n[1])


_hm_body = P([_hm(7, -3), _hm(_hm_len, -3), _hm(_hm_len, 3), _hm(7, 3)]) + ci(*_hm(_hm_len, 0), 3)
_hm_cone = P([_hm(0, 0), _hm(7, 3), _hm(7, -3)])
_hm_lead = P([_hm(0, 0), _hm(2.6, 1.15), _hm(2.6, -1.15)])

# ---------------------------------------------------------------- isometric cubes
def _iso(cx, top, w, h, H):
    T = (cx, top); Tr = (cx + w, top + h); Tc = (cx, top + 2 * h); Tl = (cx - w, top + h)
    Bl = (cx - w, top + h + H); Bc = (cx, top + 2 * h + H); Br = (cx + w, top + h + H)
    return dict(top=[T, Tr, Tc, Tl], left=[Tl, Tc, Bc, Bl], right=[Tc, Tr, Br, Bc],
                hull=[T, Tr, Br, Bc, Bl, Tl])


def _face_pt(face, u, v):
    """Point on a parallelogram face: face[0] + u * (face[1] - face[0]) + v * (face[3] - face[0])."""
    a, b, _, d = face
    return (a[0] + u * (b[0] - a[0]) + v * (d[0] - a[0]), a[1] + u * (b[1] - a[1]) + v * (d[1] - a[1]))


_jc = _iso(32, 11, 16.5, 9.4, 19)
_jc_pips = (ci(*_face_pt(_jc['top'], 0.5, 0.5), 2.6)
            + ''.join(ci(*_face_pt(_jc['left'], u, v), 2.1) for u, v in ((0.28, 0.28), (0.72, 0.72)))
            + ''.join(ci(*_face_pt(_jc['right'], u, v), 2.1) for u, v in ((0.24, 0.24), (0.5, 0.5), (0.76, 0.76))))

_kb = _iso(32, 10, 18, 10.4, 19.2)

def _kc(c, r):
    return rr(11.75 + 14 * c, 9.75 + 14 * r, 12.5, 12.5, 2.8)


# ---------------------------------------------------------------- Konquest: ringed planet
_kq_c, _kq_phi = (32, 30), -20
_kq_ring = P(earc(*_kq_c, 22, 7.6, _kq_phi, 0, 360, 72)) + P(earc(*_kq_c, 16, 4.6, _kq_phi, 0, 360, 72))
_kq_front = P(earc(*_kq_c, 22, 7.6, _kq_phi, 0, 180) + earc(*_kq_c, 16, 4.6, _kq_phi, 180, 0))

# ---------------------------------------------------------------- KPatience: two cards
_kp_back = rrpts(25, 31, 22, 31, 3.2, -14)
_kp_back_in = rrpts(25, 31, 16.5, 25.5, 2, -14)
_kp_front = rrpts(38, 29.5, 22, 31, 3.2, 10)
_kp_spade = xpath('M0 -7.5C-2 -4.5 -7.5 -1.5 -7.5 2.5C-7.5 5.8 -4.2 7.2 -1.6 5.3L-3.2 9.3L3.2 9.3L1.6 5.3'
                  'C4.2 7.2 7.5 5.8 7.5 2.5C7.5 -1.5 2 -4.5 0 -7.5Z',
                  lambda p: rot([(38 + p[0] * 0.95, 28.6 + p[1] * 0.95)], 10, 38, 29.5)[0])

# ---------------------------------------------------------------- KSame: cross-shaped tray
_ks_cells = [(0, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (2, 3), (3, 3), (2, 4)]
_ks_cs = 7.4
_ks_x0, _ks_y0 = 32 - 2.5 * _ks_cs, 30 - 2.5 * _ks_cs
_ks_tray = ''.join(rr(_ks_x0 + _ks_cs * c - 1.8, _ks_y0 + _ks_cs * r - 1.8, _ks_cs + 3.6, _ks_cs + 3.6, 1.8) for c, r in _ks_cells)
_ks_balls = ''.join(ci(_ks_x0 + _ks_cs * (c + 0.5), _ks_y0 + _ks_cs * (r + 0.5), 3.05) for c, r in _ks_cells)

# ---------------------------------------------------------------- KsirK: cannon
_sk_B, _sk_M = (43, 26.5), (14.5, 18.5)
_sk_L = math.hypot(_sk_M[0] - _sk_B[0], _sk_M[1] - _sk_B[1])
_sk_u = ((_sk_M[0] - _sk_B[0]) / _sk_L, (_sk_M[1] - _sk_B[1]) / _sk_L)
_sk_n = (-_sk_u[1], _sk_u[0])
_sk_ang = math.degrees(math.atan2(_sk_u[1], _sk_u[0]))
_sk_barrel = (P([(_sk_B[0] + 5.6 * _sk_n[0], _sk_B[1] + 5.6 * _sk_n[1]), (_sk_M[0] + 3.7 * _sk_n[0], _sk_M[1] + 3.7 * _sk_n[1]),
                 (_sk_M[0] - 3.7 * _sk_n[0], _sk_M[1] - 3.7 * _sk_n[1]), (_sk_B[0] - 5.6 * _sk_n[0], _sk_B[1] - 5.6 * _sk_n[1])])
              + ci(*_sk_B, 5.6) + rrr(_sk_M[0] - 0.6 * _sk_u[0], _sk_M[1] - 0.6 * _sk_u[1], 3.4, 10, 1.4, _sk_ang)
              + ci(_sk_B[0] - 6.8 * _sk_u[0], _sk_B[1] - 6.8 * _sk_u[1], 2.5))
_sk_W = (35, 32.5)
_sk_spokes = ''.join(f"M{_f(_sk_W[0])} {_f(_sk_W[1])}L{_f(pt(*_sk_W, 8, a)[0])} {_f(pt(*_sk_W, 8, a)[1])}"
                     for a in range(0, 360, 60))

# ---------------------------------------------------------------- Kolor Lines: diamond grid + red balls
_kl_dia, _kl_balls, _kl_hi = '', '', ''
for r, y in enumerate((16, 23, 30, 37, 44)):
    for x in ((18, 32, 46) if r % 2 == 0 else (25, 39)):
        _kl_dia += rrr(x, y, 8, 8, 1.6, 45)
for x, y in ((18, 44), (25, 37), (32, 30), (39, 23), (46, 16)):
    _kl_balls += ci(x, y, 4.7)
    _kl_hi += ci(x - 1.5, y - 1.6, 1.5)

# ---------------------------------------------------------------- Palapeli: two interlocking pieces
# Right piece's knob enters the left piece at y 22; the left piece's knob enters the right one at y 41.
_pp_kr, _pp_neck, _pp_gap = 4.6, 2.0, 1.6
_pp_K1 = (25.7, 22)      # right piece's knob centre (inside the left piece)
_pp_K2 = (38.3, 41)      # left piece's knob centre (inside the right piece)


def _pp_left():
    R = _pp_kr + _pp_gap
    hn = _pp_neck + _pp_gap
    sx = _pp_K1[0] + math.sqrt(R * R - hn * hn)
    nx = _pp_K2[0] - math.sqrt(_pp_kr ** 2 - _pp_neck ** 2)
    return (f"M15 11H31V{_f(_pp_K1[1] - hn)}H{_f(sx)}A{_f(R)} {_f(R)} 0 1 0 {_f(sx)} {_f(_pp_K1[1] + hn)}H31"
            f"V{_f(_pp_K2[1] - _pp_neck)}H{_f(nx)}A{_f(_pp_kr)} {_f(_pp_kr)} 0 1 1 {_f(nx)} {_f(_pp_K2[1] + _pp_neck)}"
            f"H31V46A3 3 0 0 1 28 49H15A3 3 0 0 1 12 46V38.59A3.6 3.6 0 1 0 12 33.41V14A3 3 0 0 1 15 11z")


def _pp_right():
    R = _pp_kr + _pp_gap
    hn = _pp_neck + _pp_gap
    sx = _pp_K2[0] - math.sqrt(R * R - hn * hn)
    nx = _pp_K1[0] + math.sqrt(_pp_kr ** 2 - _pp_neck ** 2)
    return (f"M33 11H49A3 3 0 0 1 52 14V21.41A3.6 3.6 0 1 0 52 26.59V46A3 3 0 0 1 49 49H33V{_f(_pp_K2[1] + hn)}H{_f(sx)}"
            f"A{_f(R)} {_f(R)} 0 1 0 {_f(sx)} {_f(_pp_K2[1] - hn)}H33V{_f(_pp_K1[1] + _pp_neck)}H{_f(nx)}"
            f"A{_f(_pp_kr)} {_f(_pp_kr)} 0 1 1 {_f(nx)} {_f(_pp_K1[1] - _pp_neck)}H33z")


# ---------------------------------------------------------------- Naval Battle: warship on the waves (side view)
_nb_ship = ('M11 33L53 31L48.6 44C48.2 45 47.5 45.5 46.4 45.5L16.2 45.5C15 45.5 14.1 45 13.6 44Z'
            + rr(22.5, 24, 17, 9.5, 2) + rr(26, 16.5, 8.5, 9, 2) + rr(37.5, 19.5, 5.5, 6, 1.5)
            + rr(42, 26.5, 8.5, 5.5, 2.5) + rr(14, 26.5, 8.5, 5.5, 2.5))
_nb_waves = 'M10 47.5' + ''.join(
    f"C{_f(10 + 8.8 * k + 2.9)} {45.2 if k % 2 == 0 else 49.8} {_f(10 + 8.8 * k + 5.9)} {45.2 if k % 2 == 0 else 49.8} "
    f"{_f(10 + 8.8 * (k + 1))} 47.5" for k in range(5)) + 'L54 50.5L10 50.5Z'


# ---------------------------------------------------------------- Skladnik: octahedron gem
_sd = dict(T=(32, 9.5), L=(14.5, 27.5), R=(49.5, 27.5), F=(31, 32), B=(32, 50.5))

TILES = {
    'blinken': dict(label='Blinken', base='#2c3348', lip='#1a1f2e',
                    x=[(_bk['top'], YELLOW), (_bk['right'], RED), (_bk['bottom'], GREEN), (_bk['left'], BLUE),
                       (_bk_sep[45] + _bk_sep[135], '#2c3348'), (_bk_sep[225] + _bk_sep[315], _bk_sheen),
                       (ci(32, 30, 10.5), INK),
                       (gear(32, 30, 7.6, 5.6, 8), WHITE), (ci(32, 30, 2.6), INK)]),

    'gcompris': dict(label='GCompris', base='#e8743b', lip='#b8552a',
                     g1=ci(30, 27, 12.5) + rr(21, 45.5, 18, 4, 2), c1=WHITE,
                     s1=(f"M{_f(pt(30, 27, 16.2, 292)[0])} {_f(pt(30, 27, 16.2, 292)[1])}"
                         f"A16.2 16.2 0 1 0 {_f(pt(30, 27, 16.2, 72)[0])} {_f(pt(30, 27, 16.2, 72)[1])}"
                         "M30 43.2V46.5"), sc=WHITE, sw=3.4,
                     g3=band(30, 27, 9, 4.3, 0, 315) + rr(30, 24.6, 9, 4.7, 0.5), c3='#e8743b',
                     x=[(rrr(*_gc_die, 17.5, 17.5, 4.6, -15), '#e8743b'), (rrr(*_gc_die, 13.5, 13.5, 3, -15), BLUE),
                        (''.join(ci(x, y, 1.75) for x, y in _gc_pips), WHITE)]),

    'kanagram': dict(label='Kanagram', base='#3f8f5a', lip='#2d6b42',
                     g1=rr(10, 10, 44, 28, 3.5), c1=WHITE,
                     g2=rr(13, 13, 38, 21, 1.5), c2=INK,
                     s1=('M16 29C19 27 21.5 21.5 21 18C20.5 15 17.5 15.5 17.5 19.5C17.5 24 18.5 29 21.5 29'
                         'C24.5 29 25.5 24 28.5 24C31.5 24 30 29 33 29C36 29 37 24 40 24C43 24 41.5 29 44.5 29'
                         'C46.5 29 47.5 27 48 25.5'
                         'M24.5 38L19.5 49.5M39.5 38L44.5 49.5M32 38V47'),
                     sc=WHITE, sw=2.4),

    'katomic': dict(label='KAtomic', base='#c2410c', lip='#922f08',
                    g1=ci(22.5, 21.5, 9.6), c1=WHITE,
                    g2=ci(40.5, 20.5, 10) + ci(21.5, 39.5, 10), c2=INK,
                    s1='M35.5 17.5A6 6 0 0 1 38 15.2M16.5 36.5A6 6 0 0 1 19 34.2', sc='#5d6680', sw=2.4,
                    g3=ci(40.5, 38, 11), c3=WHITE),

    'kdiamond': dict(label='KDiamond', base='#f4f5f9', lip='#d5d9e3',
                     x=[(rrr(22, 20, 13, 13, 2.4, 45), RED), (rrr(42, 20, 13, 13, 2.4, 45), ORANGE),
                        (rrr(22, 40, 13, 13, 2.4, 45), GREEN), (rrr(42, 40, 13, 13, 2.4, 45), BLUE)]),

    'khangman': dict(label='KHangMan', base='#3a7bd5', lip='#2a5ea8',
                     g1=rr(12, 10, 30, 40, 3), c1=WHITE,
                     s1=('M15.5 41H25M18.5 41V14.5H31V18M18.5 20.5L24.5 14.5'
                         + ci(31, 21.4, 3.2).replace('z', '') + 'M31 24.6V32M27 29L31 26.6L35 29M27.5 37L31 32L34.5 37'
                         'M15.5 46H19.5M23 46H27'),
                     sc='#3a7bd5', sw=2.4,
                     g3=_hm_body, c3=INK,
                     x=[(_hm_cone, ORANGE), (_hm_lead, INK)]),

    'killbots': dict(label='Killbots', base='#475069', lip='#323950',
                     g1=rr(20.5, 16.5, 23, 12, 4) + rr(17, 30, 30, 13, 4) + rr(10.5, 24, 6.5, 17, 3.2) + rr(47, 24, 6.5, 17, 3.2),
                     c1=YELLOW,
                     g2=rr(24, 19.5, 16, 6.5, 3.25) + rr(21, 33, 22, 7, 2) + rr(13.5, 43.5, 37, 6, 3), c2=INK,
                     g3=''.join(P([(24 + 5 * k, 40), (27 + 5 * k, 40), (31 + 5 * k, 33), (28 + 5 * k, 33)]) for k in range(3)),
                     c3=YELLOW,
                     x=[('M27.5 16.5V14.5A4.5 4.5 0 0 1 36.5 14.5V16.5z' + ci(28.5, 22.75, 1.8) + ci(35.5, 22.75, 1.8)
                         + ci(13.75, 28, 1.7) + ci(50.25, 28, 1.7), RED)]),

    # review: teal instead of red; a white die on red was Kiriki's twin at 32 px
    'kjumpingcube': dict(label='KJumpingCube', base='#1aa391', lip='#127a6c',
                         g1=P(_jc['top']), c1=WHITE,
                         g2=P(_jc['left']), c2='#d6f1ec',
                         g3=P(_jc['right']), c3='#a8e2d9',
                         x=[(_jc_pips, INK)]),

    'klickety': dict(label='Klickety', base='#262c42', lip='#131726',
                     x=[(_kc(0, 0) + _kc(0, 1), RED), (_kc(2, 0) + _kc(2, 1), BLUE),
                        (_kc(1, 1) + _kc(0, 2), ORANGE), (_kc(1, 2) + _kc(2, 2), GREEN)]),

    # review: green (a minefield) instead of yellow; the ink mine on yellow was Granatier's ink bomb on yellow
    'kmines': dict(label='KMines', base='#3aa65b', lip='#2a7e44',
                   g1=ci(32, 30.5, 12.5), c1=INK,
                   s1=''.join(f"M{_f(pt(32, 30.5, 10, a)[0])} {_f(pt(32, 30.5, 10, a)[1])}"
                              f"L{_f(pt(32, 30.5, 17.6, a)[0])} {_f(pt(32, 30.5, 17.6, a)[1])}" for a in range(0, 360, 45)),
                   sc=INK, sw=3.8,
                   g3=ring(28, 26.5, 4.6, 2), c3=TEAL,
                   x=[(ci(28, 26.5, 2), WHITE)]),

    # review: red instead of blue; the white globe on blue sat next to Marble's white globe on blue
    'knetwalk': dict(label='KNetWalk', base='#c93a42', lip='#992a31',
                     g1=ci(32, 27, 16.5), c1=WHITE,
                     g2=('M19 17C22 14 28 13.5 30 15.5C31.5 17 29 18.5 27.5 20C26 21.5 26.5 23.5 25 24.5'
                         'C23 25.5 21 24 20 22C19 20.5 18 19 19 17Z'
                         'M25.5 27.5C28 27 30 28.5 30 31C30 34 28 36.5 26.5 39.5C25.5 41.5 24.5 41 24.5 39'
                         'C24.5 36 23.5 33 23.5 30.5C23.5 28.8 24.2 27.7 25.5 27.5Z'
                         'M36 14.5C38.5 13.5 42 14 43.5 16C44.5 17.5 42.5 18.5 41 19C43.5 19.5 46.5 21 46.5 24.5'
                         'C46.5 28 44.5 30.5 43 33.5C42 36 40.5 38.5 39 38.5C37.5 38.5 37.5 36 37 33.5'
                         'C36.5 31 35 29.5 35 27C35 25 34 23.5 34.5 21.5C35 19.5 34.5 16 36 14.5Z'), c2=BLUE,
                     s1='M12 47C16 47 19.5 45.5 23 43.5C25.5 42 27.5 41.5 30 41.5', sc=INK, sw=3.4,
                     g3=rrr(37, 40, 14, 9, 2, -18), c3=INK,
                     x=[(rrr(41.6, 38.5, 3, 6.4, 0.8, -18), WHITE)]),

    'klines': dict(label='Kolor Lines', base='#5b6478', lip='#414859',
                   g1=_kl_dia, c1='#8a93a8',
                   g3=_kl_balls, c3=RED,
                   x=[(_kl_hi, WHITE)]),

    'konquest': dict(label='Konquest', base='#5a2ca0', lip='#3e1e70',
                     g2=_kq_ring, c2='#d9ccff',
                     g3=ci(32, 30, 12.5), c3=WHITE,
                     x=[(_kq_front, '#d9ccff'), (sparkle(16.5, 14, 4, 1.3) + sparkle(48, 46, 3.2, 1.1), YELLOW)]),

    'kpat': dict(label='KPatience', base='#2f9e6e', lip='#227650',
                 g1=P(_kp_back), c1=WHITE,
                 g2=P(_kp_back_in), c2='#2f6fdf',
                 s1=P(_kp_front), sc='#2f9e6e', sw=3.4,
                 g3=P(_kp_front), c3=WHITE,
                 x=[(_kp_spade, INK)]),

    'ksame': dict(label='KSame', base='#1aa391', lip='#127a6c',
                  g1=_ks_tray, c1=WHITE,
                  g3=_ks_balls, c3=GREEN),

    'ksirk': dict(label='KsirK', base='#b7792f', lip='#8a5a20',
                  g1=_sk_barrel + P([(33.5, 29.5), (36.5, 27), (53, 41.5), (50.5, 44.5)]), c1=INK,
                  g2=ring(*_sk_W, 10, 7.2), c2=YELLOW,
                  s1=_sk_spokes, sc=YELLOW, sw=2.6,
                  g3=ci(*_sk_W, 2.8), c3=YELLOW,
                  x=[(ci(17, 43, 3.6) + ci(25, 43.5, 3.6), INK)]),

    'ksudoku': dict(label='KSudoku', base='#f6f4ef', lip='#d6d0c2',
                    g1=rr(29, 10, 3, 40, 1.5) + rr(10, 28.5, 44, 3, 1.5), c1=INK,
                    g2='M32.5 31.5H50.5A3.5 3.5 0 0 1 54 35V46.5A3.5 3.5 0 0 1 50.5 50H32.5z', c2=TEAL,
                    s1=(ci(20, 17.5, 4.3).replace('z', '') + 'M24.3 17.5V21C24.3 25 21 26.5 16.5 25.5'
                        'M37.5 14C39.5 11.8 45.5 12 45.5 15.5C45.5 18.2 43 19 40.5 19C44 19 46.3 20.5 46 23.5'
                        'C45.6 26.5 39.5 27 37 24.5'
                        'M16.5 37.5L21 34.5V47'
                        'M37.5 37.5C37.5 33.5 46 33 46 37.5C46 40.5 41.5 42.5 37.5 47H46.5'),
                    sc=INK, sw=2.8),

    'ktuberling': dict(label='KTuberling', base='#2f6fdf', lip='#2152ad',
                       g1=el(32, 25.5, 14.5, 12.3) + 'M21 50C21 43 26 39 32 39C38 39 43 43 43 50z', c1=ORANGE,
                       g2=el(26.8, 22.5, 3.6, 4.4) + el(37.2, 22.5, 3.6, 4.4), c2=WHITE,
                       s1='M25 29.5C28 33.5 36 33.5 39 29.5M32 13.2C31.4 11.2 33.8 10.4 34.8 11.6', sc=INK, sw=2.6,
                       g3='M22 37.5L32 40.5L42 37.5L41 43L32 41.5L23 43z', c3=WHITE,
                       x=[(ci(27.6, 23.4, 1.9) + ci(36.4, 23.4, 1.9), INK)]),

    'kubrick': dict(label='Kubrick', base='#9b3fb5', lip='#742d88',
                    g1=P(_kb['hull']), c1=WHITE,
                    g2=P(inset(_kb['top'], 1.6)), c2=GREEN,
                    g3=P(inset(_kb['left'], 1.6)), c3=YELLOW,
                    x=[(P(inset(_kb['right'], 1.6)), BLUE)]),

    'lskat': dict(label='LSkat', base='#1f9e8f', lip='#15756a',
                  g1=rr(18, 9.5, 28, 41, 4), c1=WHITE,
                  g2=rr(21, 12.5, 22, 35, 2.5), c2=RED,
                  g3=P([(32, 20), (38.5, 30), (32, 40), (25.5, 30)]), c3=WHITE),

    'knavalbattle': dict(label='Naval Battle', base='#3f7fe0', lip='#2b5db5',
                         g1=_nb_ship, c1=WHITE,
                         g2=_nb_waves, c2='#bcd4ff',
                         s1='M30.25 17V10.5M26.5 10.5H34M47.5 28L52.3 25.3M17 28L12.2 25.3', sc=WHITE, sw=2.4,
                         g3=rr(25.5, 27, 11, 3, 1.5) + ci(19, 37.5, 1.6) + ci(26, 37.2, 1.6) + ci(33, 36.9, 1.6) + ci(40, 36.6, 1.6),
                         c3=INK),

    'palapeli': dict(label='Palapeli', base='#3aa65b', lip='#2a7e44',
                     g1=_pp_left(), c1=WHITE,
                     g3=_pp_right(), c3='#c4ecc9'),

    'picmi': dict(label='Picmi', base='#7b5cd6', lip='#5a40a8',
                  g1=rr(10.5, 18.5, 43, 28, 7) + 'M27 19A5 5 0 0 1 37 19z' + rr(16, 45, 7, 4.5, 2) + rr(41, 45, 7, 4.5, 2),
                  c1=YELLOW,
                  g2=rr(15, 22.5, 34, 20, 5), c2=INK,
                  s1='M30 15L25 11.6M34 15L40.8 11.4', sc=YELLOW, sw=2.4,
                  g3=(rr(23.5, 26.5, 3.6, 4.6, 0.6) + rr(36.9, 26.5, 3.6, 4.6, 0.6)
                      + rr(27, 36.3, 10, 3.2, 0.6) + rr(23.5, 33.3, 3.6, 3.6, 0.6) + rr(36.9, 33.3, 3.6, 3.6, 0.6)),
                  c3=TEAL,
                  x=[(ci(24.6, 11.3, 2.1) + ci(41.3, 11.1, 2.1), YELLOW)]),

    'skladnik': dict(label='Skladnik', base='#d6457a', lip='#a8325d',
                     g1=P([_sd['T'], _sd['R'], _sd['B'], _sd['L']]), c1=WHITE,
                     g2=P([_sd['T'], _sd['R'], _sd['F']]) + P([_sd['L'], _sd['F'], _sd['B']]), c2='#f8c6d8',
                     g3=P([_sd['F'], _sd['R'], _sd['B']]), c3='#ee98b9'),
}

APPS = {
    'org.kde.blinken': 'blinken',
    'org.kde.gcompris': 'gcompris',
    'org.kde.kanagram': 'kanagram',
    'org.kde.katomic': 'katomic',
    'org.kde.kdiamond': 'kdiamond',
    'org.kde.khangman': 'khangman',
    'org.kde.killbots': 'killbots',
    'org.kde.kjumpingcube': 'kjumpingcube',
    'org.kde.klickety': 'klickety',
    'org.kde.kmines': 'kmines',
    'org.kde.knetwalk': 'knetwalk',
    'org.kde.klines': 'klines',
    'org.kde.konquest': 'konquest',
    'org.kde.kpat': 'kpat',
    'org.kde.ksame': 'ksame',
    'org.kde.ksirk': 'ksirk',
    'org.kde.ksudoku': 'ksudoku',
    'org.kde.ktuberling': 'ktuberling',
    'org.kde.kubrick': 'kubrick',
    'org.kde.lskat': 'lskat',
    'org.kde.knavalbattle': 'knavalbattle',
    'org.kde.palapeli': 'palapeli',
    'org.kde.picmi': 'picmi',
    'org.kde.skladnik': 'skladnik',
}
