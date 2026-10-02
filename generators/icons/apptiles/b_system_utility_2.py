# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles: batch system-utility-2 (KDE system tools and small utilities).
import math

from apptiles.kit import *  # noqa: F401,F403  rr, ci, el, gear, ring, poly, PALETTE


# ---- local path helpers (they only build path strings) -------------------------------------
def _pt(p):
    return f"{f(p[0])} {f(p[1])}"


def bar(x1, y1, x2, y2, w):
    """Filled rectangle of width w along the segment (x1, y1)-(x2, y2), butt ends."""
    dx, dy = x2 - x1, y2 - y1
    n = math.hypot(dx, dy)
    nx, ny = -dy / n * w / 2, dx / n * w / 2
    return poly((x1 + nx, y1 + ny), (x2 + nx, y2 + ny), (x2 - nx, y2 - ny), (x1 - nx, y1 - ny))


def along(p0, p1, t, off=0.0):
    """Point at fraction t of p0->p1, shifted off units to the left of the direction."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    n = math.hypot(dx, dy)
    return (p0[0] + dx * t - dy / n * off, p0[1] + dy * t + dx / n * off)


def seg_arc(cx, cy, r, a0, a1):
    """Open arc path (for strokes), angles in degrees, 0 = up, clockwise."""
    def p(a):
        a = math.radians(a)
        return (cx + r * math.sin(a), cy - r * math.cos(a))
    return f"M{_pt(p(a0))}A{f(r)} {f(r)} 0 0 1 {_pt(p(a1))}"


def pencil(tail, tip, w, tipl):
    """Pencil body (rectangle) and its sharpened tip (triangle), as two paths."""
    dx, dy = tip[0] - tail[0], tip[1] - tail[1]
    n = math.hypot(dx, dy)
    ux, uy = dx / n, dy / n
    sx, sy = tip[0] - ux * tipl, tip[1] - uy * tipl
    body = bar(tail[0], tail[1], sx, sy, w)
    nx, ny = -uy * w / 2, ux * w / 2
    point = poly((sx + nx, sy + ny), tip, (sx - nx, sy - ny))
    return body, point


# Sweeper: three arrows chasing round a triangle, each bent over one corner.
def _recycle(cx, cy, R, gap=0.07):
    V = [(cx + R * math.sin(math.radians(a)), cy - R * math.cos(math.radians(a))) for a in (0, 120, 240)]
    lines, heads = [], []
    for i in range(3):
        a, b, c = V[i], V[(i + 1) % 3], V[(i + 2) % 3]
        s = along(a, b, 0.5 + gap)
        h0 = along(b, c, 0.27)
        lines.append(f"M{_pt(s)}L{_pt(b)}L{_pt(h0)}")
        tip = along(b, c, 0.5 - gap / 2)
        heads.append(poly(along(b, c, 0.25, 6), tip, along(b, c, 0.25, -6)))
    return "".join(lines), "".join(heads)


_rc_lines, _rc_heads = _recycle(32, 32.5, 17, gap=0.1)


# Kronometer: segmented ring like the stopwatch's digital face (filled blocks, three left dark).
def sector(cx, cy, ri, ro, a0, a1):
    def p(a, r):
        a = math.radians(a)
        return (cx + r * math.sin(a), cy - r * math.cos(a))
    return (f"M{_pt(p(a0, ro))}A{f(ro)} {f(ro)} 0 0 1 {_pt(p(a1, ro))}L{_pt(p(a1, ri))}"
            f"A{f(ri)} {f(ri)} 0 0 0 {_pt(p(a0, ri))}z")


_kron_lit = "".join(sector(32, 31, 6.6, 10.8, a + 4, a + 26) for a in range(0, 270, 30))


# KMag: a lens showing a slice of the Breeze wallpaper (two tones split on the diagonal).
def _half_disc(cx, cy, r, ang):
    a0, a1 = math.radians(ang), math.radians(ang + 180)
    p0 = (cx + r * math.cos(a0), cy + r * math.sin(a0))
    p1 = (cx + r * math.cos(a1), cy + r * math.sin(a1))
    return f"M{_pt(p0)}A{f(r)} {f(r)} 0 0 1 {_pt(p1)}z"


# Plasma logo (Welcome Center), from breeze start-here-kde-plasma, scaled into the safe area.
def _plasma(x, y):
    return (32 + (x - 48) * 0.5, 29.5 + (y - 47.5) * 0.5)


_pl_chev = poly(_plasma(61, 8), _plasma(52, 17), _plasma(69, 34), _plasma(52, 51), _plasma(61, 60), _plasma(87, 34))

# Syringe for Vakzination, along a 45 degree axis.
_SYR0, _SYR1 = (50, 12.3), (27.5, 34.8)


def _syr(t0, t1, w):
    a, b = along(_SYR0, _SYR1, t0), along(_SYR0, _SYR1, t1)
    return bar(a[0], a[1], b[0], b[1], w)


_syr_len = math.hypot(_SYR1[0] - _SYR0[0], _SYR1[1] - _SYR0[1])
_syr_white = (_syr(0, 2.6 / _syr_len, 9) + _syr(2.6 / _syr_len, 7 / _syr_len, 3.4)
              + _syr(7 / _syr_len, 9.4 / _syr_len, 12) + _syr(9.4 / _syr_len, 24 / _syr_len, 8.4)
              + _syr(24 / _syr_len, 26.5 / _syr_len, 4) + _syr(26.5 / _syr_len, 1, 2.4))


# The syringe's separating outline is base-coloured; above y 28 the tile carries the 9 % white
# sheen, so that part is painted in the sheen-blended base colour to stay invisible off the card.
def _bar_pts(p0, p1, w):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    n = math.hypot(dx, dy)
    nx, ny = -dy / n * w / 2, dx / n * w / 2
    return [(p0[0] + nx, p0[1] + ny), (p1[0] + nx, p1[1] + ny), (p1[0] - nx, p1[1] - ny), (p0[0] - nx, p0[1] - ny)]


def _clip_y(pts, y, below):
    """Sutherland-Hodgman clip of a polygon to y' >= y (below=True) or y' <= y."""
    inside = (lambda p: p[1] >= y) if below else (lambda p: p[1] <= y)
    out = []
    for i, cur in enumerate(pts):
        prev = pts[i - 1]
        if inside(cur) != inside(prev):
            t = (y - prev[1]) / (cur[1] - prev[1])
            out.append((prev[0] + (cur[0] - prev[0]) * t, y))
        if inside(cur):
            out.append(cur)
    return out


def _sheen(hexcol):
    c = [int(hexcol[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join("%02x" % round(v * 0.91 + 255 * 0.09) for v in c)


_syr_gap_parts = [_bar_pts(along(_SYR0, _SYR1, a / _syr_len), along(_SYR0, _SYR1, b / _syr_len), w)
                  for a, b, w in ((0, 2.6, 12.5), (2.6, 9.4, 15.5), (9.4, 24, 12), (24, _syr_len, 7))]
_syr_gap_low = "".join(poly(*q) for q in (_clip_y(g, 28, True) for g in _syr_gap_parts) if len(q) > 2)
_syr_gap_high = "".join(poly(*q) for q in (_clip_y(g, 28, False) for g in _syr_gap_parts) if len(q) > 2)
_syr_liquid = _syr(15 / _syr_len, 23 / _syr_len, 4.4)

_kj_pen, _kj_nib = pencil((50.5, 11), (31, 33.5), 6, 7)
_kn_pen, _kn_tip = pencil((45, 15), (27, 33), 5.6, 6)
_me_pen, _me_tip = pencil((51.5, 18.5), (37, 44.5), 5.6, 6)

TILES = {
    # Note book with a fountain pen (KJots: the yellow book with a black spine and a pen).
    'kjots': dict(label='KJots', base='#e8743b', lip='#b8552a',
                  g1=rr(20, 13, 26, 36, 3), c1='#ffffff',
                  g2='M20 11h21a3 3 0 0 1 3 3v30a3 3 0 0 1-3 3H20z', c2='#f7c948',
                  g3=rr(14, 11, 10, 38, 3) + _kj_pen, c3='#1b2031',
                  x=[(_kj_nib, '#ffffff')]),
    # Eye of Horus (Breeze Kleopatra) in white on the gold of its stone tablet.
    'kleopatra': dict(label='Kleopatra', base='#b7792f', lip='#8a5a20',
                      g1='M13 19.5c9-6 23-7.5 37-5l-.6 4c-12.5-2-25-1-34.4 4.3z'
                         + 'M15 29C21 20.5 37 18.5 44 28 37 35.5 22 36 15 29z', c1='#ffffff',
                      s1='M44 28h8M25.5 34.5l-.8 9M33.5 34.5c1.5 5 5.5 9.5 10.5 9.5 3 0 4.5-2.4 3.4-4.4-1.1-2-4-1.8-4.5.2',
                      sc='#ffffff', sw=3,
                      g3=ci(30, 27.5, 5), c3='#1b2031',
                      x=[(ci(24.7, 45, 2.6), '#ffffff')]),
    # Magnifier whose lens shows the Breeze wallpaper slice of the KMag screen.
    'kmag': dict(label='KMag', base='#5a2ca0', lip='#3e1e70',
                 g1=_half_disc(28, 26, 10, 135), c1='#3cc4b0',
                 g2=_half_disc(28, 26, 10, -45), c2='#f3b8d8',
                 s1='M37.5 35.5 47 45', sc='#ffffff', sw=6.5,
                 g3=ring(28, 26, 14, 10), c3='#ffffff'),
    # Green speech bubble with a speaker (KMouth).
    'kmouth': dict(label='KMouth', base='#3aa65b', lip='#2a7e44',
                   g1='M15 11h34a4 4 0 0 1 4 4v24a4 4 0 0 1-4 4h-7l1.5 7-9-7H15a4 4 0 0 1-4-4V15a4 4 0 0 1 4-4z',
                   c1='#ffffff',
                   s1='M36.5 22a7 7 0 0 1 0 10M41 18.5a12.5 12.5 0 0 1 0 17', sc='#3aa65b', sw=2.8,
                   g3='M19 23h5l8-6.5v23l-8-6.5h-5z', c3='#3aa65b'),
    # Yellow sticky note with a curled corner and a pencil (KNotes).
    'knotes': dict(label='KNotes', base='#f5c84c', lip='#c99a22',
                   g1='M17 11h30a3 3 0 0 1 3 3v31a3 3 0 0 1-3 3H25l-11-11V14a3 3 0 0 1 3-3z', c1='#fffaf0',
                   g2='M14 37h8a3 3 0 0 1 3 3v8z', c2='#e9c76a',
                   s1='M30 41h14', sc='#e9c76a', sw=2.6,
                   g3=_kn_pen, c3='#f2a65a',
                   x=[(_kn_tip, '#1b2031')]),
    # Krename: A turns into B (red A, ink arrow, blue B), on paper like the Breeze icon.
    'krename': dict(label='Krename', base='#f6f4ef', lip='#d6d0c2',
                    s1='M14 34l7.5-21 7.5 21M17 27.5h9', sc='#e5484d', sw=4.4,
                    g3='M35 23h9a6 6 0 0 1 0 12h-9zM35 35h10a6 6 0 0 1 0 12h-10z'
                       + 'M39.5 27h4.5a2 2 0 0 1 0 4h-4.5zM39.5 39h5.5a2 2 0 0 1 0 4h-5.5z', c3='#2f6fdf',
                    x=[(rr(12, 41.2, 13, 3.6, 1.8) + poly((23.5, 37), (31, 43), (23.5, 49)), '#1b2031')]),
    # Stopwatch with a dark face and a ring of teal segments (Kronometer).
    'kronometer': dict(label='Kronometer', base='#1aa391', lip='#127a6c',
                       g1=ci(32, 31, 16.5) + rr(28, 9, 8, 4.5, 2) + rr(30.25, 12.5, 3.5, 3.5, 0)
                          + bar(17.5, 16.5, 21.5, 20.5, 4.5) + bar(46.5, 16.5, 42.5, 20.5, 4.5), c1='#ffffff',
                       g2=ci(32, 31, 13), c2='#1b2031',
                       g3=_kron_lit, c3='#3cc4b0'),
    # Twin-panel window with a big pointer (Krusader).
    'krusader': dict(label='Krusader', base='#7b5cd6', lip='#5a40a8',
                     g1=rr(11, 12, 42, 34, 4), c1='#ffffff',
                     g2=rr(14, 18, 17, 25, 2) + rr(33, 18, 17, 25, 2), c2='#d9ccff',
                     s1='M17.5 23h10M17.5 28.5h10M17.5 34h7', sc='#7b5cd6', sw=2.6,
                     x=[(poly((33.5, 21.5), (33.5, 47.5), (39.3, 42), (43.3, 50.5), (48.3, 48.2), (44.4, 40), (52.2, 39.4)), '#ffffff'),
                        (poly((35.5, 26), (35.5, 43.2), (39.9, 38.9), (44, 47.6), (45.9, 46.7), (41.8, 38.1), (47.7, 37.6)), '#1b2031')]),
    # Tea cup on a saucer with a timer tag (KTeaTime).
    'kteatime': dict(label='KTeaTime', base='#2f6fdf', lip='#2152ad',
                     g1='M14 27h32l-2.4 11.5a7 7 0 0 1-6.9 5.5H23.3a7 7 0 0 1-6.9-5.5z' + el(30, 27, 16, 4.2)
                        + el(30, 46.5, 19, 3.2) + ci(45, 15.5, 6.2), c1='#ffffff',
                     g2=el(30, 27, 13, 2.6), c2='#f2a65a',
                     s1='M46 30.5c5.5 0 6 8.5-1.5 9M36 25.5 41 20', sc='#ffffff', sw=3,
                     g3=rr(43.9, 11.6, 2.2, 5, 1.1) + rr(43.9, 14.4, 4.6, 2.2, 1.1), c3='#2f6fdf'),
    # Classic clock face (KTimer): white dial in the original's blue rim, ink hands and ticks.
    # review: green base and blue rim; the white dial on blue was KClock's twin at 32 px
    'ktimer': dict(label='KTimer', base='#2f9e6e', lip='#227650',
                   g1=ci(32, 30, 18.5), c1='#5b9dff',
                   g2=ci(32, 30, 15), c2='#ffffff',
                   s1='M32 30 25.4 26.2M32 30 40.4 25.2', sc='#1b2031', sw=3.4,
                   g3=rr(30.75, 16.6, 2.5, 4, 1.25) + rr(30.75, 39.4, 2.5, 4, 1.25)
                      + rr(18.6, 28.75, 4, 2.5, 1.25) + rr(41.4, 28.75, 4, 2.5, 1.25), c3='#1b2031',
                   x=[(bar(29.2, 35, 36.8, 21, 2.4), '#5b9dff'), (ci(32, 30, 2.6), '#5b9dff')]),
    # Wallet with a card peeking out (KWalletManager: the leather wallet / the Breeze cards).
    'kwalletmanager': dict(label='KWalletManager', base='#c2410c', lip='#922f08',
                           g1=rr(14, 10, 27, 18, 3), c1='#5b9dff',
                           g2=rr(22, 13.5, 27, 18, 3), c2='#f7c948',
                           g3=rr(11, 22, 42, 26, 5.5), c3='#ffffff',
                           x=[('M37 29h16v12H37a6 6 0 0 1 0-12z', '#922f08'), (ci(38, 35, 2.6), '#ffffff')]),
    # Text document with a caret (KWrite).
    # review: steel (the original's grey board); on blue it was one of four white-page-on-blue tiles
    # (LibreOffice Writer, Calligra Words, Kompare)
    'kwrite': dict(label='KWrite', base='#475069', lip='#323950',
                   g1=rr(21, 9, 28, 37, 3), c1='#c3c9d9',
                   g2='M17 12h18l10 10v25a3 3 0 0 1-3 3H17a3 3 0 0 1-3-3V15a3 3 0 0 1 3-3z', c2='#ffffff',
                   s1='M19 21h12M19 27h20M19 33h16M19 41h11', sc='#475069', sw=2.6,
                   g3=rr(33, 37.5, 2.6, 7.5, 1.3), c3='#f2a65a',
                   x=[('M35 12v7a3 3 0 0 0 3 3h7z', '#c3c9d9')]),
    # Menu list with a highlighted entry and a pencil (Menu Editor).
    'kmenuedit': dict(label='Menu Editor', base='#1f9e8f', lip='#15756a',
                      g1=rr(11, 11, 32, 38, 4), c1='#ffffff',
                      g2=rr(14, 24, 26, 9, 2.5), c2='#1f9e8f',
                      s1='M17 18h20M17 39h20M17 44.5h13', sc='#a8ded5', sw=2.6,
                      g3=rr(17, 27.2, 15, 2.6, 1.3), c3='#ffffff',
                      x=[(_me_pen, '#f2a65a'), (_me_tip, '#ffffff')]),
    # Notae: the hash and lines of its own flat mark.
    'notae': dict(label='Notae', base='#1a9bbd', lip='#13738c',
                  s1='M19 16.5v21M27 16.5v21M14.5 22.5h17M14.5 31.5h17M36 18h14M36 27h14M36 36h14M15 44h35',
                  sc='#ffffff', sw=3.8),
    # Hex editor: a page of byte columns on a circuit chip with gold pins (Okteta).
    'okteta': dict(label='Okteta', base='#3f8f5a', lip='#2d6b42',
                   g1=''.join(rr(10, y, 7, 3, 1.5) + rr(47, y, 7, 3, 1.5) for y in (17, 24, 31, 38))
                      + ''.join(rr(x, 46, 3, 4, 1.5) for x in (20, 26.5, 33, 39.5)), c1='#f7c948',
                   g2=rr(14, 11, 36, 37, 4), c2='#2d6b42',
                   g3=rr(19, 15, 26, 29, 2.5), c3='#ffffff',
                   x=[(''.join(rr(x, y, 5, 2.6, 1.3) for y in (20, 25.5, 31, 36.5) for x in (22, 29.5, 37)
                               if not (y == 36.5 and x == 37)), '#3f8f5a')]),
    # Mail and contacts with an export badge (PIM Data Exporter, from the Kontact mark).
    'pimdataexporter': dict(label='PIM Data Exporter', base='#d6457a', lip='#a8325d',
                            g1=rr(22, 9, 26, 20, 3), c1='#f8c6d8',
                            g2=rr(11, 21, 33, 25, 3.5), c2='#ffffff',
                            s1='M13.5 23.5 27.5 34l14-10.5', sc='#d6457a', sw=3,
                            g3=ci(29, 15.5, 3) + 'M23.5 25.5c0-4 2.5-5.5 5.5-5.5s5.5 1.5 5.5 5.5z', c3='#d6457a',
                            x=[(ci(45, 40, 10), '#d6457a'), (ci(45, 40, 8), '#ffffff'),
                               (poly((39.4, 41.2), (45, 34.2), (50.6, 41.2)) + rr(43, 40, 4, 6.4, 1.2), '#d6457a')]),
    # Phone with the settings sliders (Plasma Settings, Plasma Mobile).
    # review: slate (System Settings' grey family); on kde-blue it was KDE Connect's twin (white phone on blue)
    'plasma-settings-mobile': dict(label='Plasma Settings', base='#5b6478', lip='#414859',
                                   g1=rr(19.5, 9.5, 25, 40.5, 6), c1='#ffffff',
                                   g2=rr(23, 22, 18, 4, 2) + rr(23, 34, 18, 4, 2), c2='#d5d9e3',
                                   g3=rr(23, 22, 13, 4, 2) + rr(23, 34, 6, 4, 2) + rr(28.5, 12.5, 7, 2.5, 1.25), c3='#5b6478',
                                   x=[(ci(36, 24, 4) + ci(28, 36, 4), '#1b2031')]),
    # Phone with the terminal prompt (QMLKonsole, the mobile Konsole).
    'qmlkonsole': dict(label='QMLKonsole', base='#262c42', lip='#131726',
                       g1=rr(19.5, 9.5, 25, 40.5, 6), c1='#e8ebf4',
                       g2=rr(22.5, 14, 19, 31, 3), c2='#1b2031',
                       s1='M26 24l5 4.5-5 4.5', sc='#3cc4b0', sw=3.2,
                       g3=rr(32, 35, 7, 3, 1.5), c3='#e8ebf4'),
    # Terminal window with a title bar, a red close dot and #! (Station).
    'station': dict(label='Station', base='#5b6478', lip='#414859',
                    g1=rr(11, 13, 42, 34, 4.5), c1='#1b2031',
                    g2='M15.5 13h33a4.5 4.5 0 0 1 4.5 4.5V21H11v-3.5a4.5 4.5 0 0 1 4.5-4.5z', c2='#e8ebf4',
                    s1='M20.5 26.5v13M26.5 26.5v13M17 31h13M17 35.5h13', sc='#ffffff', sw=2.6,
                    g3=rr(34, 26, 4, 9, 2) + ci(36, 39.5, 2.1), c3='#ffffff',
                    x=[(ci(48, 17, 2.2), '#e5484d')]),
    # Three chasing arrows (Sweeper's recycle mark).
    'sweeper': dict(label='Sweeper', base='#c93a42', lip='#992a31',
                    s1=_rc_lines, sc='#ffffff', sw=5.4,
                    g3=_rc_heads, c3='#ffffff'),
    # Vaccination certificate: a card with a QR mark and a syringe (Vakzination).
    'vakzination': dict(label='Vakzination', base='#2f9e6e', lip='#227650',
                        g1=rr(10, 23, 30, 25, 4), c1='#ffffff',
                        g2=rr(14, 28, 11, 11, 2) + rr(16.6, 30.6, 5.8, 5.8, 1) + rr(18.3, 32.3, 2.4, 2.4, 0.6)
                           + rr(28, 28, 3.5, 3.5, 0.8) + rr(32, 32, 3.5, 3.5, 0.8) + rr(28, 36, 3.5, 3.5, 0.8)
                           + rr(14, 42, 21, 2.6, 1.3), c2='#1b2031',
                        x=[(_syr_gap_low, '#2f9e6e'), (_syr_gap_high, _sheen('#2f9e6e')),
                           (_syr_white, '#ffffff'), (_syr_liquid, '#3cc4b0')]),
    # The Plasma logo (chevron and three dots) on white (Welcome Center).
    'plasma-welcome': dict(label='Welcome Center', base='#f4f5f9', lip='#d5d9e3',
                           g1=_pl_chev, c1='#1b2031',
                           x=[(ci(*_plasma(28, 14), 3.2), '#f2a65a'), (ci(*_plasma(16, 45), 4.2), '#3aa65b'),
                              (ci(*_plasma(39, 77), 5.6), '#2b8be6')]),
    # Screen with the red streaming dot (Xwayland Video Bridge).
    'xwaylandvideobridge': dict(label='Xwayland Video Bridge', base='#2c3348', lip='#1a1f2e',
                                g1=rr(10, 11, 44, 31, 4) + 'M28 42h8v3.5h-8zM22 45h20a1.75 1.75 0 0 1 0 3.5H22a1.75 1.75 0 0 1 0-3.5z',
                                c1='#e8ebf4',
                                g2=rr(13.5, 14.5, 37, 24, 2), c2='#9bb6e0',
                                g3=ci(32, 26.5, 9), c3='#e5484d'),
}

APPS = {
    'org.kde.kjots': 'kjots',
    'org.kde.kleopatra': 'kleopatra',
    'org.kde.kmag': 'kmag',
    'org.kde.kmouth': 'kmouth',
    'org.kde.knotes': 'knotes',
    'org.kde.konsole': 'board:terminal',
    'org.kde.krename': 'krename',
    'org.kde.kronometer': 'kronometer',
    'org.kde.krusader': 'krusader',
    'org.kde.kteatime': 'kteatime',
    'org.kde.ktimer': 'ktimer',
    'org.kde.kwalletmanager5': 'kwalletmanager',
    'org.kde.kwrite': 'kwrite',
    'org.kde.kmenuedit': 'kmenuedit',
    'org.kde.notae': 'notae',
    'org.kde.okteta': 'okteta',
    'org.kde.pimdataexporter': 'pimdataexporter',
    'org.kde.mobile.plasmasettings': 'plasma-settings-mobile',
    'org.kde.plasma-systemmonitor': 'board:monitor',
    'org.kde.qmlkonsole': 'qmlkonsole',
    'org.kde.spectacle': 'board:screenshot',
    'org.kde.station': 'station',
    'org.kde.sweeper': 'sweeper',
    'org.kde.systemsettings': 'round1:systemsettings',
    'org.kde.vakzination': 'vakzination',
    'org.kde.kweather': 'board:weather',
    'org.kde.plasma-welcome': 'plasma-welcome',
    'org.kde.xwaylandvideobridge': 'xwaylandvideobridge',
}
