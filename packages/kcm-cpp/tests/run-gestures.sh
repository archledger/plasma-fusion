#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver (tests/CMakeLists.txt, test kcmctl-gestures): the settings module's touchpad
# gestures and "Keep desktops in one row", in scratch HOMEs on a private D-Bus session without
# service activation (session-bus.conf), with a stand-in KWin (packages/powerfx/tests/
# mock-session.py --kwin-config: its reconfigure and its desktops' rows, each logged):
#   - the defaults (the owner's, 2026-10-16; the desktops in one row, as the setup puts them) and
#     what kwinrc [Script-plasmafusion-snap] says;
#   - Apply writes a changed gesture's key with the name the snap script reads (each of the nine
#     names: its contents/ui/Gestures.js ACTIONS), the others not, and reconfigures KWin;
#   - values out of range are not taken;
#   - the notes: KWin also uses three fingers sideways with more than one column of desktops, up
#     and down with more than one row, as the page has them, also for a desktop added while the
#     page is open (KWin's countChanged; it writes kwinrc without a change notification);
#   - desktops in one row: KWin's rows over D-Bus and kwinrc [Desktops] Rows, the rows before kept
#     and given back when it goes off.
#   - the snap script on as KWin 6.7.5 loads it (kwinrc [Plugins] plasmafusion-snapEnabled as a
#     QVariant converts it, off when missing as its metadata.json has it), also turned on while
#     the page is open (a write with a change notification).
# Needs node and python3 with GObject introspection (mock-session.py).
#
#   run-gestures.sh KCMCTL PLUGIN_DIR WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kcmctl=$1 plugins=$2 work=$3
powerfx=$here/../../powerfx
for t in node python3 busctl kreadconfig6 kwriteconfig6 dbus-run-session; do
  command -v "$t" >/dev/null || { echo "FAIL: run-gestures.sh needs $t"; exit 1; }
done

rm -rf "$work"
mkdir -p "$work/home" "$work/data" "$work/cache" "$work/state" "$work/runtime" "$work/bin"
chmod 700 "$work/runtime"
work=$(cd "$work" && pwd)
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export HOME=$work/home XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache
export XDG_STATE_HOME=$work/state XDG_RUNTIME_DIR=$work/runtime XDG_DATA_DIRS=$work/nodata
export QT_PLUGIN_PATH=$plugins QT_QPA_PLATFORM=offscreen
for tool in systemctl plasma-apply-lookandfeel plasma-apply-colorscheme; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/programs.log"\n' "$tool" "$work" >"$work/bin/$tool"
  chmod +x "$work/bin/$tool"
done
export PATH=$work/bin:$PATH
echo '{"desktops": [{"id": 1, "widgets": []}], "panels": []}' >"$work/layout.json"
node -e '
const fs = require("fs"), vm = require("vm");
vm.runInThisContext(fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library$/m, ""));
console.log(ACTIONS.join(" "));
' "$here/../../kwin/scripts/plasmafusion-snap/contents/ui/Gestures.js" >"$work/actions.txt"
cp "$here/../../kwin/scripts/plasmafusion-snap/metadata.json" "$work/snap-metadata.json"

cat >"$work/inner.sh" <<'EOF2'
set -u
work=$1 kcmctl=$2 powerfx=$3
N=0 FAIL=0
check() { local d=$1; shift; N=$((N + 1)); if "$@"; then echo "ok $N $d"; else FAIL=$((FAIL + 1)); echo "not ok $N $d"; fi; }
# session NAME COMMAND...: the module runs the commands with the stand-in KWin; its output in
# $work/NAME.log, the stand-in's calls in $work/calls.log.
session() {
  local name=$1; shift
  : >"$work/calls.log"
  rm -f "$work/mock-session.out"
  python3 "$powerfx/tests/mock-session.py" --address "$DBUS_SESSION_BUS_ADDRESS" --layout "$work/layout.json" \
    --log "$work/calls.log" --node "$(command -v node)" --kwin-config >"$work/mock-session.out" 2>&1 &
  local mock=$!
  for _ in $(seq 300); do grep -q ready "$work/mock-session.out" 2>/dev/null && break; sleep 0.1; done
  check "the stand-in KWin started ($name)" grep -q ready "$work/mock-session.out"
  printf '%s\n' waitshell "$@" "wait 500" | timeout 120 "$kcmctl" >"$work/$name.log" 2>&1
  kill "$mock" 2>/dev/null; wait "$mock" 2>/dev/null
}
got() { sed -n "s/^kcmctl: $2=//p" "$work/$1.log" | tail -1; }
key() { kreadconfig6 --file "$1" --group "$2" --key "$3"; }
gets="get gestureSwipeUp,get gestureSwipeDown,get gestureSwipeLeft,get gestureSwipeRight,get gesturePinchIn,get gesturePinchOut"
values() { local n; for n in gestureSwipeUp gestureSwipeDown gestureSwipeLeft gestureSwipeRight gesturePinchIn gesturePinchOut; do printf '%s ' "$(got "$1" "$n")"; done; }

