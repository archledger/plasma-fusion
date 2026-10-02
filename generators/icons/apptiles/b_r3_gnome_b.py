# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, round 3 batch gnome-b.
from apptiles.kit import *  # noqa: F401,F403  helpers and palette
# Plasma Fusion app tiles, round 3, batch gnome-b: GNOME core apps (viewers, maps, terminal, settings, media).
import math


# ---- local helpers ---------------------------------------------------------------------------

def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pt(cx, cy, r, deg):
    """Point on a circle; deg 0 = +x, positive = clockwise on screen."""
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def xform(pts, ang, tx, ty):
    """Rotate points by ang degrees about the origin, then translate."""
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(x * c - y * s + tx, x * s + y * c + ty) for x, y in pts]


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


def ci_cw(cx, cy, r):
    """Circle drawn clockwise (ci() runs the other way), so ci_cw(outer) + ci(inner) is a ring in a nonzero layer."""
    return (f"M{_f(cx - r)} {_f(cy)}a{_f(r)} {_f(r)} 0 1 1 {_f(2 * r)} 0"
            f"a{_f(r)} {_f(r)} 0 1 1 {_f(-2 * r)} 0z")


def pin(cx, cy, r, tip):
    """Map pin: a disc of radius r with a point at (cx, tip) below it."""
    d = tip - cy
    t = math.degrees(math.acos(r / d))
    p0 = pt(cx, cy, r, 90 + t); p1 = pt(cx, cy, r, 90 - t)
    return (f"M{_f(cx)} {_f(tip)}L{_f(p0[0])} {_f(p0[1])}"
            f"A{_f(r)} {_f(r)} 0 1 1 {_f(p1[0])} {_f(p1[1])}z")


# ---- shapes ----------------------------------------------------------------------------------

# Image Viewer (Loupe): a photo card on a tilted second card, a large magnifier over its lower-left corner.
# Round-3 review: the lens is larger (ring radius 12, was 10.2) and cut free by a base-coloured halo, so
# at 32 px the dark ring tells Loupe from OptiImage's framed photo on the same blue.
_LP_BACK = rot_rr(35.5, 26.5, 34, 29, 3.5, 9)
_LP_CARD = rr(16.5, 10, 36, 31, 4)
_LP_PIC = rr(20.5, 14, 28, 23, 1.5)
_LP_HILL = poly((21, 37), (29.5, 27.5), (35.5, 33), (40, 29), (48, 37))
_LP_C, _LP_RO, _LP_RI = (24.5, 35), 12, 8.4
_LP_HALO = ci_cw(*_LP_C, _LP_RO + 1.6)
_LP_LENS = ci(*_LP_C, _LP_RI)
_LP_RING = ci_cw(*_LP_C, _LP_RO) + ci(*_LP_C, _LP_RI)
_LP_HANDLE = rot_rr(_LP_C[0] - (_LP_RO + 3.6) / math.sqrt(2), _LP_C[1] + (_LP_RO + 3.6) / math.sqrt(2),
                    8, 5, 2.5, 135)

# Maps: the folded map (tan land, blue water panel, green land rising to the fold's peak) crossed
# by white roads, with the large red pin at the top right.
_MP_BODY = 'M14 15h5.5v-1.2h3L26 9.5l5.5 5.5H50a3 3 0 0 1 3 3v27a3 3 0 0 1-3 3H14a3 3 0 0 1-3-3V18a3 3 0 0 1 3-3z'
_MP_WATER = 'M11 39V18a3 3 0 0 1 3-3h5.5v24z'
_MP_ROADS = 'M12.5 40.5H20l6-6 6 6h11a2.5 2.5 0 0 0 2.5-2.5V25M21 39V15.3'
_MP_LAND = ('M22.5 13.8L26 9.5l5.5 5.5H44v23a1 1 0 0 1-1 1H32.6L26 32.4l-3.5 3.5z')
_MP_PIN = pin(42.5, 17.5, 9, 32.5)

# Document Viewer (Papers): a page with the red header band and folded corner, reading glasses.
_PA_PAGE = 'M20 9h19l9 9v27.5a4 4 0 0 1-4 4H20a4 4 0 0 1-4-4V13a4 4 0 0 1 4-4z'
_PA_HEAD = 'M20 9h19v6a3 3 0 0 0 3 3h6v9.5H16V13a4 4 0 0 1 4-4z'
_PA_GLASSES = (ci(25.5, 39.5, 4.3) + ci(38.5, 39.5, 4.3) + 'M29.8 39q2.2-1.5 4.4 0'
               + 'M21.3 38.5 19.3 32M42.7 38.5l2-6.5')

