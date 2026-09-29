#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Contact sheets for the built cursor themes (verification only, not part of the build).

    QT_QPA_PLATFORM=offscreen sheet.py --icons DIR --out OUTDIR [--board theme-parts-5.png]

contact-<theme>.png   every drawing, read back from the Xcursor files (24, 32, 48 px on light,
                      dark and window backgrounds, amber ring on the 48 px hotspot) plus the
                      SVG rendered the way KWin does (nominal 32 -> size 64), and every alias
board-compare.png     the board render (Pointers.dc.html) above the same panels rebuilt from
                      the built themes: the 12 cards at 72 px, the light variant at 48 px,
                      the size ramp from the Xcursor images and the busy key frames at 52 px
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

from PySide6.QtCore import QPointF, QRectF, Qt  # noqa: E402
from PySide6.QtGui import (QColor, QFont, QFontDatabase, QGuiApplication, QImage, QPainter,  # noqa: E402
                           QPen)
from PySide6.QtSvg import QSvgRenderer  # noqa: E402

import gen_cursors  # noqa: E402
import shapes  # noqa: E402
import xcursor  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
DARK_THEME = 'PlasmaFusion-cursors'
LIGHT_THEME = 'PlasmaFusion-Light-cursors'


def font(px, weight=700, family='Manrope'):
    f = QFont(family)
    f.setPixelSize(px)
    f.setWeight(QFont.Weight(weight))
    return f


def x_frames(theme_dir, name, size):
    with open(os.path.join(theme_dir, 'cursors', name), 'rb') as f:
        imgs = xcursor.decode(f.read())
    out = []
    for im in imgs:
        if im.size != size:
            continue
        q = QImage(im.pixels, im.width, im.height, im.width * 4, QImage.Format.Format_ARGB32_Premultiplied)
        out.append((q.copy(), im.xhot, im.yhot, im.delay))
    return out


def margin_px(size):
    """Offset of the board's 32-unit canvas inside a cursor image of this nominal size."""
    return gen_cursors.MARGIN * size / gen_cursors.NOMINAL


def svg_image(theme_dir, name, size, frame=0):
    """Rendered like KWin's SvgCursorReader: scale = size / nominal_size. The image is larger
    than the size by the shadow margin; the hotspot is relative to the image."""
    d = os.path.join(theme_dir, 'cursors_scalable', name)
    meta = json.load(open(os.path.join(d, 'metadata.json')))
    e = meta[frame]
    r = QSvgRenderer(os.path.join(d, e['filename']))
    scale = size / e['nominal_size']
    w, h = round(r.defaultSize().width() * scale), round(r.defaultSize().height() * scale)
    img = QImage(w, h, QImage.Format.Format_ARGB32_Premultiplied)
    img.fill(0)
    p = QPainter(img)
    r.render(p, QRectF(0, 0, w, h))
    p.end()
    return img, (e['hotspot_x'] * scale, e['hotspot_y'] * scale), len(meta)


def ring(p, x, y, r=3.0):
    p.setPen(QPen(QColor('#f2a65a'), 1.2))
    p.setBrush(Qt.BrushStyle.NoBrush)
    p.drawEllipse(QPointF(x, y), r, r)


