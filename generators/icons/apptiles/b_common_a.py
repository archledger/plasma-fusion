# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, batch common-a: common third-party apps (browsers, office, chat).
import math
import re

from apptiles.kit import *  # noqa: F401,F403  helpers and palette


# ---- local helpers ---------------------------------------------------------------------------

def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def rel(cx, cy, rx, ry, deg):
    """Ellipse rotated by deg degrees."""
    a = math.radians(deg)
    dx, dy = rx * math.cos(a), rx * math.sin(a)
    return (f"M{_f(cx - dx)} {_f(cy - dy)}A{_f(rx)} {_f(ry)} {_f(deg)} 1 0 {_f(cx + dx)} {_f(cy + dy)}"
            f"A{_f(rx)} {_f(ry)} {_f(deg)} 1 0 {_f(cx - dx)} {_f(cy - dy)}z")


def pt(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def arc(cx, cy, r, a0, a1):
    """Open arc from angle a0 to a1 (degrees, clockwise on screen when a1 > a0)."""
    x0, y0 = pt(cx, cy, r, a0)
    x1, y1 = pt(cx, cy, r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    sweep = 1 if a1 > a0 else 0
    return f"M{_f(x0)} {_f(y0)}A{_f(r)} {_f(r)} 0 {large} {sweep} {_f(x1)} {_f(y1)}"


def rotp(points, deg, c=(32, 30)):
    a = math.radians(deg)
    out = []
    for x, y in points:
        dx, dy = x - c[0], y - c[1]
        out.append((c[0] + dx * math.cos(a) - dy * math.sin(a), c[1] + dx * math.sin(a) + dy * math.cos(a)))
    return out


def scl(points, k, c=(32, 30)):
    """Scale points by k about c."""
    return [(c[0] + (x - c[0]) * k, c[1] + (y - c[1]) * k) for x, y in points]


def _arc_to(cx, cy, r, p, q, via):
    """Arc command on circle (cx, cy, r) from p to q that passes the side holding point via."""
    ang = lambda pt_: math.degrees(math.atan2(pt_[1] - cy, pt_[0] - cx)) % 360
    ap, aq, av = ang(p), ang(q), ang(via)
    cw = (aq - ap) % 360
    if (av - ap) % 360 < cw:
        sweep, span = 1, cw
    else:
        sweep, span = 0, 360 - cw
    return f"A{_f(r)} {_f(r)} 0 {1 if span > 180 else 0} {sweep} {_f(q[0])} {_f(q[1])}"


def crescent(cx1, cy1, r1, cx2, cy2, r2):
    """Disc (cx1, cy1, r1) minus disc (cx2, cy2, r2), as one closed path; the discs must cross."""
    dx, dy = cx2 - cx1, cy2 - cy1
    d = math.hypot(dx, dy)
    a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    h = math.sqrt(r1 * r1 - a * a)
    mx, my = cx1 + a * dx / d, cy1 + a * dy / d
    p = (mx + h * dy / d, my - h * dx / d)
    q = (mx - h * dy / d, my + h * dx / d)
    far = (cx1 - r1 * dx / d, cy1 - r1 * dy / d)
    near = (cx2 - r2 * dx / d, cy2 - r2 * dy / d)
    return (f"M{_f(p[0])} {_f(p[1])}" + _arc_to(cx1, cy1, r1, p, q, far)
            + _arc_to(cx2, cy2, r2, q, p, near) + "z")


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


# ---- shared motifs ---------------------------------------------------------------------------

# LibreOffice family: a white page with the suite's folded top-right corner (light tint of the
# app colour); the app's own glyph sits on the page in the app colour.
LO_PAGE = 'M19 10h18l12 12v25a3 3 0 0 1-3 3H19a3 3 0 0 1-3-3V13a3 3 0 0 1 3-3z'
LO_FOLD = 'M37 10v9a3 3 0 0 0 3 3h9z'

# Brave: the lion head (crown with two ears, tapering to the chin).
BRAVE_HEAD = [(22, 10), (42, 10), (45, 12.5), (50, 12), (51.5, 17), (49, 22.5), (50, 27), (46.5, 38), (38, 46),
              (32, 49), (26, 46), (17.5, 38), (14, 27), (15, 22.5), (12.5, 17), (14, 12), (19, 12.5)]


def _bv(pts):
    return scl(pts, 0.95, (32, 29.5))


# LibreWolf: a front-facing wolf head with tall ears.
# Review: howling wolf in profile, snout up to the right, neck merging into the ring at the bottom.
LW_WOLF = [(36.3, 46.2), (36.6, 39.5), (34.8, 33.2), (36.8, 28.6), (39.8, 25.6), (35.4, 24), (41.2, 20),
           (40.6, 16.6), (31.6, 20), (28.2, 21.2), (23.4, 16.2), (20.6, 22.4), (16.1, 25.7), (15.8, 34.3),
           (21.2, 42.9), (30.5, 46.7)]
LW_HEAD = [(18, 10), (26.5, 19), (37.5, 19), (46, 10), (48, 26), (43, 37), (32, 48), (21, 37), (16, 26)]


def _lw(pts):
    return scl(pts, 0.96, (32, 30.5))


# Chromium: the Chrome construction in the Chromium blues.
_ch = chrome_parts(32, 30, 18, 8.2, 150)


def _slack():
    out = []
    for k in range(4):
        parts = []
        for x, y, w, h in [(13, 21, 16, 6), (23, 13, 6, 6)]:
            pts = rotp([(x, y), (x + w, y + h)], 90 * k)
            x0, x1 = sorted([pts[0][0], pts[1][0]]); y0, y1 = sorted([pts[0][1], pts[1][1]])
            parts.append(rr(x0, y0, x1 - x0, y1 - y0, 3))
        out.append("".join(parts))
    return out


_sl = _slack()


def _element():
    out = []
    for k in range(4):
        cx, cy = rotp([(30, 25.5)], 90 * k)[0]
        out.append(arc(cx, cy, 10.5, -90 + 90 * k, 90 * k))
    return "".join(out)


def _signal_ring():
    return "".join(arc(32, 30, 17, a, a + 19) for a in range(-80, 280, 30))


def _whatsapp_bubble(r_out, r_in):
    c = (32, 29)
    p0 = pt(*c, r_out, 152); p1 = pt(*c, r_out, 118)
    outer = (f"M{_f(p0[0])} {_f(p0[1])}A{_f(r_out)} {_f(r_out)} 0 1 1 {_f(p1[0])} {_f(p1[1])}"
             f"L14 47.5z")
    return outer + ci(c[0], c[1], r_in)


CLYDE = ("M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,"
         "72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,"
         "105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,"
         "2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,"
         "6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,"
         "65.69,31,60,31,53s5-12.74,11.44-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,"
         "73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z")
_cs = 37 / 127.14


# Microsoft Edge: the wave swirl (white crest, teal inner curl, light underside), baked from a circle
# and three ellipses (crest = disc minus ellipse) as plain polygons.
EDGE_CREST = (
    'M50 29.8L49.9 28L49.6 26.3L49.2 24.6L48.5 22.9L47.8 21.3L46.8 19.8L45.8 18.4L44.6 17.1'
    'L43.2 15.9L41.8 14.9L40.3 14L38.7 13.3L37 12.7L35.3 12.3L33.5 12.1L31.8 12L30 12.1L28.3 12.4'
    'L26.6 12.8L24.9 13.5L23.3 14.2L21.8 15.2L20.4 16.2L19.1 17.4L17.9 18.8L16.9 20.2L16 21.7'
    'L15.3 23.3L14.7 25L14.3 26.7L14.1 28.5L14 30.2L14.1 32L14.4 33.7L14.8 35.4L15.5 37.1'
    'L16.2 38.7L17.2 40.2L18.2 41.6L19.4 42.9L20.8 44.1L22.2 45.1L23.7 46L25.3 46.7L27 47.3'
    'L28.7 47.7L30.5 47.9L32.2 48L34.3 47.9L32.5 47.6L30.9 47.2L29.3 46.5L28 45.7L26.8 44.7'
    'L25.8 43.6L25.1 42.3L24.6 40.9L24.4 39.6L24.3 38.3L24.5 37.1L24.8 35.8L25.4 34.4L26 33.3'
    'L26.8 32.2L27.8 31L28.8 30.1L30 29.2L31.2 28.4L32.7 27.6L34.2 27L35.6 26.6L37.1 26.3'
    'L38.7 26.1L40.5 26.1L42.3 26.4L44.1 26.8L45.6 27.4L46.9 28.2L48.1 29.2L49.2 30.4L49.9 31.7z'
)
EDGE_CURL = (
    'M38.8 33.9L38.2 32.8L37.4 31.8L36.3 31L35.1 30.4L33.8 30L32.2 29.7L30.6 29.7L29 29.9'
    'L28.1 30.7L27.4 31.5L26.7 32.3L26.1 33.2L25.5 34.1L25.1 35L24.8 35.9L24.5 36.8L24.4 37.8'
    'L24.3 38.7L24.4 39.6L24.5 40.5L24.7 41.4L25.1 42.3L25.5 43.1L26.1 43.9L27.1 45L27.5 45.3'
    'L27.7 45.3L27.6 44.8L27.6 44.1L27.7 43.4L28 42.7L28.3 42L28.8 41.3L29.9 40L30.8 39.1'
    'L31.9 38.3L33 37.6L34.2 37L35.5 36.5L36.7 36.1L38 35.8L39.2 35.6L39.1 34.8z'
)
EDGE_UNDER = (
    'M34.2 47.8L36.6 47.4L38.5 46.8L40.5 45.9L42.2 44.8L43.8 43.6L45.2 42.3L46.5 40.7L47.6 39.1'
    'L48.5 37.3L49.2 35.4L49.7 33.5L49.9 31.7L49.2 30.5L48.4 29.5L47.4 28.6L46.2 27.7L45.3 27.3'
    'L44.4 26.9L43.4 26.6L42.3 26.4L41.3 26.2L40.2 26.1L37.9 26.2L35.6 26.6L33.4 27.3L31.4 28.3'
    'L30.4 28.9L29.4 29.6L30.5 29.1L31.8 28.6L33 28.2L34.3 27.9L35.5 27.7L36.7 27.7L37.8 27.7'
    'L38.9 27.8L39.9 28L40.9 28.3L41.8 28.8L42.6 29.3L43.3 29.9L43.9 30.6L44.3 31.3L44.7 32.2'
    'L44.9 33.3L44.8 34.6L44.5 36L44 37.3L43.2 38.6L42.3 39.8L41.1 41L39.8 42.1L38.3 43L36.7 43.8'
    'L35.1 44.5L33.4 44.9L31.8 45.2L30.1 45.3L28.6 45.3L27.1 45L27.9 45.6L28.7 46.2L29.6 46.6'
    'L30.5 47L31.5 47.4L32.7 47.6z'
)

# ---- tiles -----------------------------------------------------------------------------------

TILES = {
    # Browsers
    'chromium': dict(label='Chromium', base='#f4f5f9', lip='#d5d9e3',
                     g1=_ch[0], c1='#1967d2', g2=_ch[1], c2='#a8c7fa', g3=_ch[2], c3='#5e97f6',
                     x=[(ci(32, 30, 8.2), '#ffffff'), (ci(32, 30, 6), '#1a73e8')]),
    'brave': dict(label='Brave', base='#ec5a2c', lip='#b8401c',
                  g1=poly(*_bv(BRAVE_HEAD)), c1='#ffffff', s1=poly(*_bv(BRAVE_HEAD)), sc='#ffffff', sw=2.4,
                  g3=poly(*_bv([(21.5, 26), (28, 28), (27.2, 30.6), (22.5, 29)]))
                  + poly(*_bv([(42.5, 26), (36, 28), (36.8, 30.6), (41.5, 29)]))
                  + poly(*_bv([(27, 34.5), (37, 34.5), (33.2, 39), (33.2, 44), (30.8, 44), (30.8, 39)])),
                  c3='#ec5a2c'),
    # Review: the real mark is a red V inside a white disc (the bare white V read like another letter tile).
    'vivaldi': dict(label='Vivaldi', base='#ef4040', lip='#bb3030',
                    g1=ci(32, 30, 18.5), c1='#ffffff',
                    s1='M24.2 23.2c2.4 4.6 4.6 9.2 7.6 14.6c3-5.4 6-11.6 8.6-17.6', sc='#ef4040', sw=5.4,
                    g3=ci(24.2, 22.4, 3.6), c3='#ef4040'),
    'microsoft-edge': dict(label='Microsoft Edge', base='#1f75d1', lip='#17589e',
                           g1=EDGE_CREST, c1='#ffffff', g2=EDGE_UNDER, c2='#9fd0ff', g3=EDGE_CURL, c3='#3cc4b0'),
    'librewolf': dict(label='LibreWolf', base='#1a9ee6', lip='#1377b0',
                      g1=poly(*LW_WOLF), c1='#ffffff',
                      g2=ring(32, 30, 19, 15.8), c2='#ffffff',
                      g3=poly((28.4, 24.6), (32.4, 23.4), (30.6, 26.6)), c3='#1a9ee6'),
    'zen-browser': dict(label='Zen Browser', base='#2c3348', lip='#1a1f2e',
                        g2=ring(32, 30, 18, 14.5) + ring(32, 30, 11, 7.5), c2='#ffffff',
                        g3=ci(32, 30, 4), c3='#ffffff'),
    'torbrowser': dict(label='Tor Browser', base='#7f3bb8', lip='#5e2b8a',
                       g1='M32 12a18 18 0 0 0 0 36z', c1='#ffffff',
                       s1=arc(32, 30, 16.5, -90, 90) + arc(32, 30, 11, -90, 90) + arc(32, 30, 5.5, -90, 90),
                       sc='#ffffff', sw=2.8),
    # Mail
    'thunderbird': dict(label='Thunderbird', base='#1f6fd6', lip='#1752a3',
                        g1=crescent(32, 30, 18.5, 39.5, 22, 16) + ci(31.5, 14.6, 5.4)
                           + 'M35.5 10.6L43.5 12.6L36.4 18.6Z' + 'M27 10.6Q22 9.2 18.6 11.6Q22.4 12.6 25.4 15.4Z', c1='#8cc4ff',
                        g3=rr(17, 23.5, 30, 21, 4), c3='#ffffff',
                        x=[('M19.5 26l12.5 9 12.5-9v3l-12.5 9-12.5-9z', '#1f6fd6'), (ci(32.6, 13.8, 1.6), '#1f6fd6')]),
    'evolution': dict(label='Evolution', base='#7b5cd6', lip='#5a40a8',
                      g1=rr(11, 14, 34, 25, 4), c1='#ffffff',
                      g2=ci(44, 38, 11.5), c2='#7b5cd6',
                      s1='M13.5 16.5l14.5 11 14.5-11', sc='#7b5cd6', sw=3,
                      g3=ci(44, 38, 9), c3='#ffffff',
                      x=[('M42.8 31.5h2.4v6.8l4 2.5-1.2 2-5.2-3.2z', '#5a40a8')]),
    # LibreOffice
    'libreoffice-writer': dict(label='LibreOffice Writer', base='#2b78d8', lip='#1f5aa6',
                               g1=LO_PAGE, c1='#ffffff', g2=LO_FOLD, c2='#a9cbf5',
                               s1='M21.5 18h11M21.5 24.5h11M21.5 31h9M21.5 37.5h22M21.5 44h14', sc='#2b78d8', sw=2.6,
                               g3=rr(34, 26, 10, 8, 1.5), c3='#2b78d8',
                               x=[('M35.5 33l3-3.2 2 2 1.2-1.2 1.8 2.4z', '#ffffff')]),
    'libreoffice-calc': dict(label='LibreOffice Calc', base='#3aa65b', lip='#2a7e44',
                             g1=LO_PAGE, c1='#ffffff', g2=LO_FOLD, c2='#b5e3c1',
                             g3=''.join(rr(21 + 8.5 * c, 26 + 7 * r, 6, 4.5, 1) for c in range(3) for r in range(3)),
                             c3='#3aa65b',
                             x=[(rr(21, 16, 14, 5, 1.5), '#2a7e44')]),
    'libreoffice-impress': dict(label='LibreOffice Impress', base='#e0602c', lip='#b0461d',
                                g1=LO_PAGE, c1='#ffffff', g2=LO_FOLD, c2='#f7c3a8',
                                g3=rr(20.5, 27, 24, 17, 2.5), c3='#e0602c',
                                s1='M21.5 18.5h12', sc='#e0602c', sw=2.6,
                                x=[('M24 39.5l5-5 4 3 7-7.5 1.6 1.6-8.4 8.9-4-3-3.6 3.6z', '#ffffff')]),
    'libreoffice-draw': dict(label='LibreOffice Draw', base='#e39b1e', lip='#b07514',
                             g1=LO_PAGE, c1='#ffffff', g2=LO_FOLD, c2='#f6dba6',
                             g3=ci(25.5, 27.5, 5.5) + poly((25.5, 46), (32.5, 35), (39.5, 46)), c3='#e39b1e',
                             s1=rr(33.5, 24.5, 9, 9, 1.5), sc='#b07514', sw=2.4),
    'libreoffice-math': dict(label='LibreOffice Math', base='#d43a5f', lip='#a42b48',
                             g1=LO_PAGE, c1='#ffffff', g2=LO_FOLD, c2='#f4bccb',
                             s1='M20.5 32h3l3.5 9 5.5-17h12M34.5 29.5l7.5 8M42 29.5l-7.5 8', sc='#d43a5f', sw=2.6),
    'libreoffice-base': dict(label='LibreOffice Base', base='#a33bb5', lip='#7c2c8a',
                             g1=LO_PAGE, c1='#ffffff', g2=LO_FOLD, c2='#e6bdee',
                             g3=el(32.5, 26, 9, 3.6) + 'M23.5 29.5a9 3.6 0 0 0 18 0v4a9 3.6 0 0 1-18 0z'
                             + 'M23.5 37a9 3.6 0 0 0 18 0v4a9 3.6 0 0 1-18 0z', c3='#a33bb5'),
    'libreoffice-startcenter': dict(label='LibreOffice', base='#5b6478', lip='#414859',
                                    g1=LO_PAGE, c1='#ffffff', g2=LO_FOLD, c2='#c9cfdd'),
    'onlyoffice': dict(label='ONLYOFFICE', base='#f4f5f9', lip='#d5d9e3',
                       g1=poly((32, 31), (50, 39), (32, 47), (14, 39)), c1='#e5484d',
                       g2=poly((32, 22.5), (52, 31.5), (32, 40.5), (12, 31.5)), c2='#f4f5f9',
                       g3=poly((32, 23), (50, 31), (32, 39), (14, 31)), c3='#8bc34a',
                       x=[(poly((32, 14.5), (52, 23.5), (32, 32.5), (12, 23.5)), '#f4f5f9'),
                          (poly((32, 15), (50, 23), (32, 31), (14, 23)), '#3fa9f5')]),
    # Notes and reading
    'obsidian': dict(label='Obsidian', base='#2c3348', lip='#1a1f2e',
                     g1=poly((27, 9), (43, 16.5), (48, 36), (37, 50), (18, 41), (17, 23)), c1='#8463ec',
                     g2=poly((27, 9), (43, 16.5), (48, 36), (37, 50), (34, 30)), c2='#a98cff',
                     g3=poly((27, 9), (34, 30), (37, 50), (23, 32)), c3='#dcd0ff'),
    'joplin': dict(label='Joplin', base='#1872d0', lip='#1256a0',
                   s1='M30 16.5h11v17.5a9.5 9.5 0 0 1-19 0', sc='#ffffff', sw=6),
    'logseq': dict(label='Logseq', base='#2c919f', lip='#216d78',
                   g1=rel(33, 37, 15, 8, -8), c1='#d2f0f0',
                   g2=rel(22.5, 21, 6.5, 4.5, -25), c2='#ffffff',
                   g3=rel(40, 19.5, 7.5, 5, 15), c3='#ffffff'),
    'zotero': dict(label='Zotero', base='#c4283a', lip='#961e2c',
                   g1=poly((18, 12), (46, 12), (46, 18.5), (29, 41), (46, 41), (46, 47.5), (18, 47.5),
                           (18, 41), (35, 18.5), (18, 18.5)), c1='#ffffff'),
    'calibre': dict(label='Calibre', base='#b7792f', lip='#8a5a20',
                    g1=rr(13, 12, 10, 36, 2.5) + rr(25, 16, 8.5, 32, 2.5), c1='#ffffff',
                    s1='M13.8 19h8.4M13.8 41h8.4M25.8 22h7M25.8 42h7', sc='#b7792f', sw=2.4,
                    g3=poly(*rotp([(36, 15), (43, 15), (43, 48), (36, 48)], 16, (39.5, 48))), c3='#5b9dff',
                    x=[(poly(*rotp([(38.5, 15), (40.5, 15), (40.5, 25), (39.5, 23.5), (38.5, 25)], 16, (39.5, 48))),
                        '#ffffff')]),
    'foliate': dict(label='Foliate', base='#1f9e8f', lip='#15756a',
                    g1='M11 18q10.5-4 21 1q10.5-5 21-1v27q-10.5-4-21 1q-10.5-5-21-1z', c1='#ffffff',
                    s1='M32 19v26M37 25.5h11M37 31h11M37 36.5h8', sc='#9ad8cf', sw=2.4,
                    g3='M15.5 40c0-11 4-19 13-26c1 9-2 18-13 26z', c3='#1aa391'),
    # Chat and calls
    'discord': dict(label='Discord', base='#4a57e3', lip='#3640b0',
                    g2=xf(CLYDE, _cs, 32 - 63.57 * _cs, 30 - 48.18 * _cs), c2='#ffffff'),
    'telegram': dict(label='Telegram', base='#2aa3e0', lip='#1d7cad',
                     g1=poly((13, 29.5), (51, 14), (44, 46), (32.5, 37.5), (27, 44), (26.5, 35)), c1='#ffffff',
                     g3=poly((26.5, 35), (46, 20), (32.5, 37.5), (27, 44)), c3='#c6e5f6'),
    'signal-desktop': dict(label='Signal', base='#3d78e8', lip='#2c5bb8',
                           g1=ci(32, 30, 11.5) + poly((22, 35), (26.5, 40), (19.5, 42)), c1='#ffffff',
                           s1=_signal_ring(), sc='#ffffff', sw=2.6),
    'slack': dict(label='Slack', base='#f4f5f9', lip='#d5d9e3',
                  g1=_sl[0], c1='#36c5f0', g2=_sl[1], c2='#2eb67d', g3=_sl[2], c3='#ecb22e',
                  x=[(_sl[3], '#e01e5a')]),
    'element-desktop': dict(label='Element', base='#14bd8c', lip='#0e8f6a',
                            s1=_element(), sc='#ffffff', sw=4.4),
    'zoom-meetings': dict(label='Zoom', base='#2462e6', lip='#1a4bb3',
                          g1=rr(12, 20, 27, 21, 5), c1='#ffffff',
                          s1=poly((42.5, 26.5), (51, 21.5), (51, 39.5), (42.5, 34.5)), sc='#ffffff', sw=2.6,
                          g3=poly((42.5, 26.5), (51, 21.5), (51, 39.5), (42.5, 34.5)), c3='#ffffff'),
    'teams-for-linux': dict(label='Teams for Linux', base='#5559cc', lip='#3f43a3',
                            g1=ci(44, 18.5, 5) + 'M35 26h15a3 3 0 0 1 3 3v8a9 9 0 0 1-18 0z', c1='#c5c7f2',
                            g2=rr(11, 17, 27, 27, 5), c2='#ffffff',
                            g3='M17 23h15v4.5h-5.25V39h-4.5V27.5H17z', c3='#5559cc'),
    'whatsapp': dict(label='WhatsApp', base='#22b35e', lip='#1a8746',
                     g2=_whatsapp_bubble(17, 13.8), c2='#ffffff',
                     s1='M26.5 23.5c-1 5 3.5 11 10 12.5', sc='#ffffff', sw=4.2,
                     x=[(rel(26.6, 23, 2.6, 3.4, 20), '#ffffff'), (rel(37, 35.6, 3.4, 2.6, 20), '#ffffff')]),
}

APPS = {
    'org.mozilla.firefox': 'round1:firefox',
    'google-chrome': 'round1:chrome',
    'chromium-browser': 'chromium',
    'com.brave.Browser': 'brave',
    'com.vivaldi.Vivaldi': 'vivaldi',
    'com.microsoft.Edge': 'microsoft-edge',
    'io.gitlab.librewolf-community': 'librewolf',
    'app.zen_browser.zen': 'zen-browser',
    'org.torproject.torbrowser-launcher': 'torbrowser',
    'org.mozilla.Thunderbird': 'thunderbird',
    'org.gnome.Evolution': 'evolution',
    'libreoffice-writer': 'libreoffice-writer',
    'libreoffice-calc': 'libreoffice-calc',
    'libreoffice-impress': 'libreoffice-impress',
    'libreoffice-draw': 'libreoffice-draw',
    'libreoffice-math': 'libreoffice-math',
    'libreoffice-base': 'libreoffice-base',
    'libreoffice-startcenter': 'libreoffice-startcenter',
    'org.onlyoffice.desktopeditors': 'onlyoffice',
    'md.obsidian.Obsidian': 'obsidian',
    'net.cozic.joplin_desktop': 'joplin',
    'com.logseq.Logseq': 'logseq',
    'org.zotero.Zotero': 'zotero',
    'calibre-gui': 'calibre',
    'com.github.johnfactotum.Foliate': 'foliate',
    'com.discordapp.Discord': 'discord',
    'org.telegram.desktop': 'telegram',
    'org.signal.Signal': 'signal-desktop',
    'com.slack.Slack': 'slack',
    'im.riot.Riot': 'element-desktop',
    'us.zoom.Zoom': 'zoom-meetings',
    'com.github.IsmaelMartinez.teams_for_linux': 'teams-for-linux',
    'com.ktechpit.whatsie': 'whatsapp',
}
