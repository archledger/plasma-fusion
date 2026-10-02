# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles: development batch (build/kdeicons; not shipped).
import math
import re

from apptiles.kit import *  # noqa: F401,F403  helpers and palette; the batch runs with build/kdeicons on sys.path


# ---- local path helpers -------------------------------------------------------------------------
def _p(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def capsule(x1, y1, x2, y2, r):
    """A stroke-like bar with round ends from (x1, y1) to (x2, y2), as a fill path."""
    L = math.hypot(x2 - x1, y2 - y1)
    dx, dy = (x2 - x1) / L, (y2 - y1) / L
    nx, ny = dy * r, -dx * r
    return (f"M{_p(x1 + nx)} {_p(y1 + ny)}L{_p(x2 + nx)} {_p(y2 + ny)}"
            f"A{_p(r)} {_p(r)} 0 0 1 {_p(x2 - nx)} {_p(y2 - ny)}L{_p(x1 - nx)} {_p(y1 - ny)}"
            f"A{_p(r)} {_p(r)} 0 0 1 {_p(x1 + nx)} {_p(y1 + ny)}z")


def arcband(cx, cy, ro, ri, a0, a1):
    """Annulus segment from angle a0 clockwise to a1 (degrees, screen coordinates)."""
    span = (a1 - a0) % 360
    big = 1 if span > 180 else 0
    def pt(r, a):
        return _p(cx + r * math.cos(math.radians(a))), _p(cy + r * math.sin(math.radians(a)))
    o0, o1, i1, i0 = pt(ro, a0), pt(ro, a1), pt(ri, a1), pt(ri, a0)
    return (f"M{o0[0]} {o0[1]}A{_p(ro)} {_p(ro)} 0 {big} 1 {o1[0]} {o1[1]}L{i1[0]} {i1[1]}"
            f"A{_p(ri)} {_p(ri)} 0 {big} 0 {i0[0]} {i0[1]}z")


def ring_nz(cx, cy, ro, ri):
    """Annulus that also works under the nonzero rule (inner circle drawn the other way)."""
    return (ci(cx, cy, ro) + f"M{_p(cx - ri)} {_p(cy)}a{_p(ri)} {_p(ri)} 0 1 1 {_p(2 * ri)} 0"
            f"a{_p(ri)} {_p(ri)} 0 1 1 {_p(-2 * ri)} 0z")


def rpoly(pts, r):
    """Closed polygon with every corner rounded by r (quadratic corners)."""
    n = len(pts)
    out = []
    for i in range(n):
        px, py = pts[i - 1]
        x, y = pts[i]
        qx, qy = pts[(i + 1) % n]
        la, lb = math.hypot(px - x, py - y), math.hypot(qx - x, qy - y)
        ra, rb = min(r, la / 2), min(r, lb / 2)
        a = (x + (px - x) * ra / la, y + (py - y) * ra / la)
        b = (x + (qx - x) * rb / lb, y + (qy - y) * rb / lb)
        out.append(("M" if i == 0 else "L") + f"{_p(a[0])} {_p(a[1])}Q{_p(x)} {_p(y)} {_p(b[0])} {_p(b[1])}")
    return "".join(out) + "z"


def clip(subject, clipper):
    """Clip a convex polygon to a convex, clockwise (screen) polygon; both as lists of (x, y)."""
    def inside(p, a, b):
        return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0
    def cross(p, q, a, b):
        x1, y1, x2, y2, x3, y3, x4, y4 = *p, *q, *a, *b
        d = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / d
        return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))
    out = list(subject)
    for i in range(len(clipper)):
        a, b = clipper[i], clipper[(i + 1) % len(clipper)]
        inp, out = out, []
        for j in range(len(inp)):
            p, q = inp[j - 1], inp[j]
            if inside(q, a, b):
                if not inside(p, a, b):
                    out.append(cross(p, q, a, b))
                out.append(q)
            elif inside(p, a, b):
                out.append(cross(p, q, a, b))
    return out


