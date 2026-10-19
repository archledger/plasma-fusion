#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Saved app pairs (board TabletPairs.dc.html, docs/parts/apppairs.md) in a private session in
# tablet posture, with real touch (pfinput) and the navigation effect built from this tree
# (make-seed.sh):
#   0. a pair saved on the laptop, where the home screen's layer is not loaded, is pinned once
#      tablet posture loads it;
#   1. Dolphin quick-tiled left and KWrite right; the tablet script's "Split One Third" puts the
#      split at a third;
#   2. the app switcher shows the two as one card with "Save pair" under it; a tap saves the pair
#      (its entry: Dolphin left, KWrite right, a third) and the home screen pins it;
#   3. the split moved to half and both apps sent away, the home screen shows the pair; a tap on it
#      opens Dolphin on the left and KWrite on the right, at a third again, through the dock;
#   4. the pair's sides swapped (the helper, as Swap Sides runs it), the split at half again: the
#      tile opens KWrite on the left and Dolphin on the right, at a third;
#   5. a pair whose app is not installed: its tile is shown, and a tap opens nothing;
# and no QML errors from the switcher, the home screen, its pair tile or pairs.js, nor the dock.
# Run: tools/vsession/remote.sh ap-1 packages/apppairs/tests/vsession/scenario-apppairs.sh SEED 1440x900 600
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
KLOG=$OUT/kwin.log
APPS=$HOME/.local/share/applications
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
key() { awk -v k="$2" '/^\[/ { g = $0; next } g == "[Desktop Entry]" && index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$1"; }
act() { # CLASS
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    if (w) { workspace.activeWindow = w; } report(w ? String(w.resourceClass) : null);" >>"$OUT/act.log"
}
shortcut() { qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "$1"; }
tile() { act "$2"; sleep 0.6; shortcut "Window Quick Tile $1"; sleep 1.5; }
tap() { pfinput 'sleep 0.6' "tap $1 $2 0.15" "${@:3}"; }
# Where the two apps are: "dolphinX dolphinW kwriteX kwriteW areaX areaW", or "none".
where() {
  K run "var l = workspace.windowList(), d = null, k = null;
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (!c.normalWindow || c.minimized) { continue; }
      if (String(c.resourceClass).indexOf('dolphin') >= 0) { d = c.frameGeometry; }
      if (String(c.resourceClass).indexOf('kwrite') >= 0) { k = c.frameGeometry; } }
    var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
    report(d && k ? [d.x, d.width, k.x, k.width, a.x, a.width].map(Math.round).join(' ') : 'none');" |
    python3 -c 'import json,sys; print(json.load(sys.stdin))'
}
# LEFT RIGHT SHARE: the app LEFT (dolphin or kwrite) on the left with SHARE of the work area.
side_by_side() {
  python3 - "$(where)" "$1" "$3" <<'PY'
import sys
v = sys.argv[1].split()
if len(v) != 6:
    sys.exit(1)
dx, dw, kx, kw, ax, aw = map(int, v)
left = (dx, dw) if sys.argv[2] == "dolphin" else (kx, kw)
right = (kx, kw) if sys.argv[2] == "dolphin" else (dx, dw)
share = float(sys.argv[3])
ok = left[0] < right[0] and abs(left[0] - ax) <= 16 and abs(right[0] + right[1] - (ax + aw)) <= 16 \
    and abs(left[0] + left[1] - (ax + aw * share)) <= 20
sys.exit(0 if ok else 1)
PY
}
logged() { grep -a "$1" "$2" | tail -n 1 || true; }
# The split moved to half (the tablet script's Split Half), then both apps away: the next open has
# to put the split where the pair was saved.
reset_then_away() { # LABEL
  act dolphin; sleep 0.6
  shortcut "Plasma Fusion: Split Half"
  sleep 1.5
  if side_by_side dolphin kwrite 0.5 || side_by_side kwrite dolphin 0.5; then
    pass "$1: the split moved to half first: $(where)"
  else
    fail "$1: the split did not move to half: $(where)"
  fi
  K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow) { l[i].minimized = true; } } report(1);" >/dev/null
  sleep 3
}
# The last position the log gives after "at ": "X Y".
at_of() { sed -n 's/.* at \([0-9]*\),\([0-9]*\)$/\1 \2/p' <<<"$1"; }

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || info "fusion-config rc=$?"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-snap --key Gap 6
kwriteconfig6 --file kwinrc --group Script-plasmafusion-tablet --key InternalOutputs "eDP,LVDS,DSI,Virtual"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion 99
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
# ---- 0. a pair saved on the laptop (the switcher works there too), where the home screen's layer
# is not loaded: it is pinned once tablet posture loads it; then removed again (the grid as before)
early=$("$HOME/.local/libexec/plasma-fusion/plasma-fusion-app-pair" save org.kde.kcalc.desktop org.kde.konsole.desktop 0.5 2>>"$OUT/helper.log" || true)
sleep 3
if [ -n "$early" ] && grep -aq "home: pair: pin applications:$early" "$PLOG"; then info "0: pinned on the laptop already"; fi
pfv_tablet on; sleep 8
info "navigation effect: $(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded plasmafusion_navigation)"
if [ -n "$early" ] && grep -aq "home: pair: pin applications:$early" "$PLOG"; then
  pass "0: a pair saved on the laptop is pinned once tablet posture shows the home screen ($early)"
