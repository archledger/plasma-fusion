# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""File types, places and devices: a port of renderVals() in design/boards/FileIcons.dc.html.

All drawings use the board's 64-unit grid. Layers are drawn in the board's order:
f1, f2, f3, f4, s1 (stroke), f5, f6, then the tag text and the large 'Aa' text.
"""
from svgkit import Svg, ci, el, gear, rr
from textoutline import text_in_box

K68 = 64 / 68  # the board draws these at 68 px; a few CSS values are in those pixels

# ---------------------------------------------------------------- file types
PAGE = 'M14 4h26l12 12v42a4 4 0 0 1-4 4H14a4 4 0 0 1-4-4V8a4 4 0 0 1 4-4z'
PAGE_LIP = 'M10 55h42v3a4 4 0 0 1-4 4H14a4 4 0 0 1-4-4z'
FOLD = 'M40 4v8a4 4 0 0 0 4 4h8z'
TAG_BOX = (6, 38, 34, 15)
# Light pages and trash cans vanish on white views (the light colour scheme's View background is
# #ffffff). A thin, faint rim keeps them separate on light backgrounds; on the boards' dark
# backgrounds it is barely visible (the Icons board: "lip and edge keep tiles separate on both").
RIM = dict(color='#1b2031', width=1, opacity=0.2)

# Category -> tag colour and glyph layers (from the board's files[] entries).
FILE_KINDS = {
    'doc': dict(c='#2f6fdf', s1='M18 16h16M18 22h24M18 28h20'),
    'sheet': dict(c='#2d8a4a', s1='M18 13h26v20H18zM18 20h26M18 26.5h26M27 13v20M35.5 13v20', sw=2),
    'slides': dict(c='#d0612b', s1='M18 13h26v18H18zM24 27v-5M30 27v-9M36 27v-3', sw=2.2),
    'pdf': dict(c='#d9434b', s1='M18 16h24M18 22h24M18 28h14'),
    'image': dict(c='#9b3fb5', f4='M17 33l8-10 6 7 4-4 9 7z' + ci(38, 16, 3.5)),
    'audio': dict(c='#d6457a', f4='M26 14l14-3v4l-14 3zM26 16h3v13h-3zM37 12h3v14h-3z' + el(24, 29.5, 4, 3.2) + el(35, 26.5, 4, 3.2)),
    'video': dict(c='#c2410c', f4='M25 13l14 9-14 9z'),
    'archive': dict(c='#a8702c', s1='M31 5v3M31 11v3M31 17v3M31 23v3', sw=3.2, f4=rr(27.5, 27, 7, 8, 1.5)),
    'code': dict(c='#7b5cd6', s1='M24 15l-6 7 6 7M38 15l6 7-6 7M33 13l-4 18', sw=2.6),
    'text': dict(c='#5b6478', s1='M18 15h24M18 21h24M18 27h24M18 33h12', sw=2.2),
    'font': dict(c='#1f9e8f', t2='Aa'),
    'disk': dict(c='#475069', s1=ci(31, 22, 10) + ci(31, 22, 2.5), sw=2.4),
    # derived kinds (not on the board), same construction
    'exec': dict(c='#475069', f4=gear(31, 22, 10.5, 8, 8) + ci(31, 22, 3.6), evenodd4=True),
    'generic': dict(c='#6f7892'),
    'blank': dict(c=None),
}
# Board glyph colours: glyph strokes/fills use the tag colour, except the plain page.


def file_svg(kind, label):
    k = FILE_KINDS[kind]
    c = k['c']
    s = Svg(64)
    s.fill(PAGE, '#f6f7fb')
    s.fill(PAGE_LIP, '#dfe3ec')
    s.fill(FOLD, '#cfd5e2')
    s.stroke(PAGE, RIM['color'], RIM['width'], opacity=RIM['opacity'])
    s.fill(k.get('f4'), c, evenodd=k.get('evenodd4', False))
    s.stroke(k.get('s1'), c, k.get('sw', 2.6))
    if c and label is not None:
        s.fill(rr(*TAG_BOX, 4), c)
        if label:
            s.fill(text_in_box(label, 'manrope-800', 9, TAG_BOX, 0.04, max_width=TAG_BOX[2] - 4), '#ffffff')
    if k.get('t2'):
        # <span style="left:0;top:9px;width:66px;height:28px;font-size:18px"> in a 68 px icon
        s.fill(text_in_box(k['t2'], 'spacegrotesk-700', 18 * K68, (0, 9 * K68, 66 * K68, 28 * K68)), c)
    return s.render()


# ---------------------------------------------------------------- places
F_BACK = 'M6 15a5 5 0 0 1 5-5h13.5l6 6H53a5 5 0 0 1 5 5v6H6z'
F_SHEEN = 'M12 21h40a6 6 0 0 1 6 6v5H6v-5a6 6 0 0 1 6-6z'
PLACE_GLYPHS = {
    'folder': {},
    'home': dict(s1='M24 42l8-7 8 7M26.5 40v8h11v-8'),
    'desktop': dict(s1=rr(23, 33, 18, 12, 2) + 'M28.5 49h7M32 45v4'),
    'documents': dict(s1='M25 35h14M25 40.5h14M25 46h9'),
    'downloads': dict(s1='M32 33v11M27 39.5l5 5 5-5M25 49h14'),
    'music': dict(f5='M29 35l9-2v3l-9 2zM29 36h2.4v9h-2.4zM35.6 34h2.4v9h-2.4z' + el(28, 45.5, 3, 2.4) + el(34.6, 43.5, 3, 2.4)),
    'pictures': dict(f5='M24 48l6-7 4 4.5 3-3 6 5.5z' + ci(38, 36, 2.5)),
    'videos': dict(f5='M28 34l10 6.5-10 6.5z'),
    'projects': dict(s1='M28 35l-5 5.5 5 5.5M36 35l5 5.5-5 5.5'),
    'network': dict(s1='M32 35v5M24 47v-3.5h16V47M32 40v3.5', f5=ci(32, 34, 2.6) + ci(24, 48, 2.6) + ci(40, 48, 2.6)),
    # derived symbols in the same style
    'templates': dict(s1=rr(25, 33, 14, 16, 2) + 'M29 38h6M29 42.5h6'),
    'public': dict(s1=ci(32, 36.5, 3.2) + 'M25 49a7 7 0 0 1 14 0'),
    'recent': dict(s1=ci(32, 41, 8) + 'M32 36.5V41l3 2'),
    'cloud': dict(s1='M27 47h11a4.5 4.5 0 0 0 .6-9 6 6 0 0 0-11.4-1.3A5 5 0 0 0 27 47z'),
    'git': dict(s1=ci(26, 36, 2.6) + ci(26, 47, 2.6) + ci(38, 38, 2.6) + 'M26 38.6v5.8M38 40.6c0 3-4 4-9.6 5.2'),
    'games': dict(s1='M27 36h10a5 5 0 0 1 5 5v1a5 5 0 0 1-5 5H27a5 5 0 0 1-5-5v-1a5 5 0 0 1 5-5zM27 39.5v5M24.5 42h5', f5=ci(36, 41, 1.4) + ci(39, 43.5, 1.4)),
    'locked': dict(s1=rr(25, 40, 14, 9, 2) + 'M28 40v-2.5a4 4 0 0 1 8 0V40'),
    'unlocked': dict(s1=rr(25, 40, 14, 9, 2) + 'M28 40v-2.5a4 4 0 0 1 8 0'),
    'favorites': dict(s1='M32 33.5l2.3 4.7 5.2.7-3.8 3.6.9 5.1-4.6-2.4-4.6 2.4.9-5.1-3.8-3.6 5.2-.7z'),
    'important': dict(s1='M32 34v8M32 47h.01', sw=3.2),
    'root': dict(s1='M26 38h12M26 44h12M29 35v12M35 35v12'),
    'temp': dict(s1='M27 34h10M27 49h10M28 34v3.5a4 4 0 0 0 1.5 3l2.5 2 2.5-2a4 4 0 0 0 1.5-3V34M28 49v-3.5a4 4 0 0 1 1.5-3l2.5-2'),
    'mail': dict(s1=rr(23, 35, 18, 13, 2) + 'M24 36.5l8 6 8-6'),
    'notes': dict(s1='M26 34h9l4 4v11H26zM29 41h7M29 45h5'),
    'bookmark': dict(s1='M27 34h10v14l-5-4-5 4z'),
    'books': dict(s1='M25 35h6v13h-6zM33 35h6v13h-6zM25 39.5h6M33 39.5h6'),
    'activities': dict(s1=ci(32, 41.5, 2) + ci(32, 41.5, 7)),
}

# Folder colours offered by Dolphin's "Assign folder color" (names as in Breeze).
FOLDER_TINTS = {
    None: ('#2b5db5', '#4a88ea', '#d6e6ff'),
    'blue': ('#2b5db5', '#4a88ea', '#d6e6ff'),
    'red': ('#a8303a', '#e5484d', '#ffd9da'),
    'orange': ('#b8552a', '#e8743b', '#ffe0cc'),
    'yellow': ('#c99a22', '#f5c84c', '#fff4d1'),
    'green': ('#2a7e44', '#3aa65b', '#d4f2dd'),
    'cyan': ('#15756a', '#1f9e8f', '#cdf1eb'),
    'violet': ('#5a40a8', '#7b5cd6', '#e6ddff'),
    'magenta': ('#a8325d', '#d6457a', '#ffd6e5'),
    'brown': ('#7a5020', '#a8702c', '#f3e0c8'),
    'grey': ('#414859', '#6f7892', '#e2e5ee'),
    'black': ('#131726', '#2c3348', '#c9cfdc'),
}


def folder_svg(glyph='folder', tint=None):
    back, front, fg = FOLDER_TINTS[tint]
    g = PLACE_GLYPHS[glyph]
    s = Svg(64)
    s.fill(F_BACK, back)
    s.fill(rr(6, 21, 52, 39, 6), back)
    s.fill(rr(6, 21, 52, 36, 6), front)
    s.fill(F_SHEEN, 'rgba(255,255,255,0.1)')
    s.stroke(g.get('s1'), fg, g.get('sw', 2.6))
    s.fill(g.get('f5'), fg)
    return s.render()


TRASH_BODY = 'M17 19h30l-2.6 35a4 4 0 0 1-4 3.7H23.6a4 4 0 0 1-4-3.7z'
TRASH_BASE = 'M18.6 50h26.8l-.3 4a4 4 0 0 1-4 3.7H23.6a4 4 0 0 1-4-3.7z'


def trash_svg(full):
    s = Svg(64)
    if full:
        s.fill('M19 21l5-13 10 3-4 11z', '#f5c84c')
        s.fill(TRASH_BODY, '#e8ebf4')
        s.fill(TRASH_BASE, '#c9cfdc')
        s.stroke(TRASH_BODY, RIM['color'], RIM['width'], opacity=RIM['opacity'])
        s.fill('M31 20l4-12 9 4-3 9z', '#8ab8ff')
    else:
        s.fill(rr(14, 10, 36, 7, 3), '#cfd5e4')
        s.fill(TRASH_BODY, '#e8ebf4')
        s.fill(TRASH_BASE, '#c9cfdc')
        s.stroke(rr(14, 10, 36, 7, 3), RIM['color'], RIM['width'], opacity=RIM['opacity'])
        s.stroke(TRASH_BODY, RIM['color'], RIM['width'], opacity=RIM['opacity'])
    s.stroke('M26 25v23M32 25v23M38 25v23', '#b3bacb', 2.4)
    return s.render()


# ---------------------------------------------------------------- devices
def _devices():
    kb_keys = ''.join(rr(x, 23, 5, 5, 1.2) for x in [10, 18, 26, 34, 42, 50]) + \
        ''.join(rr(x, 31, 5, 5, 1.2) for x in [13, 21, 29, 37, 45])
    d = {
        'drive': dict(f1=rr(6, 18, 52, 30, 7), c1='#3a4258', f2=rr(6, 18, 52, 27, 7), c2='#5b6478',
                      f3=rr(10, 22, 44, 9, 4), c3='rgba(255,255,255,0.1)', s1='M14 37h18', sc='#9aa3ba', sw=2.6,
                      f5=ci(48, 37, 2.6), c5='#3cc4b0'),
        'usb': dict(f1=rr(24, 4, 16, 16, 2), c1='#cfd5e4', f2='M28 8h3v4h-3zM33 8h3v4h-3z', c2='#8f98b3',
                    f3=rr(17, 17, 30, 43, 7), c3='#2b5db5', f4=rr(17, 17, 30, 40, 7), c4='#3f7fe0',
                    s1='M32 29v18M27 35l5-5 5 5', sc='#d6e6ff', sw=2.6),
        'phone': dict(f1=rr(18, 4, 28, 56, 7), c1='#141827', f2=rr(21, 9, 22, 44, 4), c2='#2e3d73',
                      f3='M21 40l7-6 5 4 10-9v20a4 4 0 0 1-4 4H25a4 4 0 0 1-4-4z', c3='#5a7fd6', f4=ci(35, 18, 4), c4='#f2a65a',
                      f5=rr(28, 55, 8, 2, 1), c5='#5d6680'),
        'sdcard': dict(f1='M18 6h20l8 8v43a3 3 0 0 1-3 3H21a3 3 0 0 1-3-3z', c1='#c67a24',
                       f2='M18 6h20l8 8v40a3 3 0 0 1-3 3H21a3 3 0 0 1-3-3z', c2='#f2a65a',
                       f3='M22 10h3v8h-3zM27 10h3v8h-3zM32 10h3v8h-3z', c3='#fff3dc', f4=rr(22, 30, 20, 17, 3), c4='#fff3dc',
                       t='SD', box=(22, 30, 20, 17), ts=10, tc='#a35a14'),
        'optical': dict(f1=ci(32, 32, 26), c1='#cfd5e4', f2='M32 6a26 26 0 0 1 26 26H44a12 12 0 0 0-12-12z', c2='rgba(91,157,255,0.35)',
                        f3='M6 32a26 26 0 0 1 8-18.8l9.4 10A12 12 0 0 0 20 32z', c3='rgba(242,166,90,0.35)',
                        f4=ci(32, 32, 8), c4='#8f98b3', f5=ci(32, 32, 3.5), c5='#171c33'),
        'server': dict(f1=rr(14, 4, 36, 50, 6), c1='#323950', f2=rr(14, 4, 36, 47, 6), c2='#475069',
                       f3=rr(19, 10, 26, 8, 2) + rr(19, 21, 26, 8, 2) + rr(19, 32, 26, 8, 2), c3='#2c3348',
                       f4=ci(40, 14, 1.6) + ci(40, 25, 1.6), c4='#3cc4b0', f5=ci(40, 36, 1.6), c5='#f2a65a',
                       s1='M32 54v5M20 59h24', sc='#8f98b3', sw=2.4),
        'printer': dict(f1=rr(18, 6, 28, 16, 2), c1='#f6f7fb', f2=rr(8, 20, 48, 26, 7), c2='#414859', f3=rr(8, 20, 48, 23, 7), c3='#5b6478',
                        f4=rr(18, 36, 28, 22, 2), c4='#f6f7fb', s1='M23 44h18M23 50h12', sc='#b3bacb', sw=2.2,
                        f5=ci(48, 28, 2.2), c5='#3cc4b0'),
        'headphones': dict(f1=rr(9, 34, 13, 22, 5), c1='#2f6fdf', f2=rr(42, 34, 13, 22, 5), c2='#2f6fdf',
                           f3=rr(12, 37, 5, 15, 2.5) + rr(45, 37, 5, 15, 2.5), c3='rgba(255,255,255,0.2)',
                           s1='M15.5 34v-3a16.5 16.5 0 0 1 33 0v3', sc='#5b6478', sw=5),
        'keyboard': dict(f1=rr(4, 18, 56, 30, 6), c1='#3a4258', f2=rr(4, 18, 56, 27, 6), c2='#5b6478',
                         f3=kb_keys, c3='#d7dbe6', f4=rr(18, 38, 28, 4, 1.5), c4='#d7dbe6'),
        'mouse': dict(f1=rr(19, 8, 26, 48, 13), c1='#3a4258', f2=rr(19, 8, 26, 45, 13), c2='#5b6478', s1='M32 9v14', sc='#2c3348', sw=2,
                      f5=rr(30.5, 13, 3, 7, 1.5), c5='#3cc4b0'),
        'display': dict(f1=rr(4, 8, 56, 38, 5), c1='#141827', f2=rr(8, 12, 48, 30, 2), c2='#2e3d73',
                        f3='M8 34l12-10 9 7 11-10 16 12v7a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2z', c3='#5a7fd6',
                        f4='M27 46h10l2 8H25z', c4='#5b6478', f5=rr(20, 54, 24, 4, 2), c5='#5b6478'),
        'camera': dict(f1=rr(6, 18, 52, 36, 8), c1='#3a4258', f2='M22 18l4-6h12l4 6z' + rr(6, 18, 52, 33, 8), c2='#5b6478',
                       f3=ci(32, 35, 11), c3='#1b2031', f4=ci(32, 35, 6.5), c4='#3a7bd5', f5=ci(29.5, 32.5, 2) + ci(49, 25, 2), c5='#f2a65a'),
        # ---- derived in the same construction (not drawn on the board)
        'laptop': dict(f1=rr(10, 10, 44, 32, 4), c1='#141827', f2=rr(13, 13, 38, 26, 2), c2='#2e3d73',
                       f3='M13 32l10-8 8 6 8-7 12 9v5a2 2 0 0 1-2 2H15a2 2 0 0 1-2-2z', c3='#5a7fd6',
                       f4='M4 42h56v4a6 6 0 0 1-6 6H10a6 6 0 0 1-6-6z', c4='#3a4258',
                       f5='M4 42h56v1.5a6 6 0 0 1-6 6H10a6 6 0 0 1-6-6z', c5='#5b6478', f6=rr(26, 42, 12, 2.5, 1.2), c6='#3a4258'),
        'speaker': dict(f1=rr(15, 5, 34, 54, 7), c1='#3a4258', f2=rr(15, 5, 34, 51, 7), c2='#5b6478',
                        f3=ci(32, 17, 5) + ci(32, 37, 12), c3='#2c3348', f4=ci(32, 37, 5.5), c4='#475069',
                        f5=ci(32, 17, 1.8), c5='#3cc4b0', f6=ci(32, 37, 2), c6='#f2a65a'),
        'microphone': dict(f1=rr(23, 5, 18, 32, 9), c1='#3a4258', f2=rr(23, 5, 18, 30, 9), c2='#5b6478',
                           f3='M23 17h18v3H23zM23 24h18v3H23z', c3='#475069',
                           s1='M15 30a17 17 0 0 0 34 0M32 47v9M23 58h18', sc='#8f98b3', sw=3),
        'webcam': dict(f1=ci(32, 27, 20), c1='#3a4258', f2=ci(32, 25.5, 18.5), c2='#5b6478',
                       f3=ci(32, 26, 10), c3='#1b2031', f4=ci(32, 26, 6), c4='#3a7bd5',
                       f5=ci(29.8, 23.8, 1.8), c5='#f2a65a', f6='M22 50h20l3 8H19z' + ci(32, 11, 1.4), c6='#3a4258'),
        'gamepad': dict(f1='M19 17h26a12 12 0 0 1 11.6 9l3.6 14.4A7.2 7.2 0 0 1 48 46.6L43 41H21l-5 5.6A7.2 7.2 0 0 1 3.8 40.4L7.4 26A12 12 0 0 1 19 17z', c1='#3a4258',
                        f2='M19 17h26a12 12 0 0 1 11.6 9l3.2 12.6A7.2 7.2 0 0 1 48 44L43 38.5H21L16 44A7.2 7.2 0 0 1 4.2 38.6L7.4 26A12 12 0 0 1 19 17z', c2='#5b6478',
                        f3='M17 24h4v5h5v4h-5v5h-4v-5h-5v-4h5z', c3='#d7dbe6', f4=ci(43, 27, 2.6), c4='#3cc4b0', f5=ci(49, 32.5, 2.6), c5='#f2a65a'),
        'touchpad': dict(f1=rr(7, 10, 50, 44, 7), c1='#3a4258', f2=rr(7, 10, 50, 41, 7), c2='#5b6478',
                         f3=rr(12, 15, 40, 24, 4), c3='#475069', f4=rr(12, 42, 19, 4, 2) + rr(33, 42, 19, 4, 2), c4='#d7dbe6'),
        'tablet': dict(f1=rr(10, 6, 44, 54, 7), c1='#141827', f2=rr(14, 11, 36, 42, 3), c2='#2e3d73',
                       f3='M14 42l9-8 7 5 9-8 11 9v10a3 3 0 0 1-3 3H17a3 3 0 0 1-3-3z', c3='#5a7fd6', f4=ci(40, 20, 4), c4='#f2a65a',
                       f5=rr(28, 55.5, 8, 2, 1), c5='#5d6680'),
        'scanner': dict(f1=rr(6, 14, 52, 9, 3), c1='#cfd5e4', f2=rr(6, 25, 52, 27, 7), c2='#414859', f3=rr(6, 25, 52, 24, 7), c3='#5b6478',
                        f4=rr(11, 30, 42, 5, 2), c4='#2c3348', s1='M14 32.5h36', sc='#3cc4b0', sw=2, f5=ci(48, 43, 2.2), c5='#3cc4b0'),
    }
    return d


DEVICES = _devices()


def device_svg(key):
    i = DEVICES[key]
    s = Svg(64)
    for n in ('1', '2', '3', '4'):
        s.fill(i.get('f' + n), i.get('c' + n))
    s.stroke(i.get('s1'), i.get('sc'), i.get('sw'))
    for n in ('5', '6'):
        s.fill(i.get('f' + n), i.get('c' + n))
    if i.get('t'):
        s.fill(text_in_box(i['t'], 'manrope-800', i['ts'], i['box'], 0.04), i['tc'])
    return s.render()


# ------------------------------------------------------------------ emblems
# emblem-symbolic-link (BACKLOG M3/S6): the badge Dolphin and the desktop draw on the bottom-left corner
# of a link, a desktop shortcut made by "Add to Desktop" or a drag from the launcher. Derived (no board
# draws it): a white rounded badge with a faint ink edge and a curved "shortcut" arrow in the accent
# colour (ColorScheme-Highlight, so it follows the accent). Drawn on the pixel grid of each size.
EMBLEM_LINK = {
    # size: (badge inset, badge radius, edge width, arrow path, stroke width, arrow head polygon)
    16: (1, 4, 1, 'M5 11.6V10a3.6 3.6 0 0 1 3.6-3.6H9.8', 1.75, 'M9.2 3.6L12.5 6.4 9.2 9.2Z'),
    22: (1, 5.5, 1, 'M6.8 16V13.6a5 5 0 0 1 5-5h1.7', 2.25, 'M12.6 4.8L17 8.6 12.6 12.4Z'),
}


def emblem_link_svg(size):
    """The link emblem at 16 or 22 px (the scalable file is the 16 px drawing)."""
    inset, radius, edge, arrow, width, head = EMBLEM_LINK[size]
    s = Svg(size, style='.ColorScheme-Highlight{color:#2f6fdf}')
    box = size - 2 * inset
    s.fill(rr(inset, inset, box, box, radius), '#ffffff')
    s.fill(rr(inset, inset, box, box, radius) + rr(inset + edge, inset + edge, box - 2 * edge, box - 2 * edge,
                                                   radius - edge),
           'rgba(20,24,39,0.22)', evenodd=True)
    s.stroke(arrow, 'currentColor', width, cls='ColorScheme-Highlight', cap='round', join='round')
    s.fill(head, 'currentColor', cls='ColorScheme-Highlight')
    return s.render()
