# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, round 3 batch user-apps.
from apptiles.kit import *  # noqa: F401,F403  helpers and palette
# Plasma Fusion app tiles, round 3, batch user-apps: the owner's own and third-party desktop apps.
import math
import re

from textoutline import text_in_box


# ---- local helpers ---------------------------------------------------------------------------

def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pt(cx, cy, r, deg):
    """Point on a circle; deg in degrees, 0 = +x, positive = clockwise on screen."""
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def band(cx, cy, ro, ri, a0, a1):
    """Annular sector from a0 to a1 (clockwise on screen)."""
    p0 = pt(cx, cy, ro, a0); p1 = pt(cx, cy, ro, a1)
    q1 = pt(cx, cy, ri, a1); q0 = pt(cx, cy, ri, a0)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{_f(p0[0])} {_f(p0[1])}A{_f(ro)} {_f(ro)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}"
            f"L{_f(q1[0])} {_f(q1[1])}A{_f(ri)} {_f(ri)} 0 {large} 0 {_f(q0[0])} {_f(q0[1])}z")


def rpoly(pts, r):
    """Closed polygon with every corner rounded by r (quadratic corners); (x, y, r) overrides r."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        rad = p1[2] if len(p1) > 2 else r
        la = math.hypot(p0[0] - p1[0], p0[1] - p1[1]); lb = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        ra, rb = min(rad, la / 2), min(rad, lb / 2)
        a = (p1[0] + (p0[0] - p1[0]) * ra / la, p1[1] + (p0[1] - p1[1]) * ra / la)
        b = (p1[0] + (p2[0] - p1[0]) * rb / lb, p1[1] + (p2[1] - p1[1]) * rb / lb)
        out.append(("M" if i == 0 else "L") + f"{_f(a[0])} {_f(a[1])}"
                   + (f"Q{_f(p1[0])} {_f(p1[1])} {_f(b[0])} {_f(b[1])}" if rad > 0 else ""))
    return "".join(out) + "z"


def xform(pts, ang, tx, ty):
    """Rotate points by ang degrees about the origin, then translate."""
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(x * c - y * s + tx, x * s + y * c + ty) + tuple(p[2:]) for p in pts for x, y in [p[:2]]]


_TOK = re.compile(r"[MLHVCSQTAZmlhvcsqtaz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
_NARGS = dict(M=2, L=2, H=1, V=1, C=6, S=4, Q=4, T=2, A=7, Z=0)


def xf(d, s, tx, ty):
    """Uniformly scale (s) and translate (tx, ty) an SVG path with absolute and relative commands."""
    toks = _TOK.findall(d)
    out, i, cmd = [], 0, None
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t; i += 1
            if cmd in "Zz":
                out.append("z"); continue
        n = _NARGS[cmd.upper()]
        a = [float(v) for v in toks[i:i + n]]; i += n
        rel_ = cmd.islower(); U = cmd.upper()
        if U == "H":
            v = [a[0] * s + (0 if rel_ else tx)]
        elif U == "V":
            v = [a[0] * s + (0 if rel_ else ty)]
        elif U == "A":
            v = [a[0] * s, a[1] * s, a[2], a[3], a[4],
                 a[5] * s + (0 if rel_ else tx), a[6] * s + (0 if rel_ else ty)]
        else:
            v = [a[k] * s + (0 if rel_ else (tx if k % 2 == 0 else ty)) for k in range(n)]
        out.append(cmd + " ".join(_f(x) if k not in (3, 4) or U != "A" else str(int(x)) for k, x in enumerate(v)))
        if cmd == "M":
            cmd = "L"
        elif cmd == "m":
            cmd = "l"
    return "".join(out)


# ---- marks -----------------------------------------------------------------------------------

# ChatGPT: the OpenAI knot (six interlaced links around a hexagon), traced from the app's icon
# and thickened so its bands stay at least 2.4 units wide.
CHATGPT_KNOT = 'M27.1 10.02L24.35 11.09L22.68 12.29L20.71 14.62L19.63 17.13L16.76 18.44L15.75 19.22L14.37 20.66L13.24 22.45L12.52 24.42L12.28 25.8L12.28 28.07L12.52 29.44L13.53 31.95L15.09 33.98L14.85 35.18L14.79 37.09L15.03 38.82L15.63 40.61L16.7 42.47L18.67 44.5L20.89 45.81L22.74 46.41L25.61 46.65L27.46 46.35L29.49 47.91L32.3 48.98L35.11 49.22L37.2 48.86L39.35 48.02L41.32 46.65L43.35 44.2L44.31 41.87L46.1 41.15L47.48 40.32L48.43 39.54L49.87 37.93L50.88 36.13L51.6 33.68L51.66 30.87L51.3 29.08L50.47 27.11L48.85 24.96L49.09 23.64L49.09 21.31L48.43 18.68L47.06 16.29L45.21 14.44L43.23 13.25L41.32 12.59L39.89 12.35L38.04 12.35L36.54 12.65L34.57 11.15L33.08 10.44L31.46 9.96L28.59 9.78zM36.12 35.18L36.12 38.34L35.88 38.7L28.65 42.89L26.98 43.6L25.67 43.84L24.29 43.84L22.98 43.6L21.3 42.89L20.35 42.23L18.61 40.2L18.08 39.06L17.66 37.39L17.6 36.13L17.78 35.95L25.13 40.26L25.96 40.61L26.44 40.61zM39.05 28.72L41.62 30.22L41.92 30.75L41.92 39.3L41.32 41.87L40.49 43.36L39.29 44.68L37.2 45.93L35.59 46.35L34.03 46.41L32.6 46.17L31.46 45.75L30.39 45.1L38.27 40.56L38.87 39.9zM31.94 24.66L36.12 27.11L36.12 31.83L32 34.28L27.82 31.83L27.82 27.11zM37.62 21.37L37.98 21.43L45.92 26.09L47.36 27.53L48.37 29.32L48.91 31.71L48.79 33.32L48.37 34.76L47.12 36.85L45.98 37.93L44.73 38.7L44.61 29.02L43.89 28.3L34.75 23.05zM19.21 20.24L19.33 29.92L20.05 30.64L29.13 35.89L26.38 37.51L25.96 37.51L18.26 33.03L16.7 31.59L15.63 29.8L15.03 27.35L15.09 25.97L15.39 24.66L15.93 23.4L16.82 22.09L17.96 21.01zM46.34 21.85L46.28 23.05L38.45 18.5L37.56 18.33L27.82 23.76L27.82 20.54L28.12 20.18L35.47 15.93L36.72 15.4L38.16 15.1L39.77 15.1L41.02 15.34L42.46 15.93L43.53 16.65L44.67 17.79L45.57 19.16L46.04 20.36zM32.3 13.07L33.55 13.84L25.61 18.44L25.13 18.98L24.89 30.22L22.32 28.72L22.02 28.25L22.02 19.46L22.62 17.01L23.51 15.46L24.23 14.62L25.43 13.66L26.68 13.01L28.18 12.59L30.21 12.53z'

# Paseo: the single looped line (a butterfly drawn in one stroke), traced from the app's icon.
PASEO_LOOP = 'M22.89 11.03L21 11.45L19.47 12.34L18.11 13.97L17.16 16.03L16.58 18.5L16.47 21.97L16.68 24.08L17.53 27.71L17.53 28.45L17.21 29.03L15.68 30.71L14.26 33.34L13.63 35.66L13.53 38.61L13.89 40.71L14.53 42.45L15.58 44.29L17.32 46.24L19 47.45L21.05 48.39L22.95 48.87L24.84 48.97L26.26 48.82L28 48.24L29.16 47.55L30.53 46.45L35.79 41.18L43.21 32.29L45 30.55L45.63 30.18L46.26 30.18L46.74 30.71L46.79 31.61L46.53 32.39L45.47 34.24L42.95 37.24L38.84 40.97L38.05 41.97L38 43.13L38.68 43.97L39.21 44.18L40 44.18L41 43.71L43.37 41.71L45.89 39.24L48.32 36.34L50 33.34L50.42 31.82L50.47 30.45L50.16 29.18L49.47 28.03L48.58 27.18L47.47 26.61L46.79 26.45L45.16 26.55L43.89 27.08L42.26 28.13L41.63 28.08L41.26 27.5L40.26 24.29L38.84 21.55L36.95 18.92L34.21 16.08L31.37 13.87L28.11 12.08L25.53 11.24zM23.42 30.87L24.21 30.76L25.21 30.97L26.16 31.39L27.05 32.13L27.53 32.92L27.68 33.55L27.58 34.39L27.05 35.08L26.74 35.24L25.95 35.18L25.32 34.82L24.42 33.92L23.11 31.71L23.11 31.24zM23.21 14.45L25.26 14.71L27.89 15.82L30.79 17.76L33.42 20.24L35.26 22.55L36.74 25.13L37.47 27.08L37.89 29.34L37.89 30.76L37.47 32.82L36.84 34.24L35.53 36.08L31.74 40.39L28.63 43.45L26.63 45.03L24.89 45.55L23.58 45.5L22.16 45.13L19.95 43.87L18.74 42.61L17.74 40.87L17.26 39.39L17.05 37.82L17.16 36.34L17.58 34.66L18.26 33.29L18.89 32.76L19.21 32.76L19.74 33.18L21.37 35.76L22.84 37.34L24.05 38.18L25.42 38.71L27.42 38.76L28.95 38.18L30.21 37.08L31.11 35.39L31.32 34.24L31.11 32.18L30.42 30.66L29.16 29.24L28.11 28.5L25.95 27.61L24.16 27.29L21.58 27.13L20.84 26.24L20.37 24.34L20.05 22.03L20.05 19.66L20.26 18.24L20.74 16.66L21.37 15.5L22.11 14.82z'

# Irlume (the owner's project): the scanner mark, kept faithfully: viewfinder corners, the outer
# ring, the thick inner ring and the centre dot, in the mark's crimson-to-orange colours.
_IR = (32, 29.5)
_IR_S = 0.235
def _irp(x, y):
    return _f(_IR[0] + x * _IR_S), _f(_IR[1] + y * _IR_S)
_IR_CORNERS = ''.join('M{} {}L{} {}L{} {}'.format(*_irp(sx * 84, sy * 58), *_irp(sx * 84, sy * 80), *_irp(sx * 62, sy * 80))
                      for sx in (-1, 1) for sy in (-1, 1))

# Sunshine: LizardByte's sun swoosh, from the original paths (256 box): the red outer swoosh,
# the orange body and the yellow inner crescent.
SUN_YELLOW = ('M118.7688675,20.7120476c0,0-63.8333359,26-74.3333359,83.8333282s37.1666718,91.5,86.3333282,75.3333282'
              's70.3333435-51,81.8333435-86.9999924c0,0-9.3333435,100.4999924-96.1666718,115.4999924s-118.1666641-50-82.1666641-119.8333282'
              'C44.2688675,67.0453796,80.5188675,29.6287155,118.7688675,20.7120476z')
SUN_ORANGE = ('M118.7688675,20.7120476c0,0-41.125,3.6666679-83.25,61.0416679s-28.125,139.125,34.25,149.375'
              's115.8749924-44.875,133.5-82.375s15.1666718-61.4583282,9.75-77.8749924c0,0,0.6666718,36.4166641-13.3333282,59.6666641'
              's-29.75,46.3333282-65.0833282,62.1666718s-74.1666718,13.75-95.4166718-19.25s-5.9166641-76.0833359-0.2916641-85.3333359'
              'S72.3938675,33.7953796,118.7688675,20.7120476z')
SUN_RED = ('M73.0188675,39.6287155c0,0,38.125-28.125,76.8749924-28.125s63,28.25,68.5,52.25s6,54.125-11.5,87.6249924'
           's-37.375,56-79.1249924,76.125s-84.625,2.75-84.625,2.75s25.9769745,25.8750153,71.0509872,16.5'
           'c45.0740051-9.375,82.2406769-40.875,98.4073486-69.5s28.7916565-57.3749924,27.6666565-92.2499924s-23.75-54.5-31.25-60.25'
           's-23.1875-17.8125-58.1875-16.5625S86.4563675,29.8162155,73.0188675,39.6287155z'
           'M73.0188675,39.6287155c0,0,35-32.8125,82.4374924-32.8125s69.1875,24.8125,78.875,44.6875'
           's21.8125,70-12.1875,122.9999924s-74.625,67.375-93.625,71.625s-42.4311447,4.269165-59.1114044-1.2299957'
           'c0,0,35.1947479,8.3966675,66.7780762-7.4366608s51.6666718-32.1666718,74.0833282-68.8333435'
           's25.9166718-72.7499924,22.1666718-93.9166565s-12.1666718-42.4166718-36.5-56.3333359s-56.7291718-10.531251-74.4791641-4.531251'
           'S91.9876175,26.4099655,73.0188675,39.6287155z')
_SUN_S = 0.165
def _sun(d):
    return xf(d, _SUN_S, 32 - 127.9 * _SUN_S, 29.8 - 127.9 * _SUN_S)

# OpenCode: the block O of the opencode logo, its counter half filled.
_OC = dict(x=15.75, y=9.5, w=32.5, h=40.5, t=7.8, top=8.6)

# ZCode: the slanted Z whose two bars stand apart from the diagonal (centrally symmetric).
_ZS = 0.112
def _zp(X, Y):
    return (32 + (X - 256) * _ZS, 30 + (Y - 255) * _ZS)
_Z_DIAG = poly(_zp(290, 105), _zp(432, 105), _zp(222, 405), _zp(80, 405))
_Z_GAP = 9          # extra gap (orig px) between each bar and the diagonal
_Z_TOP = rpoly([(*_zp(90, 105), 0.6), (*_zp(265 - _Z_GAP, 105), 0),
                (*_zp(265 - _Z_GAP - 0.7 * 45, 150), 2.0), (*_zp(90, 150), 0.6)], 0)
_Z_BOT = rpoly([(*_zp(422, 405), 0.6), (*_zp(247 + _Z_GAP, 405), 0),
                (*_zp(247 + _Z_GAP + 0.7 * 45, 360), 2.0), (*_zp(422, 360), 0.6)], 0)

# Shadow PC: the thick white ring cut open at the upper right, one end rounded, one cut square.
_SH = (32, 30)
_SH_RO, _SH_RI = 18.5, 10.5
_SH_A0, _SH_A1 = -40, 360 - 76     # from the square-cut end clockwise round to the rounded end
_SH_CAP = pt(*_SH, (_SH_RO + _SH_RI) / 2, _SH_A1)

# Gear Lever: a down arrow (the lever) over a cog.
_GL_HEAD = rpoly([(14.5, 20.5, 4), (49.5, 20.5, 4), (44, 34, 8), (32, 44.5, 5), (20, 34, 8)], 3)

# Xournal++: the italic x and the pencil from the app's icon.
XOPP_X = ('M75.672 47.988c-3.899 0-5.645 1.477-10.887 9.68l-7.394 11.695-3.496-11.965c-2.153-7.527-5.11-9.41-8.602-9.41'
          '-3.898 0-8.605 3.36-14.656 10.215-.672.54.539 1.75 1.078 1.078 3.629-3.765 6.719-5.511 9.004-5.511 1.883 0 4.574.937 '
          '6.722 8.062l4.57 15.328-9.41 13.98c-2.148 3.09-4.167 4.032-5.913 4.032-2.688 0-2.958-2.688-6.051-2.688-2.149 0-3.63 '
          '1.344-3.899 3.227-.535 3.629 3.227 6.719 6.723 6.719 4.035 0 5.781-1.614 10.89-9.813l8.333-13.172 4.304 14.516c2.016 '
          '6.992 4.57 8.469 8.063 8.469 3.898 0 8.605-3.493 14.652-10.215.676-.672-.402-1.746-1.074-1.211-3.629 3.766-6.586 '
          '5.512-8.871 5.512-2.016 0-4.438-.54-6.32-6.856l-5.376-18.148 8.47-12.367c2.152-2.958 4.167-4.032 5.913-4.032 2.688 '
          '0 2.957 2.688 6.051 2.688 2.149 0 3.629-1.344 3.899-3.227.535-3.496-3.227-6.586-6.723-6.586z')
_XS = 0.5
_X = xf(XOPP_X, _XS, 25.5 - 56.75 * _XS, 31 - 76.3 * _XS)
_PEN_ANG = -70                     # pencil axis, degrees (pointing up and to the right)
_PEN_TIP = (40, 46.5)              # graphite point
def _pen(pts):
    return xform(pts, _PEN_ANG, *_PEN_TIP)
_PEN_BODY = rpoly(_pen([(9, -3.3, 0), (32, -3.3, 1.4), (32, 3.3, 1.4), (9, 3.3, 0)]), 0)
_PEN_CONE = poly(*_pen([(0.6, -0.5), (9.4, -3.3), (9.4, 3.3), (0.6, 0.5)]))
_PEN_LEAD = poly(*_pen([(-0.6, 0), (3.6, -1.6), (3.6, 1.6)]))

# Qt tools: the Qt plate (top-left and bottom-right corners cut) with the tool's letter.
QT_PLATE = rpoly([(10.5, 21, 1), (17.5, 14, 1), (53.5, 14, 1.5), (53.5, 39, 1), (46.5, 46, 1), (10.5, 46, 1.5)], 1)
QT_SHADE = rpoly([(10.5, 21, 0), (53.5, 39, 0), (46.5, 46, 1), (10.5, 46, 1.5)], 0)


def _qt_letter(ch, cx=32, cy=30):
    """The letter centred on its own outline (L is left-heavy), so each tool's letter sits mid-plate."""
    d = text_in_box(ch, 'manrope-800', 26, (10.5, 14, 43, 32))
    nums = [float(v) for v in re.findall(r"-?\d+\.?\d*", d)]
    xs, ys = nums[0::2], nums[1::2]
    return xf(d, 1, cx - (min(xs) + max(xs)) / 2, cy - (min(ys) + max(ys)) / 2)


