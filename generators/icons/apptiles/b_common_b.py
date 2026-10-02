# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, batch common-b (media and graphics apps common on Linux desktops).
import math

from apptiles.kit import *  # noqa: F401,F403  (rr, ci, el, gear, ring, poly, f, PALETTE, ...)


# --- small path helpers (sampled shapes; same 64-unit tile space) --------------------------
def _pt(p):
    return f"{f(p[0])} {f(p[1])}"


def line(*pts):
    """Open polyline (for strokes)."""
    return "M" + "L".join(_pt(p) for p in pts)


def cubic(p0, p1, p2, p3, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def earc(cx, cy, rx, ry, a0, a1, n=28, rot=0):
    """Points on an ellipse from angle a0 to a1 (degrees, SVG orientation), optionally rotated."""
    out = []
    cr, sr = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cx + x * cr - y * sr, cy + x * sr + y * cr))
    return out


def thick(pts, w0, w1=None, caps=True):
    """A stroke drawn as a fill: width tapers from w0 to w1, round caps."""
    w1 = w0 if w1 is None else w1
    n = len(pts)
    left, right, norms = [], [], []
    for i, (x, y) in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(dx, dy) or 1
        nx, ny = -dy / d, dx / d
        w = (w0 + (w1 - w0) * i / (n - 1)) / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
        norms.append((nx, ny, dx / d, dy / d, w))
    out = list(left)
    if caps:
        nx, ny, fx, fy, w = norms[-1]
        cx, cy = pts[-1]
        for k in range(1, 8):
            p = k * math.pi / 8
            out.append((cx + w * (math.cos(p) * nx + math.sin(p) * fx), cy + w * (math.cos(p) * ny + math.sin(p) * fy)))
    out += right[::-1]
    if caps:
        nx, ny, fx, fy, w = norms[0]
        cx, cy = pts[0]
        for k in range(1, 8):
            p = k * math.pi / 8
            out.append((cx + w * (-math.cos(p) * nx - math.sin(p) * fx), cy + w * (-math.cos(p) * ny - math.sin(p) * fy)))
    return poly(*out)


def ccw(*pts):
    """Closed polygon wound like ci()/thick() (anticlockwise on screen), so overlapping shapes in a
    nonzero layer merge instead of cancelling."""
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    return poly(*(pts[::-1] if area > 0 else pts))


def rot(p, c, deg):
    a = math.radians(deg)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a))


def pinwheel(cx, cy, R, ri, n, start):
    """n aperture blades whose edges are tangent to the inner circle (chrome_parts for n parts)."""
    t = math.sqrt(R * R - ri * ri)
    parts, edges = [], []
    for k in range(n):
        a0 = math.radians(start + 360 / n * k)
        a1 = math.radians(start + 360 / n * (k + 1))
        P0 = (cx + ri * math.cos(a0), cy + ri * math.sin(a0))
        Q0 = (P0[0] + t * math.cos(a0 + math.pi / 2), P0[1] + t * math.sin(a0 + math.pi / 2))
        P1 = (cx + ri * math.cos(a1), cy + ri * math.sin(a1))
        Q1 = (P1[0] + t * math.cos(a1 + math.pi / 2), P1[1] + t * math.sin(a1 + math.pi / 2))
        parts.append(f"M{_pt(P0)}L{_pt(Q0)}A{f(R)} {f(R)} 0 0 1 {_pt(Q1)}L{_pt(P1)}"
                     f"A{f(ri)} {f(ri)} 0 0 0 {_pt(P0)}z")
        edges.append((P0, Q0))
    return parts, edges


def sector(cx, cy, ro, ri, a0, a1, n=10):
    """Annular sector (degrees, SVG orientation)."""
    return poly(*(earc(cx, cy, ro, ro, a0, a1, n) + earc(cx, cy, ri, ri, a1, a0, n)))


