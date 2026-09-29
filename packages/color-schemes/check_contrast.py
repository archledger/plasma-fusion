#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the Plasma Fusion colour schemes against the Colors board.

    check_contrast.py [--markdown] [DIR]

Reads PlasmaFusionDark.colors and PlasmaFusionLight.colors from DIR (default: this directory) and

  1. checks every text/background pair of design/boards/Colors.dc.html: the scheme must hold the
     board's colours and the WCAG 2 contrast ratio must match the board's figure (within 0.1);
  2. checks every foreground role of every colour set against that set's background
     (text roles need 4.5:1, the focus colour 3:1; the hover colour is reported without a minimum,
     as are secondary roles on the accent fill; the inactive title bar's secondary text needs 3:1);
  3. estimates the disabled text colour with KColorScheme's state effect (fade towards the
     background, then darken) and compares it with the board's disabled grey.

With --markdown it prints the tables used in docs/parts/foundation.md. The exit status is 1 when
a board colour is missing or a pair falls below its minimum.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def parse_colors(path):
    """Minimal KConfig reader: returns {group: {key: value}}; '[A][B]' becomes 'A][B'."""
    groups, cur = {}, None
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if line.startswith('['):
                cur = line[1:-1]
                groups.setdefault(cur, {})
                continue
            k, _, v = line.partition('=')
            groups[cur][k.strip()] = v.strip()
    return groups


def hx(c):
    c = c.lstrip('#')
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb):
    return '#%02x%02x%02x' % tuple(max(0, min(255, int(round(v)))) for v in rgb)


def from_ini(v):
    return to_hex(tuple(int(x) for x in v.split(',')[:3]))


