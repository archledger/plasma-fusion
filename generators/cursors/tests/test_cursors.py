#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Checks for the cursor themes.

    QT_QPA_PLATFORM=offscreen test_cursors.py [--work DIR]

1. builds both themes twice into DIR and compares every file and link (reproducible build)
2. parses every SVG with ElementTree and every metadata.json the way KWin's SvgCursorReader does
3. loads every name through the system libXcursor (XcursorLibraryLoadImages with XCURSOR_PATH set
   to the build), so theme lookup, aliases and the binary format are checked by the real reader,
   and compares the pixels with the drawing the alias points to
4. checks that every name of breeze_cursors and Adwaita exists, so nothing falls back to them
"""
import argparse
import ctypes
import filecmp
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(os.path.dirname(HERE), 'gen_cursors.py')
sys.path.insert(0, os.path.dirname(HERE))
import gen_cursors  # noqa: E402
import shapes  # noqa: E402

THEMES = sorted(shapes.THEMES)


def tree_digest(root):
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for n in dirnames + filenames:
            p = os.path.join(dirpath, n)
            rel = os.path.relpath(p, root)
            if os.path.islink(p):
                out[rel] = 'link:' + os.readlink(p)
            elif os.path.isfile(p):
                out[rel] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    return out


class XcursorImage(ctypes.Structure):
    _fields_ = [('version', ctypes.c_uint), ('size', ctypes.c_uint), ('width', ctypes.c_uint),
                ('height', ctypes.c_uint), ('xhot', ctypes.c_uint), ('yhot', ctypes.c_uint),
                ('delay', ctypes.c_uint), ('pixels', ctypes.POINTER(ctypes.c_uint))]


class XcursorImages(ctypes.Structure):
    _fields_ = [('nimage', ctypes.c_int), ('images', ctypes.POINTER(ctypes.POINTER(XcursorImage))),
                ('name', ctypes.c_char_p)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--work', help='scratch directory (default: a new temporary directory)')
    args = ap.parse_args()
    work = tempfile.mkdtemp(prefix='pf-cursors-', dir=args.work)
    fails = []
    try:
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen')
        a, b = os.path.join(work, 'a'), os.path.join(work, 'b')
        for d in (a, b):
            subprocess.run([sys.executable, '-B', GEN, '--out', d], check=True, env=env, stdout=subprocess.DEVNULL)
        for t in THEMES:
            da, db = tree_digest(os.path.join(a, t)), tree_digest(os.path.join(b, t))
            if da != db:
                diff = sorted(k for k in set(da) | set(db) if da.get(k) != db.get(k))
                fails.append(f'{t}: build not reproducible: {diff[:5]}')
        print(f'reproducible: {len(tree_digest(a))} paths compared')

        # SVG + metadata, as KWin reads them
        nsvg = 0
        for t in THEMES:
            scal = os.path.join(a, t, 'cursors_scalable')
            for n in os.listdir(scal):
                meta = json.load(open(os.path.join(scal, n, 'metadata.json')))
                if not isinstance(meta, list) or not meta:
                    fails.append(f'{t}/{n}: metadata is not a non-empty array')
                for e in meta:
                    for k in ('filename', 'nominal_size', 'hotspot_x', 'hotspot_y'):
                        if k not in e:
                            fails.append(f'{t}/{n}: metadata lacks {k}')
                    c = gen_cursors.CANVAS
                    if not (0 <= e['hotspot_x'] < c and 0 <= e['hotspot_y'] < c):
                        fails.append(f'{t}/{n}: hotspot outside the canvas')
                    if e['nominal_size'] != gen_cursors.NOMINAL:
                        fails.append(f'{t}/{n}: nominal_size {e["nominal_size"]}')
                    root = ET.parse(os.path.join(scal, n, e['filename'])).getroot()
                    if root.get('width') != str(c) or root.get('height') != str(c):
                        fails.append(f'{t}/{n}: canvas is not {c}x{c}')
                    nsvg += 1
                if len(meta) > 1 and sum(e.get('delay', 0) for e in meta) != 800:
                    fails.append(f'{t}/{n}: animation loop is not 800 ms')
        print(f'svg: {nsvg} documents parsed (aliases included)')

        # libXcursor, the reader of XWayland apps and the cursor settings page
        os.environ['XCURSOR_PATH'] = a
        xc = ctypes.CDLL('libXcursor.so.1')
        xc.XcursorLibraryLoadImages.restype = ctypes.POINTER(XcursorImages)
        xc.XcursorLibraryLoadImages.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
        xc.XcursorImagesDestroy.argtypes = [ctypes.POINTER(XcursorImages)]
        names = set(shapes.SHAPES) | {x for v in shapes.ALIASES.values() for x in v}
        target = {n: n for n in shapes.SHAPES}
        target.update({x: k for k, v in shapes.ALIASES.items() for x in v})
        checked = 0
        for t in THEMES:
            for n in sorted(names):
                for size in (24, 48):
                    p = xc.XcursorLibraryLoadImages(n.encode(), t.encode(), size)
                    if not p:
                        fails.append(f'libXcursor: {t} {n} {size} not found')
                        continue
                    imgs = p.contents
                    frames = len(shapes.SHAPES[target[n]]['frames'])
                    if imgs.nimage != frames:
                        fails.append(f'libXcursor: {t} {n}: {imgs.nimage} frames, expected {frames}')
                    im = imgs.images[0].contents
                    edge = gen_cursors.image_px(size)
                    if im.size != size or im.width != edge or im.height != edge:
                        fails.append(f'libXcursor: {t} {n}: size {im.size}/{im.width}, expected {size}/{edge}')
                        xc.XcursorImagesDestroy(p)
                        continue
                    hx, hy = shapes.SHAPES[target[n]]['hotspot']
                    m = gen_cursors.MARGIN
                    if (im.xhot, im.yhot) != (int((hx + m) * size / 32), int((hy + m) * size / 32)):
                        fails.append(f'libXcursor: {t} {n}: hotspot {im.xhot},{im.yhot}')
                    px = bytes(ctypes.cast(im.pixels, ctypes.POINTER(ctypes.c_ubyte * (edge * edge * 4))).contents)
                    own = open(os.path.join(a, t, 'cursors', target[n]), 'rb').read()
                    if px not in own:
                        fails.append(f'libXcursor: {t} {n}: pixels do not come from {target[n]}')
                    xc.XcursorImagesDestroy(p)
                    checked += 1
        print(f'libXcursor: {checked} name/size lookups')

        for ref in ('/usr/share/icons/breeze_cursors/cursors', '/usr/share/icons/Adwaita/cursors'):
            if os.path.isdir(ref):
                missing = sorted(set(os.listdir(ref)) - names)
                if missing:
                    fails.append(f'names of {ref} missing: {missing}')
                print(f'coverage: all {len(os.listdir(ref))} names of {ref} present' if not missing else '')
        same = filecmp.cmp(os.path.join(a, THEMES[0], 'cursors', 'default'),
                           os.path.join(a, THEMES[1], 'cursors', 'default'), shallow=False)
        if same:
            fails.append('dark and light Xcursor files are identical')
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if fails:
        print('FAIL\n  ' + '\n  '.join(fails))
        sys.exit(1)
    print('ok')


if __name__ == '__main__':
    main()
