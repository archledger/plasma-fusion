# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, batch graphics-media (KDE graphics, photo, audio and video apps).
import math

from apptiles.kit import *  # noqa: F401,F403


def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pt(cx, cy, r, a):
    """Point on a circle; a in degrees, 0 = +x, positive = clockwise on screen."""
    t = math.radians(a)
    return cx + r * math.cos(t), cy + r * math.sin(t)


def wedge(cx, cy, r, a0, a1):
    p0 = pt(cx, cy, r, a0); p1 = pt(cx, cy, r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{_f(cx)} {_f(cy)}L{_f(p0[0])} {_f(p0[1])}"
            f"A{_f(r)} {_f(r)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}z")


def xform(pts, ang, tx, ty):
    """Rotate (x, y[, r]) points by ang degrees about the origin, then translate."""
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(p[0] * c - p[1] * s + tx, p[0] * s + p[1] * c + ty) + tuple(p[2:]) for p in pts]


def rpoly(pts, r=0.0):
    """Closed polygon with rounded corners. Points are (x, y) or (x, y, radius)."""
    n = len(pts)
    segs = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        rad = p1[2] if len(p1) > 2 else r
        d0 = math.hypot(p0[0] - p1[0], p0[1] - p1[1]); d2 = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        r0 = min(rad, d0 / 2); r2 = min(rad, d2 / 2)
        a = (p1[0] + (p0[0] - p1[0]) * r0 / d0, p1[1] + (p0[1] - p1[1]) * r0 / d0)
        b = (p1[0] + (p2[0] - p1[0]) * r2 / d2, p1[1] + (p2[1] - p1[1]) * r2 / d2)
        segs.append((a, p1, b, rad > 0))
    out = []
    for i, (a, p1, b, rounded) in enumerate(segs):
        out.append(("M" if i == 0 else "L") + f"{_f(a[0])} {_f(a[1])}")
        if rounded:
            out.append(f"Q{_f(p1[0])} {_f(p1[1])} {_f(b[0])} {_f(b[1])}")
    return "".join(out) + "z"


def rrect(cx, cy, w, h, r, ang):
    """Rotated rounded rectangle centred on (cx, cy)."""
    return rpoly(xform([(-w / 2, -h / 2, r), (w / 2, -h / 2, r), (w / 2, h / 2, r), (-w / 2, h / 2, r)],
                       ang, cx, cy))


def drop(cx, cy, r):
    """Paint drop: round bottom centred on (cx, cy), point up."""
    return (f"M{_f(cx)} {_f(cy - 2.1 * r)}C{_f(cx + .45 * r)} {_f(cy - 1.35 * r)} {_f(cx + r)} {_f(cy - .65 * r)} "
            f"{_f(cx + r)} {_f(cy)}A{_f(r)} {_f(r)} 0 0 1 {_f(cx - r)} {_f(cy)}"
            f"C{_f(cx - r)} {_f(cy - .65 * r)} {_f(cx - .45 * r)} {_f(cy - 1.35 * r)} {_f(cx)} {_f(cy - 2.1 * r)}z")


def ann(cx, cy, ro, ri):
    """Annulus that also works as a nonzero fill (inner circle drawn the other way round)."""
    return ci(cx, cy, ro) + (f"M{_f(cx - ri)} {_f(cy)}a{_f(ri)} {_f(ri)} 0 1 1 {_f(2 * ri)} 0"
                             f"a{_f(ri)} {_f(ri)} 0 1 1 {_f(-2 * ri)} 0z")


# --- shared motifs -------------------------------------------------------------------------------

# Howling wolf (Amarok, Recorder): head up and to the right, open jaws, ear and neck tufts.
WOLF_HEAD = [
    (16.8, 40.5, 0), (15.4, 34.8, 0), (19.0, 34.2, 0), (17.6, 28.6, 2.5), (17.4, 18.6, .8),
    (24.8, 24.2, 1.2), (28.6, 23.6, 2), (43.4, 13.7, .9), (45.2, 16.8, .9), (34.6, 27.6, .4),
    (46.8, 24.6, .9), (45.8, 27.8, 1), (39.4, 32.6, 2.5), (41.4, 38.6, 2),
]
WOLF_EYE = 'M27.6 29.2c1.8-2.6 4.2-3.8 6.6-3.6-1.6 2.6-4 3.8-6.6 3.6z'


