# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Symbolic (one-colour) icons on the design's 24-unit grid: 1.75 stroke, round ends.

Glyph paths come from the boards (Icons.dc.html "Symbolic icons", FileIcons.dc.html status
groups, and the line icons used in Main, Launcher, QuickSettings, Popups, Controls, Login and
Boot). Drawings marked "derived" are not on a board and follow the same rules.

Each drawing is a list of layers (d, role, kind, opacity). Roles map to KDE colour-scheme
classes so KIconLoader recolours them, and to GTK's symbolic classes (stroke, warning, error,
success) so GTK keeps strokes and state colours when it recolours -symbolic icons.
"""
import json
import os

from svgkit import Svg, ci, fmt, rr

_OUTLINES = None


def outline_for(d, width):
    """Filled outline of a stroke (outlines.json, made by make_outlines.py)."""
    global _OUTLINES
    if _OUTLINES is None:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'outlines.json')
        with open(path, encoding='utf-8') as f:
            _OUTLINES = json.load(f)
    key = f'{width}|{d}'
    if key not in _OUTLINES:
        raise KeyError(f'no outline for stroke {key!r}: run generators/icons/make_outlines.py')
    return _OUTLINES[key]

STROKE = 1.75

# Default colours written into the SVGs (what non-KDE consumers see). From Colors.dc.html.
PALETTES = {
    'light': {'Text': '#141827', 'Background': '#ffffff', 'Highlight': '#2f6fdf', 'HighlightedText': '#ffffff',
              'PositiveText': '#23703b', 'NeutralText': '#8f4f12', 'NegativeText': '#b3262e', 'Accent': '#2f6fdf'},
    'dark': {'Text': '#e8ebf4', 'Background': '#1b2031', 'Highlight': '#2f6fdf', 'HighlightedText': '#ffffff',
             'PositiveText': '#7fd99c', 'NeutralText': '#f5c08c', 'NegativeText': '#ff8a8f', 'Accent': '#2f6fdf'},
}
# Fixed accents that the boards draw in a set colour (not recoloured by the palette).
FIXED = {
    'light': {'bolt': '#e0a008', 'dot': '#f2a65a'},
    'dark': {'bolt': '#f7c948', 'dot': '#f2a65a'},
}

ROLE_CLASS = {
    'text': ('ColorScheme-Text', None),
    'neutral': ('ColorScheme-NeutralText', 'warning'),
    'negative': ('ColorScheme-NegativeText', 'error'),
    'positive': ('ColorScheme-PositiveText', 'success'),
    'highlight': ('ColorScheme-Highlight', None),
}

# ------------------------------------------------------------------ board glyphs
G = {
    # Icons.dc.html symbolic set
    'search': 'M4 11a7 7 0 1 0 14 0a7 7 0 1 0-14 0M20 20l-4-4',
    'overview': 'M4 5h11a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM8 19h12a1 1 0 0 0 1-1V9',
    'home': 'M4 11l8-7 8 7v9H4zM10 20v-6h4v6',
    'folder': 'M3 7.5A2 2 0 0 1 5 5.5h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
    'document': 'M7 3h7l5 5v13H7zM14 3v5h5M10 13h6M10 17h4',
    'download': 'M12 4v11M7 10l5 5 5-5M5 20h14',
    'trash': 'M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v5M14 11v5',
    'bluetooth': 'M7 7l10 10-5 4V3l5 4L7 17',
    'brightness': 'M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M5 19l1.5-1.5M17.5 6.5L19 5',
    'moon': 'M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z',
    'bell': 'M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0',
    'lock': 'M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2zM8 11V8a4 4 0 0 1 8 0v3',
    'power': 'M12 3v9M6.3 6.3a8 8 0 1 0 11.4 0',
    'settings': ('M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1'
                 'M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1'),
    'clipboard': 'M9 4h6v3H9zM7 5.5H6a1 1 0 0 0-1 1V20a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V6.5a1 1 0 0 0-1-1h-1',
    'phone': 'M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2',
    'screenshot': 'M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3',
    'snap': 'M4 5h16v14H4zM12 5v14M12 12h8',
    'minimize': 'M6 12h12',
    'maximize': 'M8 6h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z',
    'close': 'M7 7l10 10M17 7L7 17',
    # line icons used on the other boards
    'arrow-right': 'M5 12h14M13 6l6 6-6 6',
    'keyboard': 'M3 7h18v10H3zM7 11h.01M11 11h.01M15 11h.01M8 14h8',
    'chevron-down': 'M6 9l6 6 6-6',
    'chevron-up': 'M6 15l6-6 6 6',
    'chevron-right': 'M9 6l6 6-6 6',
    'chevron-left': 'M15 6l-6 6 6 6',
    'check': 'M5 12l4.5 4.5L19 7',
    'document-plain': 'M7 3h7l5 5v13H7zM14 3v5h5',
    'pencil': 'M4 20l4-1 11-11-3-3L5 16zM14 6l3 3',
    'archive': 'M5 7h14v13H5zM3 4h18v3H3zM10 11h4',
    'meta': 'M5 5h14v14H5zM9 9h6v6H9z',
    'image': 'M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM7 10a2 2 0 1 0 4 0a2 2 0 1 0-4 0M21 15l-5-5-10 10',
    'table': 'M4 5h16v14H4zM4 10h16M4 15h16M10 5v14',
    'code': 'M9 8l-4 4 4 4M15 8l4 4-4 4',
    'restart': 'M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5',
    'accessibility': 'M10.5 4.5a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0M5 8l7 1.5L19 8M12 9.5V14l-3 6M12 14l3 6',
    'eye': 'M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12zM9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0',
    'caps': 'M12 4l7 8h-4v7H9v-7H5z',
    'user': 'M9 8a3 3 0 1 0 6 0a3 3 0 1 0-6 0M5 20a7 7 0 0 1 14 0',
    'cloud': 'M7 18h10a4 4 0 0 0 0-8a6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 18z',
    'grid': 'M5 4h5v6H5zM14 4h5v6h-5zM5 14h5v6H5zM14 14h5v6h-5z',
    'list': 'M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01',
    'display': 'M5 4h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM8 20h8M12 16v4',
    'music': 'M9 18V6l10-2v12M5 18a2 2 0 1 0 4 0a2 2 0 1 0-4 0M15 16a2 2 0 1 0 4 0a2 2 0 1 0-4 0',
    'drive': 'M5 7h14a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM7 12h.01M17 12h-4',
    'palette': ('M12 3a9 9 0 1 0 0 18c1.5 0 2-1 2-2s-1-1.5-1-2.5 1-1.5 2-1.5h2a4 4 0 0 0 4-4c0-4.4-4-8-9-8z'
                'M7.5 11h.01M10.5 7h.01M15 7.5h.01'),
    'dock': 'M3 16h18v3H3zM6 12h3v4H6zM11 9h3v7h-3zM16 12h3v4h-3z',
    'topbar': 'M3 5h18v4H3zM3 13h18',
    'window': 'M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM3 9h18',
    'plus': 'M12 5v14M5 12h14',
    'pause': 'M9 6v12M15 6v12',
    'usb': 'M9 2h6v5H9zM7 7h10v13a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2z',
    'eject': 'M12 5l7 8H5zM5 18h14',
    'settings-lite': 'M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3',
    'compass': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M15.5 8.5l-2 5-5 2 2-5z',
    'check-bold': 'M5 12l4 4 10-10',
    'gamepad': 'M6 8h12a3 3 0 0 1 3 3v3a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3v-3a3 3 0 0 1 3-3zM7.5 11v3M6 12.5h3M16 12h.01M18 14h.01',
    'video': 'M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zM10 9l5 3-5 3z',
    'flask': 'M9 3h6M10 3v6l-5 9a2 2 0 0 0 2 3h10a2 2 0 0 0 2-3l-5-9V3',
    'cube': 'M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9',
    'aperture': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 3l3.5 7M21 12h-7.5M16.5 19.5L12 14M7.5 19.5L10 12M3 12h7.5',
    'brush': 'M18 3l3 3-9 9-3-3zM9 12c-3 0-5 2-5 5 0 1.5-1 2.5-2 3 4 1 9 0 9-5z',
    'gauge': 'M4 16a8 8 0 0 1 16 0M12 16l4-5',
    'skip-back': 'M18 6l-8 6 8 6zM6 6v12',
    'play': 'M8 5l11 7-11 7z',
    'skip-forward': 'M6 6l8 6-8 6zM18 6v12',
    'mic': 'M9 5a3 3 0 0 1 6 0v6a3 3 0 0 1-6 0zM5 11a7 7 0 0 0 14 0M12 18v3',
    'slash': 'M3 3l18 18',
    'slash-wifi': 'M4 4l16 16',
    # Launcher.dc.html / Main.dc.html app glyph table (the one-colour app symbols); 'terminal', 'globe',
    # 'mail', 'calendar', 'bag', 'chat', 'map' (pin) and 'sysmon' (cpu) below also come from it
    'code-slash': 'M9 8l-4 4 4 4M15 8l4 4-4 4M13.5 5l-3 14',
    'crop': 'M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M9 12h6M12 9v6',
    # ---- derived glyphs in the same style
    'terminal': 'M6 8l4 4-4 4M13 16h5',
    'globe': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18',
    'mail': 'M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zM3.5 7.5l8.5 6 8.5-6',
    'calendar': 'M5 5h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zM3 10h18M8 3v4M16 3v4',
    'note': 'M5 4h14a1 1 0 0 1 1 1v9l-6 6H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zM14 20v-5a1 1 0 0 1 1-1h5M8 9h8M8 13h4',
    'calculator': ('M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM8.5 7h7v3h-7z'
                   'M8.5 14h.01M12 14h.01M15.5 14h.01M8.5 17.5h.01M12 17.5h.01M15.5 17.5h.01'),
    'bag': 'M5 8h14l-1 12H6zM9 8V6a3 3 0 0 1 6 0v2',
    'chat': 'M5 5h14a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H10l-5 4V6a1 1 0 0 1 1-1z',
    'map': 'M12 21s-7-6.5-7-12a7 7 0 0 1 14 0c0 5.5-7 12-7 12zM9.5 9a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0',
    'sysmon': ('M8 6h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2zM10 2.5v3.5M14 2.5v3.5M10 18v3.5'
               'M14 18v3.5M2.5 10H6M2.5 14H6M18 10h3.5M18 14h3.5'),
    'logo': ci(12, 8.6, 4.6) + ci(8.2, 14.8, 4.6) + ci(15.8, 14.8, 4.6),
    'network': 'M12 7.5v4M6 17v-2.5h12V17M12 11.5v3' + ci(12, 5.5, 2) + ci(6, 19, 2) + ci(18, 19, 2),
    'wired': 'M5 6h14a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-4v2H9v-2H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM8 10v2.5M10.7 10v2.5M13.3 10v2.5M16 10v2.5',
    'shield': 'M12 3l7 3v5.5c0 4.5-3 8-7 9.5-4-1.5-7-5-7-9.5V6z',
    'airplane': 'M12 3.5c.8 0 1.4.7 1.4 1.5v4.3l6.6 4v1.9l-6.6-2v3.8l1.8 1.4V20L12 19l-3.2 1v-1.6l1.8-1.4V13.2L4 15.2v-1.9l6.6-4V5c0-.8.6-1.5 1.4-1.5z',
    'hotspot': 'M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8M12 12h.01',
    'camera': 'M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1zM9 13a3 3 0 1 0 6 0a3 3 0 1 0-6 0',
    'webcam': 'M5 10a7 7 0 1 0 14 0a7 7 0 1 0-14 0M9.5 10a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0M8 21h8M12 17v4',
    'headphones': 'M4 17v-4a8 8 0 0 1 16 0v4M4 14h3v6H5a1 1 0 0 1-1-1zM20 14h-3v6h2a1 1 0 0 0 1-1z',
    'headset': 'M4 15v-3a8 8 0 0 1 16 0v3M4 13h3v6H5a1 1 0 0 1-1-1zM20 13h-3v6h2a1 1 0 0 0 1-1zM18 19c0 1.5-1.5 2-3.5 2H12',
    'speaker': 'M7 3h10a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM9 14.5a3 3 0 1 0 6 0a3 3 0 1 0-6 0M12 7h.01',
    'mouse': 'M6.5 9a5.5 5.5 0 0 1 11 0v6a5.5 5.5 0 0 1-11 0zM12 3.5V9',
    'printer': 'M7 9V4h10v5M7 17H5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-2M7 14h10v7H7z',
    'sdcard': 'M8 3h7l4 4v13a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM10 7v3M13 7v3',
    'disc': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M10 12a2 2 0 1 0 4 0a2 2 0 1 0-4 0',
    'server': 'M5 4h14v7H5zM5 13h14v7H5zM8 7.5h.01M8 16.5h.01M12 7.5h4M12 16.5h4',
    'laptop': 'M5 5h14a1 1 0 0 1 1 1v10H4V6a1 1 0 0 1 1-1zM2 19h20',
    'computer': 'M5 4h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM8 20h8M12 16v4',
    'tablet': 'M6 3h12a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2',
    'tv': 'M4 6h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM8 21h8M9 3l3 3 3-3',
    'touchpad': 'M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM3 15h18M12 15v5',
    'car': 'M5 16v-4l2-5h10l2 5v4M3.5 16h17v3h-17zM7 19v2M17 19v2M7.5 13.5h.01M16.5 13.5h.01',
    'scanner': 'M4 10h16a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1zM6 10l12-5M7 15h10',
    'leaf': 'M5 19c0-8 5-13 14-14 0 9-5 14-13 14zM5 19l6-6',
    'rocket': 'M12 3c3.5 2.5 5 6 4.5 10.5L15 17H9l-1.5-3.5C7 9 8.5 5.5 12 3zM12 9h.01M9 17l-2 4 5-2 5 2-2-4',
    'contrast': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 3v18',
    'contrast-fill': 'M12 3a9 9 0 0 1 0 18z',
    'logout': 'M10 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4M15 8l4 4-4 4M19 12H9',
    'switch-user': 'M7 8a3 3 0 1 0 6 0a3 3 0 1 0-6 0M3 20a7 7 0 0 1 11-5.7M16 14h5M19 12l2 2-2 2M21 19h-5M18 17l-2 2 2 2',
    'hibernate': 'M8 4h8M10 4v3M14 4v3M7 7h10v13H7zM10 11h4l-4 5h4',
    'minus': 'M5 12h14',
    'stop': 'M7 6h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1z',
    'record': 'M6 12a6 6 0 1 0 12 0a6 6 0 1 0-12 0',
    'cut': 'M4 7a3 3 0 1 0 6 0a3 3 0 1 0-6 0M4 17a3 3 0 1 0 6 0a3 3 0 1 0-6 0M9.5 8.5L20 19M9.5 15.5L20 5',
    'undo': 'M9 5L4 10l5 5M4 10h10a6 6 0 0 1 0 12h-3',
    'redo': 'M15 5l5 5-5 5M20 10H10a6 6 0 0 0 0 12h3',
    'save': 'M5 3h11l3 3v13a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM7 3v5h8V3M7 21v-7h10v7',
    'star': 'M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8L3.5 9.7l5.9-.9z',
    'info': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 11v5M12 8h.01',
    'help': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6M12 17h.01',
    'more': 'M5 12h.01M12 12h.01M19 12h.01',
    'menu': 'M4 6h16M4 12h16M4 18h16',
    'pin': 'M9 3h6M10 3v6l-3 4h10l-3-4V3M12 13v8',
    'send': 'M4 12l16-8-6 16-2.5-6.5z',
    'share': ci(6, 12, 2.5) + ci(18, 6, 2.5) + ci(18, 18, 2.5) + 'M8.2 10.9l7.6-3.8M8.2 13.1l7.6 3.8',
    'filter': 'M4 5h16l-6 7.5V19l-4 2v-8.5z',
    'fullscreen': 'M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5',
    'restore': 'M9 5h9a1 1 0 0 1 1 1v9M6 9h9a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z',
    'upload': 'M12 20V9M7 14l5-5 5 5M5 4h14',
    'document-new': 'M7 3h7l5 5v13H7zM14 3v5h5M12 11v6M9 14h6',
    'folder-new': 'M3 7.5A2 2 0 0 1 5 5.5h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM12 10.5v6M9 13.5h6',
    'folder-open': 'M3 18V7.5a2 2 0 0 1 2-2h4l2 2h6a2 2 0 0 1 2 2V11M3 18l2.7-6.2A2 2 0 0 1 7.5 10.5H21l-3 7.5z',
    'recent': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 7v5l3.5 2',
    'link': 'M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1',
    'sidebar': 'M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM9 4v16',
    'split-v': 'M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM3 12h18',
    'keep-above': 'M5 11h14v9H5zM12 8V3M9 5.5l3-3 3 3',
    'keep-below': 'M5 4h14v9H5zM12 16v5M9 18.5l3 3 3-3',
    'shade': 'M5 4h14a2 2 0 0 1 2 2v3H3V6a2 2 0 0 1 2-2zM9 15l3 3 3-3',
    'zoom-in': 'M4 11a7 7 0 1 0 14 0a7 7 0 1 0-14 0M20 20l-4-4M11 8v6M8 11h6',
    'zoom-out': 'M4 11a7 7 0 1 0 14 0a7 7 0 1 0-14 0M20 20l-4-4M8 11h6',
    'window-new': 'M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM3 9h18M12 12v5M9.5 14.5h5',
    'print': 'M7 9V4h10v5M7 17H5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-2M7 14h10v7H7z',
    'unpin': 'M9 3h6M10 3v6l-3 4h10l-3-4V3M12 13v8M4 4l16 16',
    'shuffle': 'M4 7h3c4.5 0 5.5 10 10 10h3M4 17h3c1.6 0 2.7-1.3 3.6-3M13.4 10c.9-1.7 2-3 3.6-3h3M17.5 4.5L20 7l-2.5 2.5M17.5 14.5L20 17l-2.5 2.5',
    'repeat': 'M4 11V9a2 2 0 0 1 2-2h14M17 4l3 3-3 3M20 13v2a2 2 0 0 1-2 2H4M7 20l-3-3 3-3',
    'repeat-one': 'M4 11V9a2 2 0 0 1 2-2h14M17 4l3 3-3 3M20 13v2a2 2 0 0 1-2 2H4M7 20l-3-3 3-3M11 11l1.5-1v4',
    'update': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 7.5v8M8.5 12.5l3.5 3.5 3.5-3.5',
    'update-arrow': 'M12 7.5v8M8.5 12.5l3.5 3.5 3.5-3.5',
    'update-ring': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0',
    'check-circle': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M8 12.5l3 3 5-6',
    'vault': 'M5 3h14a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM9 11a3 3 0 1 0 6 0a3 3 0 1 0-6 0M7 19v2M17 19v2',
    # weather (derived from the Main board's cloud, the Brightness sun and the Night light moon)
    'w-sun-small': ('M4.5 7.5a3 3 0 1 0 6 0a3 3 0 1 0-6 0M7.5 1.5v1M1.5 7.5h1M3.3 3.3l.7.7M11.7 3.3l-.7.7'
                    'M13.5 7.5h-1M3.3 11.7l.7-.7'),
    'w-moon-small': 'M12 8.97A4.4 4.4 0 1 1 6.23 3.2a3.58 3.58 0 0 0 5.77 5.77z',
    'w-cloud-small': 'M10 20h7.5a3.5 3.5 0 0 0 0-7a5 5 0 0 0-9.4 1.3A3 3 0 0 0 10 20z',
    'w-cloud-high': 'M7 14h10a4 4 0 0 0 0-8a6 6 0 0 0-11.5 1.5A3.3 3.3 0 0 0 7 14z',
    'w-rain': 'M8 17.5l-1 3M12 17.5l-1 3M16 17.5l-1 3',
    'w-rain-few': 'M9.5 17.5l-1 3M14.5 17.5l-1 3',
    'w-snow': 'M8 18h.01M12 18h.01M16 18h.01M10 21h.01M14 21h.01',
    'w-snow-few': 'M9.5 18h.01M14.5 18h.01M12 21h.01',
    'w-sleet': 'M8 17.5l-1 3M16 17.5l-1 3M12 18h.01M12 21.5h.01',
    'w-bolt': 'M13 15.5l-2.5 3.5h3l-2 3.5',
    'w-fog': 'M4 8h16M6 12h12M4 16h16M7 20h10',
}

# Wi-Fi and volume parts (FileIcons.dc.html status groups).
A1, A2, A3, DOT = 'M2 9a15 15 0 0 1 20 0', 'M5 12.5a10 10 0 0 1 14 0', 'M8.5 16a5 5 0 0 1 7 0', 'M12 19.5h.01'
SPK, W1, W2 = 'M4 9h4l5-4v14l-5-4H4z', 'M16 9a4 4 0 0 1 0 6', 'M18.5 6.5a8 8 0 0 1 0 11'
BAT = 'M4 7h14a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM22 11v2'
BOLT = 'M12.5 7.5L8 12.8h3.2L9.8 16.5 14.6 11h-3.2z'
DIM = 0.28


def L(d, role='text', kind='stroke', opacity=None, width=None):
    return (d, role, kind, opacity, width)


def simple(name):
    return [L(G[name])]


# ------------------------------------------------------------------ status families
BATTERY_LEVELS = {0: 0, 10: 1.4, 20: 2.4, 30: 3.6, 40: 4.8, 50: 6, 60: 7, 70: 8, 80: 9, 90: 10.5, 100: 12}


def battery(level, charging=False, profile=None):
    """Board: Full / 60% / 30% (warning fill) / Low (red outline and fill) / Charging (bolt)."""
    w = BATTERY_LEVELS[level]
    if charging:
        layers = [L(BAT), L(BOLT, 'fixed:bolt', 'fill')]
    else:
        if level <= 10:
            role = 'negative'
            layers = [L(BAT, role)]
        else:
            role = 'neutral' if level <= 30 else 'text'
            layers = [L(BAT)]
        if w > 0:
            layers.append(L(f'M5 10h{fmt(w)}v4H5z', role, 'fill'))
    if profile == 'powersave':
        layers.append(L('M17.8 23c0-2.6 1.6-4.2 4.3-4.3 0 2.8-1.6 4.3-4 4.3zM17.8 23l1.9-1.9', 'positive', 'stroke', width=1.25))
    elif profile == 'performance':
        layers.append(L('M19.6 18.2l-2.4 3h2.2l-.9 2.7 2.8-3.3h-2.1l.8-2.4z', 'neutral', 'fill'))
    return layers


def battery_missing():
    return [L(BAT, opacity=DIM), L('M9 9l4 6M13 9l-4 6')]


def battery_profile(profile):
    if profile == 'powersave':
        return [L(G['leaf'], 'positive')]
    if profile == 'performance':
        return [L(G['rocket'])]
    return [L(G['gauge'])]


# Wi-Fi quality: 3 = excellent, 2 = good, 1 = weak, 0 = poor (dot in warning colour).
def wifi(bars, badge=None, off=False, none=False):
    arcs = [A1, A2, A3]
    if off:
        layers = [L(A1 + A2 + A3 + DOT, opacity=DIM), L(G['slash-wifi'])]
    elif none:
        layers = [L(A1 + A2 + A3 + DOT, opacity=DIM)]
    else:
        lit = arcs[3 - bars:]
        dim = arcs[:3 - bars]
        layers = []
        if dim:
            layers.append(L(''.join(dim), opacity=DIM))
        if bars == 0:
            layers.append(L(DOT, 'neutral'))
        else:
            layers.append(L(''.join(lit) + DOT))
    if badge == 'locked':
        # small padlock in the lower right corner, clear of the arcs
        layers.append(L('M17.4 18.2h4.4a.6.6 0 0 1 .6.6v3a.6.6 0 0 1-.6.6h-4.4a.6.6 0 0 1-.6-.6v-3a.6.6 0 0 1 .6-.6z', 'text', 'fill'))
        layers.append(L('M18.3 18.2v-1a1.3 1.3 0 0 1 2.6 0v1', 'text', 'stroke', width=1.2))
    elif badge == 'limited':
        layers.append(L('M20.5 15.5v3.5M20.5 21.8h.01', 'neutral', 'stroke', width=1.9))
    return layers


def volume(state):
    if state == 'high':
        return [L(SPK + W1 + W2)]
    if state == 'medium':
        return [L(W2, opacity=DIM), L(SPK + W1)]
    if state == 'low':
        return [L(W1 + W2, opacity=DIM), L(SPK)]
    if state == 'muted':
        return [L(SPK + 'M16 9l5 6M21 9l-5 6')]
    if state == 'high-warning':
        return [L(SPK + W1), L(W2, 'neutral')]
    if state == 'high-danger':
        return [L(SPK), L(W1 + W2, 'negative')]
    raise ValueError(state)


def mic(state):
    if state == 'muted':
        return [L(G['mic'] + G['slash'], 'negative')]
    return [L(G['mic'])]


def bluetooth(state):
    if state == 'active':
        return [L(G['bluetooth']), L('M3.5 12h.01M20.5 12h.01')]
    if state == 'off':
        return [L(G['bluetooth'], opacity=DIM), L(G['slash-wifi'])]
    return [L(G['bluetooth'])]


def bell(state):
    if state == 'active':
        return [L(G['bell']), L(ci(19.5, 4.5, 3.5), 'fixed:dot', 'fill')]
    if state == 'disabled':
        return [L(G['bell'] + 'M4 4l16 16')]
    if state == 'progress':
        return [L(G['bell'], opacity=0.6)]
    return [L(G['bell'])]


def dark_style():
    return [L(G['contrast']), L(G['contrast-fill'], 'text', 'fill')]


# ------------------------------------------------------------------ SVG output
def symbolic_svg(layers, variant):
    pal = PALETTES[variant]
    used = set()
    s = Svg(24)
    for d, role, kind, opacity, width in layers:
        if not d:
            continue
        # strokes are shipped as filled outlines: GTK 4 recolours symbolic icons through `fill` only
        shape = d if kind == 'fill' else outline_for(d, width or STROKE)
        if role.startswith('fixed:') or role.startswith('#'):
            color = FIXED[variant][role[6:]] if role.startswith('fixed:') else role
            s.fill(shape, color, opacity=opacity)
            continue
        cls, gtk = ROLE_CLASS[role]
        used.add(cls)
        classes = cls + (' ' + gtk if gtk else '')
        s.fill(shape, 'currentColor', cls=classes, opacity=opacity)
    style = ''.join(f'.{c}{{color:{pal[c.split("-", 1)[1]]}}}' for c in sorted(used))
    s.style = style or f'.ColorScheme-Text{{color:{pal["Text"]}}}'
    return s.render()
