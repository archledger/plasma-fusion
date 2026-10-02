# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Drawing kit for the per-app tiles (the 2026-10-02 redesign; style guide in docs/parts/icons.md).

A tile is a dict in the art_tiles.TILES format plus two additions: g2 and g3 are filled with the
even-odd rule (cut-outs), and x = [(path, colour), ...] are extra fills drawn last. Helpers: rr, ci,
el, gear (svgkit), ring, poly, chrome_parts; PALETTE holds the board's base/lip pairs.
"""
import math

from svgkit import Svg, ci, el, gear, rr  # noqa: F401
import art_tiles

BOARD = art_tiles.TILES

PALETTE = {
    'blue': ('#3f7fe0', '#2b5db5'), 'kde-blue': ('#2b8be6', '#1f68b3'), 'accent-blue': ('#2f6fdf', '#2152ad'),
    'orange': ('#e8743b', '#b8552a'), 'teal': ('#1f9e8f', '#15756a'), 'teal-2': ('#1aa391', '#127a6c'),
    'purple': ('#7b5cd6', '#5a40a8'), 'violet': ('#9b3fb5', '#742d88'), 'deep-purple': ('#5a2ca0', '#3e1e70'),
    'pink': ('#d6457a', '#a8325d'), 'green': ('#3aa65b', '#2a7e44'), 'green-2': ('#2f9e6e', '#227650'),
    'map-green': ('#3f8f5a', '#2d6b42'), 'red': ('#c93a42', '#992a31'), 'rust': ('#c2410c', '#922f08'),
    'amber': ('#b7792f', '#8a5a20'), 'yellow': ('#f5c84c', '#c99a22'), 'slate': ('#5b6478', '#414859'),
    'slate-dark': ('#3b4255', '#262b38'), 'navy': ('#262c42', '#131726'), 'ink': ('#2c3348', '#1a1f2e'),
    'steel': ('#475069', '#323950'), 'sky': ('#3a7bd5', '#2a5ea8'), 'light': ('#f4f5f9', '#d5d9e3'),
    'paper': ('#f6f4ef', '#d6d0c2'),
}


def f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def poly(*pts):
    """Closed polygon path from (x, y) pairs."""
    return "M" + "L".join(f"{f(x)} {f(y)}" for x, y in pts) + "z"


def ring(cx, cy, ro, ri):
    """Annulus (an even-odd layer: g2 or g3)."""
    return ci(cx, cy, ro) + "M" + ci(cx, cy, ri)[1:]


def chrome_parts(cx, cy, R, ri, start=150):
    """Three segments whose boundaries are tangent to the inner circle (Chrome's hooked ring)."""
    t = math.sqrt(R * R - ri * ri)
    out = []
    for k in range(3):
        a0 = math.radians(start + 120 * k); a1 = math.radians(start + 120 * (k + 1))
        P0 = (cx + ri * math.cos(a0), cy + ri * math.sin(a0)); d0 = (math.cos(a0 + math.pi / 2), math.sin(a0 + math.pi / 2))
        Q0 = (P0[0] + t * d0[0], P0[1] + t * d0[1])
        P1 = (cx + ri * math.cos(a1), cy + ri * math.sin(a1)); d1 = (math.cos(a1 + math.pi / 2), math.sin(a1 + math.pi / 2))
        Q1 = (P1[0] + t * d1[0], P1[1] + t * d1[1])
        out.append(f"M{f(P0[0])} {f(P0[1])}L{f(Q0[0])} {f(Q0[1])}A{f(R)} {f(R)} 0 0 1 {f(Q1[0])} {f(Q1[1])}"
                   f"L{f(P1[0])} {f(P1[1])}A{f(ri)} {f(ri)} 0 0 0 {f(P0[0])} {f(P0[1])}z")
    return out


SHEEN = 'M15 0h34a15 15 0 0 1 15 15v13H0V15A15 15 0 0 1 15 0z'
# The sheen as a paint: 9 % white over the top 28 units, nothing below. Glyph parts drawn in the
# base colour (separators, cut-outs painted over the base) are covered with it again, so they
# match the base under the sheen instead of showing as darker seams.
SHEEN_GRADIENT = ('<defs><linearGradient id="pf-sheen" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="64">'
                  '<stop offset="0" stop-color="#ffffff" stop-opacity="0.09"/>'
                  '<stop offset="0.4375" stop-color="#ffffff" stop-opacity="0.09"/>'
                  '<stop offset="0.4375" stop-color="#ffffff" stop-opacity="0"/></linearGradient></defs>')


def tile_svg(i):
    base = i['base'].lower()
    s = Svg(64)
    layers = [('fill', i.get('g1'), i.get('c1'), False, None), ('fill', i.get('g2'), i.get('c2'), True, None),
              ('stroke', i.get('s1'), i.get('sc'), False, i.get('sw')), ('fill', i.get('g3'), i.get('c3'), True, None)]
    layers += [('fill', d, c, False, None) for d, c in i.get('x', [])]
    seams = [l for l in layers if l[1] and l[2] and l[2].lower() == base]
    if seams:
        s.raw(SHEEN_GRADIENT)
    s.fill(rr(0, 0, 64, 64, 15), i['lip'])
    s.fill(rr(0, 0, 64, 60, 15), i['base'])
    s.raw(f'<path d="{SHEEN}" fill="#ffffff" fill-opacity="0.09"/>')
    for kind, d, c, evenodd, sw in layers:
        if kind == 'fill':
            s.fill(d, c, evenodd=evenodd)
        else:
            s.stroke(d, c, sw)
    for kind, d, c, evenodd, sw in seams:
        if kind == 'fill':
            s.raw(f'<path d="{d}" fill="url(#pf-sheen)"' + (' fill-rule="evenodd"' if evenodd else '') + '/>')
        else:
            s.raw(f'<path d="{d}" fill="none" stroke="url(#pf-sheen)" stroke-width="{f(sw)}" '
                  'stroke-linecap="round" stroke-linejoin="round"/>')
    s.stroke(rr(0.5, 0.5, 63, 63, 14.5), 'rgba(255,255,255,0.14)', 1, cap='butt', join='miter')
    return s.render()