# Video Player (Showtime): the rounded play triangle with its colour bands (outer, middle, inner,
# baked from rings around the tip) above the green lower part.
_ST_OUTER = ('M25.1 10.3L23.8 10L22.5 10L21.3 10.3L20 10.8L19 11.5L18.5 12L17.6 13L17 14.2L16.6 15.5L16.5 16.9'
             'L16.5 33.2L22.5 33.2L22.6 30.7L23 28.3L23.2 27.1L24 24.8L24.9 22.5L26.1 20.3L27.4 18.3L29 16.4'
             'L29.8 15.5L31.5 14L26.3 10.9z')
_ST_MID = ('M31.5 14L29.8 15.5L29 16.4L27.4 18.3L26.1 20.3L24.9 22.5L24 24.8L23.2 27.1L23 28.3L22.6 30.7'
           'L22.5 33.2L34 33.2L34.1 31.2L34.6 29.3L35.3 27.4L36.3 25.7L37.5 24.1L38.9 22.8L40.6 21.6L42.5 20.6z')
_ST_INNER = ('M50.7 33.2L51.3 31.7L51.5 30.3L51.5 29.7L51.3 28.3L51.1 27.6L50.5 26.4L49.7 25.3L48.8 24.4'
             'L42.5 20.6L40.6 21.6L38.9 22.8L37.5 24.1L36.3 25.7L35.3 27.4L34.6 29.3L34.1 31.2L34 33.2z')
_ST_BOTTOM = ('M16.5 43.1L16.6 44.5L16.8 45.2L17.3 46.4L18 47.5L19 48.5L20 49.2L21.3 49.7L22.5 50L23.8 50'
              'L24.5 49.8L25.1 49.7L26.3 49.1L48.2 36L48.8 35.6L49.7 34.7L50.2 34.2L50.7 33.2L16.5 33.2z')

# Document Scanner (Simple Scan): the upright scanner, teal glass over a page with a folded corner,
# the scan line crossing it.
_SC_FRAME = rr(17, 9, 30, 41, 5)
_SC_INNER = rr(20, 12, 24, 35, 2.5)
_SC_GLASS = rr(21.5, 13.5, 21, 15, 1.5)
_SC_PAGE = 'M23 31.5h18a1.5 1.5 0 0 1 1.5 1.5v6.5l-6 6H23a1.5 1.5 0 0 1-1.5-1.5V33a1.5 1.5 0 0 1 1.5-1.5z'
_SC_FLAP = 'M36.5 45.5v-4.5a1.5 1.5 0 0 1 1.5-1.5h4.5z'
_SC_LINE = rr(13, 28.3, 38, 2.8, 1.4)

# Settings: the Adwaita gear, twelve teeth and a wide bore, with its depth showing below.
_GS_DEPTH = gear(32, 31.2, 19, 15, 12)
_GS_FACE = gear(32, 29, 19, 15, 12) + 'M' + ci(32, 29, 9.3)[1:]

# Camera (Snapshot): the lens seen from the front, white bezel, black ring, glass with highlights.
_SN_BEZEL = ci(32, 30, 19.5)
_SN_RING = ci(32, 30, 16)
_SN_GLASS = ci(32, 30, 12.5)
_SN_SHINE = ci(28, 26, 3.6) + ci(36.6, 34.6, 1.8)

# ---- tiles -----------------------------------------------------------------------------------

