# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compose text as SVG path data from glyphs.json (made by make_textpaths.py).

Placement follows the boards' CSS: a flex box centres one line (line-height 1) in a box, and
letter-spacing is added after every character, including the last one, as the browser does.
With line-height 1 the baseline sits at centre + (ascent - descent) / 2.
"""
import json
import os

from svgkit import fmt, transform_abs_path

_DATA = None


def _data():
    global _DATA
    if _DATA is None:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'glyphs.json'), encoding='utf-8') as f:
            _DATA = json.load(f)
    return _DATA


def text_width(text, style, size, letter_spacing_em=0.0):
    st = _data()['styles'][style]
    em = _data()['em']
    s = size / em
    w = 0.0
    for i, ch in enumerate(text):
        g = st['glyphs'].get(ch)
        if g is None:
            raise KeyError(f'glyph {ch!r} missing from glyphs.json ({style}); add it to CHARSET and rerun make_textpaths.py')
        w += g['adv'] * s + letter_spacing_em * size
        if i + 1 < len(text):
            w += st['kern'].get(ch + text[i + 1], 0.0) * s
    return w


def text_in_box(text, style, size, box, letter_spacing_em=0.0, max_width=None):
    """Path data for `text` centred in box=(x, y, w, h), sized `size` in the box's units.

    If max_width is given and the text is wider, it is condensed horizontally to fit.
    """
    st = _data()['styles'][style]
    em = _data()['em']
    x, y, w, h = box
    total = text_width(text, style, size, letter_spacing_em)
    hscale = 1.0
    if max_width is not None and total > max_width:
        hscale = max_width / total
    s = size / em
    left = x + (w - total * hscale) / 2
    baseline = y + h / 2 + (st['ascent'] - st['descent']) / 2 * s
    out = []
    pen = 0.0
    for i, ch in enumerate(text):
        g = st['glyphs'][ch]
        if g['d']:
            out.append(_place(g['d'], s, hscale, left + pen * hscale, baseline))
        pen += g['adv'] * s + letter_spacing_em * size
        if i + 1 < len(text):
            pen += st['kern'].get(ch + text[i + 1], 0.0) * s
    return ''.join(out)


def _place(d, s, hscale, tx, ty):
    if hscale == 1.0:
        return transform_abs_path(d, s, tx, ty)
    # condensed: scale x by s*hscale and y by s
    import re
    from svgkit import _NUM
    out = []
    for cmd, args in re.findall(r'([MLCQZ])([^MLCQZ]*)', d):
        if cmd == 'Z':
            out.append('Z')
            continue
        nums = [float(n) for n in _NUM.findall(args)]
        pairs = [f"{fmt(nums[i] * s * hscale + tx)} {fmt(nums[i + 1] * s + ty)}" for i in range(0, len(nums), 2)]
        out.append(cmd + ' '.join(pairs))
    return ''.join(out)