def chord(cx, cy, rx, ry, p, d, inset=0.0):
    """Segment of the line p + t*d inside an ellipse, shortened by inset at both ends."""
    ax, ay = (p[0] - cx) / rx, (p[1] - cy) / ry
    bx, by = d[0] / rx, d[1] / ry
    A, B, C = bx * bx + by * by, 2 * (ax * bx + ay * by), ax * ax + ay * ay - 1
    s = math.sqrt(B * B - 4 * A * C)
    t0, t1 = (-B - s) / (2 * A), (-B + s) / (2 * A)
    L = math.hypot(*d)
    t0 += inset / L
    t1 -= inset / L
    return line((p[0] + t0 * d[0], p[1] + t0 * d[1]), (p[0] + t1 * d[0], p[1] + t1 * d[1]))


def hsl(h, s, l):
    import colorsys
    r, g, b = colorsys.hls_to_rgb(h / 360, l, s)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


# --- per-app geometry --------------------------------------------------------------------
# VLC: the traffic cone (white, base-coloured stripes) on its plate.
def _cone_x(y):
    k = (y - 12.5) * (9.6 / 28.5)
    return 28.6 - k, 35.4 + k


def _cone_band(y0, y1):
    l0, r0 = _cone_x(y0)
    l1, r1 = _cone_x(y1)
    return poly((l0, y0), (r0, y0), (r1, y1), (l1, y1))


VLC_STRIPES = _cone_band(18.5, 23.5) + _cone_band(29.5, 34.5)

# Celluloid: film frame with sprocket holes, play disc and seek bar.
CELL_HOLES = ''.join(rr(12.1, y, 3.4, 4.6, 1.2) + rr(48.5, y, 3.4, 4.6, 1.2) for y in (16, 23.8, 31.6, 39.4))

# Spotify: three arcs, top one the widest.
SPOT_ARCS = (thick(cubic((15.5, 25.7), (24, 18.7), (38.5, 18.7), (48.5, 26.7)), 5.2)
             + thick(cubic((18.2, 33), (25.5, 27.4), (36.5, 27.4), (45.5, 33.4)), 4.4)
             + thick(cubic((20.8, 39.8), (27, 35.6), (35.5, 35.6), (42.6, 40)), 3.6))

# Strawberry: berry, calyx and stem.
BERRY = 'M15.5 25.5C15.5 19.5 23 18.6 32 20.2 41 18.6 48.5 19.5 48.5 25.5 48.5 35 40.5 45.5 32 48.5 23.5 45.5 15.5 35 15.5 25.5z'
CALYX = poly((15.5, 22), (25, 19), (21, 13.5), (29.5, 17.2), (32, 12.5), (34.5, 17.2), (43, 13.5),
             (39, 19), (48.5, 22), (38, 23.5), (35.5, 27.5), (32, 23.8), (28.5, 27.5), (26, 23.5))
SEEDS = ''.join(el(x, y, 1.3, 1.7) for x, y in [(23, 28), (32, 30), (41, 28), (27, 35.5), (37, 35.5), (32, 42)])

# Kodi: a tall bar and three diamonds, rounded by a same-colour stroke.
KODI = [poly(*[(x - 1.8, y) for x, y in pts]) for pts in (
    [(21.5, 13), (26.5, 18), (26.5, 42), (21.5, 47), (16.5, 42), (16.5, 18)],
    [(36, 14.5), (42.5, 21), (36, 27.5), (29.5, 21)],
    [(45, 23.5), (51.5, 30), (45, 36.5), (38.5, 30)],
    [(36, 32.5), (42.5, 39), (36, 45.5), (29.5, 39)])]

# OBS: three white crescents around three dark heads (the logo's rotational triad).
_C = (32, 30)
OBS_W = ''.join(ci(*rot((31.13, 21.62), _C, 120 * k), 6.36) for k in range(3))
OBS_D = ''.join(ci(*rot((33.16, 20.75), _C, 120 * k), 5.2) for k in range(3))

