#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Icon coverage of installed apps and dock pins (BACKLOG C8).

    coverage_report.py APPS.json [--pins ID.desktop,...] [--breeze DIR] [--markdown]

APPS.json is a list of desktop entries (file, name, icon, type, nodisplay, hidden, onlyshowin,
notshowin, categories), for example collected on the device with the snippet in
docs/parts/icons.md. For every app the launcher shows (Type=Application, not NoDisplay/Hidden,
shown in KDE) the report says whether the Plasma Fusion themes draw its icon as a Fusion tile, and
otherwise what the user sees: the Breeze icon (if Breeze has the name), an icon the app installs
itself (an absolute path or a hicolor name), or nothing. Dock pins come first. Nothing here draws
grey plates: apps without a Fusion tile keep their own icon, and the dock and launcher put that icon
on the neutral Fusion tile (FusionIconTile, BASE-1).

Exit status 0; the report is informational.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import names  # noqa: E402

DEFAULT_PINS = ['org.kde.dolphin.desktop', 'preferred://browser', 'org.kde.konsole.desktop',
                'org.kde.kmail2.desktop', 'org.kde.kate.desktop', 'org.kde.elisa.desktop',
                'org.kde.gwenview.desktop', 'org.kde.korganizer.desktop', 'systemsettings.desktop']
FALLBACKS = {'org.kde.kate.desktop': 'org.kde.kwrite.desktop', 'org.kde.kmail2.desktop': 'org.kde.kontact.desktop',
             'org.kde.korganizer.desktop': 'org.kde.merkuro.calendar.desktop'}


def fusion_app_names():
    out = {}
    for key, app_names in names.APPS.items():
        for n in app_names:
            out[n] = key
    return out


def exists_in_theme(theme_dir, icon):
    for root, _dirs, files in os.walk(theme_dir):
        if icon + '.svg' in files or icon + '.png' in files or icon + '.svgz' in files:
            return True
    return False


def shown_in_kde(app):
    if app['type'] != 'Application' or app['nodisplay'] or app['hidden']:
        return False
    only = [x for x in app['onlyshowin'].split(';') if x]
    notin = [x for x in app['notshowin'].split(';') if x]
    return (not only or 'KDE' in only) and 'KDE' not in notin


def classify(app, fusion, breeze, hicolor):
    icon = app['icon']
    if not icon:
        return 'no icon', ''
    if icon.startswith('/'):
        return 'own file', icon
    if icon in fusion:
        return 'Fusion tile', fusion[icon]
    if breeze and exists_in_theme(breeze, icon):
        return 'Breeze', ''
    if hicolor and exists_in_theme(hicolor, icon):
        return 'app (hicolor)', ''
    return 'missing', ''


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('apps')
    ap.add_argument('--pins', default=','.join(DEFAULT_PINS))
    ap.add_argument('--breeze', default='/usr/share/icons/breeze')
    ap.add_argument('--hicolor', default='/usr/share/icons/hicolor')
    a = ap.parse_args()
    apps = [x for x in json.load(open(a.apps, encoding='utf-8')) if shown_in_kde(x)]
    by_id = {os.path.basename(x['file']): x for x in apps}
    fusion = fusion_app_names()
    breeze = a.breeze if os.path.isdir(a.breeze) else None
    hicolor = a.hicolor if os.path.isdir(a.hicolor) else None
    rows = []
    for pin in a.pins.split(','):
        app_id = pin
        if pin not in by_id and pin in FALLBACKS and FALLBACKS[pin] in by_id:
            app_id = FALLBACKS[pin]
        app = by_id.get(app_id)
        if pin == 'preferred://browser':
            rows.append(('pin', 'Browser (preferred://browser)', '-', 'Fusion tile', 'browser'))
            continue
        if not app:
            rows.append(('pin', pin, '-', 'not installed (hidden)', ''))
            continue
        kind, detail = classify(app, fusion, breeze, hicolor)
        rows.append(('pin', '%s (%s)' % (app['name'], app_id), app['icon'], kind, detail))
    pinned = {r[1].split('(')[-1].rstrip(')') for r in rows}
    counts = {}
    for app in sorted(apps, key=lambda x: x['name'].lower()):
        app_id = os.path.basename(app['file'])
        kind, detail = classify(app, fusion, breeze, hicolor)
        counts[kind] = counts.get(kind, 0) + 1
        if app_id in pinned:
            continue
        rows.append(('app', '%s (%s)' % (app['name'], app_id), app['icon'], kind, detail))
    print('Apps shown by the launcher: %d. %s.' % (len(apps), ', '.join('%s %d' % kv for kv in sorted(counts.items()))))
    print()
    print('| | App (desktop file) | Icon= | Drawn as | Fusion tile |')
    print('|---|---|---|---|---|')
    for r in rows:
        print('| %s | %s | `%s` | %s | %s |' % r)
    return 0


if __name__ == '__main__':
    sys.exit(main())