# ---- The defaults, and what kwinrc says.
export XDG_CONFIG_HOME=$work/config-a
mkdir -p "$XDG_CONFIG_HOME"
IFS=, read -r -a g <<<"$gets"
session defaults "${g[@]}" "get desktopsInOneRow"
check "defaults: up Overview, down Show desktop, sideways nothing, pinch in Launcher, out Show desktop" test "$(values defaults)" = "1 2 0 0 5 2 "
check "  desktops in one row off (KWin's two rows when kwinrc has none)" test "$(got defaults desktopsInOneRow)" = false
session pagedefaults defaults "get desktopsInOneRow" "get gestureSwipeUp" "get gesturePinchIn"
check "the page's Defaults: the desktops in one row, as the setup puts them" test \
  "$(got pagedefaults desktopsInOneRow) $(got pagedefaults gestureSwipeUp) $(got pagedefaults gesturePinchIn)" = "true 1 5"
printf '[Script-plasmafusion-snap]\nGestureSwipeUp3=Grid\nGestureSwipeLeft3=windows\nGesturePinchIn4=teleport\nGesturePinchOut4=\n' >"$XDG_CONFIG_HOME/kwinrc"
session read "${g[@]}"
check "kwinrc's names are read (case aside); an unknown or empty one is the default" test "$(values read)" = "3 2 4 0 5 2 "