def amarok_wolf(R=20, cx=32, cy=30):
    """The wolf cut by the bottom of the Amarok disc."""
    a0 = math.degrees(math.atan2(math.sqrt(R * R - 10 ** 2), 10))      # x = 42
    a1 = math.degrees(math.atan2(math.sqrt(R * R - 14.5 ** 2), -14.5))  # x = 17.5
    arc = [pt(cx, cy, R, a0 + (a1 - a0) * k / 12) + (0,) for k in range(13)]
    return rpoly(WOLF_HEAD + arc)


def lens(cx, cy, glass, blade):
    """digiKam / Showfoto lens: dark barrel with an engraved band, coloured glass with a six-blade
    aperture (alternate blades a shade darker) and a dark centre."""
    R, hexr = 12.5, 4.4
    vs = [pt(cx, cy, hexr, 30 + 60 * k) for k in range(6)]
    ends = []
    for k in range(6):
        v0, v1 = vs[k], vs[(k + 1) % 6]
        d = (v1[0] - v0[0], v1[1] - v0[1]); L = math.hypot(*d); d = (d[0] / L, d[1] / L)
        ox, oy = v1[0] - cx, v1[1] - cy
        b = ox * d[0] + oy * d[1]; c = ox * ox + oy * oy - R * R
        t = -b + math.sqrt(b * b - c)
        ends.append((v1[0] + d[0] * t, v1[1] + d[1] * t))
    blades = ""
    for k in (0, 2, 4):
        e0, e1 = ends[k], ends[(k + 1) % 6]
        a0 = math.degrees(math.atan2(e0[1] - cy, e0[0] - cx)); a1 = math.degrees(math.atan2(e1[1] - cy, e1[0] - cx))
        da = (a1 - a0 + 540) % 360 - 180
        arc = [pt(cx, cy, R, a0 + da * j / 6) for j in range(7)]
        blades += rpoly([vs[(k + 1) % 6] + (0,)] + [p + (0,) for p in arc] + [vs[(k + 2) % 6] + (0,)])
    hexagon = rpoly([v + (.5,) for v in vs])
    return dict(g1=ci(cx, cy, 19.5), c1='#1b2031',
                g2=ci(cx, cy, R), c2=glass,
                s1='M' + ci(cx, cy, 16.2)[1:], sc='#5d6680', sw=2.4,
                g3=blades, c3=blade,
                x=[(hexagon, '#1b2031'), (ci(cx - 5.5, cy - 6.5, 1.8), '#ffffff')])


def scanner(pages):
    """Skanlite / Skanpage: flatbed scanner front with page(s) on the glass and a scan beam."""
    return dict(g1=rr(11, 10.5, 42, 39.5, 5.5), c1='#ffffff',
                g2=rr(14.5, 15, 35, 23.5, 2.5), c2='#cfe0fb',
                g3=pages, c3='#ffffff',
                x=[(rr(13.5, 25.2, 37, 3, 1.5), '#3cc4b0'), (ci(45.5, 44, 1.8), '#3cc4b0')])


def page(x, y, w, h, fold=4.5):
    return rpoly([(x, y, 1), (x + w - fold, y, 0), (x + w, y + fold, 0), (x + w, y + h, 1), (x, y + h, 1)])


def note8(hx, hy):
    """Eighth note with its head centred on (hx, hy) (head 10 x 8, stem 25 up, flag right)."""
    head = el(hx, hy, 5.2, 4.1)
    sx = hx + 2.2
    stem = rr(sx, hy - 25, 3.1, 25, 1.55)
    flag = (f"M{_f(sx + 2.6)} {_f(hy - 25)}c.6 4 3.2 5.6 5.6 7.4 2 1.6 3 3.8 2.4 6.8"
            f"-.5-2.4-2-3.8-3.9-4.8-1.5-.8-3.1-1.3-4.1-2.2z")
    return head + stem + flag


# --- per-app pieces ---------------------------------------------------------------------------------

