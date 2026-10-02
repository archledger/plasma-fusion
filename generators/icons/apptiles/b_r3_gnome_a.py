# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, round 3 batch gnome-a.
from apptiles.kit import *  # noqa: F401,F403  helpers and palette
# Plasma Fusion app tiles, round 3, batch gnome-a: GNOME core apps (Files, Calculator, Calendar,
# Characters, Clocks, Contacts, Connections, Disk Usage Analyzer, Fonts, Logs, Help).
import math
import re

from textoutline import text_in_box


# ---- local helpers ---------------------------------------------------------------------------

def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pt(cx, cy, r, a):
    """Point on a circle; a in degrees, 0 = +x, positive = clockwise on screen."""
    t = math.radians(a)
    return cx + r * math.cos(t), cy + r * math.sin(t)


def band(cx, cy, ro, ri, a0, a1):
    """Annular sector from a0 to a1 (clockwise)."""
    p0 = pt(cx, cy, ro, a0); p1 = pt(cx, cy, ro, a1)
    q1 = pt(cx, cy, ri, a1); q0 = pt(cx, cy, ri, a0)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{_f(p0[0])} {_f(p0[1])}A{_f(ro)} {_f(ro)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}"
            f"L{_f(q1[0])} {_f(q1[1])}A{_f(ri)} {_f(ri)} 0 {large} 0 {_f(q0[0])} {_f(q0[1])}z")


def wedge(cx, cy, r, a0, a1):
    p0 = pt(cx, cy, r, a0); p1 = pt(cx, cy, r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{_f(cx)} {_f(cy)}L{_f(p0[0])} {_f(p0[1])}"
            f"A{_f(r)} {_f(r)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}z")


def bar(x0, y0, x1, y1, w):
    """Straight bar with round ends from (x0, y0) to (x1, y1), w wide (a filled stroke)."""
    L = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / L, (y1 - y0) / L
    nx, ny = -uy * w / 2, ux * w / 2
    r = w / 2
    return (f"M{_f(x0 + nx)} {_f(y0 + ny)}L{_f(x1 + nx)} {_f(y1 + ny)}"
            f"A{_f(r)} {_f(r)} 0 0 0 {_f(x1 - nx)} {_f(y1 - ny)}L{_f(x0 - nx)} {_f(y0 - ny)}"
            f"A{_f(r)} {_f(r)} 0 0 0 {_f(x0 + nx)} {_f(y0 + ny)}z")


def hand(cx, cy, ang, length, w, tail=0.0):
    """Clock hand from the centre (tail units behind it) to length units along ang (0 = 12 o'clock)."""
    a = math.radians(ang - 90)
    ux, uy = math.cos(a), math.sin(a)
    return bar(cx - ux * tail, cy - uy * tail, cx + ux * length, cy + uy * length, w)


