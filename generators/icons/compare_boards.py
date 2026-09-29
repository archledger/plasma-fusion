#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare built icons with the rendered design boards (icons-1.png, icons-2.png).

    QT_QPA_PLATFORM=offscreen python3 compare_boards.py ICONS_DIR RENDERS_DIR OUT_DIR

Each board icon is rendered from the theme at the board's size, aligned to the board render
by a small search around its expected position, and scored by the mean colour difference over
the icon's opaque pixels (0 = identical, 255 = opposite). Writes one side-by-side sheet per
board group (board | ours | 4x difference) and prints the scores.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw
from PySide6.QtCore import QByteArray, QRectF
from PySide6.QtGui import QGuiApplication, QImage, QPainter
from PySide6.QtSvg import QSvgRenderer


def load(path, stylesheet=None):
    data = open(path, 'rb').read()
    if stylesheet:
        import re
        data = re.sub(rb'(<style[^>]*id="current-color-scheme"[^>]*>)(.*?)(</style>)',
                      lambda m: m.group(1) + stylesheet.encode() + m.group(3), data, count=1, flags=re.S)
    return QSvgRenderer(QByteArray(data))


def render(renderer, px, box, fx=0.0, fy=0.0):
    """Render at px x px, placed at (fx, fy) inside a box x box transparent image."""
    img = QImage(box, box, QImage.Format.Format_RGBA8888)
    img.fill(0)
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    renderer.render(p, QRectF(fx, fy, px, px))
    p.end()
    arr = np.frombuffer(img.constBits(), dtype=np.uint8).reshape(box, img.bytesPerLine() // 4, 4)
    return arr[:, :box].astype(float)


def composite(icon, bg):
    a = icon[..., 3:4] / 255.0
    # QImage RGBA8888 is not premultiplied
    return icon[..., :3] * a + bg * (1 - a), icon[..., 3] / 255.0


def score(board_crop, icon):
    bg = board_crop[0, 0]
    comp, a = composite(icon, bg)
    board_ink = np.abs(board_crop - bg).max(axis=2) > 12
    region = (a > 0.05) | board_ink
    if not region.any():
        return 255.0
    return float(np.abs(board_crop[region] - comp[region]).mean())


def align(board, renderer, px, approx, win, margin):
    box = px + 2 * margin
    base = render(renderer, px, box, margin, margin)
    best = None
    ax, ay = approx
    for dy in range(-win, win + 1):
        for dx in range(-win, win + 1):
            x0, y0 = int(round(ax + dx)) - margin, int(round(ay + dy)) - margin
            crop = board[y0:y0 + box, x0:x0 + box]
            if crop.shape[:2] != (box, box):
                continue
            d = score(crop, base)
            if best is None or d < best[0]:
                best = (d, x0, y0, 0.0, 0.0)
    _, x0, y0, _, _ = best
    crop = board[y0:y0 + box, x0:x0 + box]
    for fy in np.arange(-0.75, 0.76, 0.125):
        for fx in np.arange(-0.75, 0.76, 0.125):
            icon = render(renderer, px, box, margin + fx, margin + fy)
            d = score(crop, icon)
            if d < best[0]:
                best = (d, x0, y0, fx, fy)
    return best


def sheet(rows, out):
    cell = max(r['px'] for r in rows) + 12
    img = Image.new('RGB', (len(rows) * cell, cell * 3 + 16), (16, 20, 42))
    for i, r in enumerate(rows):
        x = i * cell + 6
        img.paste(r['board'], (x, 6))
        img.paste(r['ours'], (x, cell + 6))
        img.paste(r['diff'], (x, 2 * cell + 6))
        ImageDraw.Draw(img).text((x, 3 * cell + 2), f"{r['score']:.1f}", fill=(163, 171, 194))
    scale = 2 if cell < 60 else 1
    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(out)


def compare(board_png, specs, px, stylesheet, out, win=10, margin=6):
    board = np.array(Image.open(board_png).convert('RGB')).astype(float)
    rows = []
    for label, path, approx in specs:
        renderer = load(path, stylesheet)
        d, x0, y0, fx, fy = align(board, renderer, px, approx, win, margin)
        box = px + 2 * margin
        crop_arr = board[y0:y0 + box, x0:x0 + box]
        icon = render(renderer, px, box, margin + fx, margin + fy)
        comp, _a = composite(icon, crop_arr[0, 0])
        crop = Image.fromarray(crop_arr.astype('uint8'))
        ours = Image.fromarray(comp.astype('uint8'))
        diff = ImageChops.difference(crop, ours).point(lambda v: min(255, v * 4))
        rows.append({'label': label, 'px': box, 'board': crop, 'ours': ours, 'diff': diff, 'score': d})
        print(f'{os.path.basename(out)[:-4]:14s} {label:22s} diff {d:5.1f} at {x0 + margin + fx:.2f},{y0 + margin + fy:.2f}')
    sheet(rows, out)
    return rows


# Board layouts (CSS of Icons.dc.html and FileIcons.dc.html) -> expected top-left of each icon.
def fileicons_positions():
    # body padding 56, section padding 24/28, 12 columns, gap 8, icon box 68 px
    grid_w = 1440 - 2 * 56 - 2 * 28
    col = (grid_w - 11 * 8) / 12
    xs = [56 + 28 + i * (col + 8) + col / 2 - 34 for i in range(12)]
    return xs


def main():
    icons, renders, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    app = QGuiApplication(sys.argv[:1])  # noqa: F841
    dark = os.path.join(icons, 'PlasmaFusion-Dark')
    # --- app tiles, Icons board Applications grid at 88 px
    apps = ['files', 'browser', 'terminal', 'mail', 'code', 'music', 'photos', 'settings', 'calendar',
            'notes', 'calculator', 'software', 'videos', 'chat', 'maps', 'weather', 'monitor', 'screenshot']
    grid_w = 1440 - 128 - 520 - 24 - 56
    col = (grid_w - 5 * 12) / 6
    specs = []
    for i, key in enumerate(apps):
        c, r = i % 6, i // 6
        x = 64 + 520 + 24 + 28 + c * (col + 12) + col / 2 - 44
        y = 331 + r * 141
        specs.append((key, os.path.join(dark, 'art', f'tile-{key}.svg'), (x, y)))
    compare(os.path.join(renders, 'icons-1.png'), specs, 88, None, os.path.join(out, 'board-apps.png'))
    # --- logo tile at 104 px (top right of the Icons board)
    compare(os.path.join(renders, 'icons-1.png'), [('fusion', os.path.join(dark, 'art', 'tile-fusion.svg'), (1272, 125))],
            104, None, os.path.join(out, 'board-logo.png'), win=14)
    # --- symbolic set, 24 px, text colour #e8ebf4
    sym = ['search', 'overview', 'home', 'folder', 'document', 'download', 'trash', 'wifi-3', 'volume-high',
           'bluetooth', None, 'brightness', 'moon', 'bell', 'lock', 'power', 'settings', 'clipboard', 'phone',
           'screenshot', 'snap', 'minimize', 'maximize', 'close']
    style = '.ColorScheme-Text{color:#e8ebf4}'
    grid_w = 1440 - 128 - 56
    col = (grid_w - 11 * 12) / 12
    specs = []
    for i, g in enumerate(sym):
        if g is None:
            continue  # the board's Battery glyph has bars; the theme uses the status-board battery
        c, r = i % 12, i // 12
        x = 64 + 28 + c * (col + 12) + col / 2 - 12
        y = 1261 + r * 90
        specs.append((g, os.path.join(dark, 'glyphs', g + '.svg'), (x, y)))
    compare(os.path.join(renders, 'icons-1.png'), specs, 24, style, os.path.join(out, 'board-symbolic.png'), win=8)
    # --- FileIcons board: files, places, devices at 68 px
    xs = fileicons_positions()
    kinds = [('doc', 'DOC'), ('sheet', 'XLS'), ('slides', 'PPT'), ('pdf', 'PDF'), ('image', 'PNG'), ('audio', 'MP3'),
             ('video', 'MP4'), ('archive', 'ZIP'), ('code', 'JS'), ('text', 'TXT'), ('font', 'TTF'), ('disk', 'ISO')]
    specs = [(f'{k}-{l}', os.path.join(dark, 'art', f'mime-{k}-{l}.svg'), (xs[i], 296)) for i, (k, l) in enumerate(kinds)]
    compare(os.path.join(renders, 'icons-2.png'), specs, 68, None, os.path.join(out, 'board-files.png'))
    places = ['folder-folder', 'folder-home', 'folder-desktop', 'folder-documents', 'folder-downloads', 'folder-music',
              'folder-pictures', 'folder-videos', 'folder-projects', 'folder-network', 'trash', 'trash-full']
    specs = [(p, os.path.join(dark, 'art', p + '.svg'), (xs[i], 499)) for i, p in enumerate(places)]
    compare(os.path.join(renders, 'icons-2.png'), specs, 68, None, os.path.join(out, 'board-places.png'))
    devices = ['drive', 'usb', 'phone', 'sdcard', 'optical', 'server', 'printer', 'headphones', 'keyboard', 'mouse',
               'display', 'camera']
    specs = [(d, os.path.join(dark, 'art', f'device-{d}.svg'), (xs[i], 701)) for i, d in enumerate(devices)]
    compare(os.path.join(renders, 'icons-2.png'), specs, 68, None, os.path.join(out, 'board-devices.png'))
    # --- status groups, 26 px, text #e8ebf4, warning #f2c38a, error #ff8a8f
    style = ('.ColorScheme-Text{color:#e8ebf4}.ColorScheme-NeutralText{color:#f2c38a}'
             '.ColorScheme-NegativeText{color:#ff8a8f}')
    status = [['battery-100', 'battery-060', 'battery-030', 'battery-010', 'battery-100-charging'],
              ['wifi-3', 'wifi-2', 'wifi-1', 'wifi-0', 'wifi-off'],
              ['volume-high', 'volume-medium', 'volume-low', 'volume-muted', 'mic-off']]
    sec_w = (1440 - 112 - 44) / 3
    specs = []
    for s, group in enumerate(status):
        inner = sec_w - 56
        step = (inner - 52) / 4
        for i, g in enumerate(group):
            x = 56 + s * (sec_w + 22) + 28 + i * step + 13
            specs.append((g, os.path.join(dark, 'glyphs', g + '.svg'), (x, 915)))
    compare(os.path.join(renders, 'icons-2.png'), specs, 26, style, os.path.join(out, 'board-status.png'), win=10)


if __name__ == '__main__':
    main()