else
  fail "0: the pair saved on the laptop ('$early') was not pinned"
fi
"$HOME/.local/libexec/plasma-fusion/plasma-fusion-app-pair" remove "$early" >>"$OUT/helper.log" 2>&1 || info "remove rc=$?"
sleep 3

# ---- 1. Dolphin left, KWrite right, the split at a third
dolphin >/dev/null 2>&1 &
sleep 4
kwrite >/dev/null 2>&1 &
sleep 4
tile Left dolphin
tile Right kwrite
shortcut "Plasma Fusion: Split One Third"
sleep 1.5
info "1: $(where)"
if side_by_side dolphin kwrite 0.3333; then pass "1: Dolphin left at a third, KWrite right (the tablet script's Split One Third)"; else fail "1: $(where)"; fi

# ---- 2. the app switcher: the pair's card and Save pair
shortcut "Plasma Fusion App Switcher"
sleep 2
shot ap-2-switcher
button=$(logged 'Save pair for' "$KLOG")
if [[ $button == *"Save pair for org.kde.dolphin.desktop | org.kde.kwrite.desktop at "* ]]; then
  pass "2: Save pair under the pair's card, Dolphin first: ${button##*: }"
else
  fail "2: no Save pair for Dolphin | KWrite: '$button'"
fi
read -r bx by <<<"$(at_of "$button")"
if [ -n "${bx:-}" ]; then
  tap "$bx" "$by" 'sleep 0.3'
  sleep 3
  shot ap-2-saved
fi
pair=$(find "$APPS" -maxdepth 1 -name 'org.plasmafusion.pair-*.desktop' 2>/dev/null | head -n 1)
if [ -n "$pair" ] && [ "$(key "$pair" X-PlasmaFusion-PairLeft)" = org.kde.dolphin.desktop ] &&
  [ "$(key "$pair" X-PlasmaFusion-PairRight)" = org.kde.kwrite.desktop ] &&
  [ "$(key "$pair" X-PlasmaFusion-PairShare)" = 0.3333 ]; then
  pass "2: the pair saved: Dolphin left, KWrite right, a third (${pair##*/})"
else
  fail "2: no pair entry as expected: '${pair:-none}' $(cat "$pair" 2>/dev/null | tr '\n' ' ')"
