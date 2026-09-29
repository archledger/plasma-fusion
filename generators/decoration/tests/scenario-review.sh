# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Test tooling (not installed). Integrated virtual-session scenario for the window decoration,
# sourced by tools/vsession/vsession.sh; seed from make-review-seed.sh (all parts).
#
# Applies Plasma Fusion Dark or Light with tools/device/fusion-config.sh (Global Theme, layout,
# BorderSizeAuto=false), then shoots real Dolphin and System Settings windows at the Main board
# positions: 01 desktop, 02 maximize hovered, 03 close hovered, 03b minimize pressed,
# 04 the active window resized without a focus change, 05 the same after a focus change,
# 06 Files maximized, 07 a dialog with a long title, 08-10 the -Left theme (plain, hovered,
# maximized).
exec 2>&1
set -x
T=$HOME/pf-tools
D=$HOME/pf-deco
source "$D/params.sh"
export XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg QT_FORCE_STDERR_LOGGING=1

if [ -n "${SCALE:-}" ]; then
  output=$(kscreen-doctor -j | python3 -c 'import json, sys; print(json.load(sys.stdin)["outputs"][0]["name"])')
  kscreen-doctor "output.$output.scale.$SCALE"
  sleep 3
fi

if [ "$SCHEME" = dark ]; then
  bash "$T/fusion-config.sh" --reset-layout >"$OUT/config.log" 2>&1
else
  bash "$T/fusion-config.sh" --light --reset-layout >"$OUT/config.log" 2>&1
fi
# (without kdedefaults in XDG_CONFIG_DIRS: kwriteconfig6 skips a value equal to the cascade)
[ -f "$T/merge-kdedefaults.py" ] && env -u XDG_CONFIG_DIRS python3 "$T/merge-kdedefaults.py" kwinrc kcminputrc kdeglobals >"$OUT/merge.log" 2>&1
# KWin reads the title font and the colour scheme from kdeglobals
dbus-send --session --type=signal /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts
dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0
qdbus org.kde.KWin /KWin reconfigure
sleep 3
cp "$HOME/.config/kwinrc" "$OUT/kwinrc-after-config"

next() {  # run the next phase of the placement script
  qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "PF DC Next Step"
  sleep 1.5
}
deco() {  # deco THEME LEFT RIGHT
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__$1"
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft "$2"
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight "$3"
  qdbus org.kde.KWin /KWin reconfigure
  sleep 3
}
point() { python3 "$D/pointer.py" "$1" "$2" || echo "pointer $1 $2 failed"; sleep 0.8; }
park() { point 300 700; }

# Main.dc.html / MainLight.dc.html: Files 64,62 760x500 (unfocused), Appearance 548,262 652x506;
# the 1 px edge is drawn outside the KWin frame, so frames are 1 px inside on every side.
FILES='[65, 63, 758, 498]'
SETTINGS='[549, 263, 650, 504]'
P0="[{\"match\":\"dolphin\",\"max\":false,\"rect\":$FILES},{\"match\":\"systemsettings\",\"max\":false,\"rect\":$SETTINGS,\"activate\":true}]"
P1='[{"match":"systemsettings","rect":[300, 120, 1000, 700]}]'
P2='[{"match":"dolphin","activate":true}]'
P3='[{"match":"systemsettings","activate":true}]'
P4="[{\"match\":\"systemsettings\",\"rect\":$SETTINGS},{\"match\":\"dolphin\",\"max\":true,\"activate\":true}]"
P5="[{\"match\":\"dolphin\",\"max\":false,\"rect\":$FILES},{\"match\":\"kdialog\",\"rect\":[640, 400, 440, 150],\"activate\":true}]"
P6="[{\"match\":\"systemsettings\",\"max\":false,\"rect\":$SETTINGS,\"activate\":true}]"
P7='[{"match":"systemsettings","max":true,"activate":true}]'
P8="[{\"match\":\"systemsettings\",\"max\":false,\"rect\":$SETTINGS,\"activate\":true}]"
PHASES="[$P0,$P1,$P2,$P3,$P4,$P5,$P6,$P7,$P8]"

dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
systemsettings kcm_colors >"$OUT/systemsettings.log" 2>&1 &
sleep 9
sed "s|@PHASES@|$PHASES|" "$D/steps.qml.in" >"$PFV/steps.qml"
id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript "$PFV/steps.qml" pfrdcsteps)
qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run
sleep 2
park; shot 01-desktop
# Settings title bar centre y = 263 + 25; right layout: minimize 1107, maximize 1141, close 1175
point 1141 288; shot 02-hover-maximize
point 1175 288; shot 03-hover-close
python3 "$D/pointer.py" 1107 288 press 3 & presser=$!
sleep 1.8; shot 03b-pressed-minimize; wait "$presser"
park
next; sleep 0.5; shot 04-resized-no-focus-change
next; next; sleep 0.5; shot 05-resized-after-focus-change
next; sleep 1; shot 06-maximized
kdialog --title "Quarterly planning notes, budget review and the hiring plan for the design team.odt" \
  --msgbox "Save changes before closing?" >"$OUT/kdialog.log" 2>&1 &
sleep 3
next; sleep 0.5; shot 07-long-title
deco "PlasmaFusion$NAME-Left" XIA _
next; shot 08-left
# left layout: circles at x 549 + 18.5, 38.5, 58.5
point 587 288; shot 09-left-hover
park
next; sleep 1; shot 10-left-maximized
deco "PlasmaFusion$NAME" M IAX
next
qdbus org.kde.KWin /KWin supportInformation >"$OUT/kwin-support-end.txt" 2>&1
grep -n -i -A3 "^Decoration" "$OUT/kwin-support-end.txt" | head -12
cp "$HOME/.local/state/plasma-fusion/plasmashell.log" "$OUT/plasmashell-config.log" 2>/dev/null
true
