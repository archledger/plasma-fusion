#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Maintainer tool: find icon names our theme would swallow, and hand them back to Breeze.

KIconLoader (kiconthemes 6.30, KIconLoaderPrivate::findMatchingIcon) runs its whole fallback
chain inside our theme before it asks Breeze: "a-b-c" -> "a-b" -> "a", "a-b-symbolic" -> "a-b"
-> "a-symbolic" -> "a", and MIME-like names -> "<media>-x-generic". Shipping "preferences-system"
(the System Settings tile) would therefore answer "preferences-system-windows" and every other
preferences-system-* icon with the tile.

This tool simulates that chain for every icon name in Breeze and hicolor (plus optional extra
lists, e.g. from the test device) and writes capture.json. gen_icons.py turns each entry into a
link from our theme into /usr/share/icons/breeze or breeze-dark, so the exact name is found in
our theme and resolves to Breeze's own drawing. Families where our fallback is intended
(folders, drives, battery levels, Wi-Fi levels, file types, ...) stay with our drawings.

    python3 make_capture.py [--extra NAMES.txt] [--report REPORT.txt]
"""
import argparse
import configparser
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

MEDIA_TYPES = {'text', 'application', 'image', 'audio', 'inode', 'video', 'message', 'model',
               'multipart', 'x-content', 'x-epoc'}
# Captured names in these families keep our drawing (the fallback is what we want).
OURS = [re.compile(p) for p in (
    r'^folder(-|$)', r'^user-trash', r'^drive-', r'^media-optical', r'^media-flash', r'^media-removable',
    r'^battery-(?!ups)', r'^network-wireless', r'^network-wired', r'^network-vpn', r'^network-flightmode',
    r'^audio-volume-', r'^microphone-sensitivity-', r'^notification', r'^network-bluetooth', r'^bluetooth-',
    r'^redshift-', r'^start-here', r'^weather-', r'^kdeconnect-tray', r'^x-office-', r'^inode-directory',
    r'^applications-(games|education|development|graphics|internet|multimedia|office|science|system|'
    r'utilities|accessories|network)-',
    r'^view-list-', r'^go-(next|previous|up|down)-view', r'^system-shutdown', r'^system-reboot',
    r'^window-(close|minimize|maximize|restore)', r'^edit-delete', r'^media-playback-', r'^media-skip-',
    r'^media-seek-', r'^document-save', r'^document-open-folder', r'^document-new',
)]


def read_index(theme_dir):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    cp.read(os.path.join(theme_dir, 'index.theme'))
    it = cp['Icon Theme']
    dirs = [d for d in it.get('Directories', '').split(',') if d]
    scaled = [d for d in it.get('ScaledDirectories', '').split(',') if d]
    meta = {}
    for d in dirs + scaled:
        if d not in cp:
            continue
        s = cp[d]
        meta[d] = {k: (int(s[k]) if s.get(k, '').isdigit() else s[k]) for k in
                   ('Size', 'Scale', 'Context', 'Type', 'MinSize', 'MaxSize', 'Threshold') if k in s}
        meta[d].setdefault('Scale', 1)
    return meta


def scan_theme(theme_dir):
    """name -> list of directories that hold it (following the theme's index)."""
    names = {}
    for d in read_index(theme_dir):
        full = os.path.join(theme_dir, d)
        if not os.path.isdir(full):
            continue
        for fn in os.listdir(full):
            base, ext = os.path.splitext(fn)
            if ext in ('.svg', '.svgz', '.png', '.xpm'):
                names.setdefault(base, []).append(d)
    return names


def chain(name, ours):
    """Return the name of ours that KIconLoader would pick for `name`, or None."""
    generic = name.endswith('-x-generic')
    symbolic = name.endswith('-symbolic')
    cur = name
    while cur:
        if cur in ours:
            return cur
        if generic:
            return None
        if symbolic:
            cur = cur[:-len('-symbolic')]
            if cur in ours:
                return cur
        r = cur.rfind('-')
        if r > 1:
            cur = cur[:r]
            if cur.endswith('-x'):
                cur = cur[:-2]
            if symbolic:
                cur += '-symbolic'
        else:
            if cur in MEDIA_TYPES:
                cur += '-x-generic'
                generic = True
            else:
                return None
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--breeze', default='/usr/share/icons/breeze')
    ap.add_argument('--hicolor', default='/usr/share/icons/hicolor')
    ap.add_argument('--extra', action='append', default=[], help='text file with one icon name per line')
    ap.add_argument('--report')
    args = ap.parse_args()

    import gen_icons
    reg = gen_icons.build_registry()
    ours = {}
    for (d, n) in reg.links:
        ours.setdefault(n, set()).add(d)
    mime_names = {n for (d, n) in reg.links if d.startswith('mimetypes/')}

    breeze = scan_theme(args.breeze)
    breeze_meta = read_index(args.breeze)
    hicolor = scan_theme(args.hicolor) if os.path.isdir(args.hicolor) else {}
    universe = set(breeze) | set(hicolor)
    for path in args.extra:
        with open(path, encoding='utf-8') as f:
            universe |= {line.strip() for line in f if line.strip() and not line.startswith('#')}

    mirror = {}      # breeze dir -> set(names)
    kept = []        # (name, captured by) - our drawing is intended
    unresolved = []  # captured names Breeze does not have (hicolor or requested-only)
    for n in sorted(universe):
        if n in ours:
            continue
        p = chain(n, ours)
        if p is None:
            continue
        in_breeze_mime = any(d.startswith('mimetypes/') for d in breeze.get(n, []))
        if p in mime_names and (in_breeze_mime or n not in breeze):
            kept.append((n, p))
            continue
        if any(r.search(n) for r in OURS):
            kept.append((n, p))
            continue
        if n in breeze:
            for d in breeze[n]:
                mirror.setdefault(d, set()).add(n)
        else:
            unresolved.append((n, p))

    # directories: copy Breeze's metadata; scaled directories are links to their base directory
    dirs = {}
    for d in sorted(mirror):
        meta = dict(breeze_meta.get(d, {}))
        if not meta:
            continue
        dirs[d] = meta
    # Breeze's @2x/@3x directories are links to the base; mirror them for exact scaled lookups
    for d, meta in breeze_meta.items():
        m = re.fullmatch(r'(.+)@(\d)x', d)
        if m and m.group(1) in dirs:
            dirs[d] = dict(meta, base=m.group(1))
    links = sorted((d, n) for d, ns in mirror.items() if d in dirs and 'base' not in dirs[d] for n in ns)
    with open(os.path.join(HERE, 'capture.json'), 'w', encoding='utf-8') as f:
        json.dump({'breeze_version_note': 'generated from the installed breeze-icon-theme; rerun after updates',
                   'dirs': dirs, 'links': links}, f, indent=0, sort_keys=True)
        f.write('\n')
    print(f'{len(set(n for _, n in links))} names handed back to Breeze in {len(dirs)} directories, '
          f'{len(kept)} captured names keep our drawing, {len(unresolved)} captured names not in Breeze')
    if args.report:
        with open(args.report, 'w', encoding='utf-8') as f:
            f.write('# handed back to Breeze (name <- would have been captured by)\n')
            for d, n in links:
                f.write(f'mirror {d}/{n} <- {chain(n, ours)}\n')
            f.write('\n# kept with our drawing\n')
            for n, p in kept:
                f.write(f'keep {n} <- {p}\n')
            f.write('\n# captured, not in Breeze (hicolor or requested names)\n')
            for n, p in unresolved:
                where = ','.join(hicolor.get(n, [])[:3])
                f.write(f'other {n} <- {p} [{where}]\n')


if __name__ == '__main__':
    main()