_NUM = re.compile(r"-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def shear(d, k, y0):
    """Slant an absolute M/L/C/Q path (text outlines): x += k * (y0 - y)."""
    out = []
    for cmd, args in re.findall(r"([MLCQZ])([^MLCQZ]*)", d):
        if cmd == "Z":
            out.append("Z"); continue
        n = [float(v) for v in _NUM.findall(args)]
        out.append(cmd + " ".join(f"{_f(n[i] + k * (y0 - n[i + 1]))} {_f(n[i + 1])}" for i in range(0, len(n), 2)))
    return "".join(out)


# ---- motifs ----------------------------------------------------------------------------------

# Files (Nautilus): the Adwaita filing cabinet, a white frame around three blue drawers with pulls.
_CAB_DRAWERS = (13, 25, 37)
_CABINET = rr(13, 10, 38, 40, 5) + ''.join(rr(16, y, 32, 9.8, 2) for y in _CAB_DRAWERS)
_CAB_PULLS = ''.join(rr(26, y + 2.2, 12, 3.4, 1.7) for y in _CAB_DRAWERS)
_CAB_PULL_SHADOWS = ''.join(rr(26, y + 3.6, 12, 3.4, 1.7) for y in _CAB_DRAWERS)

# Calculator: green display, round dark keys and the tall orange key (the Adwaita calculator).
_CALC_KEYS = (''.join(ci(x, 26.5, 4) for x in (18, 32, 46))
              + ''.join(ci(x, y, 4) for x in (18, 32) for y in (36, 45.5)))

# Calendar: a white page with a purple header, a dot grid and one big purple dot.
_CAL_HEAD = 'M12 16a5 5 0 0 1 5-5h30a5 5 0 0 1 5 5v4H12z'
_CAL_DOTS = ''.join(ci(x, y, 1.9) for x in (18, 25, 32, 39, 46) for y in (27, 35, 43) if (x, y) != (32, 35))

# Characters: one sample per quadrant, as in the original: CJK (blue), emoji (yellow), a flower
# dingbat (purple) and Arabic (green), split by a light cross.
_MOON = (bar(17.5, 15, 26.5, 15, 2.4) + bar(26.5, 15, 26.5, 27.5, 2.4) + bar(17.5, 15, 17.5, 22.5, 2.4)
         + bar(17.5, 22.5, 15.4, 27.6, 2.4) + bar(17.5, 19.4, 26.5, 19.4, 2.4) + bar(17.5, 23.6, 26.5, 23.6, 2.4)
         + bar(26.5, 27.5, 24.6, 28.2, 2.4))
_SMILE = (ci(42, 20.5, 6.6) + el(39.6, 18.6, 1.15, 1.6) + el(44.4, 18.6, 1.15, 1.6)
          + 'M38.2 21.6h7.6a3.8 3.8 0 0 1-7.6 0z')
_FLOWER = ''.join(ci(22 + dx, 39.5 + dy, 3) for dx, dy in ((0, -3.4), (3.4, 0), (0, 3.4), (-3.4, 0))) + ci(22, 39.5, 2.4)
_SHIN = 'M47.6 37v3.2a1.4 1.4 0 0 1-2.8 0v-1.4v1.4a1.4 1.4 0 0 1-2.8 0v-1.4v1.4c0 3.2-2 5-4.2 5s-3.4-1.6-3.4-4'
_SHIN_DOTS = ci(43.2, 35.3, 1.5) + ci(46.4, 35.3, 1.5) + ci(44.8, 32.6, 1.5)

# Contacts: a white address book with the at sign and coloured index tabs.
_AT = 'M35.6 26v5.5a2.4 2.4 0 0 0 4.8 0V30A8.6 8.6 0 1 0 36.05 37.45' + ci(31.8, 30, 3.8)


def _tab(y):
    return f'M45 {y}h2.6a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H45z'


# Connections: a blue globe with green land, the dark remote screen with a pointer, and the dotted route.
_GLOBE = (28, 32.5, 17.5)


def _gp(a):
    x, y = pt(*_GLOBE, a)
    return f"{_f(x)} {_f(y)}"


_R = _f(_GLOBE[2])
_LAND = ('M' + _gp(290) + f'A{_R} {_R} 0 0 0 ' + _gp(145)
         + 'C19 40 20 36.5 24 34.5C28 32.5 25.5 27.5 29 25.5C32 23.8 31 19 ' + _gp(290) + 'z'
         + 'M' + _gp(-10) + f'A{_R} {_R} 0 0 1 ' + _gp(75)
         + 'C33 44 37.5 42 39 38.5C40.5 35 42 33 ' + _gp(-10) + 'z')
_SCREEN = rr(31, 9, 22, 19, 5)
_POINTER = poly((37, 12.3), (46.5, 19.8), (42.3, 20.5), (44.8, 24.6), (42.9, 25.6), (40.4, 21.5), (37, 24.5))
_ROUTE = 'M18 38c2.5 0 4 1.2 5 3.5s2 3.5 4.5 3.5h12c2.5 0 4-1.5 4-4V28'
_ROUTE_DOTS = ci(18, 38, 3.3) + ''.join(ci(x, y, 1.5) for x, y in ((23.5, 41.7), (29.5, 45), (35.5, 45), (42.5, 43), (43.5, 35.5)))

# Disk Usage Analyzer: the three-colour pie chart, its blue slice pulled out a little.
_PIE = (32, 30.5, 17.5)

# Fonts: four lowercase a in different styles, white on the purple book.
_FA1 = text_in_box('a', 'manrope-800', 25, (13.5, 7, 18, 22))
_FA2 = text_in_box('a', 'spacegrotesk-700', 25, (32.5, 7, 18, 22))
_FA3 = text_in_box('a', 'spacegrotesk-700', 25, (13.5, 26, 18, 22))
_FA4 = shear(text_in_box('a', 'manrope-800', 25, (32.5, 26, 18, 22)), 0.22, 39)

# Logs: a white log page with a turned corner and the blue magnifier over it.
_LOG_PAGE = 'M21.5 10h23a3.5 3.5 0 0 1 3.5 3.5V41l-9 9H21.5a3.5 3.5 0 0 1-3.5-3.5v-33a3.5 3.5 0 0 1 3.5-3.5z'
_LOG_CURL = 'M39 50v-6a3 3 0 0 1 3-3h6z'
_LOG_LINES = 'M35 17.5h9M36.5 23h7.5M22.5 31h21M22.5 36.5h21M22.5 42h13'

# Help (Yelp): the red and white lifebuoy with its rope.
_BUOY_BANDS = ''.join(band(32, 30, 17.3, 7.7, a - 17, a + 17) for a in (0, 90, 180, 270))


TILES = {
    'gnome-files': dict(label='Files', base='#2b8be6', lip='#1f68b3',
                        g2=_CABINET, c2='#ffffff',
                        x=[(_CAB_PULL_SHADOWS, '#1f68b3'), (_CAB_PULLS, '#ffffff')]),
    # Light body with dark keys, as in Adwaita; a dark body with light keys would be board:calculator (KCalc).
    'gnome-calculator': dict(label='Calculator', base='#f4f5f9', lip='#d5d9e3',
                             g1=rr(13, 10, 38, 10.5, 3.5), c1='#3aa65b',
                             g2=_CALC_KEYS, c2='#2c3348',
                             g3=rr(42, 32, 8, 17.5, 4), c3='#e8743b'),
    'gnome-calendar': dict(label='Calendar', base='#9b3fb5', lip='#742d88',
                           g1=rr(12, 11, 40, 38, 5), c1='#ffffff',
                           g2=_CAL_HEAD, c2='#5e2475',
                           g3=_CAL_DOTS, c3='#c9cfdd',
                           x=[(ci(32, 35, 5), '#9b3fb5')]),
    # More than three glyph colours on purpose: the four coloured scripts are the app's mark (like Slack).
    'gnome-characters': dict(label='Characters', base='#f4f5f9', lip='#d5d9e3',
                             g1=rr(30.8, 12, 2.4, 36, 1.2) + rr(13, 28.8, 38, 2.4, 1.2), c1='#d5d9e3',
                             g2=_SMILE, c2='#f7c948',
                             s1=_SHIN, sc='#3aa65b', sw=2.4,
                             x=[(_MOON, '#5b9dff'), (_FLOWER, '#9b3fb5'), (_SHIN_DOTS, '#3aa65b')]),
    # Dark face on an ink base; the blue base with a white ring is KDE Clock (kclock).
    'gnome-clocks': dict(label='Clocks', base='#2c3348', lip='#1a1f2e',
                         g2=ring(32, 30, 19, 14.5), c2='#f4f5f9',
                         g3=hand(32, 30, 312, 8.5, 4) + ci(32, 30, 3), c3='#b4bccc',
                         x=[(hand(32, 30, 48, 12.5, 3), '#ffffff'),
                            (hand(32, 30, 208, 12.5, 2.4, tail=3), '#e5484d'),
                            (ci(32, 30, 1.3), '#2c3348')]),
    'gnome-contacts': dict(label='Contacts', base='#3f7fe0', lip='#2b5db5',
                           g1=rr(13, 10, 33, 40, 4), c1='#ffffff',
                           s1='M18.5 10.5v39' + _AT, sc='#3f7fe0', sw=2.8,
                           x=[(_tab(13.5), '#f7c948'), (_tab(22.5), '#3cc4b0'), (_tab(31.5), '#9b3fb5'),
                              (_tab(40.5), '#e5484d')]),
    'gnome-connections': dict(label='Connections', base='#2f6fdf', lip='#2152ad',
                              g1=ci(*_GLOBE), c1='#5b9dff',
                              g2=_LAND, c2='#3aa65b',
                              s1=_ROUTE, sc='#f2a65a', sw=3,
                              g3=_SCREEN, c3='#1b2031',
                              x=[(_POINTER, '#ffffff'), (_ROUTE_DOTS, '#ffffff')]),
    'gnome-disk-usage': dict(label='Disk Usage Analyzer', base='#475069', lip='#323950',
                             g1=wedge(_PIE[0] + 1.2, _PIE[1] - 1.2, _PIE[2], -90, 0), c1='#5b9dff',
                             g2=wedge(*_PIE, 0, 150), c2='#f7c948',
                             g3=wedge(*_PIE, 150, 270), c3='#3aa65b'),
    # Deep purple, so it is not a second violet tile next to Calendar.
    'gnome-fonts': dict(label='Fonts', base='#5a2ca0', lip='#3e1e70',
                        g1=_FA1 + _FA2 + _FA3, c1='#ffffff',
                        g3=_FA4, c3='#ffffff'),
    # Ink base (a system log viewer); slate made it a twin of KWrite's page tile at 32 px.
    'gnome-logs': dict(label='Logs', base='#2c3348', lip='#1a1f2e',
                       g1=_LOG_PAGE, c1='#ffffff',
                       g2=_LOG_CURL, c2='#c9cfdd',
                       s1=_LOG_LINES, sc='#9aa3b8', sw=2.4,
                       g3=ring(26.5, 20, 9, 6), c3='#5b9dff',
                       x=[(bar(19.6, 26.9, 14, 32.5, 4.2), '#9aa3b8')]),
    # Red base with the bands on the axes; KHelpCenter is the same buoy on blue with diagonal bands.
    'gnome-help': dict(label='Help', base='#c93a42', lip='#992a31',
                       s1=ci(32, 30, 19.2), sc='#f5c2c5', sw=2.4,
                       g2=ring(32, 30, 16.5, 8.5), c2='#ffffff',
                       g3=_BUOY_BANDS, c3='#e5484d'),
}

APPS = {
    'org.gnome.Nautilus': 'gnome-files',
    'org.gnome.Calculator': 'gnome-calculator',
    'org.gnome.Calendar': 'gnome-calendar',
    'org.gnome.Characters': 'gnome-characters',
    'org.gnome.clocks': 'gnome-clocks',
    'org.gnome.Contacts': 'gnome-contacts',
    'org.gnome.Connections': 'gnome-connections',
    'org.gnome.baobab': 'gnome-disk-usage',
    'org.gnome.font-viewer': 'gnome-fonts',
    'org.gnome.Logs': 'gnome-logs',
    'org.gnome.Yelp': 'gnome-help',
}
