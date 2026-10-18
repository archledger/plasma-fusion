#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Full screen off in tablet posture (board TabletSnap.dc.html, docs/parts/kwin-tablet.md "Full
# screen off takes a half"): the window card's Full screen switch, tapped with real touch, in a
# private session:
#   1. Dolphin alone: it takes the right half, without a title bar; the home screen offers the
#      apps in the left half;
#   2. KWrite in the left half, Dolphin full screen over it: Dolphin takes the free right half;
#   3. KWrite in the right half: Dolphin takes the left half;
#   4. KWrite in the left two thirds (the divider's split): Dolphin takes the right third when its
#      minimum width fits there, and floats when it does not;
#   5. KWrite sent home (minimized: it keeps its two-thirds tile, and KWin the split): Dolphin, the
#      only window shown, takes the right half, the split back in the middle;
#   6. laptop posture: a window un-maximized there is not tiled.
# Run: tools/vsession/remote.sh fo-1 packages/kwin/tests/vsession/scenario-fullscreen-off.sh SEED 1440x900 420
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
KLOG=$OUT/kwin.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
# Touch 0.6 s after pfinput starts (the seat's touch appears with pfinput's device; a down sent
# before plasmashell binds wl_touch is lost: docs/parts/desktop.md, the free side's tests).
touch_() { pfinput 'sleep 0.6' "$@"; }
act() { K run "var l = workspace.windowList(), w = null; for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } } if (w) { workspace.activeWindow = w; } report(1);" >/dev/null; }
tile() { act "$1"; sleep 0.6; qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Window Quick Tile $2"; sleep 1.5; }
# The window card's Full screen row, for the active window: pulled down from the pill, then the
# row the card logs ("rows fullscreen 184,163; ...").
fullscreen_off() {
  touch_ "swipe 60 22 60 82 0.3"; sleep 1.5
  read -r RX RY <<<"$(grep -a 'window card at' "$PLOG" | tail -n 1 | sed 's/.*rows fullscreen \([0-9]*\),\([0-9]*\);.*/\1 \2/')"
  touch_ "tap $RX $RY"; sleep 2.5
}
# CLASS: "x w tiled noBorder maximized" of the newest such window.
win() {
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    var g = w ? w.frameGeometry : null;
    report(w ? [Math.round(g.x), Math.round(g.width), !!w.tile, w.noBorder, w.maximizeMode === 3].join(' ') : 'none');" | python3 -c 'import json,sys; print(json.load(sys.stdin))'
}
# LABEL CLASS CHECK (python over x, w, tiled, nb, maxed)
expect() {
  local s x w tiled nb maxed
  s=$(win "$2"); read -r x w tiled nb maxed <<<"$s"
  if [ "$s" != none ] && python3 -c "x, w, tiled, nb, maxed = $x, $w, '$tiled' == 'true', '$nb' == 'true', '$maxed' == 'true'; raise SystemExit(0 if ($3) else 1)"; then
    pass "$1: $2 x $x w $w tiled $tiled no-title-bar $nb maximized $maxed"
  else
    fail "$1: $2 $s"
  fi
}

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || info "fusion-config rc=$?"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-snap --key Gap 6
kwriteconfig6 --file kwinrc --group Script-plasmafusion-tablet --key InternalOutputs "eDP,LVDS,DSI,Virtual"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion 99
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
pfv_tablet on; sleep 8

# ---- 1. Dolphin alone
dolphin >/dev/null 2>&1 &
sleep 6
expect "1: Dolphin opens full screen" dolphin "maxed"
fullscreen_off
shot fo-1
expect "1: Full screen off: Dolphin takes the right half" dolphin "tiled and nb and x >= 700 and 600 <= w <= 760 and not maxed"
case "$(grep -a 'home: free side:' "$PLOG" | tail -n 1)" in *"free side: left"*dolphin*) pass "1: the home screen offers the apps in the left half" ;; *) fail "1: no free side on the left: $(grep -a 'home: free side:' "$PLOG" | tail -n 1)" ;; esac

