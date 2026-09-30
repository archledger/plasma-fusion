#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Plasma Fusion wallpapers: the Dusk Ridge scene of the Main boards and the board palettes.

    gen_wallpapers.py wallpapers OUT_DIR [--sizes all|quick]
        Wallpaper packages PlasmaFusion (Dusk Ridge; images/ light, images_dark/ dark) and
        PlasmaFusion-<Name> for the other palettes of Main.dc.html, as OUT_DIR/<Id>/.
    gen_wallpapers.py backgrounds OUT_DIR
        Pre-blurred and pre-darkened Dusk Ridge (dark) for the splash, lock and login screens.
    gen_wallpapers.py svg OUT_DIR
        Write the SVG sources (every scene at 16:10, 16:9 and portrait) to OUT_DIR.
    gen_wallpapers.py check-svg DIR
        Exit 1 if the SVG sources in DIR differ from what this generator writes.

Every picture is an SVG document (see scene_svg) rendered with QtSvg and full anti-aliasing, so
the ridge edges are crisp at every size. The board scene is 1440x900 (16:10). Other aspect ratios
extend or crop the scene instead of stretching it: wider screens (16:9, 21:9, 32:9) get more ridge
at both sides (the ridge lines continue along their outer slopes); 3:2, 4:3 and 5:4 screens show the
full height with the sides cropped around the centre, so the sun and the ridges keep their size
relative to the screen height; portrait screens get more sky above a narrower crop around the sun,
with the front ridge filling the lowest 8 % (under the dock).
"""
import json
import os
import sys

BOARD_W, BOARD_H = 1440, 900

# Ridge outlines of design/boards/Main.dc.html (front to back order is reversed: back first).
RIDGES = [
    [(0, 560), (180, 430), (330, 505), (520, 350), (700, 485), (860, 405), (1060, 520), (1240, 385), (1440, 470)],
    [(0, 650), (220, 545), (420, 620), (640, 505), (880, 612), (1100, 540), (1300, 622), (1440, 580)],
    [(0, 760), (260, 662), (520, 732), (780, 642), (1040, 722), (1280, 662), (1440, 702)],
    [(0, 846), (300, 786), (600, 834), (900, 774), (1200, 824), (1440, 792)],
]
SUN = (1010, 360, 150)       # cx, cy, r
RING_R = 212                 # orbit ring: 2 px stroke of the sun colour at 18 %
SUN_MARGIN = 40              # board units kept between the sun and a cropped screen edge
LINEAR_REACH = 90            # ridges continue straight up to this far past the board (16:9: 80)
BANDS = [(180, 160), (340, 220)]   # y, height of the two sky bands

# The two Dusk Ridge scenes, exactly as drawn on Main.dc.html and MainLight.dc.html.
DUSK_DARK = dict(sky='#141a2e', bands=['#181f3a', '#1c2446'], sun='#f2a65a',
                 ridges=['#253058', '#2e3d73', '#3b56a0', '#5a7fd6'])
DUSK_LIGHT = dict(sky='#dde6f4', bands=['#e6ecf7', '#eef2fa'], sun='#f2a65a',
                  ridges=['#b9c9e8', '#9bb2e0', '#7896d4', '#5a7fd6'])

# const P of Main.dc.html: name, background, sun, near ridge, front ridge.
PALETTES = [
    ('Dusk Ridge', '#1a2140', '#f2a65a', '#2e3d73', '#5a7fd6'),
    ('Coral Bay', '#fbe3d0', '#e8743b', '#f0a384', '#c85a3a'),
    ('Pine Fog', '#dfe8e2', '#9fb8a8', '#6d8f7d', '#3f5f4f'),
    ('Night Grid', '#0f1220', '#8ab8ff', '#1f2a4d', '#33457a'),
    ('Desert Noon', '#f6e7c8', '#f0b429', '#e0b06c', '#b9804a'),
    ('Lagoon', '#cdeef0', '#ffffff', '#5fc3c9', '#1f9e8f'),
    ('Aurora', '#121a26', '#6fe0b0', '#1d3a3f', '#2c5d5a'),
    ('Plum Hills', '#2a1830', '#f2a65a', '#4c2a55', '#7b4a86'),
    ('Glacier', '#e8f0fb', '#9cc3f0', '#b7cdea', '#6f93c7'),
    ('Ember', '#1e1212', '#ff7a45', '#3d1f1a', '#6e2f22'),
    ('Meadow', '#eef5d8', '#f7d154', '#a9c96b', '#5f8f3e'),
    ('Slate Rain', '#2b313f', '#c9d1e0', '#3e4659', '#59627a'),
]

SIZES_ALL = ['1920x1200', '2560x1600', '3840x2400', '1920x1080', '2560x1440', '3840x2160', '1200x1920',
             # ADAPTIVE 5.13: 21:9 and 32:9, 3:2, 4:3, 5:4 and 9:16 screens get their own picture, so
             # Plasma (which picks the image closest in aspect ratio, then width) never crops one
             '2560x1080', '3440x1440', '5120x1440', '3000x2000', '2256x1504', '2048x1536', '1280x1024',
             '1080x1920', '1440x2560', '2160x3840']
SIZES_QUICK = ['1920x1200', '1920x1080', '1200x1920']
ASPECTS = {'16x10': (1600, 1000), '16x9': (1600, 900), 'portrait': (1200, 1920)}

AUTHOR = {'Name': 'Wisbendji Fimerlus', 'Email': 'archledger236@gmail.com'}


# --- colour helpers ------------------------------------------------------------------------------
def hx(c):
    c = c.lstrip('#')
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    A, B = hx(a), hx(b)
    return '#%02x%02x%02x' % tuple(int(round(x + (y - x) * t)) for x, y in zip(A, B))


def luminance(c):
    def lin(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = hx(c)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def palette_scene(bg, sun, m1, m2):
    """The Dusk Ridge composition in another board palette.

    The board thumbnails give only background, sun, near ridge (m1) and front ridge (m2). The full
    scene needs a sky, two lighter sky bands towards the horizon and four ridges; the mixing weights
    below reproduce the board's own Dusk Ridge scenes from their palettes to within a few units per
    channel (dark: Main.dc.html, light: MainLight.dc.html).
    """
    if luminance(bg) < 0.2:   # dark palettes: the sky darkens upwards
        sky, band1, band2 = mix(bg, '#000000', 0.25), mix(bg, '#000000', 0.10), mix(bg, m1, 0.10)
        r3 = mix(m1, m2, 0.40)
    else:                     # light palettes: the horizon is the lightest part
        sky, band1, band2 = mix(bg, m1, 0.18), bg, mix(bg, '#ffffff', 0.35)
        r3 = mix(m1, m2, 0.50)
    return dict(sky=sky, bands=[band1, band2], sun=sun, ridges=[mix(bg, m1, 0.55), m1, r3, m2])


def package_id(name):
    return 'PlasmaFusion' if name == 'Dusk Ridge' else 'PlasmaFusion-' + name.replace(' ', '')


def scenes():
    """(package id, display name, {'images': scene, 'images_dark': scene or None}, accent)."""
    out = [('PlasmaFusion', 'Plasma Fusion Dusk Ridge', {'images': DUSK_LIGHT, 'images_dark': DUSK_DARK}, '#2F6FDF')]
    for name, bg, sun, m1, m2 in PALETTES[1:]:
        out.append((package_id(name), 'Plasma Fusion ' + name, {'images': palette_scene(bg, sun, m1, m2)}, None))
    return out


# --- geometry ------------------------------------------------------------------------------------
def view_box(width, height):
    """Board-unit rectangle (x, y, w, h) shown on a width x height screen."""
    aspect = width / height
    if abs(aspect - BOARD_W / BOARD_H) < 1e-3:
        return 0.0, 0.0, float(BOARD_W), float(BOARD_H)
    if aspect > BOARD_W / BOARD_H:            # wider: more ridge on both sides
        w = BOARD_H * aspect
        return (BOARD_W - w) / 2.0, 0.0, w, float(BOARD_H)
    if aspect >= 1.0:                         # between square and 16:10 (3:2, 4:3, 5:4)
        # The whole height of the scene, cropped at both sides: the ridge stays anchored to the
        # bottom centre (the lightest ridge under the dock) and the sun keeps its size relative
        # to the screen height. Nearly square screens shift the crop right so the sun stays whole.
        w = BOARD_H * aspect
        x0 = (BOARD_W - w) / 2.0
        x0 = max(x0, SUN[0] + SUN[2] + SUN_MARGIN - w)
        return x0, 0.0, w, float(BOARD_H)
    # portrait: a 1000-unit wide crop with the sun at 55 % of the width and 58 % of the height;
    # more sky above, and the front ridge carried down to fill the lowest 8 %
    w = 1000.0
    h = w / aspect
    return SUN[0] - 0.55 * w, BOARD_H - 0.92 * h, w, h


def extend(points, x0, x1):
    """Continue a ridge polyline so it spans [x0, x1].

    Up to LINEAR_REACH board units past an edge (16:9 and narrower) the outer segment continues in a
    straight line, as before. Wider screens (21:9, 32:9) mirror the ridge at the board edges instead:
    a straight continuation over hundreds of units ran the ridges off the bottom on one side and up
    into the sky on the other; the mirrored profile keeps the same mountains and height range.
    """
    pts = list(points)
    lo, hi = pts[0][0], pts[-1][0]
    if x0 >= lo - LINEAR_REACH and x1 <= hi + LINEAR_REACH:
        if x0 < lo:
            (ax, ay), (bx, by) = pts[0], pts[1]
            pts.insert(0, (x0, ay + (by - ay) * (x0 - ax) / (bx - ax)))
        if x1 > hi:
            (ax, ay), (bx, by) = pts[-2], pts[-1]
            pts.append((x1, by + (by - ay) * (x1 - bx) / (bx - ax)))
        return pts
    width = hi - lo

    def y_at(x):
        # reflect x into [lo, hi] (period 2 * width), then interpolate the board polyline
        t = (x - lo) % (2 * width)
        xx = lo + (t if t <= width else 2 * width - t)
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            if ax <= xx <= bx:
                return ay + (by - ay) * (xx - ax) / (bx - ax)
        return pts[-1][1]
    # every board vertex mirrored into [x0, x1], plus the two ends
    xs = {x0, x1}
    k0, k1 = int((x0 - lo) // width) - 1, int((x1 - lo) // width) + 1
    for k in range(k0, k1 + 1):
        for px, _ in pts:
            for x in (px + 2 * k * width, 2 * lo - px + 2 * k * width):
                if x0 < x < x1:
                    xs.add(x)
    return [(x, y_at(x)) for x in sorted(xs)]


def fmt(v):
    s = ('%.2f' % v).rstrip('0').rstrip('.')
    return '0' if s == '-0' else s


def scene_svg(scene, width, height, ring=True, bands=True, title='Plasma Fusion wallpaper'):
    x, y, w, h = view_box(width, height)
    x0, x1 = x - 2, x + w + 2        # a little past the edges so no anti-aliased seam shows
    lines = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%s %s %s %s">' % (
            width, height, fmt(x), fmt(y), fmt(w), fmt(h)),
        '<title>%s</title>' % title,
        '<desc>SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus; SPDX-License-Identifier: CC-BY-SA-4.0</desc>',
        '<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' % (fmt(x0), fmt(y - 2), fmt(x1 - x0), fmt(h + 4), scene['sky']),
    ]
    if bands:
        for i, ((by, bh), colour) in enumerate(zip(BANDS, scene['bands'])):
            if i == len(BANDS) - 1:
                # the lower band ends where the ridges begin on the board (y 560 at both edges);
                # carry it down so a wider crop never shows the darker sky under a continued ridge
                bh = int(round(y + h)) + 2 - by
            lines.append('<rect x="%s" y="%d" width="%s" height="%d" fill="%s"/>' % (fmt(x0), by, fmt(x1 - x0), bh, colour))
    cx, cy, r = SUN
    if ring:
        lines.append('<circle cx="%d" cy="%d" r="%d" fill="none" stroke="%s" stroke-opacity="0.18" stroke-width="2"/>' % (
            cx, cy, RING_R, scene['sun']))
    lines.append('<circle cx="%d" cy="%d" r="%d" fill="%s"/>' % (cx, cy, r, scene['sun']))
    bottom = int(round(y + h)) + 2
    for points, colour in zip(RIDGES, scene['ridges']):
        pts = extend(points, x0, x1)
        d = 'M' + ' L'.join('%s %s' % (fmt(px), fmt(py)) for px, py in pts)
        d += ' L%s %d L%s %d Z' % (fmt(pts[-1][0]), bottom, fmt(pts[0][0]), bottom)
        lines.append('<path d="%s" fill="%s"/>' % (d, colour))
    lines.append('</svg>')
    return '\n'.join(lines) + '\n'


# --- rendering -----------------------------------------------------------------------------------
_app = None


def _qt():
    global _app
    os.environ['QT_QPA_PLATFORM'] = 'offscreen'   # never touch a real display, even inside a session
    from PySide6 import QtCore, QtGui, QtSvg
    if _app is None:
        _app = QtGui.QGuiApplication.instance() or QtGui.QGuiApplication([sys.argv[0]])
    return QtCore, QtGui, QtSvg


def render_svg(svg, width, height):
    """QImage (ARGB32 premultiplied) of an SVG document at the given pixel size."""
    QtCore, QtGui, QtSvg = _qt()
    renderer = QtSvg.QSvgRenderer(QtCore.QByteArray(svg.encode('utf-8')))
    if not renderer.isValid():
        raise SystemExit('invalid SVG')
    image = QtGui.QImage(width, height, QtGui.QImage.Format_ARGB32_Premultiplied)
    image.fill(QtCore.Qt.transparent)
    painter = QtGui.QPainter(image)
    painter.setRenderHint(QtGui.QPainter.Antialiasing, True)
    painter.setRenderHint(QtGui.QPainter.SmoothPixmapTransform, True)
    renderer.render(painter, QtCore.QRectF(0, 0, width, height))
    painter.end()
    return image


def save_png(image, path):
    QtCore, QtGui, _ = _qt()
    image = image.convertToFormat(QtGui.QImage.Format_RGB32)
    if not image.save(path, 'PNG', 0):   # 0 = best compression
        raise SystemExit('cannot write ' + path)


def to_pil(image):
    from PIL import Image
    QtCore, QtGui, _ = _qt()
    image = image.convertToFormat(QtGui.QImage.Format_RGBA8888)
    data = bytes(image.constBits())
    return Image.frombuffer('RGBA', (image.width(), image.height()), data, 'raw', 'RGBA', image.bytesPerLine(), 1).copy()


# --- outputs -------------------------------------------------------------------------------------
def write_wallpapers(out_dir, sizes):
    for pid, name, variants, accent in scenes():
        pkg = os.path.join(out_dir, pid)
        meta = {'KPlugin': {'Authors': [AUTHOR], 'Id': pid, 'License': 'CC-BY-SA-4.0', 'Name': name}}
        if accent:
            meta['X-KDE-PlasmaImageWallpaper-AccentColor'] = {'Light': accent, 'Dark': accent}
        os.makedirs(pkg, exist_ok=True)
        with open(os.path.join(pkg, 'metadata.json'), 'w') as f:
            json.dump(meta, f, indent=4, sort_keys=True)
            f.write('\n')
        for sub, scene in variants.items():
            d = os.path.join(pkg, 'contents', sub)
            os.makedirs(d, exist_ok=True)
            for size in sizes:
                w, h = (int(v) for v in size.split('x'))
                save_png(render_svg(scene_svg(scene, w, h, title=name), w, h), os.path.join(d, '%s.png' % size))
        print('wallpaper %s: %s x %d sizes' % (pid, '+'.join(variants), len(sizes)))


def _css_layer(scene, width, height, blur, opacity, scale, ring, bands):
    """A board SVG layer drawn the way the startup boards style it: CSS filter blur(), opacity and
    transform: scale() about the centre. Returns an RGBA PIL image of width x height."""
    from PIL import Image, ImageFilter
    k = width / BOARD_W
    pad = int(round(4 * blur * k)) if blur else 0
    layer = Image.new('RGBA', (width + 2 * pad, height + 2 * pad), (0, 0, 0, 0))
    layer.alpha_composite(to_pil(render_svg(scene_svg(scene, width, height, ring=ring, bands=bands), width, height)), (pad, pad))
    if blur:
        # blur with premultiplied alpha over a transparent surround, as a browser does
        layer = layer.convert('RGBa').filter(ImageFilter.GaussianBlur(blur * k)).convert('RGBA')
    if scale != 1.0:
        inv = 1.0 / scale
        ox, oy = pad + width / 2.0, pad + height / 2.0
        layer = layer.transform((width, height), Image.AFFINE,
                                (inv, 0, ox - (width / 2.0) * inv, 0, inv, oy - (height / 2.0) * inv),
                                resample=Image.BICUBIC)
    elif pad:
        layer = layer.crop((pad, pad, pad + width, pad + height))
    if opacity < 1.0:
        layer.putalpha(layer.getchannel('A').point(lambda a: int(round(a * opacity))))
    return layer


def write_backgrounds(out_dir, width=1920, height=1200):
    """Dusk Ridge (dark) prepared for the startup screens, at 16:10 (the screens crop to fit)."""
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)

    def base(colour):
        return Image.new('RGBA', (width, height), hx(colour) + (255,))

    def veil(img, rgba):
        img.alpha_composite(Image.new('RGBA', img.size, rgba))
        return img

    outputs = {}
    # Lock.dc.html: the wallpaper as is, under rgba(8,10,22,0.22).
    img = base(DUSK_DARK['sky'])
    img.alpha_composite(_css_layer(DUSK_DARK, width, height, 0, 1.0, 1.0, True, True))
    outputs['dusk-ridge-dark-dimmed.png'] = veil(img, (8, 10, 22, int(round(0.22 * 255))))
    # Login.dc.html: blur(20px) scale(1.08) over #0f1428 (no top band, no ring), then rgba(8,11,24,0.5).
    login = dict(DUSK_DARK, bands=[DUSK_DARK['sky'], DUSK_DARK['bands'][1]])
    img = base('#0f1428')
    img.alpha_composite(_css_layer(login, width, height, 20, 1.0, 1.08, False, True))
    outputs['dusk-ridge-dark-blurred.png'] = img.copy()
    outputs['dusk-ridge-dark-login.png'] = veil(img, (8, 11, 24, int(round(0.5 * 255))))
    # Splash.dc.html: blur(26px) scale(1.08) at 28 % over #0b0e1b (no bands, no ring).
    img = base('#0b0e1b')
    img.alpha_composite(_css_layer(dict(DUSK_DARK, bands=[DUSK_DARK['sky']] * 2), width, height, 26, 0.28, 1.08, False, False))
    outputs['dusk-ridge-dark-splash.png'] = img
    for fname, img in outputs.items():
        img.convert('RGB').save(os.path.join(out_dir, fname), optimize=True)
        print('background', fname, '%dx%d' % img.size)


def svg_sources():
    for pid, name, variants, _ in scenes():
        for sub, scene in variants.items():
            tag = 'dark' if sub == 'images_dark' else ('light' if pid == 'PlasmaFusion' else '')
            for aspect, (w, h) in ASPECTS.items():
                fname = '%s%s-%s.svg' % (pid, ('-' + tag) if tag else '', aspect)
                yield fname, scene_svg(scene, w, h, title=name)


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd, target = argv[0], argv[1]
    if cmd == 'wallpapers':
        sizes = SIZES_QUICK if '--sizes' in argv and argv[argv.index('--sizes') + 1] == 'quick' else SIZES_ALL
        write_wallpapers(target, sizes)
    elif cmd == 'backgrounds':
        write_backgrounds(target)
    elif cmd == 'svg':
        os.makedirs(target, exist_ok=True)
        for fname, svg in svg_sources():
            with open(os.path.join(target, fname), 'w') as f:
                f.write(svg)
    elif cmd == 'check-svg':
        stale = []
        expected = dict(svg_sources())
        for fname, svg in expected.items():
            path = os.path.join(target, fname)
            if not os.path.exists(path) or open(path).read() != svg:
                stale.append(fname)
        extra = sorted(set(f for f in os.listdir(target) if f.endswith('.svg')) - set(expected))
        if stale or extra:
            sys.exit('SVG sources out of date (run: gen_wallpapers.py svg %s): %s' % (target, ' '.join(stale + extra)))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