# HandBrake: pineapple and a tall glass with a straw.
HB_HATCH = (chord(24, 36.5, 9, 11.5, (24, 31), (1, 1), 2.2) + chord(24, 36.5, 9, 11.5, (24, 40), (1, 1), 2.2)
            + chord(24, 36.5, 9, 11.5, (24, 31), (1, -1), 2.2) + chord(24, 36.5, 9, 11.5, (24, 40), (1, -1), 2.2))
HB_LEAVES = (ccw((21.5, 26.5), (24, 10.5), (26.5, 26.5)) + ccw((19, 27), (14.5, 15.5), (23.5, 24.5))
             + ccw((29, 27), (33.5, 15.5), (24.5, 24.5)))
HB_GLASS = 'M35.5 21.5h14l-1.6 24.6a2.2 2.2 0 0 1-2.2 2h-6.4a2.2 2.2 0 0 1-2.2-2z'
HB_STRAW = thick([(43.5, 23), (48.5, 11.5)], 3)


# Audacity: headphones around an orange/yellow waveform.
def _wave(cx, cy, xs, hs, k=1.0):
    top, bot = [], []
    for i, (x, h) in enumerate(zip(xs, hs)):
        top.append((x, cy - h * k))
        bot.append((x, cy + h * k * (0.85 if i % 2 else 1.0)))
    return poly(*(top + bot[::-1]))


_WX = [21.5 + i * 1.75 for i in range(13)]
_WH = [1, 5, 1.5, 9, 2, 12, 3, 11, 2, 8, 1.5, 5, 1]
AUD_WAVE_O = _wave(32, 32, _WX, _WH)
AUD_WAVE_I = _wave(32, 32, _WX, _WH, 0.5)

# OpenShot: sphere, S swoosh, film strip wrapped round it.
OS_S = thick(cubic((45, 16.5), (35, 9.5), (20.5, 15), (27.5, 25.5)) + cubic((27.5, 25.5), (32, 31), (44.5, 28.5), (42, 40))[1:], 4.6, 3.4)
OS_FILM = line(*earc(32, 30, 19.2, 10, 0, 180, 30, rot=24))
OS_HOLES = ''.join(rr(x - 1.3, y - 1.3, 2.6, 2.6, 0.6) for x, y in earc(32, 30, 19.2, 10, 17, 163, 7, rot=24))

# Ardour: the A with a waveform comb cut from its base.
ARD_SLOTS = ''.join(rr(32 + d - 1.25, 49 - 17 * math.exp(-(d / 11) ** 2), 2.5, 17 * math.exp(-(d / 11) ** 2) + 2, 1.25)
                    for d in (-14.4, -9.6, -4.8, 0, 4.8, 9.6, 14.4))

# LMMS: open hexagon with two thick ear cups.
LMMS_CUPS = poly((13.4, 32), (19.4, 32), (19.4, 35.6), (27.4, 40.2), (27.4, 48), (24.2, 48), (13.4, 41.8)) + \
            poly((50.6, 32), (44.6, 32), (44.6, 35.6), (36.6, 40.2), (36.6, 48), (39.8, 48), (50.6, 41.8))


# MuseScore: the cyan clef-like "3" (traced on the original's 64 grid, scaled 0.9).
def _ms(p):
    return (32 + (p[0] - 32.5) * 0.9, 29.5 + (p[1] - 32.5) * 0.9)


def _ms_shape():
    hook = ([(18.5, 28.5)] + earc(31, 21.5, 12.5, 10.5, 180, 340, 24) + earc(33, 21.5, 6, 6.5, 340, 170, 20)
            + [(27.5, 28.5)])
    bar = [(29, 28.5), (42, 28.5), (34.5, 36), (22.5, 36)]
    bowl = [(36, 36)] + earc(33, 41, 14.5, 13, -22.6, 150, 24) + earc(31, 41.5, 7, 7.5, 150, -47, 20)
    return (ccw(*map(_ms, hook)) + ccw(*map(_ms, bar)) + ccw(*map(_ms, bowl))
            + ci(*_ms((41, 19.5)), 4.8 * 0.9) + ci(*_ms((23.5, 45.5)), 4.8 * 0.9))


