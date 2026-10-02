# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, round 3 batch wine.
from apptiles.kit import *  # noqa: F401,F403  helpers, PALETTE, BOARD, tile_svg
# Plasma Fusion app tiles, batch wine: the Wine tools and the owner's Windows 11 VM launcher.
#
# Family motif: every Wine tool carries Wine's glass (white bowl with red wine, stem and foot) at the
# bottom right, cut free from the tool's object by a base-coloured halo, as in Wine's own icons. Each
# tool keeps its own object and its own base colour; the Wine tile itself is the glass alone, large.
import math
import re


# ---- local helpers ---------------------------------------------------------------------------

def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


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


def pt(cx, cy, r, a):
    """Point on a circle; a in degrees, 0 = +x, positive = clockwise on screen."""
    t = math.radians(a)
    return cx + r * math.cos(t), cy + r * math.sin(t)


def xform(pts, ang, tx, ty):
    """Rotate points by ang degrees about the origin, then translate."""
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(x * c - y * s + tx, x * s + y * c + ty) for x, y in pts]


def cw(pts):
    """Clockwise (on screen) orientation, so nonzero unions never cancel."""
    a = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]))
    return pts if a > 0 else pts[::-1]


def rr_pts(w, h, r, n=5):
    """Rounded rectangle centred on the origin, as a point list (for rotated parts)."""
    pts = []
    for (cx, cy, a0) in ((w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0),
                         (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def ci_cw(cx, cy, r):
    """Circle drawn clockwise, so it unions with rr() and bar() shapes in a nonzero layer."""
    return (f"M{_f(cx - r)} {_f(cy)}a{_f(r)} {_f(r)} 0 1 1 {_f(2 * r)} 0"
            f"a{_f(r)} {_f(r)} 0 1 1 {_f(-2 * r)} 0z")


def bar(x0, y0, x1, y1, w, r=None):
    """Rounded bar of width w from (x0, y0) to (x1, y1), as a clockwise polygon."""
    L = math.hypot(x1 - x0, y1 - y0)
    ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
    r = w / 2 - 0.01 if r is None else r
    return poly(*cw(xform(rr_pts(L, w, r, 6), ang, (x0 + x1) / 2, (y0 + y1) / 2)))


def wrench(hx, hy, ang, r=6.5, slot=2.4, depth=-0.5, hw=2.8, length=22.0):
    """Open-end wrench: head centred on (hx, hy), jaw opening away from the handle, handle along ang."""
    a0 = math.degrees(math.asin(slot / r))
    head = [(depth, -slot)]
    for k in range(41):
        a = 180 + a0 + (360 - 2 * a0) * k / 40
        head.append((r * math.cos(math.radians(a)), r * math.sin(math.radians(a))))
    head.append((depth, slot))
    handle = rr_pts(length, 2 * hw, hw - 0.01, 6)
    handle = [(x + length / 2 + r * 0.4, y) for x, y in handle]
    return poly(*cw(xform(head, ang, hx, hy))) + poly(*cw(xform(handle, ang, hx, hy)))


# ---- the shared motif: Wine's glass ------------------------------------------------------------
# Local units: origin at the centre of the rim, 12.4 wide, 20.8 tall. All parts run clockwise, so
# they union in a nonzero layer.
_BOWL = ('M-5.6 0H5.6C6.4 3.4 6.6 6.4 5 8.6C3.8 10.3 2.1 11 0 11'
         'C-2.1 11-3.8 10.3-5 8.6C-6.6 6.4-6.4 3.4-5.6 0z')
_WINE = ('M-5 4.4H5C5.2 6 4.9 7.1 4 8C3 9 1.6 9.6 0 9.6'
         'C-1.6 9.6-3 9-4 8C-4.9 7.1-5.2 6-5 4.4z')
_STEM = rr(-1.3, 10.4, 2.6, 8.2, 0.6)
_FOOT = rr(-5.4, 18, 10.8, 2.8, 1.4)
_HALO = xf(_BOWL, 1.28, 0, -1.55) + rr(-2.9, 9.5, 5.8, 10, 2.5) + rr(-7, 16.4, 14, 6, 3)


def glass(cx, top, k=1.0):
    """(halo, glass, wine) paths for a glass whose rim centre is at (cx, top), scaled by k."""
    return (xf(_HALO, k, cx, top), xf(_BOWL + _STEM + _FOOT, k, cx, top), xf(_WINE, k, cx, top))


def with_glass(base, cx=45.5, top=28, k=1.05):
    """x layers that put the family glass on a tool tile: halo in the base colour, then the glass."""
    h, g, w = glass(cx, top, k)
    return [(h, base), (g, '#ffffff'), (w, '#e5484d')]


# ---- objects -----------------------------------------------------------------------------------

# Wine (the main tile): the glass alone, large.
_BIG = glass(32, 9, 1.98)

# Wine Configuration: a wrench and a screwdriver crossed, as in winecfg's icon.
_WRENCH = wrench(42, 17.5, 135, r=7.2, slot=2.7, depth=0.0, hw=3.1, length=30)
_SD_HANDLE = bar(13.5, 13.5, 22.5, 22.5, 7.6)
_SD_SHAFT = bar(21.5, 21.5, 34.5, 34.5, 3.2, r=0.9)
_SD_CUT = bar(13.5, 13.5, 22.5, 22.5, 7.6 + 2.8) + bar(21.5, 21.5, 34.5, 34.5, 3.2 + 2.8)

# Notepad: a spiral-bound pad with ruled lines.
_PAD = rr(13, 13, 29, 36, 3.5)
_RINGS = ''.join(rr(x - 1.4, 9.5, 2.8, 7.5, 1.4) for x in (18, 23.5, 29, 34.5))
_PAD_LINES = (rr(17, 22, 21, 2.8, 1.4) + rr(17, 28.5, 21, 2.8, 1.4) + rr(17, 35, 17, 2.8, 1.4)
              + rr(17, 41.5, 14, 2.8, 1.4))

# Regedit: the registry cube, a 2 x 2 x 2 block of cubes seen from the front (oblique, depth running
# up to the right), with the top front-right block missing, as in regedit's icon.
_RS = 12.0                     # front edge of one block
_RD = (4.6, -4.0)              # depth offset of one block
_RX, _RY = 11.5, 21.5          # top-left corner of the front face


def _ro(i, j, k):
    """Screen point of lattice corner (i right, j down, k back)."""
    return (_RX + i * _RS + k * _RD[0], _RY + j * _RS + k * _RD[1])


def _regcube(gap=0.85):
    blocks = [(i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1) if (i, j, k) != (1, 0, 0)]
    blocks.sort(key=lambda b: (-b[2], -b[1], b[0]))
    layers = []
    for i, j, k in blocks:
        front = [_ro(i, j, k), _ro(i + 1, j, k), _ro(i + 1, j + 1, k), _ro(i, j + 1, k)]
        top = [_ro(i, j, k), _ro(i, j, k + 1), _ro(i + 1, j, k + 1), _ro(i + 1, j, k)]
        side = [_ro(i + 1, j, k), _ro(i + 1, j, k + 1), _ro(i + 1, j + 1, k + 1), _ro(i + 1, j + 1, k)]
        layers += [(poly(*_inset(top, gap)), '#8fded1'), (poly(*_inset(side, gap)), '#12695f'),
                   (poly(*_inset(front, gap)), '#ffffff')]
    return layers


def _inset(pts, d):
    """Pull every corner of a convex polygon towards its centroid by d units."""
    cx = sum(p[0] for p in pts) / len(pts); cy = sum(p[1] for p in pts) / len(pts)
    out = []
    for x, y in pts:
        L = math.hypot(x - cx, y - cy)
        out.append((x - (x - cx) / L * d, y - (y - cy) / L * d))
    return out


# Uninstaller: an open cardboard box with its flaps folded out.
_BA, _BH = 14.5, 12.5          # box edge and height (isometric units)
_BF, _BR = 5.5, 6.0             # how far the back flaps reach out and up
_BC = (28, 20.5)                # screen point of the box's back top corner


def _bx(x, y, z):
    return (_BC[0] + (x - y) * math.cos(math.radians(30)), _BC[1] + (x + y) / 2 - (z - _BH))


_BOX_L = poly(_bx(0, _BA, _BH), _bx(_BA, _BA, _BH), _bx(_BA, _BA, 0), _bx(0, _BA, 0))       # front-left side
_BOX_R = poly(_bx(_BA, 0, _BH), _bx(_BA, _BA, _BH), _bx(_BA, _BA, 0), _bx(_BA, 0, 0))       # front-right side
_BOX_IN = poly(_bx(0, 0, _BH), _bx(_BA, 0, _BH), _bx(_BA, _BA, _BH), _bx(0, _BA, _BH))     # the opening
_FLAPS = (poly(_bx(0, 0, _BH), _bx(0, _BA, _BH), _bx(-_BF, _BA, _BH + _BR), _bx(-_BF, 0, _BH + _BR))
          + poly(_bx(0, 0, _BH), _bx(_BA, 0, _BH), _bx(_BA, -_BF, _BH + _BR), _bx(0, -_BF, _BH + _BR)))

# Wine File: a filing cabinet with two drawers.
_CAB = rr(13.5, 11, 26, 37, 3.5)
_DRAWERS = rr(16.5, 14, 20, 15, 2) + rr(16.5, 31.5, 20, 13.5, 2)
_HANDLES = rr(22, 21.5, 9, 3, 1.5) + rr(22, 38, 9, 3, 1.5)

# WineMine: a sea mine with four lugs and four spikes.
_MX, _MY = 27.5, 27.5
_MINE = (ci_cw(_MX, _MY, 11.5) + ''.join(bar(_MX, _MY, *pt(_MX, _MY, 17, a), 4.8) for a in (0, 90, 180, 270))
         + ''.join(bar(_MX, _MY, *pt(_MX, _MY, 15.5, a), 3.6) for a in (45, 135, 225, 315)))
_MINE_SHINE = rr(_MX - 6.5, _MY - 6.5, 5, 5, 1.6)

# Wine Help: the help disc with a question mark.
_HX, _HY = 30, 28.5
_HELP_RING = ring(_HX, _HY, 17.5, 14)
_HELP_Q = f'M{_f(_HX - 5.6)} {_f(_HY - 4.6)}a5.8 5.8 0 1 1 8.7 5c-1.9 1.1-3.1 2.3-3.1 4.4v1.2'
_HELP_DOT = ci(_HX, _HY + 9.6, 2.6)

# Wine Wordpad: a page with a large serif A and text lines.
_PAGE = rr(12.5, 11, 29, 37, 3.5)
_A = 'M17 33 25 15.5 33 33M20.2 26.5H29.8'
_A_SERIFS = rr(13.8, 32, 7.2, 3, 1.2) + rr(29.4, 32, 7.6, 3, 1.2)
_PAGE_LINES = rr(16.5, 39, 20, 2.8, 1.4) + rr(16.5, 44, 13, 2.8, 1.4)

# Windows 11 Home (a virtual machine): the Windows 11 logo.
_WIN = rr(16, 14, 15, 15, 1.6) + rr(33, 14, 15, 15, 1.6) + rr(16, 31, 15, 15, 1.6) + rr(33, 31, 15, 15, 1.6)


TILES = {
    'wine': dict(label='Wine', base='#a8304f', lip='#7e243b',
                 g1=_BIG[1], c1='#ffffff',
                 x=[(_BIG[2], '#e5484d')]),
    'wine-winecfg': dict(label='Wine Configuration', base='#2c3348', lip='#1a1f2e',
                         g1=_WRENCH, c1='#ffffff',
                         x=[(_SD_CUT, '#2c3348'), (_SD_SHAFT, '#ffffff'), (_SD_HANDLE, '#5b9dff')]
                         + with_glass('#2c3348')),
    # pink (round-3 review): blue made it a twin of LibreOffice Writer and Calligra Words, and the first
    # draft's yellow made a white page on yellow like KNotes and the board's notes tile; amber, green and
    # sky sat on Wine File, Marknote and Writer. The spiral binding and the glass carry the identity.
    'wine-notepad': dict(label='Notepad', base='#d6457a', lip='#a8325d',
                         g1=_PAD, c1='#ffffff',
                         g2=_PAD_LINES, c2='#d6457a',
                         g3=_RINGS, c3='#1b2031',
                         x=with_glass('#d6457a')),
    'wine-regedit': dict(label='Regedit', base='#1f9e8f', lip='#15756a',
                         x=_regcube() + with_glass('#1f9e8f')),
    # amber, the original's cardboard (round-3 review): on green the white box with tinted faces read like
    # Regedit's white blocks on teal at 32 px. The open flaps keep it apart from the board's archive box.
    'wine-uninstaller': dict(label='Wine Software Uninstaller', base='#b7792f', lip='#8a5a20',
                             g1=_FLAPS, c1='#f3dcb8',
                             g2=_BOX_IN, c2='#6e4616',
                             g3=_BOX_L, c3='#ffffff',
                             x=[(_BOX_R, '#f3dcb8')] + with_glass('#b7792f')),
    'wine-winefile': dict(label='Wine File', base='#e8743b', lip='#b8552a',
                          g1=_CAB, c1='#ffffff',
                          g2=_DRAWERS, c2='#ffd9c2',
                          g3=_HANDLES, c3='#e8743b',
                          x=with_glass('#e8743b')),
    'wine-winemine': dict(label='WineMine', base='#5b6478', lip='#414859',
                          g1=_MINE, c1='#1b2031',
                          g3=_MINE_SHINE, c3='#ffffff',
                          x=with_glass('#5b6478')),
    # the disc keeps a dark centre, as in Wine's icon; a plain white ring read as KHelpCenter's lifebuoy
    'wine-winhelp': dict(label='Wine Help', base='#2f6fdf', lip='#2152ad',
                         g1=ci(_HX, _HY, 14.2), c1='#2152ad',
                         g2=_HELP_RING, c2='#ffffff',
                         s1=_HELP_Q, sc='#ffffff', sw=4.6,
                         g3=_HELP_DOT, c3='#ffffff',
                         x=with_glass('#2f6fdf')),
    'wine-wordpad': dict(label='Wine Wordpad', base='#7b5cd6', lip='#5a40a8',
                         g1=_PAGE, c1='#ffffff',
                         s1=_A, sc='#7b5cd6', sw=4.4,
                         g3=_A_SERIFS + _PAGE_LINES, c3='#7b5cd6',
                         x=with_glass('#7b5cd6')),
    'windows11-home': dict(label='Windows 11 Home', base='#2b8be6', lip='#1f68b3',
                           g1=_WIN, c1='#ffffff'),
}

APPS = {
    'wine-wineboot': 'wine',
    'wine-winecfg': 'wine-winecfg',
    'wine-notepad': 'wine-notepad',
    'wine-regedit': 'wine-regedit',
    'wine-uninstaller': 'wine-uninstaller',
    'wine-winefile': 'wine-winefile',
    'wine-winemine': 'wine-winemine',
    'wine-winhelp': 'wine-winhelp',
    'wine-wordpad': 'wine-wordpad',
    'windows11-home': 'windows11-home',
}
