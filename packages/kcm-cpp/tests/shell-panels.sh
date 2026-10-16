#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver (tests/CMakeLists.txt, test kcmctl-panels): the module's panel changes against a
# stand-in Plasma shell (fakeshell/fakeshell.cpp with fakeshell/shell.js), in a scratch HOME on a
# private D-Bus session without service activation (session-bus.conf), as meters-switch.sh. Cases:
#   screenless  a top bar of a monitor that was unplugged is still in the layout, on its missing
#               screen (Plasma 6.8; reading its opacity crashes plasmashell, and the stand-in shell
#               too): the module reads the shell and changes the top bars' look without touching
#               it, and the bar on the screen gets the new opacity;
#   slowread    the shell answers every script 7 s late (just restarted): the page still reads it;
#   slowmeters  the shell answers late from the second script on: turning the system meters on
#               reports no error, the meters are placed, and the page's event loop keeps running
#               while it waits (a timer ticks during Apply, the page does not freeze);
#   slowbars    the same for "Top bar on every screen" (a stand-in ensure-topbars.js, then the
#               panels' look for the new bars);
#   launcher    the Launcher switches read from the launcher widget (one key already off, as a
#               string) and written to it, the keys it does not change left alone;
#   nolauncher  no launcher widget: the switches are not available and keep their value;
#   twolaunchers two launchers, the second with the Places chip off: the page shows it off, and
#               turning it on writes it to both;
#   mixedoff    the same two launchers: the page says they differ, the switch turned on and back
#               off is still a change to apply, and Apply writes off to both (they agree then);
#   mixedrestart the same, with the shell restarted between the switch and Apply: still a change,
#               and Apply still writes off to both;
#   docksoff    a dock on every screen turned off: the copy ensure-topbars.js made for the second
#               screen goes with its panel (its launcher too), a second dock of the user's stays,
#               and each dock left gets back the showOnlyCurrentScreen it had;
#   docksofffail the same while the shell fails the removal: an error, and the choice stays on;
#   docksoffcopies only copies left: the one on screen 0 stays as the one dock;
#   docksoffpanel a copy's panel whose dock the user removed goes too;
#   docksoffunplugged the one original on an unplugged screen: a copy on a screen that is there
#               stays as the dock, the unplugged one gets its value back;
#   docksnotmade ensure-topbars.js says it could not make a dock: an error;
#   dockson     turned on: the choice is kept and the stand-in ensure-topbars.js runs.
#
#   shell-panels.sh KCMCTL FAKESHELL PLUGIN_DIR WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kcmctl=$1 fakeshell=$2 plugins=$3 work=$4

rm -rf "$work"
mkdir -p "$work"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export QT_PLUGIN_PATH=$plugins QT_QPA_PLATFORM=offscreen
failures=0

APPNAME=org.plasmafusion.appname QS=org.plasmafusion.quicksettings CLOCK=org.plasmafusion.clockpill
TRAY=org.kde.plasma.systemtray DOCK=org.plasmafusion.dock METERS=org.plasmafusion.meters
LAUNCHER=org.plasmafusion.launcher

# run CASE LAYOUT COMMANDS...: one module session against the stand-in shell. Leaves the kcmctl
# output in $work/CASE/kcmctl.log, the shell's in $work/CASE/fakeshell.log and the panels in
# $work/CASE/panels.
run() {
  local name=$1 layout=$2
  shift 2
  local w=$work/$name
  mkdir -p "$w/home" "$w/config" "$w/data" "$w/cache" "$w/state" "$w/runtime"
  chmod 700 "$w/runtime"
  if declare -F "prepare_$name" >/dev/null; then
    "prepare_$name" "$w"
  fi
  printf '%s\n' "$layout" >"$w/layout.json"
  printf '%s\n' "$@" >"$w/commands"
  HOME=$w/home XDG_CONFIG_HOME=$w/config XDG_DATA_HOME=$w/data XDG_CACHE_HOME=$w/cache \
    XDG_STATE_HOME=$w/state XDG_RUNTIME_DIR=$w/runtime \
    dbus-run-session --config-file="$here/session-bus.conf" -- bash -c '
      "$1" "$2" "$3" "$4" >"$5/fakeshell.log" 2>&1 &
      shell=$!
      for _ in $(seq 1 100); do grep -q "fakeshell: ready" "$5/fakeshell.log" && break; sleep 0.05; done
      # For a case that restarts the stand-in shell (a kcmctl sh command).
      export PFV_FAKESHELL=$1 PFV_SHELLJS=$2 PFV_FAKESHELL_PID=$shell
      sed "s|@W@|$5|g" "$5/commands" | "$6" >"$5/kcmctl.log" 2>&1
      status=$?
      kill "$shell" 2>/dev/null || true
      exit "$status"' _ "$fakeshell" "$here/fakeshell/shell.js" "$w/layout.json" "$w/panels" "$w" "$kcmctl" \
    || { echo "FAIL $name: kcmctl exited with $?"; cat "$w/kcmctl.log"; failures=$((failures + 1)); }
}