# Recorder: the wolf mirrored (howling to the left into the microphone), scaled down.
_rw = [(48 + (64 - x - 48) * .8, 47.5 + (y - 47.5) * .8, r) for x, y, r in WOLF_HEAD]
_rw = _rw + [(48 + (64 - 42 - 48) * .8, 47.5, 0), (48 + (64 - 17.5 - 48) * .8, 47.5, 0)]
RECORDER_EYE = rpoly([(48 + (64 - x - 48) * .8, 47.5 + (y - 47.5) * .8, .5) for x, y in
                      [(27.6, 29.2), (30.5, 26.4), (34.2, 25.6), (31.6, 28.4)]])
RECORDER_WOLF = rpoly(_rw)

# JuK: luggage tag with a key ring, note in front.
_TAG = [(-18, -11, 3), (9, -11, 2), (17.5, -3.5, 1.5), (17.5, 3.5, 1.5), (9, 11, 2), (-18, 11, 3)]
_JA, _JC = -22, (33.5, 31)
_jh = xform([(12.6, 0)], _JA, *_JC)[0]
_jr = xform([(16.4, -4.6)], _JA, *_JC)[0]
JUK_TAG = rpoly(xform(_TAG, _JA, *_JC)) + "M" + ci(_jh[0], _jh[1], 2.5)[1:]
JUK_RING = ann(_jr[0], _jr[1], 5.8, 3.4)
JUK_NOTE = (el(23.6, 37.5, 4.6, 3.6) + rr(25.6, 20.5, 2.9, 17, 1.45)
            + 'M28.2 20.5c.4 3 2.4 4.2 4.2 5.6 1.6 1.2 2.4 2.9 1.9 5.2-.4-1.8-1.6-2.9-3-3.6-1.2-.6-2.4-1-3.1-1.7z')

# Kid3: speaker and a yellow tag with a note.
_k3tag = xform([(-13, -8, 2.5), (13, -8, 2.5), (13, 8, 2.5), (-13, 8, 2.5)], -14, 37.5, 37.5)
_k3hole = xform([(9, -3.6)], -14, 37.5, 37.5)[0]
_k3note = (rpoly(xform([(-3.6, -6, .8), (-1.2, -6, .8), (-1.2, 3.4, 0), (-3.6, 3.4, 0)], -14, 37.5, 37.5))
           + rpoly(xform([(-1.2, -6, .6), (3.2, -3.2, 1), (3.2, -1, .6), (-1.2, -3.2, 0)], -14, 37.5, 37.5)))
_k3head = xform([(-5.6, 3.6)], -14, 37.5, 37.5)[0]

# Krita: colour wheel and brush.
_kw = (34, 31, 18)
_KRITA_WEDGES = [(-120, -60, '#d6457a'), (-60, 0, '#f2a65a'), (0, 60, '#f7c948'),
                 (60, 120, '#3cc4b0'), (120, 180, '#5b9dff'), (180, 240, '#8a63e0')]
_kb = lambda pts: rpoly(xform(pts, 45, 10.5, 10.5))
KRITA_HANDLE = _kb([(0, -2.3, 2), (16.5, -3.4, .5), (16.5, 3.4, .5), (0, 2.3, 2)])
KRITA_FERRULE = _kb([(17, -3.6, .6), (21, -3.6, .6), (21, 3.6, .6), (17, 3.6, .6)])
KRITA_TIP = _kb([(21.5, -3.8, 1), (26.5, -4, 2.5), (30.5, -1.8, 2), (33.5, 3.2, .6), (29.5, 2.2, 1.5),
                 (26, 3.8, 1), (21.5, 3.8, 1)])

# KolourPaint: brush along a 32 degree axis.
_kp = lambda pts: rpoly(xform(pts, 32, 12, 9.5))
KP_TIP = _kp([(0, 0, .6), (3, -2.6, 1.5), (8.5, -3.8, .8), (10.5, -3.8, 0), (10.5, 3.8, 0), (8.5, 3.8, .8),
              (3, 2.6, 1.5)])
KP_HANDLE = _kp([(12.5, -3.9, .8), (16.5, -4.4, 2), (43, -2.7, 2), (46, 0, 2), (43, 2.7, 2), (16.5, 4.4, 2),
                 (12.5, 3.9, .8)])

# Kwave: growing sine wave over the K.
_wv = []
for k in range(97):
    x = 24.5 + 27.5 * k / 96
    amp = 2 + 8.5 * k / 96
    _wv.append((x, 34 - amp * math.sin(2 * math.pi * (x - 24.5) / 9.17)))
