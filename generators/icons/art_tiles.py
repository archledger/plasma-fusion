# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""App tiles: a port of renderVals() in design/boards/AppIcon.dc.html.

Tile 64 x 64, radius 15, 4-unit lip, 9 % sheen, 1-unit light edge, glyph layers g1, g2, s1, g3.
The calendar's SEP / 28 labels are drawn as outlines (see textoutline.py).
"""
from svgkit import Svg, ci, el, gear, rr
from textoutline import text_in_box


def _keys():
    keys = []
    for row, y in enumerate([27, 36, 45]):
        for col, x in enumerate([17, 28, 39]):
            if not (row == 2 and col == 2):
                keys.append(rr(x, y, 8, 7, 2))
    return ''.join(keys)


TILES = {
    'files': dict(label='Files', base='#3f7fe0', lip='#2b5db5',
                  g1='M13 19a4 4 0 0 1 4-4h9l4 4h17a4 4 0 0 1 4 4v19H13z', c1='#bcd4ff',
                  g2=rr(13, 24, 38, 22, 4), c2='#ffffff',
                  s1='M20 39h10', sc='#8fb4f5', sw=3),
    'browser': dict(label='Browser', base='#e8743b', lip='#b8552a',
                    g1=ci(32, 30, 17), c1='#ffffff',
                    s1='M15 30h34M18 21h28M18 39h28M32 13c7 6 7 28 0 34M32 13c-7 6-7 28 0 34', sc='#e8743b', sw=2.4),
    'terminal': dict(label='Terminal', base='#262c42', lip='#131726',
                     g1=rr(30, 38, 14, 4, 2), c1='#e8ebf4',
                     g2=ci(17, 13, 2) + ci(23, 13, 2) + ci(29, 13, 2), c2='#5d6680',
                     s1='M18 25l8 7-8 7', sc='#3cc4b0', sw=4),
    'mail': dict(label='Mail', base='#1f9e8f', lip='#15756a',
                 g1=rr(12, 17, 40, 28, 4), c1='#ffffff',
                 s1='M14.5 20l17.5 13 17.5-13', sc='#1f9e8f', sw=3,
                 g3=ci(49, 17, 6.5), c3='#f2a65a'),
    'code': dict(label='Code', base='#7b5cd6', lip='#5a40a8',
                 g1='M35 15h4.5l-10 30H25z', c1='#d9ccff',
                 s1='M22 20l-10 10 10 10M42 20l10 10-10 10', sc='#ffffff', sw=4.5),
    'music': dict(label='Music', base='#d6457a', lip='#a8325d',
                  g1='M26 19l20-5v5l-20 5zM26 21h4v22h-4zM42 15h4v23h-4z', c1='#ffffff',
                  g2=el(24, 43, 6, 5) + el(40, 38, 6, 5), c2='#ffffff'),
    'photos': dict(label='Photos', base='#3aa65b', lip='#2a7e44',
                   g1=rr(12, 14, 40, 32, 4), c1='#ffffff',
                   g2='M16 42l10-12 7 8 5-5 10 9z', c2='#3aa65b',
                   g3=ci(41, 23, 4), c3='#f2a65a'),
    'settings': dict(label='Settings', base='#5b6478', lip='#414859',
                     g1=gear(32, 30, 18, 13.5, 8), c1='#eef0f6',
                     g2=ci(32, 30, 6), c2='#5b6478'),
    'calendar': dict(label='Calendar', base='#f6f4ef', lip='#d6d0c2',
                     g1='M15 0h34a15 15 0 0 1 15 15v6H0V15A15 15 0 0 1 15 0z', c1='#e5484d',
                     t2='SEP', t2y=0, t2h=21, t2s=9, t2c='#ffffff',
                     t='28', ty=21, th=39, ts=26, tc='#1b2031'),
    'notes': dict(label='Notes', base='#f5c84c', lip='#c99a22',
                  g1='M18 11h20l9 9v27a3 3 0 0 1-3 3H18a3 3 0 0 1-3-3V14a3 3 0 0 1 3-3z', c1='#fffaf0',
                  g2='M38 11v6a3 3 0 0 0 3 3h6z', c2='#f0dca8',
                  s1='M21 28h20M21 34h20M21 40h12', sc='#d4b25a', sw=2.5),
    'calculator': dict(label='Calculator', base='#2c3348', lip='#1a1f2e',
                       g1=rr(17, 12, 30, 11, 3), c1='#9fe0cf',
                       g2=_keys(), c2='#e8ebf4',
                       g3=rr(39, 45, 8, 7, 2), c3='#f2a65a'),
    'software': dict(label='Software', base='#2f6fdf', lip='#2152ad',
                     g1='M16 22h32l-2.6 21.2a4 4 0 0 1-4 3.5H22.6a4 4 0 0 1-4-3.5z', c1='#ffffff',
                     s1='M25 22v-3a7 7 0 0 1 14 0v3', sc='#ffffff', sw=3.5,
                     g3='M32 27l2.2 5 5 2.2-5 2.2-2.2 5-2.2-5-5-2.2 5-2.2z', c3='#2f6fdf'),
    'videos': dict(label='Videos', base='#c2410c', lip='#922f08',
                   g1=rr(12, 15, 40, 30, 5), c1='#ffffff',
                   g2='M28 23.5l12 6.5-12 6.5z', c2='#c2410c'),
    'chat': dict(label='Chat', base='#16847a', lip='#0f6159',
                 g1='M25 12h22a4 4 0 0 1 4 4v12a4 4 0 0 1-4 4h-1v6l-7-6H25a4 4 0 0 1-4-4V16a4 4 0 0 1 4-4z', c1='#8fdccc',
                 g2='M15 22h22a4 4 0 0 1 4 4v12a4 4 0 0 1-4 4H24l-7 6v-6h-2a4 4 0 0 1-4-4V26a4 4 0 0 1 4-4z', c2='#ffffff',
                 g3=ci(19, 32, 2.2) + ci(26, 32, 2.2) + ci(33, 32, 2.2), c3='#16847a'),
    'maps': dict(label='Maps', base='#3f8f5a', lip='#2d6b42',
                 g1='M12 18l13-5 14 5 13-5v30l-13 5-14-5-13 5z', c1='#dff1d3',
                 g2='M25 13l14 5v30l-14-5z', c2='#bfe0ad',
                 g3='M40 13c-4.7 0-8.5 3.6-8.5 8.2 0 6.3 8.5 14.8 8.5 14.8s8.5-8.5 8.5-14.8c0-4.6-3.8-8.2-8.5-8.2z'
                    + ci(40, 21.5, 3.2), c3='#e5484d'),
    'weather': dict(label='Weather', base='#3a7bd5', lip='#2a5ea8',
                    g1=ci(27, 23, 9), c1='#f7c948',
                    g2='M22 46h21a8 8 0 0 0 1.2-15.9A10.5 10.5 0 0 0 24 31.5a7.3 7.3 0 0 0-2 14.5z', c2='#ffffff',
                    s1='M27 9.5v-2M17.5 13.5l-1.5-1.5M36.5 13.5l1.5-1.5M13.5 23h-2', sc='#f7c948', sw=2.5),
    'monitor': dict(label='System Monitor', base='#475069', lip='#323950',
                    g1=rr(12, 12, 40, 30, 4), c1='#1b2031',
                    g2='M29 42h6v4h-6zM23 46h18a1.5 1.5 0 0 1 0 3H23a1.5 1.5 0 0 1 0-3z', c2='#cfd5e4',
                    s1='M17 33l7-7 6 5 8-10 9 6', sc='#3cc4b0', sw=3,
                    g3=ci(47, 27, 3), c3='#f2a65a'),
    'screenshot': dict(label='Screenshot', base='#9b3fb5', lip='#742d88',
                       g1=ci(32, 30, 8), c1='#f3d4fb',
                       g2=ci(32, 30, 3.5), c2='#9b3fb5',
                       s1='M15 23v-5a3 3 0 0 1 3-3h5M41 15h5a3 3 0 0 1 3 3v5M49 37v5a3 3 0 0 1-3 3h-5M23 45h-5a3 3 0 0 1-3-3v-5',
                       sc='#ffffff', sw=4),
    # Derived tiles (not on the AppIcon board; same construction), added for the apps the icon
    # coverage report (coverage_report.py, BACKLOG C8) found most often without a Fusion tile.
    'archive': dict(label='Archive', base='#b7792f', lip='#8a5a20',
                    g1=rr(11, 14, 42, 12, 3.5), c1='#ffffff',
                    g2=rr(14, 26, 36, 22, 3), c2='#fbe7c6',
                    g3=rr(25, 31, 14, 5, 2.5), c3='#8a5a20'),
    'reader': dict(label='Document Viewer', base='#c93a42', lip='#992a31',
                   g1='M19 11h18l10 10v29a3 3 0 0 1-3 3H19a3 3 0 0 1-3-3V14a3 3 0 0 1 3-3z', c1='#ffffff',
                   g2='M37 11v7a3 3 0 0 0 3 3h7z', c2='#f4c7ca',
                   s1='M22 30h19M22 36h19M22 42h12', sc='#c93a42', sw=2.5),
    'camera': dict(label='Camera', base='#3b4a6b', lip='#28334b',
                   g1=rr(11, 21, 42, 27, 6) + 'M23 22l3.5-6.5h11L41 22z', c1='#e8ebf4',
                   g2=ci(32, 34.5, 10), c2='#28334b',
                   s1='M45 27h.01', sc='#f2a65a', sw=4,
                   g3=ci(32, 34.5, 6.5) + ci(32, 34.5, 3.5), c3='#5b9dff'),
    'fusion': dict(label='Fusion', base='#1b2031', lip='#0c0f1c',
                   g1=ci(32, 22, 11), c1='#5b9dff',
                   g2=ci(24.5, 35, 11), c2='#f2a65a',
                   g3=ci(39.5, 35, 11), c3='#3cc4b0'),
}

# Order of the Applications grid on the Icons board, then the logo.
ORDER = ['files', 'browser', 'terminal', 'mail', 'code', 'music', 'photos', 'settings', 'calendar', 'notes',
         'calculator', 'software', 'videos', 'chat', 'maps', 'weather', 'monitor', 'screenshot', 'fusion']


def tile_svg(key):
    i = TILES[key]
    s = Svg(64)
    s.fill(rr(0, 0, 64, 64, 15), i['lip'])
    s.fill(rr(0, 0, 64, 60, 15), i['base'])
    s.raw('<path d="M15 0h34a15 15 0 0 1 15 15v13H0V15A15 15 0 0 1 15 0z" fill="#ffffff" fill-opacity="0.09"/>')
    s.fill(i.get('g1'), i.get('c1'))
    s.fill(i.get('g2'), i.get('c2'))
    s.stroke(i.get('s1'), i.get('sc'), i.get('sw'))
    s.fill(i.get('g3'), i.get('c3'), evenodd=True)
    s.stroke(rr(0.5, 0.5, 63, 63, 14.5), 'rgba(255,255,255,0.14)', 1, cap='butt', join='miter')
    if i.get('t2'):
        s.fill(text_in_box(i['t2'], 'manrope-800', i['t2s'], (0, i['t2y'], 64, i['t2h']), 0.08), i['t2c'])
    if i.get('t'):
        s.fill(text_in_box(i['t'], 'spacegrotesk-700', i['ts'], (0, i['ty'], 64, i['th'])), i['tc'])
    return s.render()


# The logo mark on its own (Main.dc.html top bar and dock Start button): three translucent discs.
def logo_svg():
    s = Svg(24)
    s.raw('<path d="' + ci(12, 8.5, 5.5) + '" fill="#5b9dff" fill-opacity="0.9"/>')
    s.raw('<path d="' + ci(8, 15, 5.5) + '" fill="#f2a65a" fill-opacity="0.9"/>')
    s.raw('<path d="' + ci(16, 15, 5.5) + '" fill="#3cc4b0" fill-opacity="0.85"/>')
    return s.render()
