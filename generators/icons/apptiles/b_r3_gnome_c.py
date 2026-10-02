# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, round 3 batch gnome-c.
from apptiles.kit import *  # noqa: F401,F403  helpers and palette
# Plasma Fusion app tiles, round 3, batch gnome-c: GNOME core apps (Software, System Monitor, Text Editor,
# Tour, Weather, Decibels, Sound Recorder, Color Profile Viewer).
import math


# ---- local helpers ---------------------------------------------------------------------------

def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pt(cx, cy, r, deg):
    """Point on a circle; deg 0 = +x, positive = clockwise on screen."""
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def ci_cw(cx, cy, r):
    """Circle drawn clockwise, so it unions with rr() and cw() polygons in a nonzero layer."""
    return (f"M{_f(cx - r)} {_f(cy)}a{_f(r)} {_f(r)} 0 1 1 {_f(2 * r)} 0"
            f"a{_f(r)} {_f(r)} 0 1 1 {_f(-2 * r)} 0z")


def cw(pts):
    """Clockwise (on screen) orientation, so nonzero unions never cancel."""
    a = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]))
    return pts if a > 0 else pts[::-1]


def round_pts(pts, r, n=8):
    """Polygon with every corner rounded by radius r, as a sampled point list (clockwise)."""
    pts = cw(list(pts))
    out = []
    m = len(pts)
    for i in range(m):
        P, V, N = pts[i - 1], pts[i], pts[(i + 1) % m]
        u1 = ((P[0] - V[0]), (P[1] - V[1])); l1 = math.hypot(*u1); u1 = (u1[0] / l1, u1[1] / l1)
        u2 = ((N[0] - V[0]), (N[1] - V[1])); l2 = math.hypot(*u2); u2 = (u2[0] / l2, u2[1] / l2)
        th = math.acos(max(-1.0, min(1.0, u1[0] * u2[0] + u1[1] * u2[1])))
        d = r / math.tan(th / 2)
        bis = (u1[0] + u2[0], u1[1] + u2[1]); lb = math.hypot(*bis); bis = (bis[0] / lb, bis[1] / lb)
        c = (V[0] + bis[0] * r / math.sin(th / 2), V[1] + bis[1] * r / math.sin(th / 2))
        A = (V[0] + u1[0] * d, V[1] + u1[1] * d)
        B = (V[0] + u2[0] * d, V[1] + u2[1] * d)
        a0 = math.atan2(A[1] - c[1], A[0] - c[0]); a1 = math.atan2(B[1] - c[1], B[0] - c[0])
        while a1 < a0:
            a1 += 2 * math.pi
        if a1 - a0 > math.pi:
            a1 -= 2 * math.pi
        for k in range(n + 1):
            a = a0 + (a1 - a0) * k / n
            out.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a)))
    return out


def rot(pts, deg, c):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(c[0] + (x - c[0]) * ca - (y - c[1]) * sa, c[1] + (x - c[0]) * sa + (y - c[1]) * ca) for x, y in pts]


def clip_half(pts, a, b, c):
    """Sutherland-Hodgman: keep the part of a polygon where a*x + b*y + c >= 0."""
    out = []
    m = len(pts)
    for i in range(m):
        P, Q = pts[i - 1], pts[i]
        fp, fq = a * P[0] + b * P[1] + c, a * Q[0] + b * Q[1] + c
        if fq >= 0:
            if fp < 0:
                t = fp / (fp - fq)
                out.append((P[0] + t * (Q[0] - P[0]), P[1] + t * (Q[1] - P[1])))
            out.append(Q)
        elif fp >= 0:
            t = fp / (fp - fq)
            out.append((P[0] + t * (Q[0] - P[0]), P[1] + t * (Q[1] - P[1])))
    return out