# ---- Apply: a changed gesture's key, with the snap script's name; KWin reconfigured.
export XDG_CONFIG_HOME=$work/config-b
mkdir -p "$XDG_CONFIG_HOME"
read -r -a actions <"$work/actions.txt"
check "the snap script has nine actions" test "${#actions[@]}" = 9
for i in "${!actions[@]}"; do
  session "action$i" "set gesturePinchOut $i" save
  check "action $i is written as the snap script's '${actions[$i]}'" bash -c "
    if [ $i = 2 ]; then ! grep -q GesturePinchOut4 '$XDG_CONFIG_HOME/kwinrc' 2>/dev/null || [ \"\$(kreadconfig6 --file kwinrc --group Script-plasmafusion-snap --key GesturePinchOut4)\" = desktop ];
    else [ \"\$(kreadconfig6 --file kwinrc --group Script-plasmafusion-snap --key GesturePinchOut4)\" = '${actions[$i]}' ]; fi"
done
session change "set gestureSwipeRight 8" save
check "a changed gesture's key is written, the others are not" bash -c "
  [ \"\$(kreadconfig6 --file kwinrc --group Script-plasmafusion-snap --key GestureSwipeRight3)\" = snaplayouts ] &&
  [ -z \"\$(kreadconfig6 --file kwinrc --group Script-plasmafusion-snap --key GestureSwipeUp3)\" ]"
check "  and KWin is reconfigured (the snap script reads its keys from KWin's copy)" grep -q 'kwin reconfigure' "$work/calls.log"
session range "set gestureSwipeUp 9" "set gestureSwipeUp -1" "get gestureSwipeUp"
check "values out of range are not taken" test "$(got range gestureSwipeUp)" = 1

# ---- The notes, and desktops in one row.
export XDG_CONFIG_HOME=$work/config-c
mkdir -p "$XDG_CONFIG_HOME"
printf '[Desktops]\nNumber=1\nRows=2\n' >"$XDG_CONFIG_HOME/kwinrc"
session one "get gestureSidewaysShared" "get gestureUpDownShared" "get desktopsInOneRow"
check "one desktop: KWin uses neither three-finger pair" test "$(got one gestureSidewaysShared) $(got one gestureUpDownShared)" = "false false"
printf '[Desktops]\nNumber=1\nRows=1\n' >"$XDG_CONFIG_HOME/kwinrc"
session added "get gestureSidewaysShared" \
  "sh busctl --user call org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager createDesktop us 1 Two" \
  "wait 1000" "get gestureSidewaysShared"
check "a desktop added while the page is open: the sideways note comes" test \
  "$(sed -n 's/^kcmctl: gestureSidewaysShared=//p' "$work/added.log" | tr '\n' ' ')" = "false true "
printf '[Desktops]\nNumber=2\nRows=2\n' >"$XDG_CONFIG_HOME/kwinrc"
session tworows "get gestureSidewaysShared" "get gestureUpDownShared"
check "two desktops in KWin's two rows: up and down are KWin's too" test "$(got tworows gestureSidewaysShared) $(got tworows gestureUpDownShared)" = "false true"
printf '[Desktops]\nNumber=4\nRows=2\n' >"$XDG_CONFIG_HOME/kwinrc"
session grid "get gestureSidewaysShared" "get gestureUpDownShared" "set desktopsInOneRow true" "get gestureSidewaysShared" "get gestureUpDownShared"
check "four desktops in two rows: both pairs KWin's too; in one row (not applied yet) only sideways" test \
  "$(sed -n 's/^kcmctl: gesture\(Sideways\|UpDown\)Shared=//p' "$work/grid.log" | tr '\n' ' ')" = "true true true false "
session onerow "set desktopsInOneRow true" save
check "desktops in one row: KWin's rows over D-Bus and kwinrc, the rows before kept" bash -c "
  grep -q 'kwin rows 1' '$work/calls.log' && [ \"\$(kreadconfig6 --file kwinrc --group Desktops --key Rows)\" = 1 ] &&
  [ \"\$(kreadconfig6 --file plasmafusionrc --group Gestures --key PreviousRows)\" = 2 ]"
session onerowread "get desktopsInOneRow" "get gestureUpDownShared"
check "  read back on, up and down no longer KWin's" test "$(got onerowread desktopsInOneRow) $(got onerowread gestureUpDownShared)" = "true false"
kwriteconfig6 --file kwinrc --group Desktops --key Rows 1
kwriteconfig6 --file plasmafusionrc --group Gestures --key PreviousRows 3
session rowsback "set desktopsInOneRow false" save
check "off: the rows the user had come back (3), the kept number goes" bash -c "
  grep -q 'kwin rows 3' '$work/calls.log' && [ \"\$(kreadconfig6 --file kwinrc --group Desktops --key Rows)\" = 3 ] &&
  [ -z \"\$(kreadconfig6 --file plasmafusionrc --group Gestures --key PreviousRows)\" ]"

# ---- The snap script, which does the gestures: on as KWin loads it.
export XDG_CONFIG_HOME=$work/config-d
mkdir -p "$XDG_CONFIG_HOME"
session nosnap "get snapScriptOn"
check "the snap script off while kwinrc does not turn it on (its EnabledByDefault)" test "$(got nosnap snapScriptOn)" = false
check "  the snap script's metadata.json has it off by default" python3 -c '
import json, sys
sys.exit(json.load(open(sys.argv[1]))["KPlugin"]["EnabledByDefault"] is not False)' "$work/snap-metadata.json"
snap=
for value in true 1 off false 0 ''; do
  printf '[Plugins]\nplasmafusion-snapEnabled=%s\n' "$value" >"$XDG_CONFIG_HOME/kwinrc"
  session "snap$value" "get snapScriptOn"
  snap+="$(got "snap$value" snapScriptOn) "
done
check "  kwinrc's entry read as KWin reads it: true, 1 and off load the script, false, 0 and empty do not" \
  test "$snap" = "true true true false false false "
printf '[Plugins]\nplasmafusion-snapEnabled=false\n' >"$XDG_CONFIG_HOME/kwinrc"
session snapon "get snapScriptOn" \
  "sh kwriteconfig6 --file kwinrc --group Plugins --key plasmafusion-snapEnabled --notify true" \
  "wait 1000" "get snapScriptOn"
check "  turned on while the page is open (a change notification): the note goes" test \
  "$(sed -n 's/^kcmctl: snapScriptOn=//p' "$work/snapon.log" | tr '\n' ' ')" = "false true "

echo "$((N - FAIL)) of $N passed"
[ "$FAIL" = 0 ]
EOF2

status=0
dbus-run-session --config-file="$here/session-bus.conf" -- bash "$work/inner.sh" "$work" "$kcmctl" "$powerfx" || status=$?
if [ "$status" != 0 ]; then
  for f in "$work"/*.log; do echo "--- $f"; cat "$f"; done
  echo "FAIL: kcmctl-gestures"
  exit 1
fi
echo "PASS: kcmctl-gestures"
