#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build the Plasma Fusion cursor themes.

    QT_QPA_PLATFORM=offscreen gen_cursors.py --out DIR [--theme NAME ...]

writes DIR/PlasmaFusion-cursors (dark fill, white outline) and DIR/PlasmaFusion-Light-cursors
(white fill, #1b2031 outline). Each theme holds

  index.theme                    [Icon Theme] Name, Comment, Example, Inherits
  cursors_scalable/<shape>/      KWin SVG cursor: <shape>.svg or <shape>-NN.svg + metadata.json
  cursors_scalable/<alias>       relative symlink to a drawing directory (same directory)
  cursors/<shape>                Xcursor file for XWayland, GTK 3 and the cursor settings page
  cursors/<alias>                relative symlink to an Xcursor file

The SVGs keep the board's 32-unit canvas (nominal_size 32): at cursor size 24 the 32 units are
drawn at 24 px, exactly like the board's 24/32/48/64 size ramp. A 4-unit margin around it
(viewBox -4 -4 40 40, hotspots shifted by 4) holds the shadow, so a size-24 image is 30 px. The
Xcursor images are the same SVGs rendered with QtSvg (the renderer KWin uses) at every size in
XCURSOR_SIZES.
"""
import argparse
import json
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import shapes  # noqa: E402
import xcursor  # noqa: E402

NOMINAL = 32
# The drawings use the board's 32-unit canvas; the image adds MARGIN units on every side so the
# shadow is not cut off (Breeze does the same: 32 px images for nominal size 24). MARGIN is a
# multiple of 4 so the drawing keeps its pixel grid at every size (4 units = 3 px at size 24).
MARGIN = 4
CANVAS = NOMINAL + 2 * MARGIN
# The board's sizes 24/32/48/64 plus 96 and 128 for GTK 3 on a scaled output (it asks for
# size x ceil(scale): 24 at 4/3 -> 48, 48 at 2 -> 96, 64 at 2 -> 128). The cursor settings page
# offers exactly these sizes (it lists the sizes found in cursors/left_ptr).
XCURSOR_SIZES = [24, 32, 48, 64, 96, 128]

# Board, "Sizes" panel (the pointers at their real sizes): drop-shadow(0 2px 3px rgba(0,0,0,.35)).
# The shadow is designed for size 24, the size the themes are applied with: at 24 px the 32-unit
# canvas is 24 px, so 2 px -> 2.667 units down and blur radius 3 px (Gaussian sigma 1.5 px) ->
# sigma 2 units. It scales with the pointer at other sizes.
SHADOW_DY = 2 * NOMINAL / 24
SHADOW_SIGMA = 1.5 * NOMINAL / 24
SHADOW_OPACITY = 0.35

SVG_HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="{canvas}" height="{canvas}" '
            'viewBox="{origin} {origin} {canvas} {canvas}">\n'
            '<!-- Plasma Fusion cursors. SPDX-License-Identifier: CC-BY-SA-4.0 -->\n'
            '<filter id="shadow" x="{origin}" y="{origin}" width="{canvas}" height="{canvas}" '
            'filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">'
            '<feGaussianBlur stdDeviation="{sigma}"/></filter>\n')


def colour(value, theme):
    return theme[value] if value in theme else value


def body(layers, theme, out):
    edge = theme['edge']
    for layer in layers:
        kind = layer[0]
        if kind == 'F':
            _, d, c = layer
            out.append(f'<path d="{d}" fill="{colour(c, theme)}" stroke="{edge}" stroke-width="1.6" '
                       'stroke-linejoin="round"/>')
        elif kind in ('L', 'W'):
            if kind == 'L':
                _, d, c = layer
                w, u = 2.0, 4.4
            else:
                _, d, c, w, u = layer
            for stroke, width in ((edge, u), (colour(c, theme), w)):
                out.append(f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{shapes.fmt(width)}" '
                           'stroke-linecap="round" stroke-linejoin="round"/>')
        elif kind == 'P':
            _, d, c = layer
            out.append(f'<path d="{d}" fill="{colour(c, theme)}"/>')
        elif kind == 'S':
            _, d, c, w = layer
            out.append(f'<path d="{d}" fill="none" stroke="{colour(c, theme)}" stroke-width="{shapes.fmt(w)}" '
                       'stroke-linecap="round" stroke-linejoin="round"/>')
        elif kind == 'G':
            _, transform, inner = layer
            out.append(f'<g transform="{transform}">')
            body(inner, theme, out)
            out.append('</g>')
        else:
            raise ValueError(f'unknown layer {kind}')


def silhouette(layers, out):
    """Black copy of everything that is painted, for the blurred shadow."""
    for layer in layers:
        kind = layer[0]
        if kind == 'F':
            out.append(f'<path d="{layer[1]}" stroke="#000" stroke-width="1.6" stroke-linejoin="round"/>')
        elif kind in ('L', 'W'):
            u = 4.4 if kind == 'L' else layer[4]
            out.append(f'<path d="{layer[1]}" fill="none" stroke="#000" stroke-width="{shapes.fmt(u)}" '
                       'stroke-linecap="round" stroke-linejoin="round"/>')
        elif kind == 'P':
            out.append(f'<path d="{layer[1]}"/>')
        elif kind == 'G':
            out.append(f'<g transform="{layer[1]}">')
            silhouette(layer[2], out)
            out.append('</g>')
        # 'S' strokes sit inside other shapes and add nothing to the outline


def svg_document(layers, theme):
    out = [SVG_HEAD.format(sigma=shapes.fmt(SHADOW_SIGMA), canvas=CANVAS, origin=-MARGIN)]
    out.append(f'<g opacity="{shapes.fmt(SHADOW_OPACITY)}" filter="url(#shadow)">'
               f'<g transform="translate(0 {shapes.fmt(SHADOW_DY)})">')
    silhouette(layers, out)
    out.append('</g></g>\n')
    body(layers, theme, out)
    out.append('\n</svg>\n')
    return ''.join(out)


def check_names():
    names = set(shapes.SHAPES)
    for target, aliases in shapes.ALIASES.items():
        if target not in names:
            raise SystemExit(f'alias target {target} has no drawing')
        for a in aliases:
            if a in names:
                raise SystemExit(f'alias {a} collides with a drawing')
            names.add(a)
    all_aliases = [a for v in shapes.ALIASES.values() for a in v]
    dup = {a for a in all_aliases if all_aliases.count(a) > 1}
    if dup:
        raise SystemExit(f'duplicate aliases: {sorted(dup)}')
    return names


class Rasteriser:
    def __init__(self):
        os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
        from PySide6.QtCore import QByteArray, QRectF
        from PySide6.QtGui import QGuiApplication, QImage, QPainter
        from PySide6.QtSvg import QSvgRenderer
        self.app = QGuiApplication.instance() or QGuiApplication([sys.argv[0]])
        self.QByteArray, self.QRectF, self.QImage, self.QPainter, self.QSvgRenderer = (
            QByteArray, QRectF, QImage, QPainter, QSvgRenderer)

    def render(self, svg_text, px):
        """Premultiplied ARGB32 pixels, little-endian words (the Xcursor pixel format)."""
        renderer = self.QSvgRenderer(self.QByteArray(svg_text.encode()))
        if not renderer.isValid():
            raise SystemExit('QtSvg rejected a generated SVG')
        img = self.QImage(px, px, self.QImage.Format.Format_ARGB32_Premultiplied)
        img.fill(0)
        p = self.QPainter(img)
        p.setRenderHint(self.QPainter.RenderHint.Antialiasing)
        renderer.render(p, self.QRectF(0, 0, px, px))
        p.end()
        if img.bytesPerLine() != px * 4:
            raise SystemExit('unexpected QImage stride')
        if sys.byteorder != 'little':
            raise SystemExit('the Xcursor writer expects a little-endian host')
        return bytes(img.constBits())[:px * px * 4]


def image_px(size):
    """Xcursor image edge for a nominal size (the canvas plus its margin)."""
    px = size * CANVAS / NOMINAL
    if px != int(px):
        raise SystemExit(f'cursor size {size} does not give a whole-pixel image')
    return int(px)


def xcursor_hotspot(value, size):
    # The pixel that contains the design hotspot (board units, 0..32) at this nominal size.
    px = image_px(size)
    return min(px - 1, max(0, int(math.floor((value + MARGIN) * size / NOMINAL + 1e-6))))


def write_theme(out_dir, name, raster, sizes):
    display, comment, inherits, theme = shapes.THEMES[name]
    root = os.path.join(out_dir, name)
    if os.path.lexists(root):
        shutil.rmtree(root)
    scal = os.path.join(root, 'cursors_scalable')
    xdir = os.path.join(root, 'cursors')
    os.makedirs(scal)
    os.makedirs(xdir)
    with open(os.path.join(root, 'index.theme'), 'w') as f:
        f.write('[Icon Theme]\n'
                f'Name={display}\n'
                f'Comment={comment}\n'
                'Example=default\n'
                f'Inherits={inherits}\n')

    for shape in sorted(shapes.SHAPES):
        spec = shapes.SHAPES[shape]
        hx, hy = spec['hotspot']
        frames = spec['frames']
        sdir = os.path.join(scal, shape)
        os.makedirs(sdir)
        meta = []
        docs = []
        for i, (layers, delay) in enumerate(frames):
            fn = f'{shape}.svg' if len(frames) == 1 else f'{shape}-{i + 1:02d}.svg'
            doc = svg_document(layers, theme)
            with open(os.path.join(sdir, fn), 'w') as f:
                f.write(doc)
            entry = {'filename': fn, 'hotspot_x': hx + MARGIN, 'hotspot_y': hy + MARGIN,
                     'nominal_size': NOMINAL}
            if delay is not None:
                entry['delay'] = delay
            meta.append(entry)
            docs.append((doc, delay or 0))
        with open(os.path.join(sdir, 'metadata.json'), 'w') as f:
            json.dump(meta, f, indent=4)
            f.write('\n')

        images = []
        for size in sizes:
            px = image_px(size)
            xh, yh = xcursor_hotspot(hx, size), xcursor_hotspot(hy, size)
            for doc, delay in docs:
                images.append(xcursor.Image(size, px, px, xh, yh, delay, raster.render(doc, px)))
        with open(os.path.join(xdir, shape), 'wb') as f:
            f.write(xcursor.encode(images))

    for target, aliases in shapes.ALIASES.items():
        for a in aliases:
            os.symlink(target, os.path.join(scal, a))
            os.symlink(target, os.path.join(xdir, a))
    return root


def verify(root, sizes, names):
    """Read back what was written: metadata, SVG validity, Xcursor structure, aliases."""
    from PySide6.QtSvg import QSvgRenderer
    scal = os.path.join(root, 'cursors_scalable')
    xdir = os.path.join(root, 'cursors')
    problems = []
    for n in sorted(names):
        for base in (scal, xdir):
            p = os.path.join(base, n)
            if not os.path.lexists(p):
                problems.append(f'missing {p}')
            elif os.path.islink(p) and ('/' in os.readlink(p) or not os.path.exists(p)):
                problems.append(f'bad alias {p} -> {os.readlink(p)}')
    for shape in shapes.SHAPES:
        meta = json.load(open(os.path.join(scal, shape, 'metadata.json')))
        for e in meta:
            r = QSvgRenderer(os.path.join(scal, shape, e['filename']))
            if not r.isValid() or r.defaultSize().width() != CANVAS:
                problems.append(f'svg {shape}/{e["filename"]}')
        with open(os.path.join(xdir, shape), 'rb') as f:
            imgs = xcursor.decode(f.read())
        if xcursor.nominal_sizes(imgs) != sorted(sizes):
            problems.append(f'xcursor sizes {shape}')
        if any(im.width != image_px(im.size) or im.height != image_px(im.size) for im in imgs):
            problems.append(f'xcursor image size {shape}')
        if len(imgs) != len(sizes) * len(meta):
            problems.append(f'xcursor frame count {shape}')
    if problems:
        raise SystemExit('cursor theme check failed:\n  ' + '\n  '.join(problems))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', required=True, help='icons directory (for example ~/.local/share/icons)')
    ap.add_argument('--theme', action='append', choices=sorted(shapes.THEMES), help='build only this theme')
    ap.add_argument('--sizes', help='comma-separated Xcursor sizes (default: %s)' % ','.join(map(str, XCURSOR_SIZES)))
    args = ap.parse_args()
    sizes = [int(s) for s in args.sizes.split(',')] if args.sizes else XCURSOR_SIZES
    names = check_names()
    raster = Rasteriser()
    os.makedirs(args.out, exist_ok=True)
    for name in args.theme or sorted(shapes.THEMES):
        root = write_theme(args.out, name, raster, sizes)
        verify(root, sizes, names)
        print(f'{name}: {len(shapes.SHAPES)} drawings, {len(names)} names, Xcursor sizes {sizes}')


if __name__ == '__main__':
    main()
