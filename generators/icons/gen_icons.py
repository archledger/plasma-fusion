#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build the Plasma Fusion icon themes (standard library only).

    gen_icons.py --out DIR [--copies]

writes DIR/PlasmaFusion (light UI, inherits breeze) and DIR/PlasmaFusion-Dark (dark UI,
inherits breeze-dark). Coloured art is identical in both; symbolic art differs only in the
default colours that non-KDE toolkits see (KIconLoader recolours it from the palette).

Layout of each theme:
  art/            coloured drawings (tiles, folders, file types, devices), the same in both themes -
                  not a lookup dir
  glyphs/         symbolic drawings with this variant's default colours - not a lookup dir
  apps/scalable, places/scalable, devices/scalable, mimetypes/scalable   coloured names
  places/16, places/22, devices/16, devices/22 (+ @2x/@3x)              monochrome small sizes
  */symbolic                                                           NAME-symbolic and symbolic names
  breeze/<dir>/   names handed back to Breeze (capture.json), as links into /usr/share/icons
  designed-apps.txt  the app icon names drawn with an app's own designed tile (names.DESIGNED; read
                  by plasma-fusion-app-icons, which leaves them alone) - not a lookup dir
Every lookup directory holds relative symlinks into art/ or glyphs/ (or copies with --copies).
"""
import argparse
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import art_files  # noqa: E402
import art_symbolic as sym  # noqa: E402
import art_tiles  # noqa: E402
import apptiles  # noqa: E402
import names  # noqa: E402

THEMES = {'PlasmaFusion': 'light', 'PlasmaFusion-Dark': 'dark'}
INHERITS = {'light': 'breeze,hicolor', 'dark': 'breeze-dark,hicolor'}
BREEZE_DIR = {'light': '/usr/share/icons/breeze', 'dark': '/usr/share/icons/breeze-dark'}
TITLE = {'light': 'Plasma Fusion', 'dark': 'Plasma Fusion Dark'}
COMMENT = {
    'light': 'Rounded tiles and line icons for the Plasma Fusion desktop, for light colour schemes',
    'dark': 'Rounded tiles and line icons for the Plasma Fusion desktop, for dark colour schemes',
}

# lookup directories: name -> (Context, Size, Type, MinSize, MaxSize, Scale)
DIRS = {
    'apps/scalable': ('Applications', 64, 'Scalable', 8, 512, 1),
    'apps/symbolic': ('Applications', 16, 'Scalable', 8, 512, 1),
    'places/16': ('Places', 16, 'Fixed', None, None, 1),
    'places/22': ('Places', 22, 'Fixed', None, None, 1),
    'places/scalable': ('Places', 64, 'Scalable', 24, 512, 1),
    'places/symbolic': ('Places', 16, 'Scalable', 8, 512, 1),
    'devices/16': ('Devices', 16, 'Fixed', None, None, 1),
    'devices/22': ('Devices', 22, 'Fixed', None, None, 1),
    'devices/scalable': ('Devices', 64, 'Scalable', 24, 512, 1),
    'devices/symbolic': ('Devices', 16, 'Scalable', 8, 512, 1),
    'mimetypes/scalable': ('MimeTypes', 64, 'Scalable', 8, 512, 1),
    'mimetypes/symbolic': ('MimeTypes', 16, 'Scalable', 8, 512, 1),
    'status/symbolic': ('Status', 16, 'Scalable', 8, 512, 1),
    'actions/symbolic': ('Actions', 16, 'Scalable', 8, 512, 1),
    'categories/symbolic': ('Categories', 16, 'Scalable', 8, 512, 1),
    'emblems/16': ('Emblems', 16, 'Fixed', None, None, 1),
    'emblems/22': ('Emblems', 22, 'Fixed', None, None, 1),
    'emblems/scalable': ('Emblems', 16, 'Scalable', 8, 256, 1),
}
# Fractional and integer display scales look for an exact match in these first (as in Breeze).
SCALED = {f'{d}@{s}x': (d, s) for d in ('places/16', 'places/22', 'devices/16', 'devices/22', 'emblems/16',
                                        'emblems/22') for s in (2, 3)}
LICENSE_TEXT = """Plasma Fusion icon themes (PlasmaFusion, PlasmaFusion-Dark)
Copyright 2026 Wisbendji Fimerlus <archledger236@gmail.com>

