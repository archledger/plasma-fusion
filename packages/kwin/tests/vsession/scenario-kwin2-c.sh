# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# KWIN-2 private-session scenario C (test tooling; ADAPTIVE M13, GAPS G13): Plasma Fusion Light at
# 1920x1080 @1: the switcher's neutral dark dim, the flyout and the fill picker in Light.
exec 2>&1
export OUT
set -x
CHK=$OUT/checks.txt
KLOG=$OUT/kwin.log
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
place() {
  K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { var w = l[i];
    if (w.normalWindow && String(w.resourceClass).indexOf('$1') >= 0) {
      if (w.tile) { w.tile.unmanage(w); } w.setMaximize(false, false);
      w.frameGeometry = {x: $2, y: $3, width: $4, height: $5}; workspace.activeWindow = w; } }
    report('placed $1');" >>"$OUT/place.log"
}
bash "$HOME/pf-tools/device/fusion-config.sh" --light --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1
info "fusion-config --light rc=$?"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
dolphin >/dev/null 2>&1 &
sleep 4
kwrite >/dev/null 2>&1 &
sleep 4
place dolphin 900 380 820 520; place kwrite 420 160 860 560
pfinput 'move 960 1000'
sleep 1
shot light-0
pfinput 'keydown alt' 'key tab' 'sleep 3.0' 'keyup alt' &
p=$!
sleep 1.4; shot light-sw; wait $p; sleep 1
pfinput 'key meta+z'; sleep 1.6
shot light-fly
pfinput 'key return'; sleep 1.8
shot light-pick
pfinput 'key esc'; sleep 1
grep -aE 'plasmafusion-snap|org\.plasmafusion\.switcher' "$KLOG" | grep -aiE 'error|TypeError|ReferenceError|Unable to assign|is not defined' | head -10 >"$OUT/warnings.txt"
info "warnings: $(wc -l <"$OUT/warnings.txt")"
[ "$(grep -ac 'KCrash: Application' "$KLOG")" = 0 ] && pass "KWin did not crash" || fail "KWin crashed"
echo "scenario done" >>"$CHK"
