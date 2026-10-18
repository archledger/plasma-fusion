#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# The window pill's drag in tablet posture (board TabletSnap.dc.html, docs/parts/shell-topbar.md
# "The pill's drag") in a private session with real touch (pfinput): with KWrite full screen,
#   1. the pill held 0.45 s and dragged to the left third: KWrite takes the left half;
#   2. held and dragged to the middle third: KWrite is full screen again;
#   3. flicked sideways to the right (no hold): KWrite takes the right half;
#   4. moved sideways slowly: nothing;
#   5. held and dragged back into the top bar: nothing;
#   6. pulled down 60 px without the hold: the window card opens, as before;
#   7. held and dragged to the bottom: KWrite is minimized (home);
# and no QML messages about the pill's files.
# Run: tools/vsession/remote.sh pd-1 packages/plasmoids/org.plasmafusion.appname/tests/vsession/scenario-pilldrag.sh SEED 1440x900 420
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
# Touch 0.6 s after pfinput starts (see the free side scenario: the seat's touch appears with
# pfinput's device, and a down sent before plasmashell binds wl_touch is lost).
touch_() { pfinput 'sleep 0.6' "$@"; }
# KWrite's frame and state, as "x w maximized minimized".
kw_state() {
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('kwrite') >= 0) { w = l[i]; } }
    var g = w ? w.frameGeometry : null;
    report(w ? [Math.round(g.x), Math.round(g.width), g.width >= 1400, w.minimized].join(' ') : 'none');" | python3 -c 'import json,sys; print(json.load(sys.stdin))'
}
# The pill log lines so far.
pills() { grep -ac 'appname: pill ' "$PLOG" || true; }
last_pill() { grep -a 'appname: pill ' "$PLOG" | tail -n 1 | sed 's/.*appname: //' || true; }
# LABEL EXPECTED_LOG_SUBSTRING STATE_CHECK (a python expression over x, w, maxed, mini)
expect() {
  local s x w maxed mini
  sleep 2.5
  s=$(kw_state); read -r x w maxed mini <<<"$s"
  if [ -n "$2" ] && [[ "$(last_pill)" != *"$2"* ]]; then fail "$1: the last pill line is '$(last_pill)' (want '$2'); KWrite $s"; return 0; fi
  if python3 -c "x, w, maxed, mini = $x, $w, '$maxed' == 'true', '$mini' == 'true'; raise SystemExit(0 if ($3) else 1)"; then
    pass "$1: $(last_pill); KWrite x $x w $w maximized-wide $maxed minimized $mini"
  else
    fail "$1: $(last_pill); KWrite x $x w $w maximized-wide $maxed minimized $mini"
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
kwrite >/dev/null 2>&1 &
sleep 6
K windows >"$OUT/windows-0.json"
read -r PX PY <<<"$(python3 - "$OUT/windows-0.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
# The pill sits at the top bar's left end: aim at 60 px in, the bar's middle.
bar = [w for w in d["windows"] if w["cls"] == "plasmashell" and w["geo"]["y"] == 0 and w["geo"]["h"] < 60 and w["geo"]["w"] > 1000]
print(60, (bar[0]["geo"]["h"] // 2) if bar else 22)
PY
)"
info "the pill at $PX,$PY; KWrite $(kw_state)"
case "$(kw_state)" in *" true false") pass "0: KWrite opens full screen" ;; *) fail "0: KWrite is not full screen: $(kw_state)" ;; esac

# ---- 1. held and dragged to the left third
touch_ "hdrag $PX $PY 250 660 0.45 0.3"
shot pd-1
expect "1: dragged to the left" "drag to left" "x <= 12 and 600 <= w <= 760 and not mini"

# ---- 2. held and dragged to the middle third
touch_ "hdrag $PX $PY 720 450 0.45 0.3"
expect "2: dragged to the middle" "drag to full" "maxed and not mini"

# ---- 3. flicked sideways to the right, no hold
touch_ "swipe $PX $PY $((PX + 360)) $PY 0.1"
expect "3: flicked to the right" "flick to right" "x >= 700 and 600 <= w <= 760 and not mini"

# ---- 4. moved sideways slowly: nothing
n=$(pills)
touch_ "swipe $PX $PY $((PX + 120)) $PY 1.2"
sleep 2
if [ "$(pills)" = "$n" ]; then pass "4: a slow sideways move does nothing: KWrite $(kw_state)"; else fail "4: a slow move acted: $(last_pill)"; fi

# ---- 5. held and dragged back into the top bar: nothing
touch_ "hdrag $PX $PY 400 $PY 0.45 0.3"
expect "5: dragged within the top bar" "drag to nowhere" "x >= 700 and 600 <= w <= 760 and not mini"

# ---- 6. pulled down without the hold: the window card
n=$(grep -ac 'pull-down opens the window card' "$PLOG" || true)
touch_ "swipe $PX $PY $PX $((PY + 60)) 0.3"
sleep 1.5
shot pd-6
if [ "$(grep -ac 'pull-down opens the window card' "$PLOG" || true)" -gt "$n" ]; then pass "6: the pull-down still opens the window card"; else fail "6: no window card after the pull-down"; fi
pfinput 'key escape'; sleep 1

# ---- 7. held and dragged to the bottom: home
touch_ "hdrag $PX $PY 720 850 0.45 0.3"
expect "7: dragged to the bottom" "drag to home" "mini"

errs=$(grep -a -E '(main|WindowDropOverlay|WindowCard)\.qml|drop\.js' "$PLOG" | grep -a 'org.plasmafusion.appname' || true)
if [ -z "$errs" ]; then pass "no QML messages about the pill's files"; else fail "QML messages: $(echo "$errs" | head -5 | tr '\n' ' ')"; fi
grep -a 'appname: ' "$PLOG" >"$OUT/appname.log" || true
info "done"
