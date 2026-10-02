# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Foundation test scenario (not installed), sourced by scenario-dark.sh / scenario-light.sh inside a
# tools/vsession session: sets the fonts, applies the colour scheme and the PlasmaFusion wallpaper,
# then screenshots System Settings (Colours, Fonts), Dolphin, Konsole, KWrite, a GTK 3 and a
# libadwaita test window and, with EXTRA=1, the logout and lock screens. V=dark|light.
exec 2>&1
set -x
if [ "$V" = dark ]; then SCHEME=PlasmaFusionDark; KT="Plasma Fusion Dark"; else SCHEME=PlasmaFusionLight; KT="Plasma Fusion Light"; fi
F13='Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0'
kwriteconfig6 --notify --file kdeglobals --group General --key font "$F13"
kwriteconfig6 --notify --file kdeglobals --group General --key menuFont "$F13"
kwriteconfig6 --notify --file kdeglobals --group General --key toolBarFont "$F13"
kwriteconfig6 --notify --file kdeglobals --group General --key smallestReadableFont 'Manrope,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0'
kwriteconfig6 --notify --file kdeglobals --group General --key fixed 'Noto Sans Mono,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0'
kwriteconfig6 --notify --file kdeglobals --group WM --key activeFont 'Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0'
fc-list | grep -i -E "manrope|grotesk" > $OUT/fc-list.txt
{ fc-match "Manrope:weight=200"; fc-match "Manrope:weight=80"; fc-match "Space Grotesk:weight=180"; } > $OUT/fc-match.txt
plasma-apply-colorscheme $SCHEME > $OUT/apply-colorscheme.txt 2>&1
sleep 3
kreadconfig6 --file kdeglobals --group Colors:Header --group Inactive --key BackgroundNormal > $OUT/header-inactive.txt
kreadconfig6 --file kdeglobals --group Colors:Header --group Inactive --key ForegroundNormal >> $OUT/header-inactive.txt
cp ~/.config/kdeglobals $OUT/kdeglobals.txt
plasma-apply-wallpaperimage $HOME/.local/share/wallpapers/PlasmaFusion > $OUT/apply-wallpaper.txt 2>&1
sleep 2
kquitapp6 plasmashell; sleep 2
QT_FORCE_STDERR_LOGGING=1 plasmashell > $OUT/plasmashell2.log 2>&1 &
wait_for_name org.kde.plasmashell; sleep 7
{ ls -la ~/.config/gtk-3.0 ~/.config/gtk-4.0; echo ---; cat ~/.config/gtk-3.0/gtk.css; echo ---; cat ~/.config/gtk-4.0/gtk.css; echo ---; cat ~/.config/gtk-3.0/colors.css; cat ~/.config/gtk-3.0/settings.ini; } > $OUT/gtk-state.txt 2>&1
shot $V-01-desktop
QT_FORCE_STDERR_LOGGING=1 systemsettings kcm_colors > $OUT/systemsettings.log 2>&1 & P=$!; sleep 8; shot $V-02-colors; kill $P; sleep 1
QT_FORCE_STDERR_LOGGING=1 systemsettings kcm_fonts > $OUT/systemsettings-fonts.log 2>&1 & P=$!; sleep 7; shot $V-02b-fonts; kill $P; sleep 1
QT_FORCE_STDERR_LOGGING=1 dolphin --new-window $HOME/Pictures/Wallpapers > $OUT/dolphin.log 2>&1 & P=$!; sleep 6; shot $V-03-dolphin; kill $P; sleep 1
QT_FORCE_STDERR_LOGGING=1 konsole --profile "Plasma Fusion" -e bash $HOME/test/demo.sh > $OUT/konsole.log 2>&1 & P=$!; sleep 5; shot $V-04-konsole; kill $P; sleep 1
if [ "$V" = light ]; then konsole --profile "Plasma Fusion" -p ColorScheme=PlasmaFusionLight -e bash $HOME/test/demo.sh > $OUT/konsole-light.log 2>&1 & P=$!; sleep 5; shot $V-04b-konsole-lightscheme; kill $P; sleep 1; fi
kwriteconfig6 --file kwriterc --group "KTextEditor Renderer" --key "Auto Color Theme Selection" false
kwriteconfig6 --file kwriterc --group "KTextEditor Renderer" --key "Color Theme" "$KT"
QT_FORCE_STDERR_LOGGING=1 kwrite $HOME/test/sample.qml > $OUT/kwrite.log 2>&1 & P=$!; sleep 5; shot $V-05-kwrite; kill $P; sleep 1
python3 $HOME/test/gtk3-controls.py > $OUT/gtk3.log 2>&1 & P=$!; sleep 4; shot $V-06-gtk3; kill $P; sleep 1
python3 $HOME/test/gtk3-controls.py menu > $OUT/gtk3-menu.log 2>&1 & P=$!; sleep 4.5; shot $V-07-gtk3-menu; kill $P; sleep 1
python3 $HOME/test/adw-controls.py > $OUT/adw.log 2>&1 & P=$!; sleep 4.5; shot $V-08-adw; kill $P; sleep 1
python3 $HOME/test/adw-controls.py menu > $OUT/adw-menu.log 2>&1 & P=$!; sleep 4.5; shot $V-09-adw-menu; kill $P; sleep 1
if [ "${EXTRA:-0}" = 1 ]; then
  /usr/libexec/ksmserver-logout-greeter --windowed > $OUT/logout.log 2>&1 & P=$!; sleep 5; shot $V-10-logout; kill $P; sleep 1
  /usr/libexec/kscreenlocker_greet --testing > $OUT/lock.log 2>&1 & P=$!; sleep 6; shot $V-11-lock; kill $P; sleep 1
fi