def lin(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def lum(c):
    r, g, b = hx(c)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def over(fg_hex, alpha, bg_hex):
    """fg at alpha composited over bg (sRGB, as a browser does)."""
    f, b = hx(fg_hex), hx(bg_hex)
    return to_hex(tuple(fv * alpha + bv * (1 - alpha) for fv, bv in zip(f, b)))


# --- KColorUtils (kguiaddons) HCY helpers, used for the disabled-text estimate ---
YC = (0.2126, 0.7152, 0.0722)


def _norm(v):
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


def _gamma(v):
    return _norm(v) ** 2.2


def _igamma(v):
    return _norm(v) ** (1 / 2.2)


def hcy(c):
    r, g, b = (_gamma(v / 255.0) for v in hx(c))
    y = r * YC[0] + g * YC[1] + b * YC[2]
    p, n = max(r, g, b), min(r, g, b)
    d = 6.0 * (p - n)
    if n == p:
        h = 0.0
    elif r == p:
        h = (g - b) / d
    elif g == p:
        h = (b - r) / d + 1 / 3
    else:
        h = (r - g) / d + 2 / 3
    c_ = 0.0 if (r == g == b) else max((y - n) / y, (p - y) / (1 - y))
    return h, c_, y


def hcy_to_hex(h, c, y):
    h = h % 1.0
    c, y = _norm(c), _norm(y)
    hs = h * 6.0
    if hs < 1:
        th = hs; tm = YC[0] + YC[1] * th
    elif hs < 2:
        th = 2 - hs; tm = YC[1] + YC[0] * th
    elif hs < 3:
        th = hs - 2; tm = YC[1] + YC[2] * th
    elif hs < 4:
        th = 4 - hs; tm = YC[2] + YC[1] * th
    elif hs < 5:
        th = hs - 4; tm = YC[2] + YC[0] * th
    else:
        th = 6 - hs; tm = YC[0] + YC[2] * th
    if tm >= y:
        tp = y + y * c * (1 - tm) / tm
        to = y + y * c * (th - tm) / tm
        tn = y - y * c
    else:
        tp = y + (1 - y) * c
        to = y + (1 - y) * c * (th - tm) / (1 - tm)
        tn = y - (1 - y) * c * tm / (1 - tm)
    order = [(tp, to, tn), (to, tp, tn), (tn, tp, to), (tn, to, tp), (to, tn, tp), (tp, tn, to)]
    r, g, b = order[min(5, int(hs))]
    return to_hex((_igamma(r) * 255, _igamma(g) * 255, _igamma(b) * 255))


def disabled_text(scheme, fg, bg):
    """KColorScheme StateEffects(Disabled).brush(fg, bg) for the effects this scheme uses."""
    eff = scheme['ColorEffects:Disabled']
    col = fg
    if eff.get('ContrastEffect') == '1':            # ContrastFade: mix towards the background
        t = float(eff.get('ContrastAmount', '0.65'))
        col = over(bg, t, fg)
    if eff.get('IntensityEffect') == '2':           # IntensityDarken
        h, c, y = hcy(col)
        col = hcy_to_hex(h, c, y * (1 - float(eff.get('IntensityAmount', '0.1'))))
    return col


# --- the board -------------------------------------------------------------------------------
# (role, KDE section, board fg, board bg, board ratio, fg source, bg source, kind)
# a source is ('Set', 'Key') read from the scheme, or a literal '#rrggbb' that is not a scheme
# key (drawn by the style); kind: 'text' (4.5), 'ui' (3.0), 'exempt'.
BOARD = {
    'dark': [
        ('Text', 'Window · ForegroundNormal', '#e8ebf4', '#1b2031', 13.6, ('Window', 'ForegroundNormal'), ('Window', 'BackgroundNormal'), 'text'),
        ('Secondary text', 'Window · ForegroundInactive', '#a3abc2', '#1b2031', 7.1, ('Window', 'ForegroundInactive'), ('Window', 'BackgroundNormal'), 'text'),
        ('Disabled text', 'Window · disabled effect', '#6f7892', '#1b2031', 3.7, 'disabled', ('Window', 'BackgroundNormal'), 'exempt'),
        ('Alternate background', 'Window · BackgroundAlternate', '#e8ebf4', '#181c2b', 14.2, ('Window', 'ForegroundNormal'), ('Window', 'BackgroundAlternate'), 'text'),
        ('Fields and lists', 'View · BackgroundNormal', '#e8ebf4', '#1f2540', 12.6, ('View', 'ForegroundNormal'), ('View', 'BackgroundNormal'), 'text'),
        ('Link', 'View · ForegroundLink', '#8ab8ff', '#1f2540', 7.4, ('View', 'ForegroundLink'), ('View', 'BackgroundNormal'), 'text'),
        ('Visited link', 'View · ForegroundVisited', '#c3a6ff', '#1f2540', 7.3, ('View', 'ForegroundVisited'), ('View', 'BackgroundNormal'), 'text'),
        ('Button', 'Button · BackgroundNormal', '#e8ebf4', '#262d4c', 11.3, ('Button', 'ForegroundNormal'), ('Button', 'BackgroundNormal'), 'text'),
        ('Button, hover', 'Button · hover fill (style)', '#e8ebf4', '#2d355a', 10.0, ('Button', 'ForegroundNormal'), '#2d355a', 'text'),
        ('Selected, focused', 'Selection · BackgroundNormal', '#ffffff', '#2f6fdf', 4.7, ('Selection', 'ForegroundNormal'), ('Selection', 'BackgroundNormal'), 'text'),
        ('Selected row, soft', 'Selection · BackgroundAlternate', '#cfe0ff', '#28395a', 8.6, '#cfe0ff', ('Selection', 'BackgroundAlternate'), 'text'),
        ('Focus ring', 'Button · DecorationFocus', '#8ab8ff', '#1b2031', 8.0, ('Button', 'DecorationFocus'), ('Window', 'BackgroundNormal'), 'ui'),
        ('Positive', 'Window · ForegroundPositive', '#7fd99c', '#1b2031', 9.5, ('Window', 'ForegroundPositive'), ('Window', 'BackgroundNormal'), 'text'),
        ('Neutral / warning', 'Window · ForegroundNeutral', '#f5c08c', '#1b2031', 9.9, ('Window', 'ForegroundNeutral'), ('Window', 'BackgroundNormal'), 'text'),
        ('Negative', 'Window · ForegroundNegative', '#ff8a8f', '#1b2031', 7.2, ('Window', 'ForegroundNegative'), ('Window', 'BackgroundNormal'), 'text'),
        ('Destructive fill', 'Button · negative fill (style)', '#ffffff', '#c93a42', 5.0, '#ffffff', '#c93a42', 'text'),
        ('Title bar, active', 'Header · BackgroundNormal', '#e8ebf4', '#222840', 12.2, ('Header', 'ForegroundNormal'), ('Header', 'BackgroundNormal'), 'text'),
        ('Title bar, inactive', 'Header · Inactive', '#8891aa', '#1f2536', 4.9, ('Header][Inactive', 'ForegroundNormal'), ('Header][Inactive', 'BackgroundNormal'), 'text'),
        ('Shell panels', 'Complementary · BackgroundNormal', '#e8ebf4', '#1a1f33', 13.7, ('Complementary', 'ForegroundNormal'), ('Complementary', 'BackgroundNormal'), 'text'),
        ('Shell secondary', 'Complementary · ForegroundInactive', '#a3abc2', '#1a1f33', 7.1, ('Complementary', 'ForegroundInactive'), ('Complementary', 'BackgroundNormal'), 'text'),
        ('Tooltip', 'Tooltip · BackgroundNormal', '#e8ebf4', '#0c0f1c', 16.0, ('Tooltip', 'ForegroundNormal'), ('Tooltip', 'BackgroundNormal'), 'text'),
    ],
    'light': [
        ('Text', 'Window · ForegroundNormal', '#141827', '#ffffff', 17.7, ('Window', 'ForegroundNormal'), ('Window', 'BackgroundNormal'), 'text'),
        ('Secondary text', 'Window · ForegroundInactive', '#4d546a', '#ffffff', 7.5, ('Window', 'ForegroundInactive'), ('Window', 'BackgroundNormal'), 'text'),
        ('Disabled text', 'Window · disabled effect', '#9aa0b2', '#ffffff', 2.6, 'disabled', ('Window', 'BackgroundNormal'), 'exempt'),
        ('Alternate background', 'Window · BackgroundAlternate', '#141827', '#f5f6fa', 16.3, ('Window', 'ForegroundNormal'), ('Window', 'BackgroundAlternate'), 'text'),
        ('Fields and lists', 'View · BackgroundNormal', '#141827', '#ffffff', 17.7, ('View', 'ForegroundNormal'), ('View', 'BackgroundNormal'), 'text'),
        ('Link', 'View · ForegroundLink', '#2359c4', '#ffffff', 6.4, ('View', 'ForegroundLink'), ('View', 'BackgroundNormal'), 'text'),
        ('Visited link', 'View · ForegroundVisited', '#6b3fb5', '#ffffff', 7.0, ('View', 'ForegroundVisited'), ('View', 'BackgroundNormal'), 'text'),
        ('Button', 'Button · BackgroundNormal', '#141827', '#eef0f5', 15.5, ('Button', 'ForegroundNormal'), ('Button', 'BackgroundNormal'), 'text'),
        ('Button, hover', 'Button · hover fill (style)', '#141827', '#e4e7ef', 14.3, ('Button', 'ForegroundNormal'), '#e4e7ef', 'text'),
        ('Selected, focused', 'Selection · BackgroundNormal', '#ffffff', '#2f6fdf', 4.7, ('Selection', 'ForegroundNormal'), ('Selection', 'BackgroundNormal'), 'text'),
        ('Selected row, soft', 'Selection · BackgroundAlternate', '#1d4fb0', '#e6eefb', 6.4, '#1d4fb0', ('Selection', 'BackgroundAlternate'), 'text'),
        ('Focus ring', 'Button · DecorationFocus', '#2f6fdf', '#ffffff', 4.7, ('Button', 'DecorationFocus'), ('Window', 'BackgroundNormal'), 'ui'),
        ('Positive', 'Window · ForegroundPositive', '#23703b', '#ffffff', 6.1, ('Window', 'ForegroundPositive'), ('Window', 'BackgroundNormal'), 'text'),
        ('Neutral / warning', 'Window · ForegroundNeutral', '#8f4f12', '#ffffff', 6.4, ('Window', 'ForegroundNeutral'), ('Window', 'BackgroundNormal'), 'text'),
        ('Negative', 'Window · ForegroundNegative', '#b3262e', '#ffffff', 6.5, ('Window', 'ForegroundNegative'), ('Window', 'BackgroundNormal'), 'text'),
        ('Destructive fill', 'Button · negative fill (style)', '#ffffff', '#c93a42', 5.0, '#ffffff', '#c93a42', 'text'),
        ('Title bar, active', 'Header · BackgroundNormal', '#141827', '#eceff6', 15.3, ('Header', 'ForegroundNormal'), ('Header', 'BackgroundNormal'), 'text'),
        ('Title bar, inactive', 'Header · Inactive', '#646b80', '#f1f3f8', 4.8, ('Header][Inactive', 'ForegroundNormal'), ('Header][Inactive', 'BackgroundNormal'), 'text'),
        ('Shell panels', 'Complementary · BackgroundNormal', '#141827', '#f7f8fb', 16.6, ('Complementary', 'ForegroundNormal'), ('Complementary', 'BackgroundNormal'), 'text'),
        ('Shell secondary', 'Complementary · ForegroundInactive', '#5b6278', '#f7f8fb', 5.7, ('Complementary', 'ForegroundInactive'), ('Complementary', 'BackgroundNormal'), 'text'),
        ('Tooltip', 'Tooltip · BackgroundNormal', '#ffffff', '#1b2031', 16.2, ('Tooltip', 'ForegroundNormal'), ('Tooltip', 'BackgroundNormal'), 'text'),
    ],
}

FILES = {'dark': 'PlasmaFusionDark.colors', 'light': 'PlasmaFusionLight.colors'}
SETS = ['Window', 'View', 'Button', 'Selection', 'Tooltip', 'Complementary', 'Header', 'Header][Inactive']
FG_KEYS = ['ForegroundNormal', 'ForegroundInactive', 'ForegroundActive', 'ForegroundLink', 'ForegroundVisited',
           'ForegroundNegative', 'ForegroundNeutral', 'ForegroundPositive']
DECO_KEYS = ['DecorationFocus', 'DecorationHover']
MIN = {'text': 4.5, 'ui': 3.0, 'exempt': 0.0}


def get(scheme, src):
    if isinstance(src, tuple):
        return from_ini(scheme['Colors:' + src[0]][src[1]])
    return src


def main(argv):
    md = '--markdown' in argv
    args = [a for a in argv if not a.startswith('--')]
    folder = args[0] if args else HERE
    failures = []
    out = []
    for variant in ('dark', 'light'):
        scheme = parse_colors(os.path.join(folder, FILES[variant]))
        out.append('\n#### %s: board pairs\n' % FILES[variant][:-7])
        out.append('| Role | KDE section | Scheme fg / bg | Ratio | Board | Minimum | Result |')
        out.append('|---|---|---|---:|---:|---:|---|')
        for role, kde, bfg, bbg, bratio, fsrc, bsrc, kind in BOARD[variant]:
            bg = get(scheme, bsrc)
            fg = disabled_text(scheme, from_ini(scheme['Colors:Window']['ForegroundNormal']), bg) if fsrc == 'disabled' else get(scheme, fsrc)
            r = ratio(fg, bg)
            ok = r + 1e-9 >= MIN[kind]
            note = ''
            if fsrc != 'disabled' and (fg != bfg or bg != bbg):
                ok = False
                note = ' (board %s / %s)' % (bfg, bbg)
            if fsrc != 'disabled' and abs(r - bratio) > 0.1:
                ok = False
                note += ' (board ratio %.1f)' % bratio
            if fsrc == 'disabled':
                note = ' (estimate; board %s %.1f:1)' % (bfg, bratio)
            res = ('pass' if ok else 'FAIL') + note
            if kind == 'exempt':
                res = 'exempt' + note
            if not ok and kind != 'exempt':
                failures.append('%s %s: %s' % (variant, role, res))
            out.append('| %s | %s | `%s` / `%s` | %.1f:1 | %.1f:1 | %s | %s |' % (
                role, kde, fg, bg, r, bratio, ('%.1f' % MIN[kind]) if MIN[kind] else '-', res))

        out.append('\n#### %s: every role on its own background\n' % FILES[variant][:-7])
        out.append('| Set | Background | ' + ' | '.join(k.replace('Foreground', 'Fg ').replace('Decoration', 'Deco ') for k in FG_KEYS + DECO_KEYS) + ' |')
        out.append('|---|---|' + '---:|' * len(FG_KEYS + DECO_KEYS))
        for s in SETS:
            grp = scheme['Colors:' + s]
            bg = from_ini(grp['BackgroundNormal'])
            cells = []
            for k in FG_KEYS + DECO_KEYS:
                c = from_ini(grp[k])
                r = ratio(c, bg)
                need = 3.0 if k in DECO_KEYS else 4.5
                if k == 'DecorationHover':
                    need = 0.0   # a hover cue (outline or soft tint), not needed to identify a control
                # documented exceptions: secondary text on the accent fill, the inactive title bar's
                # secondary text, and decoration colours equal to the accent fill itself
                if s == 'Selection' and k not in ('ForegroundNormal', 'ForegroundActive', 'ForegroundLink'):
                    need = 3.0 if k in FG_KEYS else 0.0
                if s == 'Header][Inactive' and k == 'ForegroundInactive':
                    need = 3.0
                mark = '' if r + 1e-9 >= need else ' ✗'
                if mark:
                    failures.append('%s %s %s %.2f < %.1f' % (variant, s, k, r, need))
                cells.append('%.1f%s' % (r, mark))
            out.append('| %s | `%s` | %s |' % (s.replace('][', ' '), bg, ' | '.join(cells)))
        # the design's soft selection rows (20 % / 12 % accent over the window colour)
        win = from_ini(scheme['Colors:Window']['BackgroundNormal'])
        soft = over('#5b9dff', 0.2, win) if variant == 'dark' else over('#2f6fdf', 0.12, win)
        stext = '#cfe0ff' if variant == 'dark' else '#1d4fb0'
        out.append('\nSoft selection row (board: %s accent over the window colour) = `%s`; `%s` text on it %.1f:1; '
                   'Window text on it %.1f:1.' % ('20 % #5b9dff' if variant == 'dark' else '12 % #2f6fdf', soft, stext,
                                                  ratio(stext, soft), ratio(from_ini(scheme['Colors:Window']['ForegroundNormal']), soft)))
    text = '\n'.join(out)
    if md:
        print(text)
    else:
        print(text.replace('`', ''))
    if failures:
        print('\nFAILURES:\n  ' + '\n  '.join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