MUSE = _ms_shape()

# GIMP: Wilber's head with eyes, nose and brush.
WILBER = ('M13.5 30.5C13.5 26.5 20 25 27 25.5L42 24C49 25 51.5 33 48.5 39.5 45 46.5 31 48.5 22.5 45 16.5 42.5 13.5 36 13.5 30.5z'
          + poly((19, 27.5), (17.5, 14), (28, 25)) + poly((40, 25), (52, 10), (48.5, 31)))
WIL_EYES = ci(27.5, 22.5, 5.6) + ci(38.5, 22.5, 5.6)
WIL_PUPILS = ci(29, 23.5, 2.5) + ci(40, 23.5, 2.5)
WIL_BRUSH = thick([(39, 39.5), (50.5, 34)], 3.4)

# Inkscape: mountain with a snow cap and ink drips.
INK_MTN = poly((32, 10.6), (52, 33), (13, 33))
INK_SNOW = poly((32, 10.6), (39.8, 19.3), (36.6, 22.2), (33.6, 19.8), (30.2, 23.4), (27.6, 20.2), (24.7, 19.2))
INK_DRIPS = ('M13 33H52C49.5 36 45.5 37.6 41.5 37.2 38.5 37 36.5 38.5 35.6 41 35.2 42.4 36.4 43.2 38.6 43.6'
             'C41.6 44.2 42 46.8 39 47.6 34.5 48.6 27.5 48.6 23.5 47.4 21 46.6 21.4 44.2 24.2 43.6'
             'C26.4 43.2 27.8 42.2 27.6 40.6 27.2 38.4 24.8 37 21.6 37.2 17.8 37.4 14.6 35.8 13 33z'
             + ci(17.4, 42.6, 2.3) + ci(45.4, 41.8, 1.9))

# Blender: arms + ring + blue core.
BL_ARMS = (thick([(31, 22.2), (14.8, 22.2)], 4.8) + ccw((36.5, 19.8), (30.1, 12.6), (44, 18.5), (40, 26))
           + thick([(28, 36.6), (12, 39.8)], 4.8, 4.4))

# darktable: six aperture blades in the logo's colours.
DT_PARTS, DT_EDGES = pinwheel(32, 30, 18.5, 4.4, 6, 145)
DT_GAPS = ''.join(thick([a, b], 2.6, caps=False) for a, b in DT_EDGES)
DT_COLS = ['#e5484d', '#f28c38', '#f7c948', '#3aa65b', '#3f7fe0', '#a24bc4']


# RawTherapee: rainbow ring.
def _rt_col(theta):
    pts = [(0, 0), (90, 52), (180, 125), (225, 200), (270, 262), (315, 305), (360, 360)]
    for (a0, h0), (a1, h1) in zip(pts, pts[1:]):
        if a0 <= theta <= a1:
            return hsl((h0 + (h1 - h0) * (theta - a0) / (a1 - a0)) % 360, 0.8, 0.55)


RT_RING = [(sector(32, 30, 18.5, 9.5, -90 + 30 * k - 15.6, -90 + 30 * k + 15.6), _rt_col(30 * k)) for k in range(12)]

# Pinta: paint tube and a brush.
PIN_TUBE = rr(32.5, 18.6, 14.5, 25.4, 3) + rr(35.6, 11, 8.3, 6.4, 1.6) + rr(31.4, 45, 16.7, 4, 1.6)
PIN_HANDLE = thick([(38, 11.8), (25.6, 31.6)], 4.4, 3.6)
PIN_TIP = 'M21.6 33.4c2.6.4 4.4 1.8 4.6 3.8.4 3.4-2.6 7.2-10 11.2.4-6.6 1.6-11.6 3.8-13.6.6-.6 1-.9 1.6-1.4z'
PIN_FERRULE = thick([(26.8, 29.6), (24, 34.4)], 5)


