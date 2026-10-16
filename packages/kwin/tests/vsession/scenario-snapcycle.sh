#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Snap sizes from the keyboard (plasmafusion-snap, Cycle.js) in a private session, with real keys
# (pfinput): the Fusion setup moves Meta+Left/Right to the script's "Snap Left/Right", then
#   1. Meta+Left steps a window through the left half, third and two thirds, then the half again
#      (one screen: no screen to move to);
#   2. Meta+Right from the left half: the right half, then the right third;
#   3. the half is KWin's quick tile (tiled), the thirds plain geometry.
# The thirds show that Meta+Left/Right reach the script: KWin's own quick tile gives no third.
# Run: tools/vsession/remote.sh sc-1 packages/kwin/tests/vsession/scenario-snapcycle.sh SEED 1440x900 300
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }

# The active window's place and the work area: "X Y W H TILED AX AY AW AH".
where() {
  K run "var c = workspace.activeWindow, g = c ? c.frameGeometry : null;
    var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
    report(g ? [g.x, g.y, g.width, g.height, c.tile ? 1 : 0, a.x, a.y, a.width, a.height].join(' ') : '');"
}
# CHECK LABEL SIDE SHARE TILED: the active window touches SIDE, spans the area's height and is SHARE
# of its width (within 3 %, a terminal sizes itself in character cells), tiled or not as asked.
check() {
  local label=$1 side=$2 share=$3 tiled=$4 w
  # (pfkwin.py reports the text as a JSON string: without its quotes.)
  w=$(where | tr -d '"')
  info "$label: $w"
  if python3 - "$w" "$side" "$share" "$tiled" <<'PY'
import sys
x, y, w, h, t, ax, ay, aw, ah = (float(v) for v in sys.argv[1].split())
side, share, tiled = sys.argv[2], eval(sys.argv[3]), sys.argv[4] == "1"
edge = abs(x - ax) if side == "left" else abs(x + w - (ax + aw))
sys.exit(0 if edge <= 8 and h >= ah * 0.9 and abs(w / aw - share) <= 0.03 and (t == 1) == tiled else 1)
PY
  then pass "$label"; else fail "$label ($w)"; fi
}
press() { pfinput "key $1"; sleep 1.2; }

# ---- the Fusion setup (the Windows-style set moves the keys) and one window
fc_rc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc_rc=$?
info "fusion-config rc=$fc_rc"
grep -a "Snap Left\|Snap Right\|snap sizes" "$OUT/fc.log" | sed 's/^/INFO setup: /' >>"$CHK" || true
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap)
if [ "$loaded" = true ]; then pass "the snap script is loaded"; else fail "the snap script is not loaded ($loaded)"; fi
pfinput 'move 1400 520'
kwrite >/dev/null 2>&1 &
sleep 4
K run "var c = workspace.activeWindow; if (c) { if (c.tile) { c.tile.unmanage(c); } c.frameGeometry = {x: 300, y: 200, width: 700, height: 500}; } report(!!c);" >/dev/null
sleep 1

# ---- 1. Meta+Left four times
press meta+left
check "1: Meta+Left: the left half, KWin's quick tile" left 1/2 1
shot 10-half
press meta+left
check "1: again: the left third (plain geometry)" left 1/3 0
shot 11-third
press meta+left
check "1: again: the left two thirds" left 2/3 0
shot 12-two-thirds
press meta+left
check "1: again, one screen: back to the left half" left 1/2 1

# ---- 2. Meta+Right
press meta+right
check "2: Meta+Right: the right half" right 1/2 1
press meta+right
check "2: again: the right third" right 1/3 0
shot 20-right-third
info "done"
# A failed check fails the scenario (scenario rc), as the other KWin scenarios do: without the trap
# and errexit, so the last test sets the status vsession.sh records instead of ending its shell.
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
