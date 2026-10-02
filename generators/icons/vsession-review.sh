# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
# mine() prints one PID per line; kill takes each as an argument on purpose.
# shellcheck disable=SC2046
#
# Icons with every part, in a private Plasma session (tools/vsession): applies the Plasma Fusion
# Global Theme named in ~/.ric-variant ("dark" or "light"), then shows the desktop, the launcher,
# the tray's hidden-items popup and Dolphin (home, file types in icon and details views), and
# records KIconLoader lookups of the tray/action names added in the review. Seed HOME: a full
# build (STAGE=$SEED bash tools/build.sh) plus the variant file, for example:
#   echo light > $SEED/.ric-variant
#   tools/vsession/remote.sh ric-light generators/icons/vsession-review.sh $SEED 1440x900 200
# Note: KWin itself does not see ~/.config/kdedefaults in these sessions, so after
# plasma-apply-lookandfeel its own icon lookups (title bar app icon) fall back to hicolor/Breeze.
exec 2>>"$OUT/scenario-trace.log"
set -x
VAR=$(cat "$HOME/.ric-variant")
if [ "$VAR" = dark ]; then SCHEME=PlasmaFusionDark; LNF=org.plasmafusion.dark.desktop; THEME=PlasmaFusion-Dark; else SCHEME=PlasmaFusionLight; LNF=org.plasmafusion.light.desktop; THEME=PlasmaFusion; fi
mine() { for p in $(pgrep -x "$1"); do grep -qz "^XDG_RUNTIME_DIR=$PFV/run\$" /proc/$p/environ 2>/dev/null && echo "$p"; done; }
xdg-user-dirs-update >/dev/null 2>&1
mkdir -p "$HOME/Samples/Projects" "$HOME/Samples/Music"
python3 - "$HOME/Samples" <<'PY'
import os, sys, zipfile
d = sys.argv[1]
def w(n, b): open(os.path.join(d, n), 'wb').write(b)
w('report.pdf', b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n')
w('song.mp3', b'ID3\x03\x00\x00\x00\x00\x00\x0a' + b'\x00' * 64)
w('clip.mkv', b'\x1a\x45\xdf\xa3' + b'\x00' * 64)
with zipfile.ZipFile(os.path.join(d, 'archive.zip'), 'w') as z: z.writestr('a.txt', 'a')
w('tool.py', b'#!/usr/bin/env python3\nprint(1)\n')
w('notes.txt', b'plain text\n')
w('data.json', b'{"a": 1}\n')
w('disk.iso', b'\x00' * 40000)
w('font.ttf', b'\x00\x01\x00\x00' + b'\x00' * 64)
w('unknown.bin', bytes(range(256)))
for n, m in (('letter.odt', 'text'), ('budget.ods', 'spreadsheet'), ('talk.odp', 'presentation')):
    with zipfile.ZipFile(os.path.join(d, n), 'w') as z: z.writestr('mimetype', 'application/vnd.oasis.opendocument.' + m)
PY
plasma-apply-colorscheme "$SCHEME" > "$OUT/apply-colors.log" 2>&1
plasma-apply-lookandfeel -a "$LNF" --resetLayout > "$OUT/apply-lnf.log" 2>&1
/usr/libexec/plasma-changeicons "$THEME" > "$OUT/changeicons.log" 2>&1
sleep 3
export XDG_CONFIG_DIRS="$HOME/.config/kdedefaults:/etc/xdg"
kquitapp6 plasmashell >/dev/null 2>&1
sleep 2
plasmashell >"$OUT/plasmashell-2.log" 2>&1 &
wait_for_name org.kde.plasmashell
sleep 10
kreadconfig6 --file kdeglobals --group Icons --key Theme > "$OUT/icon-theme.txt"
for n in media-playback-playing-symbolic update-low update-high plasmavault-symbolic window-unpin media-playlist-shuffle \
         edit-clear-locationbar-rtl folder-add battery-ups-symbolic battery-050-charging-symbolic network-wireless-60-locked-symbolic \
         audio-volume-medium-symbolic klipper-symbolic org.kde.dolphin utilities-terminal-symbolic user-trash unknown \
         preferences-system-network-connection preferences-system-windows; do
  printf '%-40s %s\n' "$n" "$(kiconfinder6 "$n" 2>/dev/null)"
done > "$OUT/kiconfinder.txt"
find "$HOME/.local/share/icons" -xtype l > "$OUT/dangling-links.txt"
shot 01-desktop
evaljs - > "$OUT/panel-widgets.txt" 2>&1 <<'JS'
var out = []; for (var i = 0; i < panels().length; i++) { var p = panels()[i]; var ws = p.widgets(); for (var j = 0; j < ws.length; j++) out.push(p.id + ' ' + ws[j].id + ' ' + ws[j].type); } print(out.join('\n') + '\n');
JS
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu >/dev/null 2>&1
sleep 3
shot 02-launcher
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu >/dev/null 2>&1
sleep 1
TRAY=$(awk '$3=="org.kde.plasma.systemtray"{print $2; exit}' "$OUT/panel-widgets.txt")
evaljs - >>"$OUT/panel-widgets.txt" 2>&1 <<JS
var ps = panels(); for (var i = 0; i < ps.length; i++) { var w = ps[i].widgetById($TRAY); if (w) { w.globalShortcut = "Ctrl+Alt+Shift+F9"; print('shortcut set on ' + w.id + '\n'); } }
JS
sleep 1
qdbus org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate widget $TRAY" >/dev/null 2>&1
sleep 3
shot 03-tray-popup
qdbus org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate widget $TRAY" >/dev/null 2>&1
sleep 1
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
sleep 7
shot 04-dolphin-home
kill $(mine dolphin) 2>/dev/null
sleep 1
dolphin --new-window "$HOME/Samples" >>"$OUT/dolphin.log" 2>&1 &
sleep 6
shot 05-dolphin-samples-icons
DPID=$(mine dolphin | tail -1)
qdbus org.kde.dolphin-$DPID /dolphin/Dolphin_1 org.kde.KMainWindow.activateAction details >/dev/null 2>&1
sleep 2
shot 06-dolphin-samples-details
kill $(mine dolphin) 2>/dev/null
sleep 1
grep -iE 'icon|svg|\.svg' "$OUT/plasmashell.log" "$OUT/plasmashell-2.log" "$OUT/dolphin.log" "$OUT/kwin.log" 2>/dev/null | grep -viE 'systray|StatusNotifier' > "$OUT/icon-warnings.txt"