The artwork in this theme is licensed under the Creative Commons Attribution-ShareAlike 4.0
International licence (CC BY-SA 4.0), https://creativecommons.org/licenses/by-sa/4.0/.
It is generated from the Plasma Fusion design boards by generators/icons/ in the Plasma Fusion
repository (code: GPL-2.0-or-later).

Some icons contain letters drawn as outlines from the Manrope and Space Grotesk fonts
(SIL Open Font License 1.1).

Icons this theme does not draw come from the inherited Breeze theme. The breeze/ directory
holds links to files of the installed Breeze theme (/usr/share/icons/breeze or breeze-dark,
LGPL-3.0); no Breeze files are copied into this theme.
"""
BREEZE_SIZES = """DesktopDefault=48
DesktopSizes=16,22,32,48,64,128,256
ToolbarDefault=22
ToolbarSizes=16,22,32,48
MainToolbarDefault=22
MainToolbarSizes=16,22,32,48
SmallDefault=16
SmallSizes=16,22,32,48
PanelDefault=48
PanelSizes=16,22,32,48,64,128,256
DialogDefault=32
DialogSizes=16,22,32,48,64,128,256"""


class Registry:
    """Drawings (art: coloured, shared; glyph: symbolic, per variant) and name -> drawing links."""

    def __init__(self):
        self.art = {}       # id -> svg text
        self.glyphs = {}    # id -> layers
        self.links = {}     # (dir, name) -> ('art'|'glyph', id)

    def add_art(self, art_id, svg):
        if art_id in self.art and self.art[art_id] != svg:
            raise ValueError('conflicting art ' + art_id)
        self.art[art_id] = svg
        return art_id

    def add_glyph(self, glyph_id, layers):
        if glyph_id in self.glyphs and self.glyphs[glyph_id] != layers:
            raise ValueError('conflicting glyph ' + glyph_id)
        self.glyphs[glyph_id] = layers
        return glyph_id

    def link(self, directory, name, kind, ref):
        key = (directory, name)
        if key in self.links and self.links[key] != (kind, ref):
            raise ValueError(f'{directory}/{name} already maps to {self.links[key]}, not {(kind, ref)}')
        self.links[key] = (kind, ref)

    def symbolic_pair(self, directory, name, glyph_id):
        """NAME and NAME-symbolic both answer with the same symbolic drawing."""
        self.link(directory, name, 'glyph', glyph_id)
        self.link(directory, name + '-symbolic', 'glyph', glyph_id)


def board_glyph(reg, gid):
    if gid == '@logo':
        return None
    if gid not in reg.glyphs:
        reg.add_glyph(gid, sym.simple(gid))
    return gid


def build_registry():
    reg = Registry()
    all_names = set()

    def claim(name):
        if name in all_names:
            raise ValueError('name used twice: ' + name)
        all_names.add(name)

    # ---- applications
    reg.add_art('logo-mark', art_tiles.logo_svg())
    for n in ('plasmafusion-logo', 'plasmafusion-logo-symbolic'):
        claim(n)
        reg.link('apps/symbolic', n, 'art', 'logo-mark')
    for key, app_names in names.APPS.items():
        if not app_names:
            continue
        if key.startswith('app-'):  # a per-app tile (apptiles/)
            art_id = reg.add_art('tile-' + key, apptiles.tile_svg(key[4:]))
        else:
            art_id = reg.add_art('tile-' + key, art_tiles.tile_svg(key))
        symbol = names.APP_SYMBOLIC.get(key)
        gid = board_glyph(reg, symbol) if symbol else None
        for n in app_names:
            claim(n)
            reg.link('apps/scalable', n, 'art', art_id)
            if symbol == '@logo':
                reg.link('apps/symbolic', n + '-symbolic', 'art', 'logo-mark')
            elif gid is not None:
                reg.link('apps/symbolic', n + '-symbolic', 'glyph', gid)

    # ---- places (coloured >= 24 px, monochrome 16/22 px and -symbolic)
    for key, (fglyph, small, place_names) in names.PLACES.items():
        art_id = reg.add_art('folder-' + key, art_files.folder_svg(fglyph))
        gid = board_glyph(reg, small)
        for n in place_names:
            claim(n)
            reg.link('places/scalable', n, 'art', art_id)
            for d in ('places/16', 'places/22'):
                reg.link(d, n, 'glyph', gid)
            reg.link('places/symbolic', n + '-symbolic', 'glyph', gid)
    for tint in names.FOLDER_TINT_NAMES:
        n = 'folder-' + tint
        claim(n)
        art_id = reg.add_art('folder-tint-' + tint, art_files.folder_svg('folder', tint))
        gid = reg.add_glyph('folder-tint-' + tint, [sym.L(sym.G['folder'], art_files.FOLDER_TINTS[tint][1])])
        reg.link('places/scalable', n, 'art', art_id)
        for d in ('places/16', 'places/22'):
            reg.link(d, n, 'glyph', gid)
        reg.link('places/symbolic', n + '-symbolic', 'glyph', board_glyph(reg, 'folder'))
    reg.add_glyph('trash-full', [sym.L(sym.G['trash'].replace('M9 7V4h6v3', '')),
                                 sym.L('M8.8 7l1.2-3.4 3.4 1.1-.6 2.3M14.2 7l1.4-3.1 2.8 1.2-.8 1.9')])
    for key, (full, small, trash_names) in names.TRASH.items():
        art_id = reg.add_art(key, art_files.trash_svg(full))
        gid = board_glyph(reg, small) if small != 'trash-full' else 'trash-full'
        for n in trash_names:
            claim(n)
            reg.link('places/scalable', n, 'art', art_id)
            for d in ('places/16', 'places/22'):
                reg.link(d, n, 'glyph', gid)
            reg.link('places/symbolic', n + '-symbolic', 'glyph', gid)

    # ---- devices
    for key, (drawing, small, dev_names) in names.DEVICES.items():
        art_id = reg.add_art('device-' + drawing, art_files.device_svg(drawing))
        gid = board_glyph(reg, small)
        for n in dev_names:
            claim(n)
            reg.link('devices/scalable', n, 'art', art_id)
            for d in ('devices/16', 'devices/22'):
                reg.link(d, n, 'glyph', gid)
            reg.link('devices/symbolic', n + '-symbolic', 'glyph', gid)
    for small, extra in names.DEVICE_SYMBOLIC_EXTRA.items():
        gid = board_glyph(reg, small)
        for n in extra:
            claim(n)
            reg.link('devices/symbolic', n + '-symbolic', 'glyph', gid)

    # ---- file types
    with open(os.path.join(HERE, 'mimetable.json'), encoding='utf-8') as f:
        table = json.load(f)
    mime_symbolic = {
        'text-x-generic': 'document', 'x-office-document': 'document', 'x-office-spreadsheet': 'table',
        'x-office-presentation': 'slides', 'image-x-generic': 'image', 'audio-x-generic': 'music',
        'video-x-generic': 'video', 'package-x-generic': 'archive', 'text-x-script': 'code-slash',
        'font-x-generic': 'font', 'application-x-executable': 'settings', 'application-x-generic': 'document-plain',
        'x-office-calendar': 'calendar', 'x-office-address-book': 'user', 'application-pdf': 'document',
        'text-html': 'globe', 'application-x-cd-image': 'disc', 'unknown': 'document-plain',
    }
    reg.add_glyph('slides', [sym.L('M4 4h16v12H4zM12 16v4M8 20h8M8 12v-2M12 12V8M16 12v-3')])
    reg.add_glyph('font', [sym.L('M4 19L9 5l5 14M5.8 14.5h6.4M15 12.5a2.5 2.5 0 0 1 5 0V19M20 15.5c-4-1-5.5.5-5.5 1.8 0 1 .8 1.7 2 1.7 2 0 3.5-1.5 3.5-3.5')])
    for n, entry in sorted(table.items()):
        claim(n)
        label = entry['label']
        art_id = f"mime-{entry['kind']}-{label or 'none'}"
        if art_id not in reg.art:
            reg.add_art(art_id, art_files.file_svg(entry['kind'], label))
        reg.link('mimetypes/scalable', n, 'art', art_id)
        if n in mime_symbolic:
            reg.link('mimetypes/symbolic', n + '-symbolic', 'glyph', board_glyph(reg, mime_symbolic[n]))
    # ---- emblems: the link badge (pixel-grid drawings at 16 and 22 px, the 16 px one scalable)
    claim('emblem-symbolic-link')
    for size in (16, 22):
        art_id = reg.add_art(f'emblem-link-{size}', art_files.emblem_link_svg(size))
        reg.link(f'emblems/{size}', 'emblem-symbolic-link', 'art', art_id)
    reg.link('emblems/scalable', 'emblem-symbolic-link', 'art', 'emblem-link-16')
    add_status(reg, claim)
    add_actions(reg, claim)
    add_categories(reg, claim)
    check_contexts(reg)
    return reg


def check_contexts(reg):
    """A name may sit in several size directories of one context, never in two contexts."""
    seen = {}
    for (d, n) in reg.links:
        ctx = d.split('/')[0]
        if seen.setdefault(n, ctx) != ctx:
            raise ValueError(f'{n} is in both {seen[n]} and {ctx}')


def add_status(reg, claim):
    def put(name, gid, layers, directory='status/symbolic'):
        claim(name)
        reg.add_glyph(gid, layers)
        reg.symbolic_pair(directory, name, gid)

    # battery (FileIcons.dc.html: Full, 60 %, 30 %, Low, Charging)
    for lv in sorted(sym.BATTERY_LEVELS):
        ll = '%03d' % lv
        put(f'battery-{ll}', f'battery-{ll}', sym.battery(lv))
        put(f'battery-{ll}-charging', f'battery-{ll}-charging', sym.battery(lv, True))
        for prof in ('powersave', 'balanced', 'performance'):
            p = None if prof == 'balanced' else prof
            put(f'battery-{ll}-profile-{prof}', f'battery-{ll}-p-{prof}', sym.battery(lv, False, p))
            put(f'battery-{ll}-charging-profile-{prof}', f'battery-{ll}-c-p-{prof}', sym.battery(lv, True, p))
    for legacy, lv in (('full', 100), ('good', 60), ('low', 30), ('caution', 10), ('empty', 0)):
        put(f'battery-{legacy}', f'battery-{lv:03d}', sym.battery(lv))
        put(f'battery-{legacy}-charging', f'battery-{lv:03d}-charging', sym.battery(lv, True))
    put('battery-missing', 'battery-missing', sym.battery_missing())
    for prof in ('powersave', 'balanced', 'performance'):
        put(f'battery-profile-{prof}', f'battery-profile-{prof}', sym.battery_profile(prof))
    put('battery', 'battery-100', sym.battery(100))
    put('battery-full-charged', 'battery-100-charging', sym.battery(100, True))

    # Wi-Fi (Excellent, Good, Weak, Poor, Off)
    strength_bars = {'0': 0, '20': 0, '40': 1, '60': 2, '80': 2, '100': 3}
    for s, bars in strength_bars.items():
        put(f'network-wireless-{s}', f'wifi-{bars}', sym.wifi(bars))
        put(f'network-wireless-{s}-locked', f'wifi-{bars}-locked', sym.wifi(bars, 'locked'))
        put(f'network-wireless-{s}-limited', f'wifi-{bars}-limited', sym.wifi(bars, 'limited'))
    for s, bars in (('00', 0), ('20', 0), ('25', 1), ('40', 1), ('50', 2), ('60', 2), ('75', 2), ('80', 2), ('100', 3)):
        put(f'network-wireless-connected-{s}', f'wifi-{bars}', sym.wifi(bars))
    for s, bars in (('excellent', 3), ('good', 2), ('ok', 1), ('weak', 0)):
        put(f'network-wireless-signal-{s}', f'wifi-{bars}', sym.wifi(bars))
        put(f'network-wireless-signal-{s}-secure', f'wifi-{bars}-locked', sym.wifi(bars, 'locked'))
    put('network-wireless-signal-none', 'wifi-none', sym.wifi(0, none=True))
    put('network-wireless', 'wifi-3', sym.wifi(3))
    put('network-wireless-on', 'wifi-3', sym.wifi(3))
    put('network-wireless-connected', 'wifi-3', sym.wifi(3))
    put('network-wireless-encrypted', 'wifi-3-locked', sym.wifi(3, 'locked'))
    for n in ('network-wireless-off', 'network-wireless-disconnected', 'network-wireless-offline',
              'network-wireless-disabled', 'network-wireless-hardware-disabled', 'network-unavailable', 'network-offline'):
        put(n, 'wifi-off', sym.wifi(0, off=True))
    for n in ('network-wireless-acquiring', 'network-wireless-available', 'network-wireless-no-route'):
        put(n, 'wifi-none', sym.wifi(0, none=True))
    put('network-wireless-hotspot', 'hotspot', sym.simple('hotspot'))
    put('network-wireless-bluetooth', 'bluetooth', sym.bluetooth('on'))
    put('network-wired', 'wired', sym.simple('wired'))
    put('network-wired-activated', 'wired', sym.simple('wired'))
    put('network-wired-connected', 'wired', sym.simple('wired'))
    for n in ('network-wired-disconnected', 'network-wired-offline', 'network-wired-unavailable'):
        put(n, 'wired-off', [sym.L(sym.G['wired'], opacity=sym.DIM), sym.L(sym.G['slash-wifi'])])
    for n in ('network-wired-acquiring', 'network-wired-no-route'):
        put(n, 'wired-dim', [sym.L(sym.G['wired'], opacity=sym.DIM)])
    put('network-vpn', 'shield', sym.simple('shield'))
    put('network-flightmode-on', 'airplane', sym.simple('airplane'))
    put('airplane-mode', 'airplane', sym.simple('airplane'))
    put('network-flightmode-off', 'airplane-off', [sym.L(sym.G['airplane'], opacity=sym.DIM), sym.L(sym.G['slash-wifi'])])
    put('airplane-mode-disabled', 'airplane-off', [sym.L(sym.G['airplane'], opacity=sym.DIM), sym.L(sym.G['slash-wifi'])])

    # volume and microphone
    for state in ('high', 'medium', 'low', 'muted', 'high-warning', 'high-danger'):
        put(f'audio-volume-{state}', f'volume-{state}', sym.volume(state))
    put('audio-volume-overamplified', 'volume-high-danger', sym.volume('high-danger'))
    put('audio-volume-off', 'volume-muted', sym.volume('muted'))
    for state in ('high', 'medium', 'low'):
        put(f'microphone-sensitivity-{state}', 'mic', sym.mic('on'))
        put(f'audio-input-microphone-{state}', 'mic', sym.mic('on'))
    put('microphone-sensitivity-muted', 'mic-off', sym.mic('muted'))
    put('audio-input-microphone-muted', 'mic-off', sym.mic('muted'))
    put('microphone-disabled', 'mic-off', sym.mic('muted'))

    # Bluetooth
    put('network-bluetooth', 'bluetooth', sym.bluetooth('on'))
    put('network-bluetooth-activated', 'bluetooth-active', sym.bluetooth('active'))
    put('network-bluetooth-inactive', 'bluetooth-off', sym.bluetooth('off'))
    put('bluetooth', 'bluetooth', sym.bluetooth('on'))
    put('bluetooth-active', 'bluetooth-active', sym.bluetooth('active'))
    put('bluetooth-paired', 'bluetooth-active', sym.bluetooth('active'))
    put('bluetooth-online', 'bluetooth', sym.bluetooth('on'))
    for n in ('bluetooth-disabled', 'bluetooth-disconnected', 'bluetooth-hardware-disabled', 'bluetooth-offline'):
        put(n, 'bluetooth-off', sym.bluetooth('off'))
    claim('preferences-system-bluetooth-symbolic')
    reg.link('status/symbolic', 'preferences-system-bluetooth-symbolic', 'glyph', 'bluetooth')

    # notifications
    put('notification-inactive', 'bell', sym.bell('inactive'))
    put('notification-active', 'bell-active', sym.bell('active'))
    put('notification-new', 'bell-active', sym.bell('active'))
    put('notification-progress-inactive', 'bell-progress', sym.bell('progress'))
    put('notification-progress-active', 'bell-progress', sym.bell('progress'))
    put('notifications', 'bell', sym.bell('inactive'))
    put('notifications-disabled', 'bell-off', sym.bell('disabled'))
    put('notification-disabled', 'bell-off', sym.bell('disabled'))

    # night light and brightness
    put('redshift-status-on', 'moon', sym.simple('moon'))
    put('night-light', 'moon', sym.simple('moon'))
    put('redshift-status-day', 'brightness', sym.simple('brightness'))
    put('redshift-status-off', 'moon-off', [sym.L(sym.G['moon'], opacity=sym.DIM), sym.L(sym.G['slash'])])
    put('night-light-disabled', 'moon-off', [sym.L(sym.G['moon'], opacity=sym.DIM), sym.L(sym.G['slash'])])
    for n in ('brightness-high', 'video-display-brightness', 'display-brightness', 'brightness'):
        put(n, 'brightness', sym.simple('brightness'))
    brightness_low = ('M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0M12 4.5h.01M12 19.5h.01M4.5 12h.01M19.5 12h.01'
                      'M6.7 6.7h.01M17.3 17.3h.01M6.7 17.3h.01M17.3 6.7h.01')
    put('brightness-low', 'brightness-low', [sym.L(brightness_low)])
    kbd_light = 'M3 10h18v9H3zM7 14h.01M11 14h.01M15 14h.01M8 16.5h8M12 3v2.5M6.5 5l1.3 1.8M17.5 5l-1.3 1.8'
    put('input-keyboard-brightness', 'keyboard-brightness', [sym.L(kbd_light)])
    put('keyboard-brightness', 'keyboard-brightness', [sym.L(kbd_light)])

    # clipboard, phone link, device notifier, camera indicator, power modes, dark style
    claim('klipper-symbolic')
    reg.link('status/symbolic', 'klipper-symbolic', 'glyph', board_glyph(reg, 'clipboard'))
    put('kdeconnect-tray', 'phone', sym.simple('phone'))
    put('device-notifier', 'usb', sym.simple('usb'))
    put('camera-on', 'camera', sym.simple('camera'))
    put('camera-ready', 'camera', sym.simple('camera'))
    put('camera-off', 'camera-off', [sym.L(sym.G['camera'], opacity=sym.DIM), sym.L(sym.G['slash'])])
    put('camera-disabled', 'camera-off', [sym.L(sym.G['camera'], opacity=sym.DIM), sym.L(sym.G['slash'])])
    put('speedometer', 'gauge', sym.simple('gauge'))
    put('power-profile-balanced', 'gauge', sym.simple('gauge'))
    put('power-profile-power-saver', 'leaf', [sym.L(sym.G['leaf'], 'positive')])
    put('power-profile-performance', 'performance', sym.battery_profile('performance'))
    put('plasmafusion-dark-style', 'dark-style', sym.dark_style())
    put('plasmafusion-night-light', 'moon', sym.simple('moon'))
    put('plasmafusion-dnd', 'bell-off', sym.bell('disabled'))
    put('plasmafusion-power-mode', 'gauge', sym.simple('gauge'))
    put('input-caps-on', 'caps', sym.simple('caps'))

    G = sym.G
    # media controller in the tray (plasma-workspace mediacontroller: media-playback-playing/paused/stopped)
    put('media-playback-playing', 'play', sym.simple('play'))
    put('media-playback-paused', 'pause', sym.simple('pause'))
    put('media-playback-stopped', 'stop', sym.simple('stop'))
    # software updates (Discover notifier: update-none/low/high/busy; Breeze also has update-medium)
    put('update-none', 'check-circle', sym.simple('check-circle'))
    put('update-low', 'update', sym.simple('update'))
    put('update-medium', 'update', sym.simple('update'))
    put('update-high', 'update-high', [sym.L(G['update'], 'negative')])
    put('update-busy', 'update-busy', [sym.L(G['update-ring'], opacity=sym.DIM), sym.L(G['update-arrow'])])
    # Plasma Vaults (tray applet)
    put('plasmavault', 'vault', sym.simple('vault'))
    put('plasmavault-error', 'vault-error', [sym.L(G['vault'], 'negative')])

    # weather (kdeplasma-addons weather applet names, plus Breeze's day/night/wind variants)
    sun = ('w-clear', sym.simple('brightness'))
    moon = ('w-clear-night', sym.simple('moon'))
    few = ('w-few', [sym.L(G['w-sun-small'] + G['w-cloud-small'])])
    few_night = ('w-few-night', [sym.L(G['w-moon-small'] + G['w-cloud-small'])])
    clouds = ('w-clouds', sym.simple('cloud'))
    showers = ('w-showers', [sym.L(G['w-cloud-high'] + G['w-rain'])])
    showers_few = ('w-showers-few', [sym.L(G['w-cloud-high'] + G['w-rain-few'])])
    snow = ('w-snow', [sym.L(G['w-cloud-high'] + G['w-snow'])])
    snow_few = ('w-snow-few', [sym.L(G['w-cloud-high'] + G['w-snow-few'])])
    sleet = ('w-sleet', [sym.L(G['w-cloud-high'] + G['w-sleet'])])
    storm = ('w-storm', [sym.L(G['w-cloud-high'] + G['w-bolt'])])
    fog = ('w-fog', sym.simple('w-fog'))
    hail = ('w-hail', [sym.L(G['w-cloud-high']),
                       sym.L(sym.ci(8, 18.5, 1) + sym.ci(12, 18.5, 1) + sym.ci(16, 18.5, 1)
                             + sym.ci(10, 21.5, 1) + sym.ci(14, 21.5, 1), 'text', 'fill')])
    weather = {
        'weather-clear': sun, 'weather-clear-wind': sun,
        'weather-clear-night': moon, 'weather-clear-wind-night': moon,
        'weather-few-clouds': few, 'weather-few-clouds-wind': few,
        'weather-few-clouds-night': few_night, 'weather-few-clouds-wind-night': few_night,
        'weather-clouds-night': few_night, 'weather-clouds-wind-night': few_night,
        'weather-clouds': clouds, 'weather-clouds-wind': clouds, 'weather-overcast': clouds,
        'weather-overcast-wind': clouds, 'weather-many-clouds': clouds, 'weather-many-clouds-wind': clouds,
        'weather-snow-rain': sleet, 'weather-hail': hail, 'weather-fog': fog, 'weather-mist': fog,
        'weather-none-available': ('w-none', [sym.L(G['cloud'], opacity=sym.DIM)]),
    }
    for suffix in ('', '-day', '-night'):
        weather['weather-showers' + suffix] = showers
        weather['weather-showers-scattered' + suffix] = showers_few
        weather['weather-snow' + suffix] = snow
        weather['weather-snow-scattered' + suffix] = snow_few
        weather['weather-freezing-rain' + suffix] = sleet
        weather['weather-freezing-scattered-rain' + suffix] = sleet
        weather['weather-storm' + suffix] = storm
        for base in ('freezing-scattered-rain-storm', 'freezing-storm', 'showers-scattered-storm',
                     'snow-scattered-storm', 'snow-storm'):
            weather[f'weather-{base}{suffix}'] = storm
    for n, (gid, layers) in weather.items():
        put(n, gid, layers)


def add_actions(reg, claim):
    extra = {
        'eye-off': [sym.L(sym.G['eye'] + sym.G['slash-wifi'])],
        'list-compact': [sym.L('M4 6h6M4 12h6M4 18h6M14 6h6M14 12h6M14 18h6')],
        # edit-copy: two pages (the board's Clipboard symbol answers edit-paste)
        'copy': [sym.L('M10 9h9a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1V10a1 1 0 0 1 1-1zM6 15H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1v1')],
        'wrench': [sym.L('M15 3.5a4.5 4.5 0 0 0-4.3 5.8L4 16a2.1 2.1 0 0 0 3 3l6.7-6.7A4.5 4.5 0 0 0 19.5 8l-2.8 2.8-2.9-.6-.6-2.9z')],
        'cap': [sym.L('M2 9l10-5 10 5-10 5zM6 11v5c3 2.5 9 2.5 12 0v-5M22 9v6')],
    }
    for gid, layers in extra.items():
        reg.add_glyph(gid, layers)
    for gid, action_names in names.ACTIONS.items():
        if gid not in reg.glyphs:
            board_glyph(reg, gid)
        for n in action_names:
            claim(n)
            reg.symbolic_pair('actions/symbolic', n, gid)


def add_categories(reg, claim):
    for gid, cat_names in names.CATEGORIES.items():
        if gid not in reg.glyphs:
            board_glyph(reg, gid)
        for n in cat_names:
            claim(n)
            reg.symbolic_pair('categories/symbolic', n, gid)


# ------------------------------------------------------------------ writing
def index_theme(variant, dirs, mirror_dirs):
    lines = ['[Icon Theme]', f'Name={TITLE[variant]}', f'Comment={COMMENT[variant]}',
             f'Inherits={INHERITS[variant]}', 'Example=folder', 'FollowsColorScheme=true',
             'KDE-Extensions=.svg', '', BREEZE_SIZES, '']
    all_dirs = list(dirs) + [d for d in mirror_dirs if mirror_dirs[d].get('Scale', 1) == 1]
    scaled = [d for d in SCALED] + [d for d in mirror_dirs if mirror_dirs[d].get('Scale', 1) != 1]
    lines.append('Directories=' + ','.join(all_dirs))
    lines.append('ScaledDirectories=' + ','.join(scaled))
    lines.append('')
    for d in dirs:
        ctx, size, typ, mn, mx, scale = DIRS[d]
        lines += [f'[{d}]', f'Size={size}', f'Context={ctx}', f'Type={typ}']
        if typ == 'Scalable':
            lines += [f'MinSize={mn}', f'MaxSize={mx}']
        lines.append('')
    for d, (base, scale) in SCALED.items():
        ctx, size, typ, mn, mx, _ = DIRS[base]
        lines += [f'[{d}]', f'Size={size}', f'Scale={scale}', f'Context={ctx}', f'Type={typ}', '']
    for d, meta in mirror_dirs.items():
        lines.append(f'[{d}]')
        for k in ('Size', 'Scale', 'Context', 'Type', 'MinSize', 'MaxSize', 'Threshold'):
            if meta.get(k) is not None and not (k == 'Scale' and meta[k] == 1):
                lines.append(f'{k}={meta[k]}')
        lines.append('')
    return '\n'.join(lines)


def load_capture():
    path = os.path.join(HERE, 'capture.json')
    if not os.path.exists(path):
        return {'dirs': {}, 'links': []}
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def write_theme(root, theme, variant, reg, copies):
    base = os.path.join(root, theme)
    if os.path.lexists(base):
        shutil.rmtree(base)
    os.makedirs(base)
    # coloured art: real files in each theme, so either theme works on its own (the icons KCM can
    # remove one theme, and a system-wide copy may hold only one)
    os.makedirs(os.path.join(base, 'art'))
    for art_id, svg in sorted(reg.art.items()):
        with open(os.path.join(base, 'art', art_id + '.svg'), 'w', encoding='utf-8') as f:
            f.write(svg)
    os.makedirs(os.path.join(base, 'glyphs'))
    for gid, layers in sorted(reg.glyphs.items()):
        with open(os.path.join(base, 'glyphs', gid + '.svg'), 'w', encoding='utf-8') as f:
            f.write(sym.symbolic_svg(layers, variant))
    for d in DIRS:
        os.makedirs(os.path.join(base, d))
    for (d, n), (kind, ref) in sorted(reg.links.items()):
        target_rel = os.path.join('..', '..', 'art' if kind == 'art' else 'glyphs', ref + '.svg')
        dst = os.path.join(base, d, n + '.svg')
        if copies:
            src = os.path.join(base, 'art' if kind == 'art' else 'glyphs', ref + '.svg')
            shutil.copyfile(src, dst)
        else:
            os.symlink(target_rel, dst)
    for d, (b, _scale) in SCALED.items():
        dst = os.path.join(base, d)
        if copies:
            shutil.copytree(os.path.join(base, b), dst, symlinks=False)
        else:
            os.symlink(os.path.basename(b), dst)
    # names handed back to Breeze (see make_capture.py): exact-name links into the system theme
    cap = load_capture() if not copies else {'dirs': {}, 'links': []}
    breeze = BREEZE_DIR[variant]
    mirror_dirs = {}
    for d, meta in sorted(cap['dirs'].items()):
        mirror_dirs['breeze/' + d] = {k: v for k, v in meta.items() if k != 'base'}
        if 'base' not in meta:
            os.makedirs(os.path.join(base, 'breeze', d), exist_ok=True)
    for d, meta in sorted(cap['dirs'].items()):
        if 'base' in meta:
            os.symlink(os.path.basename(meta['base']), os.path.join(base, 'breeze', d))
    for d, n in cap['links']:
        os.symlink(os.path.join(breeze, d, n + '.svg'), os.path.join(base, 'breeze', d, n + '.svg'))
    with open(os.path.join(base, 'index.theme'), 'w', encoding='utf-8') as f:
        f.write(index_theme(variant, list(DIRS), mirror_dirs))
    with open(os.path.join(base, 'LICENSE'), 'w', encoding='utf-8') as f:
        f.write(LICENSE_TEXT)
    with open(os.path.join(base, 'designed-apps.txt'), 'w', encoding='utf-8') as f:
        f.write(''.join(n + '\n' for n in names.DESIGNED))
    return base


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', required=True, help='directory that receives PlasmaFusion and PlasmaFusion-Dark')
    ap.add_argument('--copies', action='store_true',
                    help='write file copies instead of symlinks, for file systems without links; this also '
                         'leaves out the links that hand captured names back to Breeze')
    ap.add_argument('--list-names', action='store_true', help='print every shipped icon name and exit')
    args = ap.parse_args()
    reg = build_registry()
    if args.list_names:
        for (d, n) in sorted(reg.links):
            print(f'{d}\t{n}')
        return
    os.makedirs(args.out, exist_ok=True)
    if args.copies:
        print('icons: --copies leaves out the links that hand captured names back to Breeze; install a '
              'build made without --copies, or System Settings shows the Settings tile for its pages',
              file=sys.stderr)
    for theme in sorted(THEMES, key=lambda t: THEMES[t] != 'light'):
        write_theme(args.out, theme, THEMES[theme], reg, args.copies)
    print(f'icons: {len(reg.art)} coloured drawings, {len(reg.glyphs)} symbolic drawings, '
          f'{len(reg.links)} names per theme -> {args.out}')


if __name__ == '__main__':
    main()