KWAVE_WAVE = "M" + "L".join(f"{_f(x)} {_f(y)}" for x, y in _wv)

# PlasmaTube: two film strips forming a play chevron.
def _strip(x0, y0, x1, y1, w, holes):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    L = math.hypot(x1 - x0, y1 - y0); a = math.degrees(math.atan2(y1 - y0, x1 - x0))
    body = rrect(cx, cy, L, w, 2, a)
    hs = ""
    for k in range(holes):
        u = -L / 2 + 4.5 + (L - 9) * k / (holes - 1)
        hx, hy = xform([(u, -1.4)], a, cx, cy)[0]
        hs += rrect(hx, hy, 3.4, 2.6, .5, a)
    return body, hs


PT_LOW, PT_LOW_H = _strip(14, 45, 39, 32.5, 8.5, 3)
PT_UP, PT_UP_H = _strip(14, 16, 50, 33, 9, 5)

TILES = {
    'amarok': dict(label='Amarok', base='#2f6fdf', lip='#2152ad',
                   g1=ci(32, 30, 20), c1='#ffffff',
                   g2=amarok_wolf(), c2='#2152ad',
                   x=[(WOLF_EYE, '#ffffff')]),
    'audex': dict(label='Audex', base='#3b45b8', lip='#2c3489',
                  g2=ci(30, 27, 16.5) + "M" + ci(30, 27, 2.8)[1:], c2='#ffffff',
                  s1='M' + ci(30, 27, 5.6)[1:], sc='#c5c9f0', sw=2.4,
                  g3=rr(32, 35, 21, 14, 3.5), c3='#1b2031',
                  x=[(rr(41.2, 37.6, 2.8, 5.6, .8) + rpoly([(37, 42.4, .6), (47.6, 42.4, .6), (42.6, 47, .6)]),
                      '#f7c948')]),
    'audiotube': dict(label='AudioTube', base='#e0474c', lip='#b0353a',
                      s1='M' + ci(32, 30, 15.5)[1:] + 'M12 30H16.5M47.5 30H52', sc='#f8c4c6', sw=3,
                      g3=''.join(rr(21.4 + 5.8 * k, 30 - h / 2, 3.6, h, 1.8) for k, h in enumerate([21, 15.5, 10.5, 6])),
                      c3='#ffffff'),
    'qrca': dict(label='Barcode Scanner', base='#1fa0d6', lip='#1678a3',
                 s1='M12.5 19.5v-4a3 3 0 0 1 3-3h4M44.5 12.5h4a3 3 0 0 1 3 3v4M51.5 40.5v4a3 3 0 0 1-3 3h-4'
                    'M19.5 47.5h-4a3 3 0 0 1-3-3v-4', sc='#e5484d', sw=3.2,
                 g3='M13.5 41C17 33 25 27 35 26.5 43 26.3 48.5 32 50.6 39.2L53.6 36.8 53.2 43.8 46.6 44.6'
                    'L49 41.6C46.5 37.8 42 36.2 37.5 37.2 31 38.6 22 42.2 13.5 41z'
                    'M27.6 28.4L31.8 17.4 37.2 26.8z', c3='#1b2031',
                 x=[(rr(23.2, 30.6, 3.4, 3.4, .5) + rr(27.6, 29.4, 3.4, 3.4, .5) + rr(23.8, 35.2, 3.4, 3.4, .5)
                     + rr(28.2, 33.8, 2.2, 2.2, .4), '#ffffff'),
                    (rrect(18.6, 37.6, 4.6, 2.2, 1.1, -24), '#ffffff')]),
    'digikam': dict(label='digiKam', base='#3f7fe0', lip='#2b5db5', **lens(32, 30, '#8fbfff', '#4f8ff0')),
    'showfoto': dict(label='Showfoto', base='#e8743b', lip='#b8552a', **lens(32, 30, '#f7c948', '#f2a65a')),
    'dragonplayer': dict(label='Dragon Player', base='#2b4fb0', lip='#1f3a85',
                         g1='M50 9.5C45 13 40.5 19 40 27c-.4 6 2 10 6 13-2-5-1.6-11 1-16 1.8-3.6 3.6-8.6 3-14.5z'
                            'M11.5 33C17 28 25 26.5 31 28.5 25 29.5 19 32 14.5 36.5z'
                            + rpoly([(22.5, 13, 0), (27.5, 9.2, .4), (29.2, 12.2, 0), (34.2, 9.6, .4), (34.6, 13.6, 0),
                                     (39.6, 13, .4), (38, 17.2, 0), (41.6, 19.8, .4), (37.6, 22.4, 0), (32, 18, 0)]),
                         c1='#8fbfff',
                         g2=rpoly([(14.5, 22.5, .6), (17.5, 16.5, 2), (23, 12.5, 3), (29.5, 12.2, 3), (35, 15.5, 3),
                                   (38, 21, 3), (36.5, 29, 4), (33, 33.5, 3), (36, 38.5, 1), (23.5, 38.5, 1),
                                   (27, 30, 3), (26, 24, 3), (21.5, 22, 1.5), (18, 23.5, 1)]), c2='#ffffff',
                         g3=rr(13, 41.5, 38, 7.5, 2) + ''.join(
                             'M' + rr(15 + 7.2 * k, 43.7, 5.2, 3.1, .8)[1:] for k in range(5)), c3='#8fbfff',
                         x=[(ci(24.5, 17, 1.6), '#2b4fb0')]),
    'haruna': dict(label='Haruna', base='#2c3348', lip='#1a1f2e',
                   g2=rpoly([(15, 12, 2.5), (25.5, 12, 2.5), (25.5, 25, 0), (38.5, 25, 0), (38.5, 12, 2.5),
                             (49, 12, 2.5), (49, 48, 2.5), (38.5, 48, 2.5), (38.5, 35, 0), (25.5, 35, 0),
                             (25.5, 48, 2.5), (15, 48, 2.5)])
                      + ''.join('M' + rr(17.5, y, 3.6, 3.6, .6)[1:] + 'M' + rr(42.9, y, 3.6, 3.6, .6)[1:]
                                for y in (16, 28.2, 40.4)), c2='#ffffff'),
    'juk': dict(label='JuK', base='#3aa65b', lip='#2a7e44',
                g1=JUK_RING, c1='#c4ead0',
                g2=JUK_TAG, c2='#ffffff',
                g3=JUK_NOTE, c3='#2a7e44'),
    'k3b': dict(label='K3b', base='#c93a42', lip='#992a31',
                g1='M22 48.5C14.5 45 10.5 37.5 11.5 29.5 12.2 23 15 17 19.5 12 19 16.5 19.6 19.5 21.5 21.5'
                   ' 22.5 18 24.8 15.5 27.5 13.8 27.4 16.4 28 18.4 29.5 19.6 30.2 16.2 31.8 13.2 34.2 10.8'
                   ' 34.6 14 35.5 17 37.3 19.4 38.6 17.4 40.6 15.8 43 14.8 42.4 17.4 42.6 19.6 43.6 21.4'
                   ' 45.2 18.8 45.8 15.8 45.2 12.6 50.5 17 53 23.5 52.5 30 52 38 47.5 45 41 48.5z', c1='#f2a65a',
                g2='M24.5 46C19.5 43 17 37.5 17.6 32 18 28 19.8 24.6 22.6 22 22.4 24.6 23 26.4 24.2 27.6'
                   ' 25.6 24 28.4 21.2 32 19.4 31.6 22 32.2 24 33.6 25.4 35 23.4 37.2 22 39.6 21.4'
                   ' 39.2 23.2 39.6 25 40.6 26.2 42 25 43 23.6 43.4 21.6 46.4 25.4 47.4 30.4 46.6 35'
                   ' 45.6 40 42.6 43.6 39.5 46z', c2='#f7c948',
                g3=ci(32, 34, 12.5), c3='#ffffff',
                x=[(ann(32, 34, 6.2, 3.8), '#f6d3d5'), (ci(32, 34, 2.6), '#c93a42')]),
    'kaffeine': dict(label='Kaffeine', base='#a0522d', lip='#783d21',
                     g1=ci(34, 30, 18), c1='#f3d9c8',
                     g2=ci(34, 30, 13.5), c2='#ffffff',
                     s1='M14 12.5V31', sc='#ffffff', sw=3,
                     g3=ci(34, 30, 10) + "M" + rpoly([(31, 25, 1), (39.5, 30, 1), (31, 35, 1)])[1:], c3='#783d21',
                     x=[(rr(45.5, 26.5, 8, 7, 3.5), '#ffffff'), (el(14, 38, 3.6, 5.4), '#ffffff')]),
    'kamoso': dict(label='Kamoso', base='#2b8be6', lip='#1f68b3',
                   g1=rr(10.5, 14.5, 43, 25.5, 9), c1='#ffffff',
                   g2=ci(32, 27.2, 11), c2='#1b2031',
                   g3=ci(32, 27.2, 7.4) + "M" + ci(32, 27.2, 3.2)[1:], c3='#5b9dff',
                   x=[(ci(29.2, 24.4, 1.7), '#ffffff'),
                      (rr(29, 39, 6, 6, 0) + rr(19.5, 44.5, 25, 4.5, 2.25), '#ffffff'),
                      (ci(47, 21, 1.8), '#5b9dff')]),
    'kdenlive': dict(label='Kdenlive', base='#2c3348', lip='#1a1f2e',
                     g1=''.join(rr(25 - L, 14.5 + 5.6 * k, L, 3.2, 1.6) for k, L in
                                enumerate([5, 9, 13.5, 11, 7.5, 4])), c1='#5b9dff',
                     g2=rpoly([(34, 15, 2.5), (52, 30, 2.5), (34, 45, 2.5)]), c2='#ffffff',
                     s1='M29 16V48', sc='#f2a65a', sw=2.6,
                     x=[(rpoly([(23.5, 10, 1), (34.5, 10, 1), (29, 17.5, 1)]), '#f2a65a')]),
    'kgeotag': dict(label='KGeoTag', base='#3f8f5a', lip='#2d6b42',
                    g1=ci(34, 33.5, 16), c1='#5b9dff',
                    g2=rpoly([(25.4, 31.8, 1.5), (29, 30.2, 1.5), (34.5, 30.6, 1.5), (38.4, 30, 1.5), (40.6, 32.4, 1),
                              (45.6, 35.4, 1), (42.4, 38.8, 1.5), (40.6, 43.4, 1.5), (36.6, 47.6, 1.5),
                              (34.4, 45, 1.5), (33.4, 40.2, 1.5), (31, 37.6, 1.5), (27, 37.4, 1.5), (24.4, 34.6, 1.5)])
                       + rpoly([(28.2, 27.2, 1.5), (30.4, 23.6, 1.5), (34.6, 22.8, 1.5), (38.6, 20.2, 1.5),
                                (42.6, 21.6, 1.5), (40.4, 25.6, 1.5), (36, 27, 1.5), (31.6, 28.6, 1.5)]), c2='#ffffff',
                    g3='M22 9.5c-5 0-8.5 3.6-8.5 8.2 0 5.8 8.5 13.8 8.5 13.8s8.5-8 8.5-13.8c0-4.6-3.5-8.2-8.5-8.2z'
                       + ci(22, 17.8, 3.2), c3='#e5484d'),
    'kid3': dict(label='Kid3', base='#f5c84c', lip='#c99a22',
                 g1=rpoly([(11, 18.5, 1.5), (23, 12.5, 0), (23, 34.5, 0), (11, 28.5, 1.5)]), c1='#1f9e8f',
                 g2=el(23, 23.5, 5.5, 11), c2='#ffffff',
                 s1='M' + el(23.6, 23.5, 2.6, 6.2)[1:], sc='#1f9e8f', sw=2.4,
                 g3=rpoly(_k3tag) + "M" + ci(_k3hole[0], _k3hole[1], 1.9)[1:], c3='#ffffff',
                 x=[(_k3note + el(_k3head[0], _k3head[1], 3.2, 2.5), '#1b2031')]),
    'kmix': dict(label='KMix', base='#2f9e6e', lip='#227650',
                 g1='M15.5 39.5a16.5 7.5 0 0 0 33 0v2.8a16.5 7.5 0 0 1-33 0z' + el(32, 39.5, 16.5, 7.5),
                 c1='#bfe8d4',
                 g2=el(32, 39, 14.2, 6.2), c2='#ffffff',
                 s1='M13 20A25 17 0 0 1 51 20M19.5 27A17 11.5 0 0 1 44.5 27', sc='#ffffff', sw=3.8,
                 g3=el(32, 38.8, 9.8, 4.2) + "M" + el(32, 38.4, 4.2, 1.9)[1:], c3='#227650'),
    'kolourpaint': dict(label='KolourPaint', base='#f4f5f9', lip='#d5d9e3',
                        g1=KP_TIP + KP_HANDLE, c1='#f2a65a',
                        x=[(drop(16, 43, 4.4), '#3cc4b0'), (drop(26.5, 43, 4.4), '#5b9dff'),
                           (drop(37, 43, 4.4), '#e5484d')]),
    'kontrast': dict(label='Kontrast', base='#3b4255', lip='#262b38',
                     g1=ci(32, 30, 18.5), c1='#1b2031',
                     g2='M32 11.5A18.5 18.5 0 0 1 32 48.5z'
                        + rpoly([(29.4, 15.5, .6), (34.6, 15.5, .6), (44.5, 44, .6), (39.2, 44, .6), (36.8, 37, 0),
                                 (27.2, 37, 0), (24.8, 44, .6), (19.5, 44, .6)])
                        + rpoly([(32, 23, 0), (35.2, 32.4, 0), (28.8, 32.4, 0)]), c2='#3cc4b0'),
    'kphotoalbum': dict(label='KPhotoAlbum', base='#b7792f', lip='#8a5a20',
                        g1=rr(12, 12, 40, 36, 3), c1='#ffffff',
                        g2=rr(18, 17.5, 28, 24.5, 1.5), c2='#5b9dff',
                        g3=rpoly([(18, 39, 0), (25.5, 30, 1), (31, 35.5, 1), (36.5, 28.5, 1), (46, 39, 0),
                                  (46, 42, 0), (18, 42, 0)]) + ci(25, 24, 3), c3='#ffffff',
                        x=[(rrect(44.5, 18.5, 13, 4.6, .6, 45), '#f7c948'),
                           (rrect(19.5, 41, 13, 4.6, .6, 45), '#f7c948')]),
    'krita': dict(label='Krita', base='#9b3fb5', lip='#742d88',
                  x=[(wedge(*_kw, a0, a1), c) for a0, a1, c in _KRITA_WEDGES]
                    + [(KRITA_HANDLE + KRITA_TIP, '#1b2031'), (KRITA_FERRULE, '#ffffff')]),
    'kruler': dict(label='KRuler', base='#f5c84c', lip='#c99a22',
                   g1=rpoly([(14.5, 12, 3), (51, 12, 2.5), (51, 21.5, 2.5), (24, 21.5, 1), (24, 48, 2.5),
                             (14.5, 48, 3)]), c1='#ffffff',
                   s1=''.join(f'M{x} 20.3v-{4.2 if k % 2 == 0 else 2.4}' for k, x in enumerate([28.5, 33, 37.5, 42, 46.5]))
                      + ''.join(f'M22.8 {y}h-{4.2 if k % 2 == 0 else 2.4}' for k, y in enumerate([26, 30.5, 35, 39.5, 44])),
                   sc='#b7792f', sw=2.4),
    'kwave': dict(label='Kwave', base='#475069', lip='#323950',
                  g1=rpoly([(14, 12, 1.5), (22.5, 12, 1.5), (22.5, 26, 0), (34, 12, 1.5), (44.5, 12, 1.5),
                            (30.5, 28.5, 0), (45, 48, 1.5), (34.5, 48, 1.5), (22.5, 32.5, 0), (22.5, 48, 1.5),
                            (14, 48, 1.5)]), c1='#ffffff',
                  s1=KWAVE_WAVE, sc='#3cc4b0', sw=3),
    'optiimage': dict(label='OptiImage', base='#3a7bd5', lip='#2a5ea8',
                      g1='M17 15.5H32V44.5H17a2.5 2.5 0 0 1-2.5-2.5V18a2.5 2.5 0 0 1 2.5-2.5z', c1='#1b2031',
                      g2=rr(11, 12, 42, 36, 5) + "M" + rr(14.5, 15.5, 35, 29, 2.5)[1:], c2='#ffffff',
                      g3=rpoly([(14.5, 40.5, 0), (24, 30.5, 1), (29.5, 36, 1), (37.5, 27.5, 1), (49.5, 40.5, 0),
                                (49.5, 42, 0), (47, 44.5, 0), (17, 44.5, 0), (14.5, 42, 0)]) + ci(22, 22.5, 3.2),
                      c3='#ffffff',
                      x=[(rr(30.5, 10, 3, 40, 1.5), '#e5484d')]),
    'plasmatube': dict(label='PlasmaTube', base='#2c3348', lip='#1a1f2e',
                       g1=PT_LOW, c1='#e5484d',
                       g2=PT_LOW_H, c2='#ffffff',
                       s1=PT_UP, sc='#2c3348', sw=3,
                       g3=PT_UP, c3='#e5484d',
                       x=[(PT_UP_H, '#ffffff')]),
    'krecorder': dict(label='Recorder', base='#262c42', lip='#131726',
                      g1=ci(35, 26, 13.5), c1='#e5484d',
                      g2=RECORDER_WOLF, c2='#ffffff',
                      s1='M17.5 31V46.5M12.5 47H22.5', sc='#ffffff', sw=3.2,
                      g3=rr(12, 12.5, 11, 18.5, 5.5), c3='#ffffff',
                      x=[(rr(16.5, 17.5, 6.5, 2.6, 1.3) + rr(16.5, 21.8, 6.5, 2.6, 1.3) + rr(16.5, 26.1, 6.5, 2.6, 1.3)
                          + RECORDER_EYE, '#262c42')]),
    'skanlite': dict(label='Skanlite', base='#5b6478', lip='#414859', **scanner(page(18.5, 18, 15, 18))),
    'skanpage': dict(label='Skanpage', base='#1f9e8f', lip='#15756a',
                     **scanner(page(17.5, 21, 13, 15) + "M" + page(32.5, 18, 13, 15)[1:])),
    'soundkonverter': dict(label='soundKonverter', base='#7b5cd6', lip='#5a40a8',
                           g1=note8(17.5, 40), c1='#ffffff',
                           g2=el(46, 19.5, 5.2, 4.1) + rr(41.2, 19.5, 3.1, 25, 1.55), c2='#d9ccff',
                           s1='M25 23.5C28 19.5 32 18 36.5 18.5M39 36.5C36 40.5 32 42 27.5 41.5',
                           sc='#f2a65a', sw=3,
                           g3=rpoly([(35, 14.5, .6), (40.5, 18.8, .6), (35.2, 22.6, .6)])
                              + rpoly([(29, 37.4, .6), (23.5, 41.2, .6), (28.8, 45.5, .6)]), c3='#f2a65a'),
}