# Scribus: globe with a light swoosh and the gold pen nib.
def _nib():
    T, B = (28, 47), (47.5, 12.5)
    L = math.hypot(B[0] - T[0], B[1] - T[1])
    u = ((B[0] - T[0]) / L, (B[1] - T[1]) / L)
    v = (-u[1], u[0])

    def P(s, w):
        return (T[0] + u[0] * s * L + v[0] * w, T[1] + u[1] * s * L + v[1] * w)
    outline = [P(0, 0), P(0.42, 4.6), P(0.66, 6.2), P(0.74, 4.4), P(1, 4.4), P(1, -4.4), P(0.74, -4.4),
               P(0.66, -6.2), P(0.42, -4.6)]
    slit = thick([P(0.08, 0), P(0.5, 0)], 2.4)
    hole = ci(*P(0.53, 0), 2.1)
    return poly(*outline), slit, hole


SCR_NIB, SCR_SLIT, SCR_HOLE = _nib()
SCR_SWOOSH = 'M26 13.5C16.5 18 13.5 33 23.5 45.5 20.5 35 21.5 24 30.5 15.6 29 14.6 27.5 14 26 13.5z'

# FreeCAD: bold F in front of a gear.
FC_F = 'M14 11.5h28v8h-19v7h14.5v8h-14.5v14h-9z'

