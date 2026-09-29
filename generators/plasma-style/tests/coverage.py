#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""List SVG element ids that Breeze has and the generated style lacks (per file).

    coverage.py THEME_DIR
"""
import gzip, os, re, sys
BREEZE = "/usr/share/plasma/desktoptheme/default"
OURS = sys.argv[1]
junk = re.compile(r'^(path|rect|g|defs|layer|use|stop|linear|radial|filter|fe|mask\d|clip|text|tspan|svg|metadata|namedview|circle|ellipse|sodipodi|base|grid|guide|Checkerboard|msc|st$|sb$|sl$|sr$|shadow-bottomright-9|shadow-topright-0|shadow-topleft-2|shadow-bottomleft-9|shadow-bottomright-2)')
def ids(path):
    data = open(path, 'rb').read()
    if data[:2] == b'\x1f\x8b': data = gzip.decompress(data)
    return {i.decode() for i in re.findall(rb'\bid="([^"]+)"', data) if not junk.match(i.decode())}
for root, _, files in os.walk(OURS):
    for f in sorted(files):
        if not f.endswith('.svg'): continue
        rel = os.path.relpath(os.path.join(root, f), OURS)
        b = os.path.join(BREEZE, rel + 'z')
        if not os.path.exists(b):
            # Breeze may only have it at the root (selector fallback)
            b2 = os.path.join(BREEZE, rel.split('/', 1)[1] + 'z') if rel.startswith(('translucent/', 'solid/', 'opaque/')) else None
            if b2 and os.path.exists(b2): b = b2
            else: print(f"{rel}: no Breeze counterpart"); continue
        miss = sorted(ids(b) - ids(os.path.join(root, f)))
        print(f"{rel}: missing vs Breeze: {' '.join(miss) if miss else '-'}")
