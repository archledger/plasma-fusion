# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
# Test tooling (not installed). Virtual-session scenario for the window decoration, sourced by
# tools/vsession/vsession.sh. Seed made by generators/decoration/tests/make-seed.sh.
#
# Shots: 01 two windows (Files inactive, Settings active, at the Main board positions),
# 02 maximize hovered, 03 close hovered, 03b minimize pressed, 04 Files maximized,
# 05 Files active / Settings inactive,
# 06-08 the -Left theme (buttons on the left): plain, hovered, maximized, 09 hover after an accent
# colour change. The pointer is moved with pointer.py (KWin's emulated-input D-Bus call + libei).
source "$HOME/pf-deco/params.sh"

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

# Main.dc.html positions: Files 64,62 760x500; Appearance 548,262 652x506 (the 1 px edge is
# drawn outside the KWin frame, so frames are 1 px inside on every side).
FILES='[65, 63, 758, 498]'
SETTINGS='[549, 263, 650, 504]'
LAYOUT="[{\"match\":\"dolphin\",\"max\":false,\"rect\":$FILES},{\"match\":\"systemsettings\",\"max\":false,\"rect\":$SETTINGS,\"activate\":true}]"
MAXIMIZED="[{\"match\":\"systemsettings\",\"rect\":$SETTINGS},{\"match\":\"dolphin\",\"max\":true,\"activate\":true}]"
FILES_ACTIVE="[{\"match\":\"dolphin\",\"max\":false,\"rect\":$FILES,\"activate\":true}]"
PHASES="[$LAYOUT,$MAXIMIZED,$FILES_ACTIVE,$LAYOUT,$MAXIMIZED,$LAYOUT]"
# Settings title bar centre line y = 263 + 25. Right layout: maximize centre x = 549 + 650 - 58,
# close x = 549 + 650 - 24; left layout: maximize (third circle) x = 549 + 58.
point() { python3 "$HOME/pf-deco/pointer.py" "$1" "$2" || echo "pointer $1 $2 failed"; sleep 0.8; }

if [ -n "${SCALE:-}" ]; then
  output=$(kscreen-doctor -j | python3 -c 'import json, sys; print(json.load(sys.stdin)["outputs"][0]["name"])')
  kscreen-doctor "output.$output.scale.$SCALE"
  sleep 3
fi
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
systemsettings kcm_kwindecoration >"$OUT/systemsettings.log" 2>&1 &
sleep 10
sed "s|@PHASES@|$PHASES|" "$HOME/pf-deco/steps.qml.in" >"$PFV/steps.qml"
id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript "$PFV/steps.qml" pfdcsteps)
qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run
sleep 2
point 700 820
shot 01-desktop
point 1141 288; shot 02-hover-maximize
point 1175 288; shot 03-hover-close
python3 "$HOME/pf-deco/pointer.py" 1107 288 press 3 & presser=$!
sleep 1.8; shot 03b-pressed-minimize; wait "$presser"
point 700 820
next; sleep 1; shot 04-maximized
next; shot 05-files-active
deco "PlasmaFusion$NAME-Left" XIA _
next; shot 06-left
point 607 288; shot 07-left-hover
point 700 820
next; sleep 1; shot 08-left-maximized
# accent colour change: the hover fill follows the colour scheme's Highlight (KSvg stylesheet)
deco "PlasmaFusion$NAME" M IAX
next
kwriteconfig6 --file kdeglobals --group Colors:Selection --key BackgroundNormal 60,196,176
dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0
qdbus org.kde.KWin /KWin reconfigure
sleep 2
point 1141 288; shot 09-accent-hover
qdbus org.kde.KWin /KWin supportInformation >"$OUT/kwin-support-end.txt" 2>&1
grep -n -i -A3 "^Decoration" "$OUT/kwin-support-end.txt" | head -12