TILES = {
    # The magnifier over the photo keeps it apart from OptiImage (blue, framed photo) and KMag (magnifier).
    'gnome-loupe': dict(label='Image Viewer', base='#2f6fdf', lip='#2152ad',
                        g1=_LP_BACK, c1='#bcd4ff',
                        g2=_LP_CARD, c2='#ffffff',
                        g3=_LP_PIC, c3='#2f6fdf',
                        x=[(_LP_HILL, '#bcd4ff'), (ci(42.5, 21, 3.2), '#ffffff'), (_LP_HALO, '#2f6fdf'),
                           (_LP_LENS, '#bcd4ff'), (_LP_RING + _LP_HANDLE, '#1b2031')]),
    # Light base: the board's maps tile (green base, pale map, small centred pin) already stands for the
    # category, so GNOME Maps keeps its own multi-colour map (water, land, roads) and the large corner pin.
    'gnome-maps': dict(label='Maps', base='#f4f5f9', lip='#d5d9e3',
                       g1=_MP_BODY, c1='#cdab8f',
                       g2=_MP_WATER, c2='#55a7eb',
                       s1=_MP_ROADS, sc='#ffffff', sw=3,
                       g3=_MP_LAND, c3='#2ec27e',
                       x=[(_MP_PIN, '#e5484d'), (ci(42.5, 17.5, 3.4), '#a51d2d')]),
    # Purple (the stacked back pages of the original): red would be board:reader, blue with glasses Okular.
    'gnome-papers': dict(label='Document Viewer', base='#7b5cd6', lip='#5a40a8',
                         g1=_PA_PAGE, c1='#ffffff',
                         g2=_PA_HEAD, c2='#e5484d',
                         s1=_PA_GLASSES, sc='#1b2031', sw=2.6,
                         x=[(rr(20.5, 14.5, 13, 3.2, 1.6) + rr(20.5, 20.5, 8, 3.2, 1.6), '#ffffff')]),
    # The dark terminal box with its light lower edge, cyan prompt: apart from board:terminal
    # (Konsole: ink tile, teal prompt, three dots).
    # Blue (round-3 review): on slate the dark box with a cyan prompt was a near twin of board:monitor
    # (Plasma System Monitor: dark screen with a teal line on steel) at 32 px; ink would copy Konsole's
    # board:terminal, and light would copy GNOME System Monitor. Blue is GNOME's accent and the prompt's hue.
    'gnome-ptyxis': dict(label='Terminal', base='#3f7fe0', lip='#2b5db5',
                         g1=rr(11, 11, 42, 39, 7), c1='#bcd4ff',
                         g2=rr(11, 11, 42, 35.5, 7), c2='#241f31',
                         s1='M19 30.5l7.5 5-7.5 5M30.5 40.5h8.5', sc='#62c9ea', sw=3.4),
    # The Adwaita gear in its own greys on a light tile, the inverse of board:settings (white gear on slate).
    'gnome-settings': dict(label='Settings', base='#f4f5f9', lip='#d5d9e3',
                           g1=_GS_DEPTH, c1='#68676d',
                           g2=_GS_FACE, c2='#939297',
                           g3=ring(32, 29, 9.3, 6.8), c3='#c0bfbc',
                           x=[(ci(32, 29, 6.8), '#f4f5f9')]),
    # The original's colour rings, flattened to three bands above the green lower part, on navy.
    'gnome-showtime': dict(label='Video Player', base='#262c42', lip='#131726',
                           g1=_ST_OUTER, c1='#7d7ff2',
                           g2=_ST_MID, c2='#e46aa8',
                           g3=_ST_INNER, c3='#ffa348',
                           x=[(_ST_BOTTOM, '#2ec27e')]),
    # Upright scanner (Skanlite and Skanpage are landscape flatbeds); cyan-teal from the scan glass.
    'gnome-simple-scan': dict(label='Document Scanner', base='#22a8ae', lip='#197e83',
                              g1=_SC_FRAME, c1='#ffffff',
                              g2=_SC_INNER, c2='#1b2031',
                              g3=_SC_PAGE, c3='#ffffff',
                              x=[(_SC_GLASS + _SC_FLAP, '#8eeeea'), (_SC_LINE, '#ffffff')]),
    # review: magenta instead of violet; on violet the white ring sat too close to mpv at 32 px.
    'gnome-snapshot': dict(label='Camera', base='#c23d96', lip='#912e70',
                           g1=_SN_BEZEL, c1='#ffffff',
                           g2=_SN_RING, c2='#1b2031',
                           g3=_SN_GLASS, c3='#6a74f0',
                           x=[(_SN_SHINE, '#ffffff')]),
}

APPS = {
    'org.gnome.Loupe': 'gnome-loupe',
    'org.gnome.Maps': 'gnome-maps',
    'org.gnome.Papers': 'gnome-papers',
    'org.gnome.Ptyxis': 'gnome-ptyxis',
    'org.gnome.Settings': 'gnome-settings',
    'org.gnome.Showtime': 'gnome-showtime',
    'org.gnome.SimpleScan': 'gnome-simple-scan',
    'org.gnome.Snapshot': 'gnome-snapshot',
}
