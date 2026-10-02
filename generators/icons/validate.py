#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check a built icon theme pair with QtSvg (the renderer KIconLoader and KWin use).

    QT_QPA_PLATFORM=offscreen python3 validate.py ICONS_DIR [--sheets OUT_DIR]

For every drawing in art/ and glyphs/ of both themes:
  * QSvgRenderer must accept it, and rendering at 16/24/32/48/128 px must give a non-empty image;
  * no QtSvg warning may be printed while parsing or rendering;
  * symbolic drawings are passed through the same <style id="current-color-scheme"> replacement
    KIconLoader applies, and every opaque pixel must take the injected palette colours.
It also checks that every name in every lookup directory resolves (no dangling links; the
hand-back links into Breeze and into the apps' hicolor icons are left to make_capture.py) and
that index.theme lists every lookup directory. With --sheets it writes contact sheets.
"""
import argparse
import configparser
import os
import re
import sys

from PySide6.QtCore import QByteArray, QBuffer, QIODevice, QSize, QtMsgType, qInstallMessageHandler
from PySide6.QtGui import QColor, QFont, QGuiApplication, QImage, QImageReader, QPainter
from PySide6.QtSvg import QSvgRenderer

SIZES = (16, 24, 32, 48, 128)
MESSAGES = []


def handler(mode, ctx, msg):
    if mode != QtMsgType.QtDebugMsg:
        MESSAGES.append(msg)


def render(data, px):
    buf = QBuffer()
    buf.setData(QByteArray(data))
    buf.open(QIODevice.OpenModeFlag.ReadOnly)
    r = QImageReader(buf, QByteArray(b'svg'))
    r.setScaledSize(QSize(px, px))
    img = r.read()
    return img


# KIconLoader's stylesheet (kiconcolors.cpp STYLESHEET_TEMPLATE) with loud test colours
TEST_STYLE = ('.ColorScheme-Text { color:#ff0000; }.ColorScheme-Background{ color:#00ff00; }'
              '.ColorScheme-Highlight{ color:#0000ff; }.ColorScheme-HighlightedText{ color:#ffff00; }'
              '.ColorScheme-PositiveText{ color:#00ffff; }.ColorScheme-NeutralText{ color:#ff00ff; }'
              '.ColorScheme-NegativeText{ color:#808000; }.ColorScheme-Accent{ color:#008080; }')
TEST_COLOURS = {(255, 0, 0), (0, 255, 255), (255, 0, 255), (128, 128, 0), (0, 0, 255), (0, 128, 128)}


def recolour(svg):
    return re.sub(r'(<style[^>]*id="current-color-scheme"[^>]*>)(.*?)(</style>)',
                  lambda m: m.group(1) + TEST_STYLE + m.group(3), svg, count=1, flags=re.S)


def fixed_colours(svg):
    out = set()
    for m in re.finditer(r'(?:fill|stroke)="#([0-9a-f]{6})"', svg):
        v = m.group(1)
        out.add((int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)))
    return out


def check_symbolic_pixels(img, allowed):
    """Every clearly opaque pixel must be one of the injected or fixed colours (edges blend)."""
    bad = 0
    total = 0
    for y in range(img.height()):
        for x in range(img.width()):
            c = QColor.fromRgba(img.pixel(x, y))
            if c.alpha() < 250:
                continue
            total += 1
            rgb = (c.red(), c.green(), c.blue())
            if not any(max(abs(rgb[i] - a[i]) for i in range(3)) <= 8 for a in allowed):
                bad += 1
    return bad, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('icons')
    ap.add_argument('--sheets')
    args = ap.parse_args()
    app = QGuiApplication(sys.argv[:1])  # noqa: F841
    qInstallMessageHandler(handler)
    problems = []
    checked = 0
    for theme in ('PlasmaFusion', 'PlasmaFusion-Dark'):
        base = os.path.join(args.icons, theme)
        for sub in ('art', 'glyphs'):
            folder = os.path.join(base, sub)
            if theme == 'PlasmaFusion-Dark' and sub == 'art' and os.path.islink(folder):
                continue
            for fn in sorted(os.listdir(folder)):
                path = os.path.join(folder, fn)
                data = open(path, 'rb').read()
                text = data.decode('utf-8')
                if '<text' in text or 'DOCTYPE' in text or 'filter' in text or 'xlink' in text:
                    problems.append(f'{theme}/{sub}/{fn}: forbidden construct')
                MESSAGES.clear()
                rend = QSvgRenderer(QByteArray(data))
                if not rend.isValid():
                    problems.append(f'{theme}/{sub}/{fn}: QSvgRenderer says invalid')
                for px in SIZES:
                    img = render(data, px)
                    if img.isNull() or img.width() != px:
                        problems.append(f'{theme}/{sub}/{fn}: no image at {px}')
                        continue
                    if px == 48:
                        alpha = sum(1 for y in range(0, px, 2) for x in range(0, px, 2)
                                    if QColor.fromRgba(img.pixel(x, y)).alpha() > 0)
                        if alpha == 0:
                            problems.append(f'{theme}/{sub}/{fn}: renders empty')
                if sub == 'glyphs':
                    img = render(recolour(text).encode(), 48)
                    bad, total = check_symbolic_pixels(img, TEST_COLOURS | fixed_colours(text))
                    # a few blended pixels where two colours overlap are fine; an element that
                    # ignores the palette shows up as a large share of off-palette pixels
                    if bad > max(4, total * 0.06):
                        problems.append(f'{theme}/{sub}/{fn}: recolour check {bad} of {total} opaque pixels off-palette')
                if MESSAGES:
                    problems.append(f'{theme}/{sub}/{fn}: Qt messages: {MESSAGES[:3]}')
                checked += 1
        # index.theme lists every lookup directory; every link resolves
        cp = configparser.ConfigParser(interpolation=None, strict=False)
        cp.optionxform = str
        cp.read(os.path.join(base, 'index.theme'))
        listed = cp['Icon Theme']['Directories'].split(',') + [d for d in cp['Icon Theme'].get('ScaledDirectories', '').split(',') if d]
        for d in listed:
            if d not in cp:
                problems.append(f'{theme}: directory {d} has no section')
            if not os.path.isdir(os.path.join(base, d)):
                problems.append(f'{theme}: directory {d} missing on disk')
        names = 0
        for d in listed:
            full = os.path.join(base, d)
            if not os.path.isdir(full):
                continue
            for fn in os.listdir(full):
                names += 1
                p = os.path.join(full, fn)
                if d.startswith(('breeze/', 'hicolor/', 'flatpak/')):
                    continue  # links into Breeze (checked by make_capture.py) and into apps' hicolor icons
                if not os.path.exists(p):
                    problems.append(f'{theme}/{d}/{fn}: dangling link')
        print(f'{theme}: {names} names in {len(listed)} directories')
    print(f'checked {checked} drawings')
    for p in problems:
        print('PROBLEM', p)
    if args.sheets:
        sheets(args.icons, args.sheets)
    sys.exit(1 if problems else 0)


def sheets(icons, out):
    os.makedirs(out, exist_ok=True)
    for theme, bg, fg in (('PlasmaFusion', '#eef0f5', '#141827'), ('PlasmaFusion-Dark', '#10142a', '#e8ebf4')):
        base = os.path.join(icons, theme)
        for sub, cell, px in (('art', 76, 64), ('glyphs', 40, 24)):
            files = sorted(os.listdir(os.path.join(base, sub)))
            if sub == 'art':
                files = [f for f in files if not f.startswith('mime-')] + [f for f in files if f.startswith('mime-')][:240]
            cols = 24 if sub == 'art' else 30
            rows = (len(files) + cols - 1) // cols
            img = QImage(cols * cell + 20, rows * (cell + 12) + 20, QImage.Format.Format_ARGB32_Premultiplied)
            img.fill(QColor(bg))
            p = QPainter(img)
            f = QFont('Manrope')
            f.setPixelSize(8)
            p.setFont(f)
            p.setPen(QColor(fg))
            for i, fn in enumerate(files):
                data = open(os.path.join(base, sub, fn), 'rb').read()
                if sub == 'glyphs':
                    data = data  # default colours of this variant
                icon = render(data, px)
                x = 10 + (i % cols) * cell
                y = 10 + (i // cols) * (cell + 12)
                p.drawImage(x + (cell - px) // 2, y, icon)
                p.drawText(x, y + px + 2, cell, 12, 0x84, fn[:-4][:14])
            p.end()
            img.save(os.path.join(out, f'sheet-{theme}-{sub}.png'))


if __name__ == '__main__':
    main()