def mirror(d, axis=32):
    """Mirror a path written with absolute M/L/C/Q/Z commands about the vertical line x = axis."""
    out = []
    for cmd, args in re.findall(r"([MLCQZ])([^MLCQZ]*)", d):
        nums = [float(v) for v in re.findall(r"-?\d+\.?\d*", args)]
        pairs = [f"{_p(2 * axis - nums[k])} {_p(nums[k + 1])}" for k in range(0, len(nums), 2)]
        out.append(cmd + " ".join(pairs))
    return "".join(out)


# ---- shared pieces --------------------------------------------------------------------------------
# Heaptrack: left half of the flame (absolute commands so it can be mirrored).
_HT_OUT = ("M32 50C24.5 50 17.5 45 17.5 37.5C17.5 31 21.5 27 20.5 19.5C24.5 22.5 26.5 26.5 26 31"
           "C27.5 26 26.5 19 32 10Z")
_HT_IN = ("M32 47C27.5 47 23.5 44 23.5 39.5C23.5 35.5 26 33.5 26.5 29.5C29 32.5 30.5 35.5 29.5 38.5"
          "C31.5 35 31 31 32 26.5Z")


def _hand(o):
    """KImageMapEditor's pointing hand, grown by o (o > 0 gives the halo)."""
    return [rr(29.5 - o, 21 - o, 5 + 2 * o, 17 + 2 * o, 2.5 + o),
            rr(26 - o, 31.5 - o, 14.5 + 2 * o, 15.5 + 2 * o, 5 + o),
            capsule(26.5, 38, 22.8, 33.8, 2.5 + o)]


_HALO = '#2a5ea8'

_KM_DIAMOND = [(32, 10.5), (51.5, 30), (32, 49.5), (12.5, 30)]
_KM_K = [[(24.5, 0), (29.5, 0), (29.5, 64), (24.5, 64)],                 # stem
         [(29.5, 28), (60, -2.5), (60, 4), (29.5, 34.5)],                 # upper arm
         [(33.75, 30.25), (37, 27), (65, 55), (61.75, 58.25)]]            # lower leg