# expect CASE DESCRIPTION CONDITION...: CONDITION is a command; prints PASS or FAIL.
expect() {
  local name=$1 what=$2
  shift 2
  if "$@"; then
    echo "PASS $name: $what"
  else
    echo "FAIL $name: $what"
    echo "--- panels:"; cat "$work/$name/panels" || true
    echo "--- fakeshell:"; cat "$work/$name/fakeshell.log" || true
    echo "--- kcmctl:"; grep '^kcmctl: [a-zA-Z]*=' "$work/$name/kcmctl.log" || true
    failures=$((failures + 1))
  fi
}
value() { sed -n "s/^kcmctl: $2=//p" "$work/$1/kcmctl.log" | tail -1; }
first() { sed -n "s/^kcmctl: $2=//p" "$work/$1/kcmctl.log" | head -1; }
panel() { sed -n "$2p" "$work/$1/panels"; }
is() { [ "$1" = "$2" ]; }
alive() { ! grep -q "crashed" "$work/$1/fakeshell.log"; }
# Timer ticks counted by kcmctl's heartbeat (the Nth "beats" line) and the milliseconds Apply took.
beats() { sed -n 's/^kcmctl: beats=//p' "$work/$1/kcmctl.log" | sed -n "$2p"; }
busy() { local t; mapfile -t t <"$work/$1/times"; echo $((t[1] - t[0])); }
SAVE=("sh date +%s%3N >>@W@/times" "beats" save "beats" "sh date +%s%3N >>@W@/times")

run screenless "{\"screens\": 1, \"showOpacity\": true, \"panels\": [
  {\"opacity\": \"translucent\", \"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"opacity\": \"translucent\", \"widgets\": [\"$DOCK\"]},
  {\"screen\": 1, \"opacity\": \"opaque\", \"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$QS\"]}]}" \
  waitshell "get topBarAvailable" "get solidTopBar" "set solidTopBar true" save "wait 500" "get errorText"
expect screenless "the shell did not crash" alive screenless
expect screenless "the module read the top bar" is "$(value screenless topBarAvailable)" true
expect screenless "the top bar's opacity was read (translucent: not solid next to windows)" \
  is "$(sed -n 's/^kcmctl: solidTopBar=//p' "$work/screenless/kcmctl.log" | head -1)" false
expect screenless "the bar on the screen is adaptive now" is "$(panel screenless 1)" "top 0 adaptive: appname clockpill systemtray quicksettings"
expect screenless "the bar without a screen keeps its opacity" is "$(panel screenless 3)" "top 1 opaque: appname clockpill quicksettings"
expect screenless "no error" is "$(value screenless errorText)" ""

run slowread "{\"scriptDelayMs\": 7000, \"panels\": [{\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]}]}" \
  waitshell "get shellRunning" "get topBarAvailable"
expect slowread "the page read the shell that answered 7 s late" is "$(value slowread topBarAvailable)" true

run slowmeters "{\"scriptDelayMs\": 7000, \"slowFrom\": 2, \"insert\": \"end\", \"knownWidgetTypes\": [\"$METERS\"], \"panels\": [
  {\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]}]}" \
  waitshell "get systemMeters" "heartbeat 100" "set systemMeters true" "${SAVE[@]}" "wait 9000" "get errorText"
expect slowmeters "no error although the shell answered 7 s late" is "$(value slowmeters errorText)" ""
expect slowmeters "the meters are in the bar, before quick settings" \
  is "$(panel slowmeters 1)" "top 0: appname clockpill systemtray meters quicksettings"
