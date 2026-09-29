# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Plasma Fusion pointer drawings and cursor names.

Every drawing lives on the 32-unit canvas of design/boards/Pointers.dc.html. The twelve board
pointers use the board's own path data (renderVals() in Pointers.dc.html); the other shapes are
drawn from the same parts (the arrow, the hand, the 6.4-unit badge at 25,25, the 1.6 outline,
the 4.4/2.0 line pair) so that every name a toolkit asks for gets a Fusion pointer.

A drawing is a list of layers. Colours are either literal (#rrggbb) or the theme keys
'fill' and 'edge' (dark theme: #1b2031 fill, white edge; light theme: white fill, #1b2031 edge).

  ('F', d, colour)          filled shape with a 1.6 edge outline (board: fill + stroke 1.6)
  ('L', d, colour)          line glyph: 4.4 edge under a 2.0 colour line (board: line/lc)
  ('W', d, colour, w, u)    wide line: u-wide edge under a w-wide colour line
  ('P', d, colour)          plain fill, no outline (badges, spinner dots)
  ('S', d, colour, w)       plain round-capped stroke (glyphs inside badges)
  ('G', transform, layers)  a group of layers under an SVG transform
"""
import math

# Board palette (Pointers.dc.html, Colors.dc.html)
INK = '#1b2031'
WHITE = '#ffffff'
BLUE = '#5b9dff'     # spinner dot, crosshair centre
AMBER = '#f2a65a'    # spinner dot
TEAL = '#3cc4b0'     # spinner dot
GREEN = '#3aa65b'    # copy badge
RED = '#e5484d'      # not allowed
ACCENT = '#2f6fdf'   # accent fill (Colors board), used for the help badge

THEMES = {
    # directory name: (display name, comment, inherits, colours)
    'PlasmaFusion-cursors': (
        'Plasma Fusion',
        'Dark pointers with a white outline and a soft shadow',
        'breeze_cursors',
        {'fill': INK, 'edge': WHITE},
    ),
    'PlasmaFusion-Light-cursors': (
        'Plasma Fusion Light',
        'White pointers with a dark outline and a soft shadow',
        'Breeze_Light',
        {'fill': WHITE, 'edge': INK},
    ),
}


def ci(cx, cy, r):
    """Circle as a path (board helper)."""
    return f'M{fmt(cx - r)} {fmt(cy)}a{fmt(r)} {fmt(r)} 0 1 0 {fmt(2 * r)} 0a{fmt(r)} {fmt(r)} 0 1 0 {fmt(-2 * r)} 0z'


def rr(x, y, w, h, r):
    """Rounded rectangle as a path."""
    return (f'M{fmt(x + r)} {fmt(y)}h{fmt(w - 2 * r)}a{fmt(r)} {fmt(r)} 0 0 1 {fmt(r)} {fmt(r)}'
            f'v{fmt(h - 2 * r)}a{fmt(r)} {fmt(r)} 0 0 1 {fmt(-r)} {fmt(r)}h{fmt(-(w - 2 * r))}'
            f'a{fmt(r)} {fmt(r)} 0 0 1 {fmt(-r)} {fmt(-r)}v{fmt(-(h - 2 * r))}a{fmt(r)} {fmt(r)} 0 0 1 {fmt(r)} {fmt(-r)}z')


def fmt(v):
    s = f'{v:.3f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def dots(cx, cy, r, s):
    """Three spinner dots (board helper)."""
    return [ci(cx, cy - s, r), ci(cx - s * 0.87, cy + s * 0.5, r), ci(cx + s * 0.87, cy + s * 0.5, r)]


def rotate_point(x, y, deg, cx=16.0, cy=16.0):
    a = math.radians(deg)
    dx, dy = x - cx, y - cy
    return (cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a))


# ---- board drawings (Pointers.dc.html renderVals) -------------------------------------------
ARROW = 'M6 3v21l5.5-5.2 3.6 8.2 3.7-1.6-3.6-8h7.6z'
HAND = ('M12 18V5a2 2 0 0 1 4 0v7a1.75 1.75 0 0 1 3.5 0v1.5a1.75 1.75 0 0 1 3.5 0V15a1.75 1.75 0 0 1 3.5 0'
        'v6c0 4-2.8 7-7 7h-2.5c-2.4 0-3.8-1-5-2.8L6.2 19.4a1.9 1.9 0 0 1 2.9-2.4z')
IBEAM = ('M11.5 5h2.5c1 0 2 .6 2 1.6 0-1 1-1.6 2-1.6h2.5M16 6.6v18.8'
         'M11.5 27h2.5c1 0 2-.6 2-1.6 0 1 1 1.6 2 1.6h2.5M13 16h6')
MOVE = ('M16 3l4.5 4.5h-3v7h7v-3L29 16l-4.5 4.5v-3h-7v7h3L16 29l-4.5-4.5h3v-7h-7v3L3 16l4.5-4.5v3h7v-7h-3z')
EW = 'M3 16l6-6v4h14v-4l6 6-6 6v-4H9v4z'
NS = 'M16 3l6 6h-4v14h4l-6 6-6-6h4V9h-4z'
NWSE = 'M6 6H15L11.8 9.2 22.8 20.2 26 17V26H17L20.2 22.8 9.2 11.8 6 15Z'
CROSS = 'M16 3v9M16 20v9M3 16h9M20 16h9'
NO = ci(16, 16, 10) + 'M9 9l14 14'
PLUS_GLYPH = 'M24.1 21.6h1.8v2.5h2.5v1.8h-2.5v2.5h-1.8v-2.5h-2.5v-1.8h2.5z'
MIRROR_X = 'matrix(-1 0 0 1 32 0)'

# Busy spinner: 4 key frames 30 degrees apart on the board (0/30/60/90, 800 ms loop). The dots
# are three-fold symmetric, so one loop turns them 120 degrees. We add two in-between frames per
# key frame (10-degree steps) and keep the 800 ms loop: 12 frames of 67/67/66 ms.
SPIN_FRAMES = 12
SPIN_STEP = 10.0
SPIN_DELAYS = [67, 67, 66] * 4


def spinner(cx, cy, r, s, angle, spin_cx, spin_cy):
    d = dots(cx, cy, r, s)
    return ('G', f'rotate({fmt(angle)} {fmt(spin_cx)} {fmt(spin_cy)})',
            [('P', d[0], BLUE), ('P', d[1], AMBER), ('P', d[2], TEAL)])


def badge(disc, glyph_layers, ring_colour='edge'):
    """The board's copy badge frame: 6.4 ring in the edge colour, 5.0 disc, glyph on top."""
    return [('P', ci(25, 25, 6.4), ring_colour), ('P', ci(25, 25, 5), disc)] + glyph_layers


# ---- derived drawings ------------------------------------------------------------------------
OPEN_HAND = (
    'M9 17.2V8.6a1.9 1.9 0 0 1 3.8 0V15V6.6a1.9 1.9 0 0 1 3.8 0V15V7.6a1.9 1.9 0 0 1 3.8 0V15'
    'V10.6a1.8 1.8 0 0 1 3.6 0V20.8c0 4.2-2.9 7.2-7 7.2h-2.3c-2.4 0-3.8-1-5-2.8L4.5 18.6'
    'a1.9 1.9 0 0 1 2.8-2.5z')
FIST = (
    'M8.6 17.4V14.4a1.9 1.9 0 0 1 3.8 0V16.6V13.6a1.9 1.9 0 0 1 3.8 0V16.6V14.1a1.9 1.9 0 0 1 3.8 0'
    'V16.6V15.3a1.8 1.8 0 0 1 3.6 0V21c0 4-2.9 7-7 7h-2.3c-2.4 0-3.8-1-5-2.8L5.2 21'
    'a1.9 1.9 0 0 1 2.9-2.4z')
CELL = 'M13.4 5.5h5.2v7.9h7.9v5.2h-7.9v7.9h-5.2v-7.9H5.5v-5.2h7.9z'
UP_ARROW = 'M16 3l6.5 6.5H18V28h-4V9.5H9.5z'
CENTER_PTR = 'M16 3L24.6 22.2 17.9 19.4V28h-3.8v-8.6L7.4 22.2z'
X_SHAPE = 'M5.2 8L8 5.2l8 8 8-8L26.8 8l-8 8 8 8-2.8 2.8-8-8-8 8L5.2 24l8-8z'
COL_RESIZE = [
    ('F', 'M14.3 5h3.4v22h-3.4z', 'fill'),
    ('F', 'M2.8 16l5.6-5.6v3.7h3.9v3.8H8.4v3.7z', 'fill'),
    ('F', 'M29.2 16l-5.6-5.6v3.7h-3.9v3.8h3.9v3.7z', 'fill'),
]
ALL_SCROLL = [
    ('F', 'M16 3.5l5 5.5H11z', 'fill'),
    ('F', 'M16 28.5l5-5.5H11z', 'fill'),
    ('F', 'M3.5 16l5.5-5v10z', 'fill'),
    ('F', 'M28.5 16l-5.5-5v10z', 'fill'),
    ('F', ci(16, 16, 3.2), 'fill'),
    ('P', ci(16, 16, 1.6), BLUE),
]


def zoom(glyph):
    return [
        ('W', 'M19.6 19.6l6.6 6.6', 'fill', 3.0, 5.6),
        ('F', ci(13.5, 13.5, 8), 'fill'),
        ('S', glyph, 'edge', 1.9),
    ]


# Eyedropper and pencil are drawn upright with the tip at the bottom, then turned 45 degrees
# so the tip points to the lower left like the board's arrow family.
DROPPER_TIP = (16.0, 29.6)
DROPPER = [
    ('F', 'M14.6 16.8h2.8v9.4L16 29.6l-1.4-3.4z', 'fill'),
    ('F', rr(11.4, 13.2, 9.2, 3.6, 1.3), 'fill'),
    ('F', 'M13.3 13.2V6.4a2.7 2.7 0 0 1 5.4 0v6.8z', 'fill'),
]
PENCIL_TIP = (16.0, 29.8)
PENCIL = [
    ('F', 'M13.1 9.4h5.8v13.8L16 29.8l-2.9-6.6z', 'fill'),
    ('S', 'M13.6 23.2h4.8', 'edge', 1.2),
    ('F', 'M13.1 7.8V6.1a2.9 2.9 0 0 1 5.8 0v1.7z', 'fill'),
]


def hs(pt):
    return (round(pt[0] * 4) / 4, round(pt[1] * 4) / 4)


# ---- the shape table -------------------------------------------------------------------------
def static(layers, hotspot):
    return {'frames': [(layers, None)], 'hotspot': hotspot}


def animated(make, hotspot):
    return {'frames': [(make(k * SPIN_STEP), SPIN_DELAYS[k]) for k in range(SPIN_FRAMES)],
            'hotspot': hotspot}


def _wait(angle):
    return [('F', ci(16, 16, 11), 'fill'), spinner(16, 16.6, 3, 6, angle, 16, 16.6)]


def _progress(angle):
    return [('F', ARROW + ci(25, 25, 5.6), 'fill'), spinner(25, 25, 1.7, 2.6, angle, 25, 25)]


# Question mark and link arrow for the badges (strokes, so they stay crisp at small sizes).
QUESTION = 'M23.4 23.4a1.7 1.7 0 1 1 2.4 1.55c-.5.25-.8.6-.8 1.2v.3'
LINK = 'M22.3 28v-1.4a3 3 0 0 1 3-3h2.3M26 21.8l1.9 1.8-1.9 1.8'
MENU_LINES = 'M22.3 22.6h5.4M22.3 25h5.4M22.3 27.4h5.4'
# White slash on the red disc: the not-allowed sign reduced to what still reads at 24 px.
NO_GLYPH = 'M22.4 22.4l5.2 5.2'

SHAPES = {
    # board pointers
    'default': static([('F', ARROW, 'fill')], (6, 3)),
    'pointer': static([('F', HAND, 'fill')], (14, 3)),
    'text': static([('L', IBEAM, 'fill')], (16, 16)),
    'wait': animated(_wait, (16, 16)),
    'progress': animated(_progress, (6, 3)),
    'move': static([('F', MOVE, 'fill')], (16, 16)),
    'ew-resize': static([('F', EW, 'fill')], (16, 16)),
    'ns-resize': static([('F', NS, 'fill')], (16, 16)),
    'nwse-resize': static([('F', NWSE, 'fill')], (16, 16)),
    'nesw-resize': static([('G', MIRROR_X, [('F', NWSE, 'fill')])], (16, 16)),
    'crosshair': static([('L', CROSS, 'fill'), ('P', ci(16, 16, 1.8), BLUE)], (16, 16)),
    'not-allowed': static([('L', NO, RED)], (16, 16)),
    'copy': static([('F', ARROW, 'fill')] + badge(GREEN, [('P', PLUS_GLYPH, WHITE)]), (6, 3)),
    # arrow + badge family
    'alias': static([('F', ARROW, 'fill')] + badge('fill', [('S', LINK, 'edge', 1.5)]), (6, 3)),
    'help': static([('F', ARROW, 'fill')] + badge(ACCENT, [('S', QUESTION, WHITE, 1.5),
                                                              ('P', ci(25, 28.3, 0.85), WHITE)]), (6, 3)),
    'context-menu': static([('F', ARROW, 'fill'),
                            ('P', rr(18.5, 18.5, 13, 13, 3.4), 'edge'),
                            ('P', rr(19.9, 19.9, 10.2, 10.2, 2.1), 'fill'),
                            ('S', MENU_LINES, 'edge', 1.3)], (6, 3)),
    'no-drop': static([('F', ARROW, 'fill')] + badge(RED, [('S', NO_GLYPH, WHITE, 1.9)]), (6, 3)),
    # hands
    'grab': static([('F', OPEN_HAND, 'fill')], (15, 15)),
    'grabbing': static([('F', FIST, 'fill')], (15, 18)),
    'dnd-no-drop': static([('F', FIST, 'fill')] + badge(RED, [('S', NO_GLYPH, WHITE, 1.9)]), (15, 18)),
    # precise / text
    'cell': static([('F', CELL, 'fill')], (16, 16)),
    'all-scroll': static(ALL_SCROLL, (16, 16)),
    'vertical-text': static([('G', 'rotate(90 16 16)', [('L', IBEAM, 'fill')])], (16, 16)),
    'zoom-in': static(zoom('M10 13.5h7M13.5 10v7'), (13.5, 13.5)),
    'zoom-out': static(zoom('M10 13.5h7'), (13.5, 13.5)),
    'col-resize': static(COL_RESIZE, (16, 16)),
    'row-resize': static([('G', 'rotate(90 16 16)', COL_RESIZE)], (16, 16)),
    # single arrows and legacy pointers
    'up-arrow': static([('F', UP_ARROW, 'fill')], (16, 3)),
    'right-arrow': static([('G', 'rotate(90 16 16)', [('F', UP_ARROW, 'fill')])], (29, 16)),
    'down-arrow': static([('G', 'rotate(180 16 16)', [('F', UP_ARROW, 'fill')])], (16, 29)),
    'left-arrow': static([('G', 'rotate(-90 16 16)', [('F', UP_ARROW, 'fill')])], (3, 16)),
    'center_ptr': static([('F', CENTER_PTR, 'fill')], (16, 3)),
    'right_ptr': static([('G', MIRROR_X, [('F', ARROW, 'fill')])], (26, 3)),
    'color-picker': static([('G', 'rotate(45 16 16)', DROPPER)], hs(rotate_point(*DROPPER_TIP, 45))),
    'pencil': static([('G', 'rotate(45 16 16)', PENCIL)], hs(rotate_point(*PENCIL_TIP, 45))),
    'x-cursor': static([('F', X_SHAPE, 'fill')], (16, 16)),
    'pirate': static([('F', X_SHAPE, RED)], (16, 16)),
}

# Names that reuse a drawing: CSS / cursor-shape-v1 names, X11 cursor-font names, Qt and GTK
# fallbacks and the legacy Xcursor hash names (same set as Breeze plus the extra names in KWin's
# CursorShape::alternatives table and Adwaita). Every alias points straight at a drawing.
ALIASES = {
    'default': ['left_ptr', 'arrow', 'top_left_arrow', 'wayland-cursor'],
    'pointer': ['hand', 'hand1', 'hand2', 'pointing_hand',
                '9d800788f1b08800ae810202380a0822', 'e29285e634086352946a0e7090d73106'],
    'text': ['xterm', 'ibeam'],
    'wait': ['watch', 'clock'],
    'progress': ['left_ptr_watch', 'half-busy', '00000000000000020006000e7e9ffc3f',
                 '08e8e1c95fe2fc01f976f1e063a24ccd', '3ecb610c1bf2410f44200f48c40d3599'],
    'move': ['fleur', 'size_all', 'all-resize'],
    'all-scroll': ['all_scroll'],
    'ew-resize': ['e-resize', 'w-resize', 'size_hor', 'size-hor', 'h_double_arrow', 'sb_h_double_arrow',
                  'left_side', 'right_side', '028006030e0e7ebffc7f7070c0600140'],
    'ns-resize': ['n-resize', 's-resize', 'size_ver', 'size-ver', 'v_double_arrow', 'sb_v_double_arrow',
                  'double_arrow', 'top_side', 'bottom_side', '00008160000006810000408080010102'],
    'nwse-resize': ['nw-resize', 'se-resize', 'size_fdiag', 'size-fdiag', 'bd_double_arrow',
                    'top_left_corner', 'bottom_right_corner', 'c7088f0f3e6c8088236ef8e1e3e70000'],
    'nesw-resize': ['ne-resize', 'sw-resize', 'size_bdiag', 'size-bdiag', 'fd_double_arrow',
                    'top_right_corner', 'bottom_left_corner', 'fcf1c3c7cd4491d801f1e1c78f100000'],
    'col-resize': ['split_h', '14fef782d02440884392942c11205230'],
    'row-resize': ['split_v', '2870a09082c103050810ffdffffe0204'],
    'crosshair': ['cross', 'tcross', 'cross_reverse', 'cross-reverse', 'diamond_cross', 'diamond-cross'],
    'not-allowed': ['circle', 'crossed_circle', 'forbidden', '03b6e0fcb3499374a867c041f52298f0'],
    'copy': ['dnd-copy', '1081e37283d90000800003c07f3ef6bf', '6407b0e94181790501fd1e167b474872',
             'b66166c04f8c3109214a4fbd64a50fc8'],
    'alias': ['link', 'dnd-link', '3085a0e285430894940527032f8b26df', '640fb0e74195791501fd1ed57b41487f',
              'a2a266d0498c3104214a47bd64ab0fc8'],
    'help': ['whats_this', 'left_ptr_help', 'question_arrow', '5c6cd98b3f3ebcb1f9c7f1c204630408',
             'd9ce0ab605698f320427677b458ad60b'],
    'context-menu': ['dnd-ask'],
    'grab': ['openhand', '9141b49c8149039304290b508d208c40'],
    'grabbing': ['closedhand', 'dnd-move', 'dnd-none', 'fcf21c00b30f7e3f83fe0dfd12e71cff',
                 '05e88622050804100c20044008402080', '4498f0e0c1937ffe01fd06f973665830',
                 '9081237383d90e509aa00f00170e968f'],
    'cell': ['plus'],
    'up-arrow': ['up_arrow', 'sb_up_arrow', 'based_arrow_up'],
    'down-arrow': ['down_arrow', 'sb_down_arrow', 'based_arrow_down'],
    'left-arrow': ['left_arrow', 'sb_left_arrow'],
    'right-arrow': ['right_arrow', 'sb_right_arrow'],
    'center_ptr': ['centre_ptr'],
    'pencil': ['draft', 'draft_large', 'draft_small'],
    'x-cursor': ['X_cursor'],
}

# The twelve pointers drawn on the board, in board order (for contact sheets).
BOARD_ORDER = ['default', 'pointer', 'text', 'wait', 'progress', 'move',
               'ew-resize', 'ns-resize', 'nwse-resize', 'crosshair', 'not-allowed', 'copy']