fi
id=${pair##*/}
sleep 2
if grep -aq "home: pair: pin applications:$id" "$PLOG"; then pass "2: the home screen pinned it"; else fail "2: the home screen did not pin applications:$id"; fi
shortcut "Plasma Fusion App Switcher"
sleep 1.5

# ---- 3. the pair on the home screen, and a tap
reset_then_away 3
shot ap-3-home
tilelog=$(logged "home: pair tile: $id at " "$PLOG")
if [ -n "$tilelog" ]; then pass "3: the pair's tile on the home screen: ${tilelog##*: }"; else fail "3: no tile for $id"; fi
read -r tx ty <<<"$(at_of "$tilelog")"
before=$(grep -ac 'dock: pair:' "$PLOG" || true)
if [ -n "${tx:-}" ]; then
  tap "$tx" "$ty" 'sleep 0.3'
  sleep 7
fi
shot ap-3-opened
info "3: $(where)"
if [ "$(grep -ac 'dock: pair:' "$PLOG" || true)" -gt "$before" ] && side_by_side dolphin kwrite 0.3333; then
  pass "3: the tap opened Dolphin on the left and KWrite on the right, at a third: $(logged 'dock: pair:' "$PLOG" | sed 's/.*dock: pair: //')"
else
  fail "3: after the tap: $(where); $(logged 'dock: pair:' "$PLOG")"
fi

# ---- 4. sides swapped
"$HOME/.local/libexec/plasma-fusion/plasma-fusion-app-pair" swap "$id" >>"$OUT/helper.log" 2>&1 || info "swap rc=$?"
reset_then_away 4
sleep 1
tilelog=$(logged "home: pair tile: $id at " "$PLOG")
read -r tx ty <<<"$(at_of "$tilelog")"
if [ -n "${tx:-}" ]; then
  tap "$tx" "$ty" 'sleep 0.3'
  sleep 7
fi
shot ap-4-swapped
info "4: $(where)"
if side_by_side kwrite dolphin 0.3333; then pass "4: swapped: KWrite on the left, Dolphin on the right"; else fail "4: after the swap: $(where)"; fi

# ---- 5. a pair with an app that is not installed
gone=$("$HOME/.local/libexec/plasma-fusion/plasma-fusion-app-pair" save org.plasmafusion.not-installed.desktop org.kde.dolphin.desktop 0.5 2>>"$OUT/helper.log" || true)
K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow) { l[i].minimized = true; } } report(1);" >/dev/null
sleep 4
shot ap-5-gone
tilelog=$(logged "home: pair tile: $gone at " "$PLOG")
if [ -n "$gone" ] && [ -n "$tilelog" ]; then pass "5: the pair with a missing app is shown: ${tilelog##*: }"; else fail "5: no tile for '$gone'"; fi
read -r tx ty <<<"$(at_of "$tilelog")"
before=$(grep -ac 'dock: pair:' "$PLOG" || true)
if [ -n "${tx:-}" ]; then
  tap "$tx" "$ty" 'sleep 0.3'
  sleep 3
  shot ap-5-tapped
fi
if [ "$(grep -ac 'dock: pair:' "$PLOG" || true)" = "$before" ]; then pass "5: a tap opens nothing"; else fail "5: it asked the dock: $(logged 'dock: pair:' "$PLOG")"; fi

errs=$( { grep -aE 'HomeLayer.qml|HomeActionMenu.qml|FusionPairTile.qml|pairs\.js|org\.plasmafusion\.dock' "$PLOG" || true; } | grep -aiE 'error|TypeError|ReferenceError|is not defined|Cannot' || true)
if [ -z "$errs" ]; then pass "no QML errors from the home screen, its pairs or the dock"; else fail "QML: $(echo "$errs" | head -3 | tr '\n' ' ')"; fi
errs=$( { grep -aE 'plasmafusion_navigation|Task.qml' "$KLOG" || true; } | grep -aiE 'error|TypeError|ReferenceError|is not defined|Cannot' || true)
if [ -z "$errs" ]; then pass "no QML errors from the app switcher"; else fail "switcher: $(echo "$errs" | head -3 | tr '\n' ' ')"; fi
info "done"
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