TILES = {
    'vlc': dict(label='VLC', base='#e8743b', lip='#b8552a',
                g1='M28.6 12.5A3.4 3.4 0 0 1 35.4 12.5L45 41H19z', c1='#ffffff',
                g2=rr(12, 40, 40, 8, 3), c2='#ffd2b0',
                g3=VLC_STRIPES, c3='#e8743b'),
    'mpv': dict(label='mpv', base='#9b3fb5', lip='#742d88',
                g1=ci(32, 30, 18), c1='#ffffff',
                g2=ci(32, 30, 14.6), c2='#5c2470',
                g3=ci(33.9, 28.2, 10.6), c3='#9b3fb5',
                x=[(poly((30.6, 22.6), (30.6, 33.8), (40.2, 28.2)), '#f1dcf7')]),
    'celluloid': dict(label='Celluloid', base='#5650d6', lip='#3f3ba1',
                      g1=rr(10, 12, 44, 36, 4.5), c1='#ffffff',
                      g2=rr(18.5, 15, 27, 30, 2.5) + CELL_HOLES, c2='#5650d6',
                      g3=ci(32, 25.5, 7.2) + poly((29.8, 21.8), (29.8, 29.2), (36, 25.5)), c3='#ffffff',
                      x=[(rr(22, 37.4, 20, 2.6, 1.3), '#e5484d'), (rr(22, 37.4, 6, 2.6, 1.3), '#ffffff'),
                         (ci(27.5, 38.7, 2.9), '#ffffff')]),
    'spotify': dict(label='Spotify', base='#1db954', lip='#168b3f',
                    g1=SPOT_ARCS, c1='#1b2031'),
    'strawberry': dict(label='Strawberry', base='#c93a42', lip='#992a31',
                       g1=BERRY, c1='#ffffff',
                       g2=SEEDS, c2='#c93a42',
                       s1=line((32, 18), (34.5, 10.5)), sc='#3cc4b0', sw=2.6,
                       g3=CALYX, c3='#3cc4b0'),
    'rhythmbox': dict(label='Rhythmbox', base='#475069', lip='#323950',
                      g1=rr(15.5, 10, 33, 40, 5), c1='#ffffff',
                      g2=ci(32, 26.5, 12), c2='#1b2031',
                      s1=line((15.5, 42.5), (48.5, 42.5)), sc='#475069', sw=2.4,
                      g3=ci(32, 26.5, 8.4), c3='#f7c948',
                      x=[(ci(32, 26.5, 3.4), '#1b2031')]),
    'kodi': dict(label='Kodi', base='#1fa3db', lip='#177aa4',
                 g1=''.join(KODI), c1='#ffffff',
                 s1=''.join(KODI), sc='#ffffff', sw=3),
    'obs-studio': dict(label='OBS Studio', base='#2c3348', lip='#1a1f2e',
                       g1=ci(32, 30, 18.4), c1='#ffffff',
                       g2=ci(32, 30, 15.8), c2='#1b2031',
                       g3=OBS_W, c3='#ffffff',
                       x=[(OBS_D, '#1b2031')]),
    'handbrake': dict(label='HandBrake', base='#c2410c', lip='#922f08',
                      g1=HB_GLASS, c1='#ffffff',
                      g2=el(24, 36.5, 9, 11.5), c2='#f7c948',
                      s1=HB_HATCH, sc='#c2410c', sw=2.4,
                      x=[(HB_LEAVES, '#3cc4b0'), (HB_STRAW, '#f7c948')]),
    'audacity': dict(label='Audacity', base='#2f6fdf', lip='#2152ad',
                     g1=rr(11.5, 29, 8.5, 17, 4) + rr(44, 29, 8.5, 17, 4), c1='#ffffff',
                     g2=AUD_WAVE_O, c2='#f2a65a',
                     s1='M15.75 33V29A16.25 16.25 0 0 1 48.25 29V33', sc='#ffffff', sw=4,
                     g3=AUD_WAVE_I, c3='#f7c948'),
    'shotcut': dict(label='Shotcut', base='#2694ad', lip='#1c6f82',
                    g1=rr(12, 12, 40, 36, 4), c1='#1b2031',
                    g2=rr(15, 15, 7, 30, 1.5) + rr(25, 15, 24, 30, 1.5), c2='#a6e6f2'),
    'openshot': dict(label='OpenShot', base='#3a7bd5', lip='#2a5ea8',
                     g1=ci(32, 28.5, 17), c1='#ffffff',
                     g2=OS_S, c2='#3a7bd5',
                     s1=OS_FILM, sc='#1b2031', sw=6.6,
                     g3=OS_HOLES, c3='#ffffff'),
    'ardour': dict(label='Ardour', base='#d63a5a', lip='#a12c44',
                   g1=poly((32, 11.5), (51, 47), (13, 47)), c1='#ffffff',
                   s1=poly((32, 11.5), (51, 47), (13, 47)), sc='#ffffff', sw=3,
                   x=[(ARD_SLOTS, '#d63a5a')]),
    'lmms': dict(label='LMMS', base='#3aa65b', lip='#2a7e44',
                 g1=LMMS_CUPS, c1='#ffffff',
                 s1='M16.4 34V21L32 12L47.6 21V34', sc='#ffffff', sw=5.6),
    'musescore': dict(label='MuseScore', base='#2a3aa8', lip='#1f2b7e',
                      g1=MUSE, c1='#6fe3ff'),
    'easyeffects': dict(label='Easy Effects', base='#2b8be6', lip='#1f68b3',
                        g1=rr(19.4, 12, 3.2, 36, 1.6) + rr(30.4, 12, 3.2, 36, 1.6) + rr(41.4, 12, 3.2, 36, 1.6),
                        c1='#bfdcff',
                        g3=ci(21, 32, 5) + ci(32, 20, 5) + ci(43, 36, 5), c3='#ffffff'),
    'gimp': dict(label='GIMP', base='#b7792f', lip='#8a5a20',
                 g1=WILBER, c1='#ffffff',
                 g2=WIL_EYES, c2='#ffffff',
                 s1=WIL_EYES + 'M21 38.5Q30 44 39.5 39', sc='#1b2031', sw=2.4,
                 g3=WIL_PUPILS + ci(14.8, 30, 3.3), c3='#1b2031',
                 x=[(WIL_BRUSH, '#f2a65a'), (ci(51.5, 33.5, 2.6), '#1b2031')]),
    'inkscape': dict(label='Inkscape', base='#5b6478', lip='#414859',
                     g1=INK_MTN, c1='#1b2031',
                     g2=INK_DRIPS, c2='#1b2031',
                     s1=INK_MTN, sc='#1b2031', sw=2.4,
                     g3=INK_SNOW, c3='#ffffff'),
    'blender': dict(label='Blender', base='#e0821c', lip='#a86215',
                    g1=BL_ARMS + ci(38.4, 32.4, 15), c1='#ffffff',
                    g2=ring(39, 32.4, 11, 8.6), c2='#e0821c',
                    g3=ci(38.4, 32.4, 5.6), c3='#2b5db5'),
    'darktable': dict(label='darktable', base='#2c3348', lip='#1a1f2e',
                      x=[(p, c) for p, c in zip(DT_PARTS, DT_COLS)]
                      + [(DT_GAPS + ci(32, 30, 4.9), '#2c3348'), (ci(32, 30, 2.6), '#ffffff')]),
    'rawtherapee': dict(label='RawTherapee', base='#f4f5f9', lip='#d5d9e3',
                        x=RT_RING),
    'pinta': dict(label='Pinta', base='#1f9e8f', lip='#15756a',
                  g1=PIN_HANDLE, c1='#f2a65a',
                  g2=PIN_TIP, c2='#1b2031',
                  g3=PIN_TUBE, c3='#ffffff',
                  x=[(rr(32.5, 25.5, 14.5, 4.4, 0), '#1f9e8f'), (PIN_FERRULE, '#ffffff')]),
    'scribus': dict(label='Scribus', base='#3f7fe0', lip='#2b5db5',
                    g1=ci(29, 31, 16.5), c1='#2b5db5',
                    g2=SCR_SWOOSH, c2='#bcd4ff',
                    g3=SCR_NIB, c3='#f7c948',
                    x=[(SCR_SLIT + SCR_HOLE, '#2b5db5')]),
    'freecad': dict(label='FreeCAD', base='#c93a42', lip='#992a31',
                    g1=gear(37.4, 36, 13, 10, 9), c1='#5b9dff',
                    g2=ci(37.4, 36, 4.5), c2='#c93a42',
                    g3=FC_F, c3='#ffffff'),
}

