# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Icon theme check in a private Plasma session (tools/vsession). Seed HOME: the icons stage plus a
# kdeglobals that names the theme (and a colour scheme), for example:
#   STAGE=$SEED bash tools/build.sh icons
#   { cat PlasmaFusionDark.colors; printf '\n[Icons]\nTheme=PlasmaFusion-Dark\n'; } > $SEED/.config/kdeglobals
#   tools/vsession/remote.sh ic-2 generators/icons/vsession-check.sh $SEED 1440x900 240
# Outputs: kiconfinder lookups, dangling links, sample files in Dolphin (icon and details views),
# the launcher, the tray popup, System Settings and Nautilus (GTK 4) screenshots, and the
# machine's icon-name inventory (for make_capture.py --extra).
exec 2>>"$OUT/scenario-trace.log"
set -x
ICON_THEME=$(kreadconfig6 --file kdeglobals --group Icons --key Theme)
# processes of THIS private session only (the real desktop runs as the same user)
mine() { for p in $(pgrep -x "$1"); do grep -qz "^XDG_RUNTIME_DIR=$PFV/run\$" /proc/$p/environ 2>/dev/null && echo "$p"; done; }
# 1. icon names installed on this machine (for the capture analysis) and dangling links in our themes
( cd /usr/share/icons && find hicolor breeze \( -name '*.svg' -o -name '*.png' -o -name '*.svgz' \) | sed 's/\.[^.]*$//' ) > "$OUT/icon-files-thinkpad.txt"
find "$HOME/.local/share/icons" -xtype l > "$OUT/dangling-links.txt"
rpm -q breeze-icon-theme plasma-breeze kf6-kiconthemes > "$OUT/versions.txt" 2>&1
# 2. lookups through the real KIconLoader in this session
for n in org.kde.dolphin google-chrome firefox utilities-terminal kmail korganizer preferences-system systemsettings \
         plasmadiscover elisa gwenview spectacle org.kde.neochat utilities-system-monitor accessories-calculator kwrite \
         org.gnome.Nautilus org.gnome.Weather org.gnome.Maps dragonplayer start-here-kde-plasma \
         preferences-system-windows preferences-desktop-theme okular ark kdeconnect \
         folder user-home folder-documents folder-downloads user-trash user-trash-full folder-git \
         application-pdf image-png audio-mpeg video-mp4 application-zip text-plain font-ttf application-vnd.efi.iso \
         drive-harddisk drive-removable-media-usb battery-080-symbolic network-wireless-100-symbolic \
         audio-volume-medium-symbolic notification-inactive-symbolic klipper-symbolic kdeconnect-tray-symbolic \
         image-missing input-touchpad-on; do
  printf '%-40s %s\n' "$n" "$(kiconfinder6 "$n" 2>/dev/null)"
