#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Maintainer tool: convert the glyphs the icons need into outlines (glyphs.json).

Icon SVGs must not contain <text>: QtSvg and librsvg fall back to other installed fonts.
This tool reads the repository's variable fonts with PySide6, pins the wght axis, and
stores each glyph outline (em = 1000 units, baseline at y = 0), its advance, pair kerning
and the font's vertical metrics. gen_icons.py composes strings from this file using only
the standard library, so the build does not need PySide6 or the fonts.

Run after changing the fonts or the character set:
    QT_QPA_PLATFORM=offscreen python3 generators/icons/make_textpaths.py
"""
import json
import os
import struct
import sys

from PySide6.QtCore import QPointF
from PySide6.QtGui import QFont, QFontDatabase, QFontMetricsF, QGuiApplication, QPainterPath

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
EM = 1000.0
CHARSET = ''.join(chr(c) for c in range(ord('A'), ord('Z') + 1)) + \
    ''.join(chr(c) for c in range(ord('a'), ord('z') + 1)) + '0123456789+-.#'

STYLES = {
    # key: (font file, weight) - the boards use Manrope 800 for tags and Space Grotesk 700 for figures
    'manrope-800': ('fonts/manrope/Manrope[wght].ttf', 800),
    'spacegrotesk-700': ('fonts/spacegrotesk/SpaceGrotesk[wght].ttf', 700),
}


def fnum(v):
    s = ('%.2f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def vertical_metrics(path):
    """Ascender/descender the browser uses (OS/2 typo metrics when USE_TYPO_METRICS, else hhea)."""
    data = open(path, 'rb').read()
    count = struct.unpack('>H', data[4:6])[0]
    tables = {}
    for i in range(count):
        tag, _cs, off, length = struct.unpack('>4sIII', data[12 + 16 * i:28 + 16 * i])
        tables[tag.decode('latin-1')] = off
    upm = struct.unpack('>H', data[tables['head'] + 18:tables['head'] + 20])[0]
    hasc, hdesc = struct.unpack('>hh', data[tables['hhea'] + 4:tables['hhea'] + 8])
    os2 = tables['OS/2']
    fs_sel = struct.unpack('>H', data[os2 + 62:os2 + 64])[0]
    tasc, tdesc = struct.unpack('>hh', data[os2 + 68:os2 + 72])
    if fs_sel & 0x80:
        asc, desc = tasc, -tdesc
    else:
        asc, desc = hasc, -hdesc
    return asc / upm * EM, desc / upm * EM


def path_d(p):
    out = []
    i = 0
    n = p.elementCount()
    while i < n:
        e = p.elementAt(i)
        t = e.type
        if t == QPainterPath.ElementType.MoveToElement:
            out.append(f'M{fnum(e.x)} {fnum(e.y)}')
        elif t == QPainterPath.ElementType.LineToElement:
            out.append(f'L{fnum(e.x)} {fnum(e.y)}')
        elif t == QPainterPath.ElementType.CurveToElement:
            c2 = p.elementAt(i + 1)
            ep = p.elementAt(i + 2)
            out.append(f'C{fnum(e.x)} {fnum(e.y)} {fnum(c2.x)} {fnum(c2.y)} {fnum(ep.x)} {fnum(ep.y)}')
            i += 2
        i += 1
    return ''.join(out)


def main():
    app = QGuiApplication(sys.argv[:1])  # noqa: F841 (needed for the font database)
    result = {'em': EM, 'charset': CHARSET, 'styles': {}}
    for key, (rel, weight) in STYLES.items():
        path = os.path.join(ROOT, rel)
        fid = QFontDatabase.addApplicationFont(path)
        fams = QFontDatabase.applicationFontFamilies(fid)
        if not fams:
            sys.exit(f'cannot load {path}')
        font = QFont(fams[0])
        font.setPixelSize(int(EM))
        font.setWeight(QFont.Weight(weight))
        font.setVariableAxis(QFont.Tag.fromString('wght'), float(weight))
        font.setHintingPreference(QFont.HintingPreference.PreferNoHinting)
        font.setKerning(True)
        fm = QFontMetricsF(font)
        glyphs = {}
        for ch in CHARSET:
            p = QPainterPath()
            p.addText(QPointF(0, 0), font, ch)
            glyphs[ch] = {'d': path_d(p), 'adv': round(fm.horizontalAdvance(ch), 2)}
        kern = {}
        for a in CHARSET:
            for b in CHARSET:
                k = fm.horizontalAdvance(a + b) - glyphs[a]['adv'] - glyphs[b]['adv']
                if abs(k) >= 0.5:
                    kern[a + b] = round(k, 2)
        asc, desc = vertical_metrics(path)
        result['styles'][key] = {'font': rel, 'weight': weight, 'family': fams[0],
                                 'ascent': asc, 'descent': desc, 'glyphs': glyphs, 'kern': kern}
    out = os.path.join(HERE, 'glyphs.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(result, f, sort_keys=True, separators=(',', ':'))
        f.write('\n')
    print('wrote', out, os.path.getsize(out), 'bytes')


if __name__ == '__main__':
    main()