APPS = {
    'org.videolan.vlc': 'vlc',
    'io.mpv.mpv': 'mpv',
    'io.github.celluloid_player.Celluloid': 'celluloid',
    'com.spotify.Client': 'spotify',
    'org.strawberrymusicplayer.strawberry': 'strawberry',
    'org.gnome.Rhythmbox3': 'rhythmbox',
    'tv.kodi.Kodi': 'kodi',
    'com.obsproject.Studio': 'obs-studio',
    'fr.handbrake.ghb': 'handbrake',
    'org.audacityteam.Audacity': 'audacity',
    'org.shotcut.Shotcut': 'shotcut',
    'org.openshot.OpenShot': 'openshot',
    'org.ardour.Ardour': 'ardour',
    'io.lmms.LMMS': 'lmms',
    'org.musescore.MuseScore': 'musescore',
    'com.github.wwmm.easyeffects': 'easyeffects',
    'org.gimp.GIMP': 'gimp',
    'org.inkscape.Inkscape': 'inkscape',
    'org.blender.Blender': 'blender',
    'org.darktable.darktable': 'darktable',
    'com.rawtherapee.RawTherapee': 'rawtherapee',
    'com.github.PintaProject.Pinta': 'pinta',
    'scribus': 'scribus',
    'org.freecad.FreeCAD': 'freecad',
}