# ---- 2. KWrite in the left half, Dolphin full screen over it
kwrite >/dev/null 2>&1 &
sleep 5
tile kwrite Left
act dolphin; sleep 0.5; K maximize org.kde.dolphin >/dev/null; sleep 2
expect "2: Dolphin full screen again" dolphin "maxed"
fullscreen_off
shot fo-2
expect "2: Full screen off beside KWrite on the left: Dolphin takes the free right half" dolphin "tiled and x >= 700 and not maxed"
expect "2: KWrite stays on the left" kwrite "tiled and x <= 12"

# ---- 3. KWrite in the right half
tile kwrite Right
act dolphin; sleep 0.5; K maximize org.kde.dolphin >/dev/null; sleep 2
fullscreen_off
shot fo-3
expect "3: Full screen off beside KWrite on the right: Dolphin takes the left half" dolphin "tiled and x <= 12 and not maxed"
expect "3: KWrite stays on the right" kwrite "tiled and x >= 700"
# ---- 4. KWrite in the left two thirds (as the split divider leaves it at 2/3)
tile kwrite Left
K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { var w = l[i];
  if (w.normalWindow && String(w.resourceClass).indexOf('kwrite') >= 0 && w.tile) {
    var a = workspace.clientArea(KWin.MaximizeArea, w);
    w.tile.resizeByPixels(a.x + a.width * 2 / 3 - (w.tile.absoluteGeometry.x + w.tile.absoluteGeometry.width), 4); } }  // 4: Qt.RightEdge (no Qt namespace in a KWin JavaScript script)
  report(1);" >/dev/null
sleep 1.5
act dolphin; sleep 0.5; K maximize org.kde.dolphin >/dev/null; sleep 2
DMIN=$(K run "var l = workspace.windowList(), m = -1; for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('dolphin') >= 0) { m = Math.round(l[i].minSize.width); } } report(m);")
info "4: Dolphin's minimum width $DMIN, KWrite $(win kwrite)"
fullscreen_off
shot fo-4
if [ "$DMIN" -le 472 ]; then
  expect "4: beside KWrite in two thirds: Dolphin takes the right third" dolphin "tiled and x >= 940 and w <= 500 and not maxed"
else
  expect "4: beside KWrite in two thirds: Dolphin, wider than the third, floats" dolphin "not tiled and not maxed"
fi
expect "4: KWrite keeps its two thirds" kwrite "tiled and x <= 12 and w >= 940"

# ---- 5. KWrite sent home, its tile and the 2/3 split kept: Dolphin alone, the split in the middle
K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { var w = l[i]; if (w.normalWindow && String(w.resourceClass).indexOf('kwrite') >= 0) { w.minimized = true; } } report(1);" >/dev/null
sleep 2
act dolphin; sleep 0.5; K maximize org.kde.dolphin >/dev/null; sleep 2
fullscreen_off
shot fo-5
expect "5: Dolphin alone takes the right half, the split in the middle" dolphin "tiled and 700 <= x <= 740 and 690 <= w <= 740 and not maxed"
grep -a 'windowed by the user' "$KLOG" | tail -n 5 >>"$CHK" || true

# ---- 6. laptop posture: no snap
pfv_tablet off; sleep 6
act dolphin; sleep 0.5; K maximize org.kde.dolphin >/dev/null; sleep 2
K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { var w = l[i]; if (w.normalWindow && String(w.resourceClass).indexOf('dolphin') >= 0) { w.setMaximize(false, false); } } report(1);" >/dev/null
sleep 2
expect "6: laptop posture: un-maximized Dolphin is not tiled" dolphin "not tiled and not maxed"

errs=$(grep -aE 'plasmafusion-tablet' "$KLOG" | grep -aiE 'error|TypeError|ReferenceError|is not defined|Cannot' || true)
if [ -z "$errs" ]; then pass "no QML errors from plasmafusion-tablet"; else fail "plasmafusion-tablet: $(echo "$errs" | head -3 | tr '\n' ' ')"; fi
info "done"
