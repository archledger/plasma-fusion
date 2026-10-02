# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
# vsession scenario (sourced by tools/vsession/vsession.sh): the cursor themes together with all
# other parts. The seed is a full build (tools/build.sh) with NO kcminputrc: applying each Global
# Theme must select the Fusion pointer by itself. The pointer is then shot over the desktop, the
# top bar, the dock, a decorated window (title bar, text field, edges and corners), in the dark
# and the light Global Theme, and once more with the light pointer variant.
T=$HOME/pfv-cursor-test
sup() { qdbus-qt6 org.kde.KWin /KWin supportInformation 2>/dev/null | grep -A2 '^Cursor$' | tail -n 2; }
state() { { echo "## $1"; grep -A3 '^\[Mouse\]' "$HOME/.config/kcminputrc" 2>/dev/null || echo '(no kcminputrc [Mouse])'; sup; } >>"$OUT/cursor-state.txt"; }
state 'session start'

cat >"$OUT/cells.json" <<'JSON'
{"cells": [
 {"name": "desktop", "x": 180, "y": 700},
 {"name": "topbar", "x": 720, "y": 17},
 {"name": "dock", "x": 580, "y": 845},
 {"name": "title", "x": 560, "y": 262},
 {"name": "textfield", "x": 720, "y": 374},
 {"name": "left", "x": 361, "y": 450},
 {"name": "right", "x": 1078, "y": 450},
 {"name": "top", "x": 720, "y": 242},
 {"name": "bottom", "x": 720, "y": 637},
 {"name": "topleft", "x": 362, "y": 242},
 {"name": "bottomright", "x": 1077, "y": 637}
]}
JSON

shoot_round() {  # $1 = prefix for the screenshots
  python3 "$T/edgewin.py" >"$OUT/edgewin-$1.log" 2>&1 &
  local ew=$!
  sleep 3
  local id
  id=$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$T/place.js" "pfvplace-$1")
  qdbus-qt6 org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >>"$OUT/place.log" 2>&1
  sleep 1
  python3 "$T/eipointer.py" "$OUT/cells.json" "$OUT" "$1" >"$OUT/ei-$1.log" 2>&1
  kill "$ew" 2>/dev/null
  qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "pfvplace-$1" >/dev/null 2>&1
  sleep 1
}

# A Global Theme writes its settings as new defaults into ~/.config/kdedefaults/. A real session
# reads them because startplasma puts that directory first in XDG_CONFIG_DIRS; the test session
# (tools/vsession, env -i) does not, so copy the cursor and decoration keys into the user files,
# which is what the cascade would give KWin.
dflt() { kreadconfig6 --file "$HOME/.config/kdedefaults/$1" --group "$2" --key "$3"; }
cascade() {
  local v
  v=$(dflt kcminputrc Mouse cursorTheme)
  echo "kdedefaults/kcminputrc [Mouse] cursorTheme=$v" >>"$OUT/cursor-state.txt"
  [ -n "$v" ] && kwriteconfig6 --notify --file kcminputrc --group Mouse --key cursorTheme "$v"
  for k in library theme; do
    v=$(dflt kwinrc org.kde.kdecoration2 "$k")
    [ -n "$v" ] && kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key "$k" "$v"
  done
  qdbus-qt6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1
  # KWin reloads the cursor theme on KGlobalSettings notifyChange(CursorChanged = 5, 0), the
  # signal the Global Theme and the cursor settings page send after writing kcminputrc.
  dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:5 int32:0 ||
    gdbus emit --session --object-path /KGlobalSettings --signal org.kde.KGlobalSettings.notifyChange 5 0
  sleep 2
}

for scheme in dark light; do
  plasma-apply-lookandfeel -a "org.plasmafusion.$scheme.desktop" --resetLayout >"$OUT/lnf-$scheme.txt" 2>&1
  sleep 8
  state "after plasma-apply-lookandfeel -a org.plasmafusion.$scheme.desktop"
  cascade
  state "after the kdedefaults cascade"
  shoot_round "$scheme"
done

plasma-apply-cursortheme PlasmaFusion-Light-cursors --size 24 >"$OUT/apply-light-cursors.txt" 2>&1
sleep 1
state 'after plasma-apply-cursortheme PlasmaFusion-Light-cursors --size 24'
shoot_round lightptr

grep -n -i -E 'cursor|svg|xcursor|metadata' "$OUT/kwin.log" >"$OUT/kwin-cursor-lines.txt" 2>&1
grep -n -i -E 'cursor|svg' "$OUT/plasmashell.log" >"$OUT/plasmashell-cursor-lines.txt" 2>&1
true