done > "$OUT/kiconfinder.txt"
# 3. sample files of many types
xdg-user-dirs-update >/dev/null 2>&1
mkdir -p "$HOME/Samples"
python3 - "$HOME/Samples" <<'PY'
import os, sys, zipfile, struct, zlib
d = sys.argv[1]
def w(name, data): open(os.path.join(d, name), 'wb').write(data)
png = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)
png += struct.pack('>I', zlib.crc32(png[12:29]) & 0xffffffff)
w('photo.png', png + b'\x00' * 16)
w('picture.jpg', b'\xff\xd8\xff\xe0\x00\x10JFIF\x00' + b'\x00' * 32)
w('drawing.svg', b'<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"/>')
w('report.pdf', b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n')
w('song.mp3', b'ID3\x03\x00\x00\x00\x00\x00\x0a' + b'\x00' * 64)
w('track.flac', b'fLaC' + b'\x00' * 64)
w('movie.mp4', struct.pack('>I', 24) + b'ftypisom' + b'\x00' * 12 + b'\x00' * 32)
w('clip.mkv', b'\x1a\x45\xdf\xa3' + b'\x00' * 64)
with zipfile.ZipFile(os.path.join(d, 'archive.zip'), 'w') as z: z.writestr('a.txt', 'a')
w('backup.tar.gz', b'\x1f\x8b\x08\x00' + b'\x00' * 32)
w('script.js', b'console.log("hi")\n')
w('tool.py', b'#!/usr/bin/env python3\nprint(1)\n')
w('lib.rs', b'fn main() {}\n')
w('run.sh', b'#!/bin/sh\necho hi\n')
w('notes.txt', b'plain text\n')
w('readme.md', b'# Title\n')
w('data.json', b'{"a": 1}\n')
w('page.html', b'<!doctype html><html></html>\n')
w('disk.iso', b'\x00' * 40000)
w('font.ttf', b'\x00\x01\x00\x00' + b'\x00' * 64)
w('unknown.bin', bytes(range(256)))
with zipfile.ZipFile(os.path.join(d, 'letter.odt'), 'w') as z:
    z.writestr('mimetype', 'application/vnd.oasis.opendocument.text')
with zipfile.ZipFile(os.path.join(d, 'budget.ods'), 'w') as z:
    z.writestr('mimetype', 'application/vnd.oasis.opendocument.spreadsheet')
with zipfile.ZipFile(os.path.join(d, 'talk.odp'), 'w') as z:
    z.writestr('mimetype', 'application/vnd.oasis.opendocument.presentation')
w('old.doc', b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1' + b'\x00' * 64)
w('table.csv', b'a,b\n1,2\n')
w('app.desktop', b'[Desktop Entry]\nType=Application\nName=X\nExec=true\n')
w('photo.webp', b'RIFF\x00\x00\x00\x00WEBPVP8 ' + b'\x00' * 32)
os.makedirs(os.path.join(d, 'Projects'), exist_ok=True)
PY
# 4. Dolphin: home (places, folders), then samples in icon and details views
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
sleep 7
shot 01-dolphin-home
DPID=$(mine dolphin | tail -1)
qdbus org.kde.dolphin-$DPID /dolphin/Dolphin_1 org.kde.KMainWindow.activateAction go_home >/dev/null 2>&1
dolphin --new-window "$HOME/Samples" >>"$OUT/dolphin.log" 2>&1 &
sleep 5
shot 02-dolphin-samples-icons
DPID2=$(mine dolphin | tail -1)
qdbus org.kde.dolphin-$DPID2 /dolphin/Dolphin_1 org.kde.KMainWindow.activateAction details >/dev/null 2>&1
sleep 2
shot 03-dolphin-samples-details
qdbus org.kde.dolphin-$DPID2 /dolphin/Dolphin_1 org.kde.KMainWindow.activateAction compact >/dev/null 2>&1
sleep 1
qdbus org.kde.dolphin-$DPID2 /dolphin/Dolphin_1 org.kde.KMainWindow.listActions > "$OUT/dolphin-actions.txt" 2>&1
kill $(mine dolphin) 2>/dev/null
sleep 1
# 5. panel, tray and launcher
evaljs - > "$OUT/panel-widgets.txt" 2>&1 <<'JS'
var out = []; for (var i = 0; i < panels().length; i++) { var p = panels()[i]; var ws = p.widgets(); for (var j = 0; j < ws.length; j++) out.push(p.id + ' ' + ws[j].id + ' ' + ws[j].type); } print(out.join('\n') + '\n');
JS
shot 04-desktop-panel
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu >/dev/null 2>&1
sleep 3
shot 05-launcher
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu >/dev/null 2>&1
sleep 1
# 6. system tray popup: give the tray a shortcut and invoke it
TRAY=$(awk '$3=="org.kde.plasma.systemtray"{print $2; exit}' "$OUT/panel-widgets.txt")
evaljs - >>"$OUT/panel-widgets.txt" 2>&1 <<JS
var w = panels()[0].widgetById($TRAY); if (w) { w.globalShortcut = "Ctrl+Alt+Shift+F9"; print('shortcut set on ' + w.id + '\n'); }
JS
sleep 1
qdbus org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.shortcutNames > "$OUT/shortcut-names.txt" 2>&1
qdbus org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate widget $TRAY" >/dev/null 2>&1
sleep 3
shot 06-tray-popup
# 6b. System Settings: KCM icons must stay Breeze's (names handed back through breeze/*)
systemsettings >"$OUT/systemsettings.log" 2>&1 &
sleep 8
shot 06b-systemsettings
kill $(mine systemsettings) 2>/dev/null
sleep 1
# 7. a GTK application using the theme
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
printf '[Settings]\ngtk-icon-theme-name=%s\n' "$ICON_THEME" | tee "$HOME/.config/gtk-3.0/settings.ini" > "$HOME/.config/gtk-4.0/settings.ini"
( nautilus --new-window "$HOME" >"$OUT/nautilus.log" 2>&1 & )
sleep 8
shot 07-gtk-nautilus
kill $(mine nautilus) 2>/dev/null
sleep 1