expect slowmeters "the page's event loop ran while it waited ($(beats slowmeters 2) ticks of 100 ms in $(busy slowmeters) ms)" \
  test "$(beats slowmeters 2)" -ge 40

prepare_slowbars() {
  local dir=$1/data/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts
  mkdir -p "$dir"
  printf 'print("top bars: added 0, completed 0");\n' >"$dir/ensure-topbars.js"
  printf '[TopBar]\nEveryScreen=false\n' >"$1/config/plasmafusionrc"
}
run slowbars "{\"scriptDelayMs\": 7000, \"slowFrom\": 2, \"panels\": [{\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]}]}" \
  waitshell "get topBarScriptAvailable" "get everyScreen" "heartbeat 100" "set everyScreen true" "${SAVE[@]}" "get errorText"
expect slowbars "the stand-in ensure-topbars.js was found" is "$(value slowbars topBarScriptAvailable)" true
expect slowbars "no error although the shell answered 7 s late" is "$(value slowbars errorText)" ""
expect slowbars "the choice is kept" grep -q "EveryScreen=true" "$work/slowbars/config/plasmafusionrc"
expect slowbars "the page's event loop ran while it waited ($(beats slowbars 2) ticks of 100 ms in $(busy slowbars) ms)" \
  test "$(beats slowbars 2)" -ge 80