TILES = {
    'chatgpt': dict(label='ChatGPT', base='#f4f5f9', lip='#d5d9e3',
                    g2=CHATGPT_KNOT, c2='#1b2031'),
    'opencode': dict(label='OpenCode', base='#475069', lip='#323950',
                     g1=rr(_OC['x'], _OC['y'], _OC['w'], _OC['h'], 1.5), c1='#ffffff',
                     g2=rr(_OC['x'] + _OC['t'], _OC['y'] + _OC['t'], _OC['w'] - 2 * _OC['t'], _OC['h'] - 2 * _OC['t'], 0.6),
                     c2='#1b2031',
                     g3=rr(_OC['x'] + _OC['t'], _OC['y'] + _OC['t'] + _OC['top'], _OC['w'] - 2 * _OC['t'],
                           _OC['h'] - 2 * _OC['t'] - _OC['top'], 0.6),
                     c3='#7c86a3'),
    'irlume': dict(label='Irlume', base='#262c42', lip='#131726',
                   s1=ci(_IR[0], _IR[1], 62 * _IR_S) + _IR_CORNERS, sc='#e0405a', sw=2.6,
                   g3=ring(_IR[0], _IR[1], 36 * _IR_S, 24 * _IR_S) + ci(_IR[0], _IR[1], 8.5 * _IR_S), c3='#ff6a3d'),
    'sunshine': dict(label='Sunshine', base='#f4f5f9', lip='#d5d9e3',
                     g1=_sun(SUN_ORANGE), c1='#f89a1c',
                     g2=_sun(SUN_RED), c2='#ef4423',
                     g3=_sun(SUN_YELLOW), c3='#fdd107'),
    'gear-lever': dict(label='Gear Lever', base='#357fae', lip='#285f82',
                      g1=gear(32, 33.5, 16.5, 12.8, 9), c1='#ffffff',
                      g2=rr(23.5, 9, 17, 14.5, 3.5), c2='#9db3c0',
                      g3=_GL_HEAD, c3='#24384a'),
    'paseo': dict(label='Paseo', base='#3b4255', lip='#262b38',
                  g2=PASEO_LOOP, c2='#ffffff'),
    'zcode': dict(label='ZCode', base='#2c3348', lip='#1a1f2e',
                  g1=_Z_DIAG + _Z_TOP + _Z_BOT, c1='#ffffff'),
    'shadow-pc': dict(label='Shadow PC', base='#4762dc', lip='#3549aa',
                      g1=band(*_SH, _SH_RO, _SH_RI, _SH_A0, _SH_A1), c1='#ffffff',
                      x=[(ci(*_SH_CAP, (_SH_RO - _SH_RI) / 2), '#ffffff')]),
    'xournalpp': dict(label='Xournal++', base='#f6f4ef', lip='#d6d0c2',
                      g1=_X, c1='#2c3348', s1=_X, sc='#2c3348', sw=1.1,
                      g3=_PEN_BODY, c3='#f08a2e',
                      x=[(_PEN_CONE, '#f7c948'), (_PEN_LEAD, '#2c3348')]),
    'qt-designer': dict(label='Qt Designer', base='#41cd52', lip='#2f9a3c',
                        g1=QT_PLATE, c1='#ffffff', g2=QT_SHADE, c2='#e3f7e6',
                        g3=_qt_letter('D'), c3='#2fae42'),
    'qt-linguist': dict(label='Qt Linguist', base='#41cd52', lip='#2f9a3c',
                        g1=QT_PLATE, c1='#ffffff', g2=QT_SHADE, c2='#e3f7e6',
                        g3=_qt_letter('L'), c3='#2fae42'),
}

APPS = {
    'chatgpt': 'chatgpt',
    'ai.opencode.desktop': 'opencode',
    'io.github.archledger.Irlume': 'irlume',
    'dev.lizardbyte.app.Sunshine': 'sunshine',
    'it.mijorus.gearlever': 'gear-lever',
    'Paseo': 'paseo',
    'zcode': 'zcode',
    'shadow_pc': 'shadow-pc',
    'com.github.xournalpp.xournalpp': 'xournalpp',
    'qt6-designer': 'qt-designer',
    'qt6-linguist': 'qt-linguist',
}