def contact_sheet(icons, theme, out_path):
    tdir = os.path.join(icons, theme)
    names = sorted(shapes.SHAPES, key=lambda n: (n not in shapes.BOARD_ORDER,
                                                 shapes.BOARD_ORDER.index(n) if n in shapes.BOARD_ORDER else 0, n))
    cols, cw, ch = 6, 236, 150
    rows = (len(names) + cols - 1) // cols
    head = 70
    W, H = cols * cw + 40, head + rows * ch + 20
    img = QImage(W, H, QImage.Format.Format_RGB32)
    img.fill(QColor('#10142a'))
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    p.setPen(QColor('#e8ebf4'))
    p.setFont(font(22, 800))
    p.drawText(20, 34, f'{theme}: {len(names)} drawings, '
                       f'{sum(len(v) for v in shapes.ALIASES.values())} aliases')
    p.setFont(font(12, 500))
    p.setPen(QColor('#a3abc2'))
    p.drawText(20, 56, 'Xcursor read back at 24 / 32 / 48 px (amber ring = hotspot pixel) and the SVG '
                       'rendered like KWin at size 64 (right, shown at half size)')
    tiles = [('#eef0f5', 24, 48), ('#1f2644', 32, 48), ('#2a3150', 48, 64)]
    for i, n in enumerate(names):
        x = 20 + (i % cols) * cw
        y = head + (i // cols) * ch
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor('#171c33'))
        p.drawRoundedRect(QRectF(x, y, cw - 12, ch - 12), 12, 12)
        tx = x + 8
        for bg, s, tw in tiles:
            p.setBrush(QColor(bg))
            p.drawRoundedRect(QRectF(tx, y + 10, tw, 84), 8, 8)
            frames = x_frames(tdir, n, s)
            q, xh, yh, _ = frames[0]
            ox = tx + (tw - q.width()) / 2
            oy = y + 10 + (84 - q.height()) / 2
            p.drawImage(QPointF(ox, oy), q)
            if s == 48:
                ring(p, ox + xh + 0.5, oy + yh + 0.5, 2.2)
            tx += tw + 4
        simg, _, nframes = svg_image(tdir, n, 64)
        # the SVG (rendered at size 64 like KWin) sits right of the three Xcursor tiles, half size
        p.drawImage(QRectF(tx, y + 16, simg.width() / 2, simg.height() / 2), simg)
        p.setPen(QColor('#e8ebf4'))
        p.setFont(font(12, 800))
        label = n + (f'  ({nframes} frames)' if nframes > 1 else '')
        p.drawText(QRectF(x + 8, y + 100, cw - 28, 18), Qt.AlignmentFlag.AlignLeft, label)
        p.setFont(font(10, 500))
        p.setPen(QColor('#8f98b3'))
        al = ', '.join(shapes.ALIASES.get(n, []))
        p.drawText(QRectF(x + 8, y + 116, cw - 28, 20), Qt.AlignmentFlag.AlignLeft,
                   (al[:44] + '...') if len(al) > 47 else al)
    p.end()
    img.save(out_path)


def find_box(board, colour, region, tol=4):
    """Bounding box of one background colour (within tol per channel; the render is colour
    managed, so #2a3150 comes out as #292f4f) inside region (x0, y0, x1, y1)."""
    c = QColor(colour)
    x0, y0, x1, y1 = region
    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1, 2):
            q = QColor(board.pixel(x, y))
            if abs(q.red() - c.red()) <= tol and abs(q.green() - c.green()) <= tol and abs(q.blue() - c.blue()) <= tol:
                xs.append(x)
                ys.append(y)
    return min(xs), min(ys), max(xs) + 2, max(ys) + 1


def space_around(box, n, item, pad=10):
    x0, y0, x1, y1 = box
    inner = (x1 - x0) - 2 * pad
    gap = (inner - n * item) / n
    return [x0 + pad + gap / 2 + i * (item + gap) for i in range(n)]