run launcher "{\"showConfig\": true, \"panels\": [
  {\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [{\"type\": \"$LAUNCHER\", \"config\": {\"General/showPlaces\": \"false\"}}, \"$DOCK\"]}]}" \
  waitshell "get launcherAvailable" "get launcherRecentFiles" "get launcherRecentApps" "get launcherPlaces" \
  "set launcherRecentFiles false" "set launcherPlaces true" save "wait 500" "get errorText"
expect launcher "the module found the launcher" is "$(value launcher launcherAvailable)" true
expect launcher "recent files and the Recent chip read as on (keys not set)" \
  is "$(first launcher launcherRecentFiles) $(first launcher launcherRecentApps)" "true true"
expect launcher "the Places chip read as off (the key written as the string false)" is "$(first launcher launcherPlaces)" false
expect launcher "recent files off and Places on written to the launcher, the Recent chip's key left alone" \
  is "$(panel launcher 2)" "bottom 0: launcher{General/showPlaces=true,General/showRecommended=false} dock"
expect launcher "no error" is "$(value launcher errorText)" ""

run nolauncher "{\"showConfig\": true, \"panels\": [{\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [\"$DOCK\"]}]}" \
  waitshell "get launcherAvailable" "set launcherRecentFiles false" save "wait 500" "get launcherRecentFiles" "get errorText"
expect nolauncher "no launcher widget: the switches are not available" is "$(value nolauncher launcherAvailable)" false
expect nolauncher "and keep their value" is "$(value nolauncher launcherRecentFiles)" true
expect nolauncher "nothing written to the panels" is "$(panel nolauncher 2)" "bottom 0: dock"

run twolaunchers "{\"showConfig\": true, \"panels\": [
  {\"widgets\": [\"$APPNAME\", {\"type\": \"$LAUNCHER\", \"config\": {\"General/showPlaces\": \"true\"}}, \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [{\"type\": \"$LAUNCHER\", \"config\": {\"General/showPlaces\": \"false\"}}, \"$DOCK\"]}]}" \
  waitshell "get launcherPlaces" "set launcherPlaces true" save "wait 500" "get errorText"
expect twolaunchers "two launchers that differ: the Places chip shows off" is "$(first twolaunchers launcherPlaces)" false
expect twolaunchers "turning it on writes it to the first launcher" \
  is "$(panel twolaunchers 1)" "top 0: appname launcher{General/showPlaces=true} clockpill systemtray quicksettings"
expect twolaunchers "and to the second" is "$(panel twolaunchers 2)" "bottom 0: launcher{General/showPlaces=true} dock"
expect twolaunchers "no error" is "$(value twolaunchers errorText)" ""

run mixedoff "{\"showConfig\": true, \"panels\": [
  {\"widgets\": [\"$APPNAME\", {\"type\": \"$LAUNCHER\", \"config\": {\"General/showPlaces\": \"true\"}}, \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [{\"type\": \"$LAUNCHER\", \"config\": {\"General/showPlaces\": \"false\"}}, \"$DOCK\"]}]}" \
  waitshell "get launcherPlacesMixed" "get launcherRecentAppsMixed" "set launcherPlaces true" "set launcherPlaces false" \
  "get needsSave" save "wait 500" "get launcherPlacesMixed" "get errorText"
expect mixedoff "two launchers that differ: the page says the Places chip is mixed" is "$(first mixedoff launcherPlacesMixed)" true
expect mixedoff "  and not the Recent chip, which they agree on" is "$(value mixedoff launcherRecentAppsMixed)" false
expect mixedoff "the switch on and back off is still a change to apply" is "$(value mixedoff needsSave)" true
expect mixedoff "Apply writes off to the first launcher" \
  is "$(panel mixedoff 1)" "top 0: appname launcher{General/showPlaces=false} clockpill systemtray quicksettings"
expect mixedoff "and to the second" is "$(panel mixedoff 2)" "bottom 0: launcher{General/showPlaces=false} dock"
expect mixedoff "after Apply they agree" is "$(value mixedoff launcherPlacesMixed)" false
expect mixedoff "no error" is "$(value mixedoff errorText)" ""

# The stand-in shell stopped and started again (its layout as it was) between the switch and Apply.
run mixedrestart "{\"showConfig\": true, \"panels\": [
  {\"widgets\": [\"$APPNAME\", {\"type\": \"$LAUNCHER\", \"config\": {\"General/showPlaces\": \"true\"}}, \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [{\"type\": \"$LAUNCHER\", \"config\": {\"General/showPlaces\": \"false\"}}, \"$DOCK\"]}]}" \
  waitshell "set launcherPlaces true" "set launcherPlaces false" \
  'sh kill "$PFV_FAKESHELL_PID"; sleep 0.5' "wait 500" "get shellRunning" \
  'sh "$PFV_FAKESHELL" "$PFV_SHELLJS" @W@/layout.json @W@/panels >@W@/fakeshell2.log 2>&1 & echo $! >@W@/fakeshell2.pid; for _ in $(seq 1 100); do grep -q "fakeshell: ready" @W@/fakeshell2.log && break; sleep 0.05; done' \
  "wait 4000" waitshell "get shellRunning" "get launcherPlacesMixed" "get needsSave" save "wait 500" "get errorText" \
  'sh kill "$(cat @W@/fakeshell2.pid)"'
expect mixedrestart "the shell went away" is "$(first mixedrestart shellRunning)" false
expect mixedrestart "and came back, the Places chip still mixed" is "$(value mixedrestart launcherPlacesMixed)" true
expect mixedrestart "the switch set before the restart is still a change to apply" is "$(value mixedrestart needsSave)" true
expect mixedrestart "Apply writes off to the first launcher" \
  is "$(panel mixedrestart 1)" "top 0: appname launcher{General/showPlaces=false} clockpill systemtray quicksettings"
expect mixedrestart "and to the second" is "$(panel mixedrestart 2)" "bottom 0: launcher{General/showPlaces=false} dock"
expect mixedrestart "no error" is "$(value mixedrestart errorText)" ""

prepare_docksoff() { printf '[Dock]\nEveryScreen=true\n' >"$1/config/plasmafusionrc"; }
# The main dock, a second dock of the user's on the same screen (on the left), and the copy
# ensure-topbars.js made for screen 1.
docks_on_layout() {
  printf '%s' "{\"showConfig\": true, \"screens\": 2$1, \"panels\": [
  {\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [\"$LAUNCHER\", {\"type\": \"$DOCK\", \"config\": {\"General/showOnlyCurrentScreen\": true, \"PlasmaFusion/onlyCurrentScreenBefore\": false}}]},
  {\"location\": \"left\", \"widgets\": [{\"type\": \"$DOCK\", \"config\": {\"General/showOnlyCurrentScreen\": true, \"PlasmaFusion/onlyCurrentScreenBefore\": true}}]},
  {\"location\": \"bottom\", \"screen\": 1, \"widgets\": [\"$LAUNCHER\", {\"type\": \"$DOCK\", \"config\": {\"General/showOnlyCurrentScreen\": true, \"PlasmaFusion/everyScreenCopy\": true}}]}]}"
}
run docksoff "$(docks_on_layout "")" waitshell "get everyDock" "set everyDock false" save "wait 500" "get errorText"
expect docksoff "the switch reads on (plasmafusionrc [Dock] EveryScreen)" is "$(first docksoff everyDock)" true
expect docksoff "the copy's panel is gone, the others stay" is "$(wc -l <"$work/docksoff/panels")" 3
expect docksoff "the main dock shows every screen's windows again, its remembered value emptied" \
  is "$(panel docksoff 2)" "bottom 0: launcher dock{General/showOnlyCurrentScreen=false,PlasmaFusion/onlyCurrentScreenBefore=}"
expect docksoff "the user's second dock stays, with what it had (its own screen only)" \
  is "$(panel docksoff 3)" "left 0: dock{General/showOnlyCurrentScreen=true,PlasmaFusion/onlyCurrentScreenBefore=}"
expect docksoff "the choice is kept" grep -q "EveryScreen=false" "$work/docksoff/config/plasmafusionrc"
expect docksoff "no error" is "$(value docksoff errorText)" ""

# The removal fails (the shell answers its script with an error): the choice stays on.
prepare_docksofffail() { prepare_docksoff "$@"; }
run docksofffail "$(docks_on_layout ', "failScripts": "everyScreenCopy"')" \
  waitshell "set everyDock false" save "wait 500" "get everyDock" "get errorText"
expect docksofffail "an error says so" bash -c "grep -q '^kcmctl: errorText=.*docks could not be changed' '$work/docksofffail/kcmctl.log'"
expect docksofffail "the choice stays on" grep -q "EveryScreen=true" "$work/docksofffail/config/plasmafusionrc"
expect docksofffail "  and the page shows it on" is "$(value docksofffail everyDock)" true
expect docksofffail "every dock panel is still there" is "$(wc -l <"$work/docksofffail/panels")" 4

# Only copies left (the user removed the dock there was): turned off, the one on screen 0 stays as
# the one dock, no longer a copy, listing every screen's windows.
prepare_docksoffcopies() { prepare_docksoff "$@"; }
run docksoffcopies "{\"showConfig\": true, \"screens\": 2, \"panels\": [
  {\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [\"$LAUNCHER\", {\"type\": \"$DOCK\", \"config\": {\"General/showOnlyCurrentScreen\": true, \"PlasmaFusion/everyScreenCopy\": true}}]},
  {\"location\": \"bottom\", \"screen\": 1, \"widgets\": [\"$LAUNCHER\", {\"type\": \"$DOCK\", \"config\": {\"General/showOnlyCurrentScreen\": true, \"PlasmaFusion/everyScreenCopy\": true}}]}]}" \
  waitshell "set everyDock false" save "wait 500" "get errorText"
expect docksoffcopies "one dock panel is left" is "$(wc -l <"$work/docksoffcopies/panels")" 2
expect docksoffcopies "the one on screen 0, no longer a copy, every screen's windows" \
  is "$(panel docksoffcopies 2)" "bottom 0{PlasmaFusion/everyScreenCopy=}: launcher dock{General/showOnlyCurrentScreen=false,PlasmaFusion/everyScreenCopy=}"
expect docksoffcopies "no error" is "$(value docksoffcopies errorText)" ""

# A copy's panel whose dock the user removed (its launcher left): it goes too when turned off.
prepare_docksoffpanel() { prepare_docksoff "$@"; }
run docksoffpanel "{\"showConfig\": true, \"screens\": 2, \"panels\": [
  {\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [\"$LAUNCHER\", {\"type\": \"$DOCK\", \"config\": {\"General/showOnlyCurrentScreen\": true, \"PlasmaFusion/onlyCurrentScreenBefore\": false}}]},
  {\"location\": \"bottom\", \"screen\": 1, \"config\": {\"PlasmaFusion/everyScreenCopy\": true}, \"widgets\": [\"$LAUNCHER\"]}]}" \
  waitshell "set everyDock false" save "wait 500" "get errorText"
expect docksoffpanel "the copy's panel without its dock is gone" is "$(wc -l <"$work/docksoffpanel/panels")" 2
expect docksoffpanel "no error" is "$(value docksoffpanel errorText)" ""

# The one dock the user had is on a monitor that is unplugged (screen 2 of 2, Plasma 6.8 keeps it):
# a copy on a screen that is there stays as the one dock, and the unplugged one is left alone.
prepare_docksoffunplugged() { prepare_docksoff "$@"; }
run docksoffunplugged "{\"showConfig\": true, \"screens\": 2, \"panels\": [
  {\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"screen\": 2, \"widgets\": [\"$LAUNCHER\", {\"type\": \"$DOCK\", \"config\": {\"General/showOnlyCurrentScreen\": true, \"PlasmaFusion/onlyCurrentScreenBefore\": false}}]},
  {\"location\": \"bottom\", \"screen\": 0, \"config\": {\"PlasmaFusion/everyScreenCopy\": true}, \"widgets\": [\"$LAUNCHER\", {\"type\": \"$DOCK\", \"config\": {\"General/showOnlyCurrentScreen\": true, \"PlasmaFusion/everyScreenCopy\": true}}]},
  {\"location\": \"bottom\", \"screen\": 1, \"config\": {\"PlasmaFusion/everyScreenCopy\": true}, \"widgets\": [\"$LAUNCHER\", {\"type\": \"$DOCK\", \"config\": {\"General/showOnlyCurrentScreen\": true, \"PlasmaFusion/everyScreenCopy\": true}}]}]}" \
  waitshell "set everyDock false" save "wait 500" "get errorText"
expect docksoffunplugged "the copy of screen 1 goes, the other two stay" is "$(wc -l <"$work/docksoffunplugged/panels")" 3
expect docksoffunplugged "the copy on screen 0 stays as the one dock, no longer a copy" \
  is "$(panel docksoffunplugged 3)" "bottom 0{PlasmaFusion/everyScreenCopy=}: launcher dock{General/showOnlyCurrentScreen=false,PlasmaFusion/everyScreenCopy=}"
expect docksoffunplugged "the dock of the unplugged screen gets its value back" \
  is "$(panel docksoffunplugged 2)" "bottom 2: launcher dock{General/showOnlyCurrentScreen=false,PlasmaFusion/onlyCurrentScreenBefore=}"
expect docksoffunplugged "no error" is "$(value docksoffunplugged errorText)" ""

# ensure-topbars.js runs but cannot make a dock ("not made 1"): an error says so.
prepare_docksnotmade() {
  local dir=$1/data/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts
  mkdir -p "$dir"
  printf 'print("top bars: screens 2, added 0, completed 0");\nprint("docks: screens 2, added 0, not made 1");\n' >"$dir/ensure-topbars.js"
}
run docksnotmade "{\"screens\": 2, \"panels\": [{\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [\"$LAUNCHER\", \"$DOCK\"]}]}" \
  waitshell "set everyDock true" save "wait 500" "get errorText"
expect docksnotmade "a dock not made is an error" bash -c "grep -q '^kcmctl: errorText=.*could not be made' '$work/docksnotmade/kcmctl.log'"

prepare_dockson() {
  local dir=$1/data/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts
  mkdir -p "$dir"
  # Its trace: one more dock widget in the dock panel.
  printf 'panels().forEach(function (p) { if (p.location === "bottom") p.addWidget("org.plasmafusion.dock"); });\nprint("docks: screens 2, added 1");\n' >"$dir/ensure-topbars.js"
}
run dockson "{\"screens\": 2, \"panels\": [{\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"location\": \"bottom\", \"widgets\": [\"$LAUNCHER\", \"$DOCK\"]}]}" \
  waitshell "get everyDock" "set everyDock true" save "wait 500" "get errorText"
expect dockson "off by default" is "$(first dockson everyDock)" false
expect dockson "turned on: the choice is kept" grep -q "EveryScreen=true" "$work/dockson/config/plasmafusionrc"
expect dockson "  ensure-topbars.js ran (it adds the docks)" is "$(panel dockson 2)" "bottom 0: launcher dock dock"
expect dockson "no error" is "$(value dockson errorText)" ""

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures failed"
  exit 1
fi
echo "PASS: the module's panel changes"