APPS = {
    'org.kde.amarok': 'amarok',
    'org.kde.audex': 'audex',
    'org.kde.audiotube': 'audiotube',
    'org.kde.qrca': 'qrca',
    'org.kde.digikam': 'digikam',
    'org.kde.dragonplayer': 'dragonplayer',
    'org.kde.elisa': 'round1:elisa',
    'org.kde.haruna': 'haruna',
    'org.kde.juk': 'juk',
    'org.kde.k3b': 'k3b',
    'org.kde.kaffeine': 'kaffeine',
    'org.kde.kamoso': 'kamoso',
    'org.kde.kdenlive': 'kdenlive',
    'org.kde.kgeotag': 'kgeotag',
    'org.kde.kid3': 'kid3',
    'org.kde.kid3_qt': 'kid3',
    'org.kde.kmix': 'kmix',
    'org.kde.kolourpaint': 'kolourpaint',
    'org.kde.kontrast': 'kontrast',
    'org.kde.kphotoalbum': 'kphotoalbum',
    'org.kde.krita': 'krita',
    'org.kde.kruler': 'kruler',
    'org.kde.kwave': 'kwave',
    'org.kde.optiimage': 'optiimage',
    'org.kde.plasma.camera': 'board:camera',
    'org.kde.plasmatube': 'plasmatube',
    'org.kde.krecorder': 'krecorder',
    'org.kde.showfoto': 'showfoto',
    'org.kde.skanlite': 'skanlite',
    'org.kde.skanpage': 'skanpage',
    'soundkonverter': 'soundkonverter',
}
