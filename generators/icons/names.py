# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Icon names: which drawing answers which freedesktop / KDE / GNOME icon name.

KIconLoader tries the requested name, then shorter dash-stripped names, all inside our theme,
before it looks at Breeze. So every coloured name also gets a monochrome -symbolic twin, and
families such as battery-* are shipped in full. Names that a shipped prefix would otherwise
swallow are listed in capture.json (see make_capture.py) and handed back to Breeze.
"""

# ------------------------------------------------------------------ applications
# tile key -> Icon= names used by the matching apps (Fedora 44 KDE and GNOME, common upstreams)
APPS = {
    'files': ['org.kde.dolphin', 'dolphin', 'system-file-manager', 'org.gnome.Nautilus', 'nautilus',
              'file-manager', 'thunar', 'org.xfce.thunar', 'nemo', 'pcmanfm', 'pcmanfm-qt',
              'krusader_user', 'org.kde.krusader'],
    'browser': ['google-chrome', 'google-chrome-stable', 'google-chrome-beta', 'google-chrome-unstable',
                'chromium', 'chromium-browser', 'org.chromium.Chromium', 'firefox', 'org.mozilla.firefox',
                'firefox-esr', 'web-browser', 'internet-web-browser', 'falkon', 'org.kde.falkon',
                'org.gnome.Epiphany', 'epiphany', 'brave-browser', 'com.brave.Browser', 'microsoft-edge',
                'vivaldi', 'konqueror', 'org.kde.konqueror', 'librewolf'],
    'terminal': ['utilities-terminal', 'org.kde.konsole', 'konsole', 'org.gnome.Ptyxis', 'org.gnome.Console',
                 'gnome-terminal', 'org.gnome.Terminal', 'terminal', 'xterm', 'yakuake', 'org.kde.yakuake',
                 'com.mitchellh.ghostty', 'Alacritty', 'kitty', 'foot', 'org.wezfurlong.wezterm',
                 'terminator', 'xfce4-terminal', 'org.xfce.terminal', 'qterminal', 'lxterminal'],
    'mail': ['kmail', 'org.kde.kmail2', 'org.kde.kmail', 'kontact', 'org.kde.kontact', 'internet-mail',
             'mail-client', 'thunderbird', 'org.mozilla.Thunderbird', 'net.thunderbird.Thunderbird',
             'evolution', 'geary', 'org.gnome.Geary'],
    # text editors share the Code tile: on the test device KWrite fills the dock's Code slot
    'code': ['kate', 'org.kde.kate', 'kwrite', 'org.kde.kwrite', 'accessories-text-editor', 'text-editor',
             'org.gnome.TextEditor', 'gedit', 'org.gnome.gedit', 'mousepad', 'org.xfce.mousepad', 'featherpad',
             'kdevelop', 'org.kde.kdevelop', 'vscode', 'com.visualstudio.code', 'visual-studio-code', 'code-oss',
             'vscodium', 'codium', 'com.vscodium.codium', 'org.gnome.Builder', 'gnome-builder', 'qtcreator',
             'org.qt-project.qtcreator', 'dev.zed.Zed', 'zed', 'sublime-text'],
    'music': ['elisa', 'org.kde.elisa', 'multimedia-audio-player', 'juk', 'org.kde.juk', 'amarok',
              'org.kde.amarok', 'org.gnome.Decibels', 'org.gnome.Music', 'gnome-music', 'rhythmbox',
              'org.gnome.Rhythmbox3', 'audacious', 'strawberry', 'org.strawberrymusicplayer.strawberry',
              'clementine', 'lollypop', 'org.gnome.Lollypop', 'io.bassi.Amberol'],
    'photos': ['gwenview', 'org.kde.gwenview', 'org.gnome.Loupe', 'eog', 'org.gnome.eog', 'image-viewer',
               'multimedia-photo-viewer', 'digikam', 'org.kde.digikam', 'org.kde.koko', 'koko', 'shotwell',
               'org.gnome.Shotwell', 'org.gnome.Photos', 'gthumb', 'org.gnome.gThumb', 'showfoto',
               'org.kde.showfoto', 'ristretto', 'org.xfce.ristretto'],
    # org.gnome.Settings is left out: it only runs under GNOME, and its panel icons
    # (org.gnome.Settings-*-symbolic) would fall back to our tile.
    'settings': ['preferences-system', 'systemsettings', 'org.kde.systemsettings',
                 'xfce4-settings-manager', 'org.xfce.settings.manager'],
    'calendar': ['korganizer', 'org.kde.korganizer', 'office-calendar', 'org.gnome.Calendar', 'gnome-calendar',
                 'org.kde.merkuro.calendar', 'org.kde.kalendar', 'kalendar'],
    'notes': ['marknote', 'org.kde.marknote', 'knotes', 'org.kde.knotes', 'kjots', 'org.kde.kjots',
              'org.gnome.Notes', 'bijiben',
              # handwritten notes (the pen menu's note app; installed on the test device)
              'com.github.xournalpp.xournalpp', 'xournalpp', 'com.github.flxzt.rnote'],
    'calculator': ['accessories-calculator', 'org.kde.kcalc', 'kcalc', 'org.kde.kalk', 'kalk',
                   'org.gnome.Calculator', 'gnome-calculator', 'galculator', 'qalculate', 'qalculate-qt',
                   'io.github.Qalculate', 'speedcrunch', 'org.speedcrunch.SpeedCrunch'],
    'software': ['plasmadiscover', 'org.kde.discover', 'system-software-install', 'software-store',
                 'org.gnome.Software', 'gnome-software'],
    'videos': ['dragonplayer', 'org.kde.dragonplayer', 'haruna', 'org.kde.haruna', 'multimedia-video-player',
               'org.gnome.Showtime', 'org.gnome.Totem', 'totem', 'vlc', 'org.videolan.VLC', 'mpv', 'io.mpv.Mpv',
               'smplayer', 'celluloid', 'io.github.celluloid_player.Celluloid', 'kaffeine', 'org.kde.kaffeine',
               'parole', 'org.xfce.parole', 'com.github.rafostar.Clapper'],
    'chat': ['org.kde.neochat', 'neochat', 'konversation', 'org.kde.konversation', 'internet-chat',
             'org.gnome.Polari', 'polari', 'org.gnome.Fractal', 'fractal', 'element-desktop', 'im.riot.Riot',
             'pidgin'],
    'maps': ['marble', 'org.kde.marble', 'maps', 'org.gnome.Maps', 'gnome-maps'],
    'weather': ['org.kde.kweather', 'kweather', 'org.gnome.Weather', 'gnome-weather'],
    'monitor': ['utilities-system-monitor', 'org.kde.plasma-systemmonitor', 'plasma-systemmonitor', 'ksysguard',
                'org.kde.ksysguard', 'org.gnome.SystemMonitor', 'gnome-system-monitor', 'htop', 'btop',
                'org.gnome.Usage', 'net.nokyan.Resources', 'io.missioncenter.MissionCenter'],
    'screenshot': ['spectacle', 'org.kde.spectacle', 'applets-screenshooter', 'accessories-screenshot',
                   'org.gnome.Screenshot', 'gnome-screenshot', 'org.flameshot.Flameshot', 'flameshot',
                   'ksnip', 'org.ksnip.ksnip', 'accessories-screenshot-tool'],
    'fusion': ['start-here-kde', 'start-here-kde-plasma', 'start-here', 'plasmafusion'],
    # derived tiles (coverage report, BACKLOG C8)
    'archive': ['ark', 'org.kde.ark', 'utilities-file-archiver', 'file-roller', 'org.gnome.FileRoller',
                'engrampa', 'xarchiver'],
    'reader': ['okular', 'org.kde.okular', 'org.gnome.Papers', 'org.gnome.Evince', 'evince', 'atril',
               'org.pwmt.zathura'],
    'camera': ['kamoso', 'org.kde.kamoso', 'org.gnome.Snapshot', 'org.gnome.Cheese', 'cheese'],
}
# tile key -> symbolic glyph used for the NAME-symbolic twins: the one-colour app symbols of the
# Launcher/Main boards' icon table (folder, globe, terminal, ... cpu, crop)
APP_SYMBOLIC = {
    'files': 'folder', 'browser': 'globe', 'terminal': 'terminal', 'mail': 'mail', 'code': 'code-slash',
    'music': 'music', 'photos': 'image', 'settings': 'settings', 'calendar': 'calendar', 'notes': 'document',
    'calculator': 'calculator', 'software': 'bag', 'videos': 'video', 'chat': 'chat', 'maps': 'map',
    'weather': 'cloud', 'monitor': 'sysmon', 'screenshot': 'crop', 'fusion': '@logo',
    'archive': 'archive', 'reader': 'document', 'camera': 'camera',
}

# ------------------------------------------------------------------ places
# key -> (folder glyph for the coloured drawing, small/symbolic glyph, names)
PLACES = {
    'folder': ('folder', 'folder', ['folder', 'inode-directory', 'folder-open', 'folder-drag-accept',
                                    'folder-blue', 'stock_folder']),
    'home': ('home', 'home', ['user-home', 'folder-home']),
    'desktop': ('desktop', 'display', ['user-desktop', 'folder-desktop', 'desktop']),
    'documents': ('documents', 'document-plain', ['folder-documents', 'folder-document']),
    'downloads': ('downloads', 'download', ['folder-download', 'folder-downloads']),
    'music': ('music', 'music', ['folder-music', 'folder-sound']),
    'pictures': ('pictures', 'image', ['folder-pictures', 'folder-picture', 'folder-images', 'folder-image']),
    'videos': ('videos', 'video', ['folder-videos', 'folder-video']),
    'projects': ('projects', 'code', ['folder-development', 'folder-projects', 'folder-script']),
    'network': ('network', 'network', ['folder-network', 'folder-remote', 'network-workgroup']),
    'templates': ('templates', 'document-plain', ['folder-templates']),
    'public': ('public', 'user', ['folder-publicshare', 'folder-public']),
    'recent': ('recent', 'recent', ['folder-recent', 'folder-open-recent']),
    'cloud': ('cloud', 'cloud', ['folder-cloud', 'folder-owncloud', 'folder-nextcloud', 'folder-dropbox',
                                 'folder-gdrive', 'folder-onedrive']),
    'git': ('git', 'folder', ['folder-git']),
    'games': ('games', 'gamepad', ['folder-games']),
    'locked': ('locked', 'lock', ['folder-locked', 'folder-encrypted']),
    'unlocked': ('unlocked', 'folder', ['folder-unlocked', 'folder-decrypted']),
    'favorites': ('favorites', 'star', ['folder-favorites']),
    'important': ('important', 'folder', ['folder-important']),
    'root': ('root', 'folder', ['folder-root']),
    'temp': ('temp', 'folder', ['folder-temp']),
    'mail': ('mail', 'mail', ['folder-mail']),
    'notes': ('notes', 'note', ['folder-notes']),
    'bookmark': ('bookmark', 'folder', ['folder-bookmark']),
    'books': ('books', 'folder', ['folder-book']),
    'activities': ('activities', 'folder', ['folder-activities']),
}
FOLDER_TINT_NAMES = ['red', 'orange', 'yellow', 'green', 'cyan', 'violet', 'magenta', 'brown', 'grey', 'black']
TRASH = {
    'trash': (False, 'trash', ['user-trash']),
    'trash-full': (True, 'trash-full', ['user-trash-full']),
}

# ------------------------------------------------------------------ devices
# key -> (coloured drawing, small/symbolic glyph, names)
DEVICES = {
    'drive': ('drive', 'drive', ['drive-harddisk', 'drive-harddisk-root', 'drive-harddisk-solidstate',
                                 'drive-harddisk-system', 'drive-partition', 'drive-multidisk', 'harddrive']),
    'usb': ('usb', 'usb', ['drive-removable-media-usb', 'drive-removable-media-usb-pendrive',
                           'drive-removable-media', 'media-removable', 'drive-harddisk-usb']),
    'phone': ('phone', 'phone', ['phone', 'smartphone', 'pda', 'multimedia-player']),
    'sdcard': ('sdcard', 'sdcard', ['media-flash-sd-mmc', 'media-flash', 'media-flash-memory-stick',
                                    'media-flash-smart-media', 'media-flash-compact-flash']),
    'optical': ('optical', 'disc', ['media-optical', 'media-optical-cd', 'media-optical-dvd', 'media-optical-blu-ray',
                                    'media-optical-audio', 'media-optical-data', 'media-optical-video',
                                    'media-optical-recordable', 'media-optical-cd-audio', 'media-optical-dvd-video',
                                    'media-optical-mixed-cd', 'drive-optical']),
    'server': ('server', 'server', ['network-server', 'network-server-database']),
    'printer': ('printer', 'printer', ['printer', 'printer-network', 'printer-remote']),
    'headphones': ('headphones', 'headphones', ['audio-headphones']),
    'headset': ('headphones', 'headset', ['audio-headset']),
    'keyboard': ('keyboard', 'keyboard', ['input-keyboard']),
    'mouse': ('mouse', 'mouse', ['input-mouse']),
    'display': ('display', 'display', ['video-display', 'monitor']),
    'computer': ('display', 'computer', ['computer']),
    'tv': ('display', 'tv', ['video-television']),
    'camera': ('camera', 'camera', ['camera-photo', 'camera-video']),
    'webcam': ('webcam', 'webcam', ['camera-web']),
    'laptop': ('laptop', 'laptop', ['computer-laptop', 'laptop']),
    'speaker': ('speaker', 'speaker', ['audio-speakers', 'audio-card']),
    'microphone': ('microphone', 'mic', ['audio-input-microphone']),
    'gamepad': ('gamepad', 'gamepad', ['input-gaming', 'input-gamepad']),
    'touchpad': ('touchpad', 'touchpad', ['input-touchpad']),
    'tablet': ('tablet', 'tablet', ['tablet']),
    'scanner': ('scanner', 'scanner', ['scanner']),
}
# symbolic-only device names requested by Plasma (plasma-pa form factors, KDE Connect, kdeconnect-tray)
DEVICE_SYMBOLIC_EXTRA = {
    'headset': ['hands-free'], 'car': ['car'], 'speaker': ['hifi'], 'phone': ['portable'],
    'tv': ['tv'],
}

# ------------------------------------------------------------------ status (tray and OSD)
# Filled in by gen_icons.add_status(): battery, Wi-Fi, volume, microphone, Bluetooth, weather,
# notifications, night light, brightness. Everything is shipped as NAME and NAME-symbolic.

# ------------------------------------------------------------------ actions, categories
# glyph -> action names (plain and -symbolic). Names are Breeze / freedesktop / GNOME names
# checked against the installed themes, plus plasmafusion-* names for this desktop's own parts.
ACTIONS = {
    'search': ['system-search', 'edit-find', 'search', 'plasmafusion-search'],
    'overview': ['window-duplicate', 'plasmafusion-overview'],
    'home': ['go-home'],
    'download': ['download', 'edit-download'],
    'trash': ['edit-delete', 'delete', 'trash-empty'],
    'lock': ['system-lock-screen', 'lock', 'object-locked', 'changes-prevent'],
    'power': ['system-shutdown', 'application-exit'],
    'restart': ['system-reboot', 'view-refresh'],
    'moon': ['system-suspend'],
    'hibernate': ['system-suspend-hibernate', 'system-hibernate'],
    'logout': ['system-log-out'],
    'switch-user': ['system-switch-user'],
    'settings': ['configure', 'settings-configure', 'plasmafusion-settings', 'emblem-system'],
    'settings-lite': ['plasmafusion-network-settings'],
    'clipboard': ['edit-paste', 'plasmafusion-clipboard'],
    'copy': ['edit-copy'],
    'cut': ['edit-cut'],
    'undo': ['edit-undo'],
    'redo': ['edit-redo'],
    'pencil': ['edit-rename', 'document-edit'],
    'phone': ['plasmafusion-phone'],
    'screenshot': ['plasmafusion-screenshot'],
    'snap': ['view-split-left-right', 'plasmafusion-snap'],
    'split-v': ['view-split-top-bottom'],
    'minimize': ['window-minimize'],
    'maximize': ['window-maximize'],
    'restore': ['window-restore'],
    'close': ['window-close', 'dialog-close', 'edit-clear', 'tab-close', 'process-stop', 'dialog-cancel',
              'edit-clear-all', 'edit-clear-locationbar-ltr', 'edit-clear-locationbar-rtl'],
    'minus': ['list-remove', 'value-decrease'],
    'plus': ['list-add', 'value-increase', 'tab-new'],
    'chevron-right': ['go-next', 'arrow-right', 'pan-end', 'go-next-view'],
    'chevron-left': ['go-previous', 'arrow-left', 'pan-start', 'go-previous-view'],
    'chevron-up': ['go-up', 'arrow-up', 'pan-up', 'collapse'],
    'chevron-down': ['go-down', 'arrow-down', 'pan-down', 'expand'],
    'arrow-right': ['plasmafusion-submit'],
    'check': ['dialog-ok', 'dialog-ok-apply', 'object-select', 'checkmark'],
    'document-new': ['document-new'],
    'folder-new': ['folder-new', 'folder-add'],
    'folder-open': ['document-open', 'document-open-folder'],
    'document': ['document-properties'],
    'save': ['document-save'],
    'print': ['document-print'],
    'grid': ['view-list-icons', 'view-grid', 'view-app-grid', 'applications-all', 'plasmafusion-grid'],
    'list-compact': ['view-list-details'],
    'list': ['view-list-tree', 'view-list', 'view-list-text', 'plasmafusion-list'],
    'menu': ['application-menu', 'open-menu'],
    'more': ['view-more', 'view-more-horizontal', 'overflow-menu'],
    'eye': ['view-visible', 'password-show-on'],
    'eye-off': ['view-hidden', 'view-visible-off', 'password-show-off'],
    'user': ['user-identity', 'im-user', 'avatar-default'],
    'palette': ['plasmafusion-appearance'],
    'dock': ['plasmafusion-dock'],
    'topbar': ['plasmafusion-topbar'],
    'window': ['plasmafusion-windows'],
    'window-new': ['window-new'],
    'pause': ['media-playback-pause'],
    'play': ['media-playback-start'],
    'stop': ['media-playback-stop'],
    'record': ['media-record'],
    'skip-back': ['media-skip-backward', 'media-seek-backward'],
    'skip-forward': ['media-skip-forward', 'media-seek-forward'],
    'eject': ['media-eject'],
    'compass': ['plasmafusion-discover'],
    'check-bold': ['plasmafusion-installed'],
    'cube': ['plasmafusion-3d'],
    'aperture': ['plasmafusion-photography'],
    'info': ['help-about', 'documentinfo'],
    'help': ['help-contents'],
    'star': ['starred', 'bookmark-new'],
    'pin': ['window-pin'],
    'unpin': ['window-unpin'],
    'shuffle': ['media-playlist-shuffle'],
    'repeat': ['media-playlist-repeat', 'media-repeat-all'],
    'repeat-one': ['media-playlist-repeat-song', 'media-repeat-single'],
    'send': ['mail-send', 'document-send'],
    'share': ['document-share'],
    'filter': ['view-filter'],
    'fullscreen': ['view-fullscreen'],
    'link': ['insert-link'],
    'sidebar': ['sidebar-show'],
    'keep-above': ['window-keep-above'],
    'keep-below': ['window-keep-below'],
    'shade': ['window-shade'],
    'zoom-in': ['zoom-in'],
    'zoom-out': ['zoom-out'],
    'recent': ['document-open-recent'],
    'archive': ['archive-insert'],
    'music': ['media-album-cover'],
    'meta': ['plasmafusion-meta'],
    'accessibility': ['plasmafusion-accessibility'],
    'keyboard': ['plasmafusion-keyboard'],
    'cloud': ['plasmafusion-weather'],
    'display': ['plasmafusion-displays'],
    'upload': ['plasmafusion-upload'],
}
CATEGORIES = {
    'wrench': ['applications-accessories', 'applications-utilities'],
    'code-slash': ['applications-development'],
    'cap': ['applications-education'],
    'gamepad': ['applications-games'],
    'brush': ['applications-graphics'],
    'globe': ['applications-internet'],
    'network': ['applications-network'],
    'video': ['applications-multimedia'],
    'document': ['applications-office'],
    'grid': ['applications-other'],
    'flask': ['applications-science'],
    'computer': ['applications-system'],
}

# ------------------------------------------------------------------ per-app tiles
# The 2026-10-02 redesign (apptiles/): every listed app gets its own tile, keyed "app-<key>". Its
# icon names leave the generic category lists above (which keep the apps without one); an app that
# uses a board tile as it is adds its names to that tile's list. The -symbolic twin of a per-app
# name keeps the symbol of the category the name was in, if it was in one.
import apptiles as _apptiles  # noqa: E402

_CATEGORY_OF = {_n: _k for _k, _ns in APPS.items() for _n in _ns}
# Generic names a few apps use as their Icon= (Plasma Camera: camera-photo, KUserFeedback Console:
# system-search, Vakzination: applications-development, KDebugSettings: debug-run, Kirigami
# Gallery: preferences-desktop-theme, Welcome Center: start-here-kde-plasma, KMail Import Wizard:
# kontact-import-wizard, a Breeze action in KMail's menus). They mean an action, a settings page or
# the launcher elsewhere, so they keep that drawing; the apps' own ids still get their tiles (the
# shell looks tiles up by desktop id).
_GENERIC = {'camera-photo', 'system-search', 'applications-development', 'debug-run',
            'preferences-desktop-theme', 'start-here-kde-plasma', 'kontact-import-wizard'}
for _ns in list(_apptiles.APP_NAMES.values()) + list(_apptiles.BOARD_NAMES.values()):
    _ns[:] = [_n for _n in _ns if _n not in _GENERIC]
_PER_APP = {_n for _ns in _apptiles.APP_NAMES.values() for _n in _ns}
# Other names of the same apps still in the category lists: dash variants ("google-chrome-stable"
# -> "google-chrome"), a plain name that ends a per-app reverse-DNS id ("vivaldi" ->
# "com.vivaldi.Vivaldi"), and the aliases below. They move to the app's tile, so the exact name the
# loader finds first is the app's own tile.
_ALIASES = {'org.kde.kmail': 'kmail', 'net.thunderbird.Thunderbird': 'thunderbird', 'rhythmbox': 'rhythmbox',
            'vscode': 'vscode', 'visual-studio-code': 'vscode', 'code-oss': 'vscode', 'vscodium': 'vscodium'}
_APP_OF = {_n: _k for _k, _ns in _apptiles.APP_NAMES.items() for _n in _ns}
_TAIL = {_n.rsplit('.', 1)[-1].lower(): _k for _n, _k in _APP_OF.items() if _n.count('.') >= 2}


def _moves_to(name):
    if name in _ALIASES:
        return _ALIASES[name]
    for _p, _k in _APP_OF.items():
        if '.' not in _p and name.startswith(_p + '-'):
            return _k
    if '.' not in name:
        return _TAIL.get(name.lower())
    return None


ALIAS_MOVES = []
for _k in list(APPS):
    _keep = []
    for _n in APPS[_k]:
        if _n in _PER_APP:
            continue
        _dest = _moves_to(_n)
        if _dest:
            _apptiles.APP_NAMES[_dest].append(_n)
            _PER_APP.add(_n)
            ALIAS_MOVES.append((_n, _k, _dest))
        else:
            _keep.append(_n)
    APPS[_k] = _keep
for _k, _ns in _apptiles.BOARD_NAMES.items():
    APPS[_k] += [_n for _n in _ns if _n not in _CATEGORY_OF and _n not in APPS[_k]]
for _k, _ns in _apptiles.APP_NAMES.items():
    APPS['app-' + _k] = list(_ns)
    _cats = [_CATEGORY_OF[_n] for _n in _ns if _n in _CATEGORY_OF]
    APP_SYMBOLIC['app-' + _k] = APP_SYMBOLIC[_cats[0]] if _cats else None
# The names drawn with an app's own designed tile: the per-app tiles and the apps whose design is a
# board tile (Konsole: terminal). Familiar app icons (packages/appicons) leave these names alone;
# every theme carries the list as designed-apps.txt, and FusionIconNames.js as designed().
DESIGNED = sorted({_n for _k in _apptiles.APP_NAMES for _n in APPS['app-' + _k]}
                  | {_n for _k, _ns in _apptiles.BOARD_NAMES.items() for _n in _ns if _n in APPS[_k]})