def board_compare(icons, board_path, out_path):
    board = QImage(board_path).convertToFormat(QImage.Format.Format_RGB32)
    dark = os.path.join(icons, DARK_THEME)
    light = os.path.join(icons, LIGHT_THEME)
    Z = 2  # zoom
    parts = []

    # 1) the twelve cards: board crop (100x100 around the 72 px svg) and ours
    cards_b = QImage(12 * 110, 100, QImage.Format.Format_RGB32)
    cards_o = QImage(12 * 110, 100, QImage.Format.Format_RGB32)
    cards_b.fill(QColor('#10142a'))
    cards_o.fill(QColor('#10142a'))
    pb, po = QPainter(cards_b), QPainter(cards_o)
    for i, n in enumerate(shapes.BOARD_ORDER):
        c, r = i % 6, i // 6
        x0, y0 = 56 + 224 * c, 233 + 192 * r
        sx, sy = x0 + 68, y0 + 29  # top-left of the board's 72 px svg (from the hotspot rings)
        pb.drawImage(QPointF(i * 110, 0), board.copy(sx - 14, sy - 14, 100, 100))
        po.fillRect(QRectF(i * 110, 0, 100, 100), QColor(board.pixel(sx - 10, sy - 10)))
        img, _, _ = svg_image(dark, n, 72)
        po.drawImage(QPointF(i * 110 + 14 - margin_px(72), 14 - margin_px(72)), img)
    pb.end()
    po.end()
    parts.append(('Board: the 12 pointers at 72 px (Pointers.dc.html cards)', cards_b))
    parts.append(('Build: PlasmaFusion-cursors SVGs rendered like KWin at 72 px', cards_o))

    # 2) light variant panel
    box = find_box(board, '#2a3150', (60, 640, 560, 870))
    xs = space_around(box, 6, 48)
    ytop = box[1] + (box[3] - box[1] - 48) / 2
    lb = board.copy(box[0], box[1], box[2] - box[0], box[3] - box[1])
    lo = QImage(lb.size(), QImage.Format.Format_RGB32)
    lo.fill(QColor(board.pixel(box[0] + 3, (box[1] + box[3]) // 2)))
    p = QPainter(lo)
    for i, n in enumerate(['default', 'pointer', 'text', 'progress', 'nwse-resize', 'copy']):
        img, _, _ = svg_image(light, n, 48)
        p.drawImage(QPointF(xs[i] - box[0] - margin_px(48), ytop - box[1] - margin_px(48)), img)
    p.end()
    parts.append(('Board: light variant', lb))
    parts.append(('Build: PlasmaFusion-Light-cursors at 48 px', lo))

    # 3) size ramp: board (CSS shadow .35) vs our Xcursor images at exactly 24/32/48/64 px
    box = find_box(board, '#eef0f5', (590, 640, 970, 870))
    sb = board.copy(box[0], box[1], box[2] - box[0], box[3] - box[1])
    so = QImage(sb.size(), QImage.Format.Format_RGB32)
    so.fill(QColor(board.pixel(box[0] + 3, (box[1] + box[3]) // 2)))
    p = QPainter(so)
    inner = (box[2] - box[0]) - 20
    gap = (inner - (24 + 32 + 48 + 64)) / 4
    x = 10 + gap / 2
    p.setFont(font(11, 800))
    for s in (24, 32, 48, 64):
        q = x_frames(dark, 'default', s)[0][0]
        bottom = (box[3] - box[1]) - 14 - 15 - 6
        p.drawImage(QPointF(x - margin_px(s), bottom - s - margin_px(s)), q)
        p.setPen(QColor('#3d4459'))
        p.drawText(QRectF(x, bottom + 6, s, 15), Qt.AlignmentFlag.AlignHCenter, str(s))
        x += s + gap
    p.end()
    parts.append(('Board: sizes 24 / 32 / 48 / 64', sb))
    parts.append(('Build: default pointer read back from the Xcursor file at 24 / 32 / 48 / 64', so))

    # 4) busy key frames 0/30/60/90 degrees = frames 1, 4, 7, 10 of 12
    box = find_box(board, '#1f2644', (1000, 700, 1380, 860))
    xs = space_around(box, 4, 52)
    ytop = box[1] + (box[3] - box[1] - 52) / 2
    bb = board.copy(box[0], box[1], box[2] - box[0], box[3] - box[1])
    bo = QImage(bb.size(), QImage.Format.Format_RGB32)
    bo.fill(QColor(board.pixel(box[0] + 3, (box[1] + box[3]) // 2)))
    p = QPainter(bo)
    for i, frame in enumerate((0, 3, 6, 9)):
        img, _, _ = svg_image(dark, 'wait', 52, frame)
        p.drawImage(QPointF(xs[i] - box[0] - margin_px(52), ytop - box[1] - margin_px(52)), img)
    p.end()
    parts.append(('Board: busy animation key frames', bb))
    parts.append(('Build: wait frames 1, 4, 7, 10 of 12 (0, 30, 60, 90 degrees) at 52 px', bo))

    height = 20 + sum(28 + part.height() * Z + 10 for _, part in parts)
    width = max(part.width() for _, part in parts) * Z + 40
    out = QImage(width, height, QImage.Format.Format_RGB32)
    out.fill(QColor('#0b0e1d'))
    p = QPainter(out)
    p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, False)
    y = 20
    for title, part in parts:
        p.setPen(QColor('#e8ebf4'))
        p.setFont(font(16, 800))
        p.drawText(20, y + 18, title)
        y += 28
        p.drawImage(QRectF(20, y, part.width() * Z, part.height() * Z), part)
        y += part.height() * Z + 10
    p.end()
    out.save(out_path)


def session_vs_board(board_path, session, out_path):
    """Board cards (72 px) next to what KWin drew in a virtual session at size 24, zoomed 3x."""
    board = QImage(board_path).convertToFormat(QImage.Format.Format_RGB32)
    pos = json.load(open(os.path.join(session, 'qt-positions.json')))
    cell = 96  # a 32 px crop of the session screenshot, zoomed 3x
    out = QImage(6 * (cell + 12) + 30, 2 * (2 * cell + 40) + 60, QImage.Format.Format_RGB32)
    out.fill(QColor('#0b0e1d'))
    p = QPainter(out)
    p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, False)
    p.setPen(QColor('#e8ebf4'))
    p.setFont(font(16, 800))
    p.drawText(20, 30, 'Board card (72 px) above the pointer KWin drew in the test session at size 24, zoomed 3x')
    for i, n in enumerate(shapes.BOARD_ORDER):
        c, r = i % 6, i // 6
        x0, y0 = 56 + 224 * c, 233 + 192 * r
        sx, sy = x0 + 68, y0 + 29
        bx = 20 + c * (cell + 12)
        by = 50 + r * (2 * cell + 40)
        p.drawImage(QPointF(bx, by), board.copy(sx - 12, sy - 12, cell, cell))
        hx, hy = shapes.SHAPES[n]['hotspot']
        px, py = pos[n]
        ox, oy = round(px - hx * 0.75), round(py - hy * 0.75)
        shot = QImage(os.path.join(session, f'qt-{n}.png')).copy(ox - 4, oy - 4, 32, 32)
        p.drawImage(QRectF(bx, by + cell + 6, cell, cell), shot)
        p.setFont(font(11, 700))
        p.drawText(QRectF(bx, by + 2 * cell + 8, cell, 16), Qt.AlignmentFlag.AlignHCenter, n)
    p.end()
    out.save(out_path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--icons', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--board', help='render of Pointers.dc.html (1440x920)')
    ap.add_argument('--session', help='vsession results with qt-*.png from vsession/scenario-qt.sh')
    args = ap.parse_args()
    app = QGuiApplication([sys.argv[0]])  # noqa: F841
    for fam in ('manrope/Manrope[wght].ttf',):
        QFontDatabase.addApplicationFont(os.path.join(ROOT, 'fonts', fam))
    os.makedirs(args.out, exist_ok=True)
    for theme in (DARK_THEME, LIGHT_THEME):
        contact_sheet(args.icons, theme, os.path.join(args.out, f'contact-{theme}.png'))
    if args.board:
        board_compare(args.icons, args.board, os.path.join(args.out, 'board-compare.png'))
    if args.board and args.session:
        session_vs_board(args.board, args.session, os.path.join(args.out, 'session-vs-board.png'))


if __name__ == '__main__':
    main()