TILES = {
    # { } braces in ink with the blue arrow that dives in between (as on the original).
    'accessibilityinspector': dict(
        label='Accessibility Inspector', base='#f4f5f9', lip='#d5d9e3',
        s1='M21 20.5c-3 0-5 1.5-5 4.5v4.5c0 3-1.8 5-4 5 2.2 0 4 2 4 5v4.5c0 3 2 4.5 5 4.5'
           'M43 20.5c3 0 5 1.5 5 4.5v4.5c0 3 1.8 5 4 5-2.2 0-4 2-4 5v4.5c0 3-2 4.5-5 4.5',
        sc='#1b2031', sw=4,
        g3=arcband(30, 19, 10, 6, 180, 360) + rr(20, 18, 4, 7.5, 2) + poly((32.6, 18.5), (43.4, 18.5), (38, 28.5)),
        c3='#2b8be6'),
    # The red brick wall.
    'cervisia': dict(
        label='Cervisia', base='#c93a42', lip='#992a31',
        g1=rr(12, 12.5, 18.75, 10, 2) + rr(33.25, 12.5, 18.75, 10, 2)
           + rr(12, 25, 8.1, 10, 2) + rr(22.6, 25, 18.75, 10, 2) + rr(43.9, 25, 8.1, 10, 2)
           + rr(12, 37.5, 18.75, 10, 2) + rr(33.25, 37.5, 18.75, 10, 2),
        c1='#ffffff'),
    # The ":// " mark on a dark tile.
    'fielding': dict(
        label='Fielding', base='#2c3348', lip='#1a1f2e',
        g1=ci(16.5, 24.5, 3.3) + ci(16.5, 38, 3.3)
           + poly((25.5, 46), (31.3, 46), (41, 14), (35.2, 14)) + poly((37, 46), (42.8, 46), (52.5, 14), (46.7, 14)),
        c1='#ffffff'),
    # Flame (flame graph) split by the vertical line: vivid on the left, pale on the right.
    'heaptrack': dict(
        label='Heaptrack', base='#262c42', lip='#131726',
        g1=_HT_OUT, c1='#f2a65a',
        g2=mirror(_HT_OUT), c2='#a3abc2',
        s1='M32 10.7V49.3', sc='#e5484d', sw=2.4,
        g3=_HT_IN, c3='#e5484d'),
    # Cuttlefish: yellow body, purple spots on the head, lavender eyes.
    'iconexplorer': dict(
        label='Icon Explorer', base='#7b5cd6', lip='#5a40a8',
        g1=el(32, 23, 15.5, 13) + 'M18.5 26H45.5L46.5 38C47 42 49.5 44.5 51.5 46.5C47.5 47.5 44 46.5 42 44.5'
           'C41 47.5 38.5 49.5 35.5 49C34 47 33 46 32 46C31 46 30 47 28.5 49C25.5 49.5 23 47.5 22 44.5'
           'C20 46.5 16.5 47.5 12.5 46.5C14.5 44.5 17 42 17.5 38Z',
        c1='#f7c948',
        g2=ci(15.5, 30, 5) + ci(48.5, 30, 5), c2='#d9ccff',
        s1='M13 30.5c1.6-1.2 3.4-1.2 5 0M46 30.5c1.6-1.2 3.4-1.2 5 0', sc='#5a40a8', sw=2.4,
        g3=ci(27, 16, 3) + ci(34.5, 14.5, 2.6) + ci(31, 21.5, 3.2) + ci(38.5, 20.5, 2.6) + ci(24, 22.5, 2.3),
        c3='#7b5cd6'),
    # Gear with a crossed screwdriver (yellow handle) and wrench.
    'kapptemplate': dict(
        label='KAppTemplate', base='#e8743b', lip='#b8552a',
        g1=gear(32, 30, 17.5, 13, 8), c1='#ffffff',
        g2=ci(32, 30, 5.5), c2='#e8743b',
        x=[(capsule(19, 43, 37.5, 24.5, 2.4), '#1b2031'),
           (arcband(42, 20, 6.6, 3, -10, 280), '#1b2031'),
           (capsule(21, 19, 44, 42, 1.8), '#1b2031'),
           (capsule(15, 13, 21.5, 19.5, 3.9), '#f7c948')]),
    # Gear with the dark clock face and the blue cost wedge.
    'kcachegrind': dict(
        label='KCachegrind', base='#3b4255', lip='#262b38',
        g1=gear(32, 30, 18.5, 14, 10), c1='#ffffff',
        g2=ci(32, 30, 11.2), c2='#1b2031',
        g3='M32 30L32 20.6A9.4 9.4 0 0 1 38.65 36.65z', c3='#5b9dff',
        x=[(ci(32, 30, 1.8), '#ffffff')]),
    # The revision graph: one trunk node branching into three.
    'kdesvn': dict(
        label='kdesvn', base='#3f7fe0', lip='#2b5db5',
        s1='M15 30H40.5M27.5 30L37 17.5M27.5 30L36 42H49', sc='#ffffff', sw=3,
        g3=ci(15, 30, 4.6) + ci(27.5, 30, 4.6) + ci(40.5, 30, 4.6) + ci(37, 17.5, 4.6) + ci(36, 42, 4.6) + ci(49, 42, 4.6),
        c3='#ffffff',
        x=[(ci(15, 30, 2) + ci(27.5, 30, 2) + ci(40.5, 30, 2) + ci(37, 17.5, 2) + ci(36, 42, 2) + ci(49, 42, 2), '#2b5db5')]),
    # Gear with the green dial and its pointer.
    'kdevelop': dict(
        label='KDevelop', base='#3aa65b', lip='#2a7e44',
        g1=gear(32, 30, 18.5, 14, 10), c1='#ffffff',
        g2=ci(32, 30, 11), c2='#2a7e44',
        g3=ci(32, 30, 8), c3='#bfe8c9',
        x=[(poly((24.6, 37.4), (27, 29.2), (32.8, 35)), '#2a7e44')]),
    # Window with the two pane headers and the two merge arrows (green right, blue left).
    'kdiff3': dict(
        label='KDiff3', base='#5b6478', lip='#414859',
        g1=rr(11, 11, 42, 37, 4.5), c1='#ffffff',
        g3=rr(33.5, 15, 15.5, 4, 2) + rr(14.5, 25.5, 15, 5.5, 1.5) + poly((27, 21.5), (36, 28.25), (27, 35)),
        c3='#3cc4b0',
        x=[(rr(15, 15, 15.5, 4, 2), '#5b9dff'),
           (rr(34.5, 37, 15, 5.5, 1.5) + poly((37, 33), (28, 39.75), (37, 46.5)), '#5b9dff')]),
    # Three thick plates with the chamfered (dark) seams and the diagonal shadow of the original.
    'kexi': dict(
        label='Kexi', base='#2f9e6e', lip='#227650',
        g1=rr(12, 11, 40, 10.2, 2.5) + 'M' + poly((12, 24.5), (52, 24.5), (52, 34.5), (12, 34.5))[1:]
           + 'M' + rpoly([(12, 38), (52, 38), (52, 48), (12, 48)], 2.5)[1:],
        c1='#ffffff',
        g2=poly((12, 21), (52, 21), (48, 24.5), (16, 24.5)) + 'M' + poly((16, 34.5), (48, 34.5), (52, 38), (12, 38))[1:],
        c2='#1d7350',
        g3=poly((12, 24.5), (27, 34.5), (12, 34.5)) + 'M' + rpoly([(12, 38), (27, 48), (12, 48)], 2.5)[1:],
        c3='#9ad8bb'),
    # Globe with the yellow < > tag brackets and the pointing hand.
    'kimagemapeditor': dict(
        label='KImageMapEditor', base='#3a7bd5', lip='#2a5ea8',
        g1=ci(32, 30, 17), c1=_HALO,
        g2='M36 16C41 15 46 18.5 45.5 23C45 27 47.5 30.5 45.5 35C43.5 40 39 41 38 37C37 33.5 34 31.5 35 27.5'
           'C36 24.5 32.5 19.5 36 16Z'
           'M17.5 25C20.5 22 26 23 26 27.5C26 31.5 22 32.5 20 36C17.5 33.5 15.5 29 17.5 25Z',
        c2='#bcd4ff',
        s1='M22 14.5l-6.5 6 6.5 6M42 14.5l6.5 6-6.5 6', sc='#f7c948', sw=3.4,
        x=[(p, _HALO) for p in _hand(1.8)] + [(p, '#ffffff') for p in _hand(0)]),
    # The folded paper K, light upper facets and tinted lower facets.
    'kirigami-gallery': dict(
        # review: base moved off teal; the white K on teal sat too close to KBibTeX's white K on green
        label='Kirigami Gallery', base='#5a2ca0', lip='#3e1e70',
        g1=poly((16, 12), (27.5, 12), (23.5, 30), (27.5, 48), (16, 48)) + 'M'
           + poly((36.5, 12), (48.5, 12), (36.5, 30), (48.5, 48), (36.5, 48), (27, 30))[1:],
        c1='#ffffff',
        g2=poly((16, 30), (23.5, 30), (27.5, 48), (16, 48)) + 'M' + poly((27, 30), (36.5, 30), (48.5, 48), (36.5, 48))[1:],
        c2='#d9ccff'),
    # The diamond cut by the K (Git-like mark).
    'kommit': dict(
        label='Kommit', base='#e8553a', lip='#b03f2a',
        g2=rpoly(_KM_DIAMOND, 3.5) + ''.join('M' + poly(*clip(k, _KM_DIAMOND))[1:] for k in _KM_K),
        c2='#ffffff'),
    # Two overlapping text sheets: the old one behind, the new one in front.
    'kompare': dict(
        # review: teal base; on blue it sat with KWrite, LibreOffice Writer and Calligra Words as a fourth
        # white-page-on-blue tile, and on green next to LibreOffice Calc and Marknote
        label='Kompare', base='#1aa391', lip='#127a6c',
        g1='M27.5 10H47.5A3.5 3.5 0 0 1 51 13.5V38.5A3.5 3.5 0 0 1 47.5 42H42.5V21A5.5 5.5 0 0 0 37 15.5H24V13.5'
           'A3.5 3.5 0 0 1 27.5 10z',
        c1='#ffffff',
        s1='M29 13.5h17M45.5 21h1M45.5 27.5h1M45.5 34h1', sc='#1aa391', sw=3,
        g3=rr(13, 18, 27, 32, 3.5), c3='#ffffff',
        x=[(rr(17, 24.5, 19, 4, 2) + rr(17, 31, 13, 4, 2) + rr(17, 37.5, 19, 4, 2), '#2f6fdf')]),
    # Two meshed gears: the yellow one and the grey one.
    'kuiviewer': dict(
        label='KUIViewer', base='#475069', lip='#323950',
        g2=gear(23.5, 38, 11.5, 8.5, 7) + 'M' + ci(23.5, 38, 3.6)[1:], c2='#cfd5e4',
        g3=gear(38, 23.5, 14, 10.5, 8) + 'M' + ci(38, 23.5, 4.4)[1:], c3='#f7c948'),
    # Magnifier over usage bars (analytics of user feedback).
    'kuserfeedback-console': dict(
        label='KUserFeedback Console', base='#d6457a', lip='#a8325d',
        g1=capsule(37.5, 35.5, 47.5, 45.5, 3.4), c1='#ffffff',
        g2=ring(28, 26, 14, 10.4), c2='#ffffff',
        g3=rr(21.2, 26.5, 3.8, 6.5, 1.2) + rr(30.8, 23.5, 3.8, 9.5, 1.2), c3='#ffffff',
        x=[(rr(26, 19.5, 3.8, 13.5, 1.2), '#f7c948')]),
    # Flag pole with the source card (A) and the translated card.
    'lokalize': dict(
        label='Lokalize', base='#b7792f', lip='#8a5a20',
        g1=rr(15.5, 11, 23, 22, 3) + rr(11.5, 9, 3.4, 41, 1.7), c1='#fbe7c6',
        g2=rr(30.5, 25, 22, 22, 3), c2='#ffffff',
        s1='M20 28.5L25.5 15.5L31 28.5M22.2 23.5h6.6'
           'M41.5 28.5v2M35 32h13M37.5 32c2 6.5 5.5 9.5 10 11M46 32c-2 6.5-5.5 9.5-10 11',
        sc='#8a5a20', sw=2.6,
        x=[(rr(11.5, 9, 3.4, 41, 1.7), '#ffffff')]),
    # Axes with the two stacked memory areas (blue behind, pink in front).
    'massif-visualizer': dict(
        label='Massif-Visualizer', base='#9b3fb5', lip='#742d88',
        g1='M14 47V35L23 30L32 33L48 13V47Z', c1='#5b9dff',
        g2='M14 47V39L26 26L35 37L48 30V47Z', c2='#f3d4fb',
        s1='M14 11V47.5H51', sc='#ffffff', sw=3.2),
    # Red stick figure (actor) linked to the yellow use case ellipse.
    'umbrello': dict(
        label='Umbrello', base='#f4f5f9', lip='#d5d9e3',
        g1=ci(21.5, 17.5, 6.4) + el(41.5, 42, 11, 7), c1='#e5484d',
        s1='M21.5 23.5v11.5M14.5 28h14M21.5 35l-6 9.5M21.5 35l6 9.5M26.5 22L37 36', sc='#e5484d', sw=3.2,
        g3=ci(21.5, 17.5, 3.8) + el(41.5, 42, 8.2, 4.4), c3='#f7c948'),
}

APPS = {
    'org.kde.accessibilityinspector': 'accessibilityinspector',
    'org.kde.cervisia': 'cervisia',
    'org.kde.fielding': 'fielding',
    'org.kde.heaptrack': 'heaptrack',
    'org.kde.plasma.iconexplorer': 'iconexplorer',
    'org.kde.kapptemplate': 'kapptemplate',
    'org.kde.kate': 'round1:kate',
    'org.kde.kcachegrind': 'kcachegrind',
    'org.kde.kdesvn': 'kdesvn',
    'org.kde.kdevelop': 'kdevelop',
    'org.kde.kdiff3': 'kdiff3',
    'org.kde.kexi': 'kexi',
    'org.kde.kimagemapeditor': 'kimagemapeditor',
    'org.kde.kirigami2.gallery': 'kirigami-gallery',
    'org.kde.kommit': 'kommit',
    'org.kde.kompare': 'kompare',
    'org.kde.kuiviewer': 'kuiviewer',
    'org.kde.kuserfeedback-console': 'kuserfeedback-console',
    'org.kde.lokalize': 'lokalize',
    'org.kde.massif_visualizer': 'massif-visualizer',
    'org.kde.umbrello': 'umbrello',
}
