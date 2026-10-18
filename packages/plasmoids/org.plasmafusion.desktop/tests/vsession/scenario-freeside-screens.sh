#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# The free side with a dock on every screen (docs/parts/desktop.md "The free side beside an app"),
# in a private session with two outputs in tablet posture: KWrite quick-tiled left on the first
# screen, one tap on Konsole in the free part, and Konsole starts once (the home screen's split
# request reaches the dock of its own screen only; every dock used to start the app).
# Run: PFV_OUTPUTS=2 tools/vsession/remote.sh fss-1 packages/plasmoids/org.plasmafusion.desktop/tests/vsession/scenario-freeside-screens.sh SEED 1440x900 420
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
last_free() { grep -a 'home: free side:' "$PLOG" | tail -n 1 | sed 's/.*home: free side: //' || true; }
# A tap 0.6 s after pfinput's start (see scenario-freeside.sh: the seat's touch appears with
# pfinput's device, and a down sent before plasmashell binds wl_touch is lost).
tap() { pfinput 'sleep 0.6' "tap $1 $2 0.15"; }

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || info "fusion-config rc=$?"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-snap --key Gap 6
kwriteconfig6 --file kwinrc --group Script-plasmafusion-tablet --key InternalOutputs "eDP,LVDS,DSI,Virtual"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion 99
kwriteconfig6 --file plasmafusionrc --group Dock --key EveryScreen true
bash "$HOME/pf-tools/device/fusion-config.sh" --screens >"$OUT/screens.log" 2>&1 || info "fusion-config --screens rc=$?"
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
docks=$(evaljs - <<'JS'
var s = []; panels().forEach(function (p) { if (p.widgets("org.plasmafusion.dock").length > 0) { s.push(p.screen); } }); print(s.join(","));
JS
)
info "docks on screens: $docks"
case "$docks" in *0*1* | *1*0*) pass "a dock on each of the two screens" ;; *) fail "docks on screens '$docks' (want 0 and 1)" ;; esac
pfv_tablet on; sleep 8

kwrite >/dev/null 2>&1 &
sleep 5
K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('kwrite') >= 0) { workspace.activeWindow = l[i]; } } report(1);" >/dev/null
sleep 0.6
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Window Quick Tile Left"
sleep 2
K windows >"$OUT/windows-1.json"
for _ in $(seq 1 30); do case "$(last_free)" in right*kwrite*) break ;; esac; sleep 0.2; done
case "$(last_free)" in right*kwrite*) pass "KWrite on the left: $(last_free)" ;; *) fail "no free side beside KWrite: '$(last_free)'" ;; esac
shot fss-1

# The free part's corner on the screen KWrite is on (the home screen logs it in that screen's work
# area), and the second home tile's centre there: Konsole in this session's pins (Dolphin, Konsole).
read -r TX TY <<<"$(python3 - "$OUT/windows-1.json" "$(last_free)" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
kw = [w for w in d["windows"] if "kwrite" in w["cls"] and w["normal"]][-1]
out = [o for o in d["outputs"] if o["name"] == kw["output"]][0]
m = re.search(r"from x (\d+)", sys.argv[2])
fx = int(m.group(1)) if m else 0
print(out["work"]["x"] + fx + 40 + 64 + 128, out["work"]["y"] + 141)
PY
)"
info "tap on the second home tile at $TX,$TY"
before=$(grep -ac 'dock: split: ' "$PLOG" || true)
tap "$TX" "$TY"
sleep 8
K windows >"$OUT/windows-2.json"
shot fss-2
splits=$(( $(grep -ac 'dock: split: ' "$PLOG" || true) - before ))
python3 - "$OUT/windows-2.json" "$splits" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); splits = int(sys.argv[2])
kon = [w for w in d["windows"] if "konsole" in w["cls"] and w["normal"]]
print(("PASS" if len(kon) == 1 and splits == 1 else "FAIL")
      + f" one tap, one Konsole: {len(kon)} Konsole windows {[(w['output'], w['geo']) for w in kon]}, {splits} docks acted on the request")
PY
grep -a 'home: split request\|dock: split' "$PLOG" >"$OUT/splits.log" || true
errs=$(grep -a -E '(HomeLayer|FreeSidePicker)\.qml|home\.js' "$PLOG" || true)
if [ -z "$errs" ]; then pass "no QML messages about HomeLayer.qml, FreeSidePicker.qml or home.js"; else fail "QML messages: $(echo "$errs" | head -5 | tr '\n' ' ')"; fi
info "done"
