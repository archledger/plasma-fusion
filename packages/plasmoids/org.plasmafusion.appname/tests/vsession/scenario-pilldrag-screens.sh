#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# The window pill's drag with two screens in tablet posture (docs/parts/shell-topbar.md "The
# pill's drag"): a top bar on each screen shows the active window, which is on the first. Held and
# dragged on the second screen's bar, the pill does nothing (its overlay would show the second
# screen's halves while the window is on the first); on the first screen's bar the same drag puts
# KWrite in the left half.
# Run: PFV_OUTPUTS=2 tools/vsession/remote.sh pds-1 packages/plasmoids/org.plasmafusion.appname/tests/vsession/scenario-pilldrag-screens.sh SEED 1440x900 420
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
# Touch 0.6 s after pfinput starts (see scenario-pilldrag.sh).
touch_() { pfinput 'sleep 0.6' "$@"; }
kw_state() {
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('kwrite') >= 0) { w = l[i]; } }
    var g = w ? w.frameGeometry : null;
    report(w ? [Math.round(g.x), Math.round(g.width), !!w.tile, String(w.output.name)].join(' ') : 'none');" | python3 -c 'import json,sys; print(json.load(sys.stdin))'
}
pills() { grep -ac 'appname: pill ' "$PLOG" || true; }

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || info "fusion-config rc=$?"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-snap --key Gap 6
kwriteconfig6 --file kwinrc --group Script-plasmafusion-tablet --key InternalOutputs "eDP,LVDS,DSI,Virtual"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion 99
kwriteconfig6 --file plasmafusionrc --group TopBar --key EveryScreen true
bash "$HOME/pf-tools/device/fusion-config.sh" --screens >"$OUT/screens.log" 2>&1 || info "fusion-config --screens rc=$?"
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
bars=$(evaljs - <<'JS'
var s = []; panels().forEach(function (p) { if (p.widgets("org.plasmafusion.appname").length > 0) { s.push(p.screen); } }); print(s.join(","));
JS
)
info "app name pills on screens: $bars"
case "$bars" in *0*1* | *1*0*) pass "a top bar with the app's pill on each screen" ;; *) fail "pills on screens '$bars' (want 0 and 1)" ;; esac
pfv_tablet on; sleep 8
kwrite >/dev/null 2>&1 &
sleep 5
K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { var w = l[i]; if (w.normalWindow && String(w.resourceClass).indexOf('kwrite') >= 0) { workspace.sendClientToScreen(w, workspace.screens[0]); workspace.activeWindow = w; } } report(1);" >/dev/null
sleep 1.5
K windows >"$OUT/windows-0.json"
read -r OX <<<"$(python3 - "$OUT/windows-0.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
outs = sorted(d["outputs"], key=lambda o: o["geo"]["x"])
print(outs[1]["geo"]["x"] if len(outs) > 1 else 1440)
PY
)"
before=$(kw_state)
info "KWrite $before; the second screen from x $OX"

# ---- 1. held and dragged on the second screen's bar: nothing
n=$(pills)
touch_ "hdrag $((OX + 60)) 22 $((OX + 250)) 660 0.45 0.3"
sleep 2.5
after=$(kw_state)
if [ "$(grep -a 'appname: pill drag starts' "$PLOG" | wc -l)" = 0 ] && [ "$before" = "$after" ]; then
  pass "1: the second screen's pill does not drag the first screen's window: KWrite $after"
else
  fail "1: the second screen's pill acted: $(grep -a 'appname: pill ' "$PLOG" | tail -n 2 | tr '\n' ' '); KWrite $before -> $after"
fi
shot pds-1
# (held without the lift there, the drag was the pull-down: the window card opened on the second
# screen and took the focus; closed, and KWrite active again)
pfinput 'key escape'; sleep 1
K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { var w = l[i]; if (w.normalWindow && String(w.resourceClass).indexOf('kwrite') >= 0) { workspace.activeWindow = w; } } report(1);" >/dev/null
sleep 1.5

# ---- 2. the same drag on the first screen's bar: the left half
touch_ "hdrag 60 22 250 660 0.45 0.3"
sleep 2.5
s=$(kw_state); read -r x _ tiled _ <<<"$s"
if [ "$(pills)" -gt "$n" ] && [ "$x" -le 12 ] && [ "$tiled" = true ]; then
  pass "2: the first screen's pill puts KWrite in the left half: $s"
else
  fail "2: KWrite $s; $(grep -a 'appname: pill ' "$PLOG" | tail -n 2 | tr '\n' ' ')"
fi
shot pds-2
errs=$(grep -a -E '(main|WindowDropOverlay)\.qml|drop\.js' "$PLOG" | grep -a 'org.plasmafusion.appname' || true)
if [ -z "$errs" ]; then pass "no QML messages about the pill's files"; else fail "QML messages: $(echo "$errs" | head -5 | tr '\n' ' ')"; fi
info "done"