def petal(cx, cy, deg, length, half_w, sector=45.0, gap=0.45, n=14):
    """Pointed lens from the centre outward along deg, clipped to its own sector (seams of width 2*gap)."""
    R = (length * length / 4 + half_w * half_w) / (2 * half_w)
    side = []
    for k in range(n + 1):
        x = length * k / n
        side.append((x, math.sqrt(max(0.0, R * R - (x - length / 2) ** 2)) - (R - half_w)))
    loc = side + [(x, -y) for x, y in reversed(side)]
    for s in (1, -1):                       # the two sector edges, each moved inward by gap
        h = math.radians(sector / 2) * s
        nx, ny = math.sin(h) * s, -math.cos(h) * s          # inward normal of the edge ray at angle h
        loc = clip_half(loc, nx, ny, -gap)
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return poly(*[(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in loc])


def star8(cx, cy, ro):
    """Two overlapping squares (Adwaita's weather sun rays): 8 points, ro = centre-to-point distance."""
    ri = ro / math.sqrt(2) / math.cos(math.radians(22.5))
    pts = []
    for k in range(16):
        pts.append(pt(cx, cy, ro if k % 2 == 0 else ri, -90 + 22.5 * k))
    return poly(*pts)


def bar(x, cy, h, w=3.4):
    """Vertical rounded bar centred on (x, cy)."""
    return rr(x - w / 2, cy - h / 2, w, h, w / 2)


# ---- GNOME Software: the shopping bag with the three coloured shapes --------------------------
_BAG_HANDLE = 'M25.5 21V15.5a3 3 0 0 1 3-3h7a3 3 0 0 1 3 3V21'
_BAG = rr(11, 20, 42, 30, 4.5)
_SW_TRI = poly(*round_pts([(30.5, 41.2), (46, 33.6), (46, 48.8)], 2.4))

# ---- GNOME System Monitor: the light case is the tile; dark screen with the pulse line -------
_SM_SCREEN = rr(10, 11.5, 36.5, 36.5, 4.5)
_SM_PULSE = 'M14 29.5H21.5L25.5 17.5L30.5 41.5L34 29.5H37.5'

# ---- GNOME Text Editor: page with the blue title band, curled corner and the orange pencil ---
_TE_PAGE = 'M18 10h22a4 4 0 0 1 4 4V39.5L33.5 50H18a4 4 0 0 1-4-4V14a4 4 0 0 1 4-4z'
_TE_BAND = 'M18 10h22a4 4 0 0 1 4 4v4H14v-4a4 4 0 0 1 4-4z'
_TE_CURL = 'M44 39.5L33.5 50C33.5 44 37.5 39.5 44 39.5z'
_TE_LINES = rr(18, 22, 17, 3.2, 1.6) + rr(18, 28, 12, 3.2, 1.6) + rr(18, 34, 9, 3.2, 1.6)
# pencil along the 45 degree diagonal: eraser at the top right, tip at the bottom left
_PC = (36.5, 25.5)                                  # pencil centre
_PL, _PW = 38.0, 7.0                                # length, width


def _pencil_part(t0, t1, w0=None, w1=None):
    """Part of the pencil between t0 and t1 (0 = eraser end, 1 = tip), with end widths w0/w1."""
    w0 = _PW if w0 is None else w0; w1 = _PW if w1 is None else w1
    loc = [(-_PL / 2 + _PL * t0, -w0 / 2), (-_PL / 2 + _PL * t1, -w1 / 2),
           (-_PL / 2 + _PL * t1, w1 / 2), (-_PL / 2 + _PL * t0, w0 / 2)]
    return [(_PC[0] + x * math.cos(math.radians(135)) - y * math.sin(math.radians(135)),
             _PC[1] + x * math.sin(math.radians(135)) + y * math.cos(math.radians(135))) for x, y in loc]


_TE_ERASER = poly(*_pencil_part(0.0, 0.13))
_TE_BODY = poly(*_pencil_part(0.13, 0.78))
_TE_CONE = poly(*_pencil_part(0.78, 1.0, _PW, 0.01))
_TE_LEAD = poly(*_pencil_part(0.92, 1.0, _PW * 0.36, 0.01))
_TE_OUTLINE = poly(*_pencil_part(0.0, 1.0, _PW, 0.01))

# ---- GNOME Tour: the striped hot-air balloon ---------------------------------------------------
_BAL = 'M15 23A17 14 0 0 1 49 23C49 29.5 43.5 34 40 38.5H24C20.5 34 15 29.5 15 23z'
_BAL_STRIPES = ('M32 9C22.5 11.5 19.5 27 26.5 38.5H30.2C26.2 28 27 14 32 9z'
                'M32 9C41.5 11.5 44.5 27 37.5 38.5H33.8C37.8 28 37 14 32 9z')
_BAL_RING = rr(23.5, 37.5, 17, 3.2, 1.6)
_BAL_ROPES = 'M26 40.5 28.5 44.5M38 40.5 35.5 44.5'
_BAL_BASKET = rr(26.5, 43.5, 11, 7, 2)

# ---- GNOME Weather: sun with the eight-point ray star, cloud in front --------------------------
_WE_STAR = star8(28, 26, 17)
_WE_SUN = ci(28, 26, 12.3)
_WE_CLOUD = rr(27, 40.5, 26, 9.5, 4.75) + ci_cw(35, 40.5, 5.4) + ci_cw(44, 37.5, 7.4)

# ---- Decibels: the rounded play triangle with a waveform ---------------------------------------
_DB_TRI = poly(*round_pts([(16, 7.5), (58, 30), (16, 52.5)], 6.5))     # shifted right: optical centre

# ---- Sound Recorder: the recorder with its waveform display and the red record button ---------
_SR_BODY = rr(10.5, 11.5, 43, 37.5, 5.5)
_SR_SCREEN = rr(14, 15, 36, 13, 2.8)
_SR_WAVE = ''.join(bar(x, 21.5, h, 2.6) for x, h in
                   ((18.5, 3), (22, 5.5), (25.5, 3.5), (29, 7.5), (32.5, 5), (36, 8.5), (39.5, 4.5), (43, 3)))
_SR_REC = rr(14, 31.5, 17.5, 14, 2.8)
_SR_PLAY = poly(*round_pts([(35, 33.5), (41.5, 38.5), (35, 43.5)], 0.8)) + rr(43, 33.5, 2.8, 10, 1) + rr(47, 33.5, 2.8, 10, 1)

# ---- Color Profile Viewer: the eight-petal colour flower ---------------------------------------
_CP_COLOURS = {180: '#e5484d', 225: '#f2a65a', 270: '#f7c948', 315: '#9ccc4a',
               0: '#3aa65b', 45: '#5bb8f0', 90: '#3f7fe0', 135: '#8d5ad6'}
_CP = {a: petal(32, 30, a, 17.5, 5.2, gap=0.55) for a in _CP_COLOURS}
# the white sticker outline of the Adwaita icon: the same petals, longer and wider, without seams
_CP_OUTLINE = ''.join(petal(32, 30, a, 20.1, 7.5, gap=0.0) for a in _CP_COLOURS)


TILES = {
    'gnome-software': dict(label='Software', base='#f4f5f9', lip='#d5d9e3',
                           s1=_BAG_HANDLE, sc='#bfc5d1', sw=3.4,
                           g1=_BAG, c1='#d2d7e1',
                           g3=rr(15.5, 28, 14, 14, 4), c3='#e5484d',
                           x=[(ci(39, 27.8, 7), '#7b5cd6'), (_SW_TRI, '#3cc4b0')]),
    'gnome-system-monitor': dict(label='System Monitor', base='#f4f5f9', lip='#d5d9e3',
                                 g1=_SM_SCREEN, c1='#262a3d',
                                 s1=_SM_PULSE, sc='#f7c948', sw=3,
                                 g3=''.join(ci(50.5, y, 1.9) for y in (15.5, 22, 28.5, 35)), c3='#b9bfcc',
                                 x=[(ci(38, 29.5, 2.3), '#fff1c9')]),
    # amber, not blue (round-3 review): on blue the white page with a diagonal pencil was a twin of
    # Calligra Words (same base, same silhouette) and close to LibreOffice Writer; green and teal sit on
    # Marknote, slate on KWrite. The blue title band now carries the Adwaita blue.
    'gnome-text-editor': dict(label='Text Editor', base='#b7792f', lip='#8a5a20',
                              g1=_TE_PAGE, c1='#ffffff',
                              g2=_TE_BAND, c2='#5b9dff',
                              s1=_TE_OUTLINE, sc='#b7792f', sw=2,
                              g3=_TE_BODY, c3='#f2a65a',
                              x=[(_TE_LINES, '#e6d3b8'), (_TE_CURL, '#e6d3b8'), (_TE_ERASER, '#e5484d'),
                                 (_TE_CONE, '#fbe7c6'), (_TE_LEAD, '#1b2031')]),
    'gnome-tour': dict(label='Tour', base='#3a7bd5', lip='#2a5ea8',
                       g1=_BAL, c1='#e5484d',
                       g2=_BAL_STRIPES, c2='#ffffff',
                       s1=_BAL_ROPES, sc='#ffffff', sw=2.4,
                       g3=_BAL_RING, c3='#ffffff',
                       x=[(_BAL_BASKET, '#f2a65a')]),
    'gnome-weather': dict(label='Weather', base='#e8743b', lip='#b8552a',
                          g1=_WE_STAR, c1='#f7c948',
                          g2=_WE_SUN, c2='#ffe9a8',
                          s1=_WE_CLOUD, sc='#e8743b', sw=3.4,
                          x=[(_WE_CLOUD, '#ffffff')]),
    'gnome-decibels': dict(label='Audio Player', base='#7b5cd6', lip='#5a40a8',
                           g1=_DB_TRI, c1='#ffffff',
                           g3=ci(22.5, 30, 2) + bar(27.3, 30, 10), c3='#e5484d',
                           x=[(bar(32.3, 30, 23), '#d6457a'),
                              (bar(37.3, 30, 14) + ci(42, 30, 2) + ci(46.1, 30, 2), '#7b5cd6')]),
    'gnome-sound-recorder': dict(label='Sound Recorder', base='#c93a42', lip='#992a31',
                                 g1=_SR_BODY, c1='#ffffff',
                                 g2=_SR_SCREEN, c2='#1b2031',
                                 g3=_SR_WAVE, c3='#3cc4b0',
                                 x=[(_SR_REC, '#e5484d'), (ci(22.75, 38.5, 4.3), '#ffffff'), (_SR_PLAY, '#1b2031')]),
    # slate with the original's white outline (round-3 review): the bare rainbow flower on ink was a twin
    # of darktable's rainbow aperture on ink at 32 px.
    'gnome-color-profile-viewer': dict(label='Color Profile Viewer', base='#5b6478', lip='#414859',
                                       g1=_CP_OUTLINE, c1='#ffffff',
                                       x=[(_CP[a], c) for a, c in _CP_COLOURS.items()]),
}

APPS = {
    'org.gnome.Software': 'gnome-software',
    'org.gnome.SystemMonitor': 'gnome-system-monitor',
    'org.gnome.TextEditor': 'gnome-text-editor',
    'org.gnome.Tour': 'gnome-tour',
    'org.gnome.Weather': 'gnome-weather',
    'org.gnome.Decibels': 'gnome-decibels',
    'org.gnome.SoundRecorder': 'gnome-sound-recorder',
    'org.gnome.ColorProfileViewer': 'gnome-color-profile-viewer',
}
