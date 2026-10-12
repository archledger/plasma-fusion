#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver (tests/CMakeLists.txt, test kcmctl-meters): the "System meters in the top bar"
# switch against a stand-in Plasma shell (fakeshell/fakeshell.cpp with fakeshell/shell.js), in a
# scratch HOME on a private D-Bus session without service activation (session-bus.conf), as
# run-kcmctl.sh. Each case loads a layout, turns the switch on (or off) with kcmctl and checks the
# panels afterwards, the error the page shows and how long Apply kept the module busy:
#   handplaced  a second top bar has meters placed by hand: they stay where they are, and the
#               main bar's new meters (listed by the shell 0.6 s late, added at the bar's end) are
#               placed before quick settings;
#   noqs        no quick settings in the top bar: an error says so and the switch reads off again;
#   addfails    the shell cannot make the widget: an error says so;
#   slow        the new widget is listed 1.5 s late: Apply returns at once and the meters are
#               placed afterwards;
#   twobars     two top bars get meters, listed 0.4 s and 1.8 s late: both are placed before
#               quick settings, not only the first one the shell lists;
#   off         every meters widget goes.
#
#   meters-switch.sh KCMCTL FAKESHELL PLUGIN_DIR WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kcmctl=$1 fakeshell=$2 plugins=$3 work=$4

rm -rf "$work"
mkdir -p "$work"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export QT_PLUGIN_PATH=$plugins QT_QPA_PLATFORM=offscreen
failures=0

APPNAME=org.plasmafusion.appname QS=org.plasmafusion.quicksettings METERS=org.plasmafusion.meters
CLOCK=org.plasmafusion.clockpill TRAY=org.kde.plasma.systemtray

# run CASE LAYOUT COMMANDS...: one module session against the stand-in shell. Leaves the kcmctl
# output in $work/CASE/kcmctl.log and the panels in $work/CASE/panels.
run() {
  local name=$1 layout=$2
  shift 2
  local w=$work/$name
  mkdir -p "$w/home" "$w/config" "$w/data" "$w/cache" "$w/state" "$w/runtime"
  chmod 700 "$w/runtime"
  printf '%s\n' "$layout" >"$w/layout.json"
  printf '%s\n' "$@" >"$w/commands"
  HOME=$w/home XDG_CONFIG_HOME=$w/config XDG_DATA_HOME=$w/data XDG_CACHE_HOME=$w/cache \
    XDG_STATE_HOME=$w/state XDG_RUNTIME_DIR=$w/runtime \
    dbus-run-session --config-file="$here/session-bus.conf" -- bash -c '
      "$1" "$2" "$3" "$4" >"$5/fakeshell.log" 2>&1 &
      shell=$!
      for _ in $(seq 1 100); do grep -q "fakeshell: ready" "$5/fakeshell.log" && break; sleep 0.05; done
      sed "s|@W@|$5|g" "$5/commands" | "$6" >"$5/kcmctl.log" 2>&1
      status=$?
      kill "$shell"
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
    echo "--- kcmctl:"; grep '^kcmctl: [a-zA-Z]*=' "$work/$name/kcmctl.log" || true
    failures=$((failures + 1))
  fi
}
value() { sed -n "s/^kcmctl: $2=//p" "$work/$1/kcmctl.log" | tail -1; }
panel() { sed -n "$2p" "$work/$1/panels"; }
is() { [ "$1" = "$2" ]; }
has() { [[ $1 == *"$2"* ]]; }
# Milliseconds the save command took (kcmctl's own 200 ms pause included).
busy() { local t; mapfile -t t <"$work/$1/times"; echo $((t[1] - t[0])); }

ON=(waitshell "get topBarAvailable" "get metersAvailable" "get systemMeters" "set systemMeters true"
    "sh date +%s%3N >>@W@/times" save "sh date +%s%3N >>@W@/times")

run handplaced "{\"insert\": \"end\", \"listDelayMs\": 600, \"knownWidgetTypes\": [\"$METERS\"], \"panels\": [
  {\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"screen\": 1, \"widgets\": [\"$APPNAME\", \"$METERS\", \"$CLOCK\", \"$QS\"]}]}" \
  "${ON[@]}" "wait 3500" "get errorText"
expect handplaced "the main bar's meters are placed before quick settings" \
  is "$(panel handplaced 1)" "top 0: appname clockpill systemtray meters quicksettings"
expect handplaced "the meters placed by hand in the other bar stay where they are" \
  is "$(panel handplaced 2)" "top 1: appname meters clockpill quicksettings"
expect handplaced "no error" is "$(value handplaced errorText)" ""

run noqs "{\"knownWidgetTypes\": [\"$METERS\"], \"panels\": [{\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\"]}]}" \
  "${ON[@]}" "wait 1500" "get errorText" waitshell "get systemMeters"
expect noqs "the module could change the top bar" is "$(value noqs topBarAvailable)" true
expect noqs "an error says the top bar has no quick settings" has "$(value noqs errorText)" "Quick Settings"
expect noqs "the switch reads off again" is "$(value noqs systemMeters)" false
expect noqs "the bar is unchanged" is "$(panel noqs 1)" "top 0: appname clockpill systemtray"

run addfails "{\"knownWidgetTypes\": [\"$METERS\"], \"failAdd\": [\"$METERS\"], \"panels\": [
  {\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]}]}" \
  "${ON[@]}" "wait 1500" "get errorText" waitshell "get systemMeters"
expect addfails "an error says the meters could not be added" has "$(value addfails errorText)" "could not be added"
expect addfails "the switch reads off again" is "$(value addfails systemMeters)" false

run slow "{\"insert\": \"end\", \"listDelayMs\": 1500, \"knownWidgetTypes\": [\"$METERS\"], \"panels\": [
  {\"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]}]}" \
  "${ON[@]}" "wait 4000" "get errorText"
expect slow "Apply returns at once ($(busy slow) ms with kcmctl's 200 ms pause)" test "$(busy slow)" -lt 1000
expect slow "the meters are placed once the shell lists them" \
  is "$(panel slow 1)" "top 0: appname clockpill systemtray meters quicksettings"
expect slow "no error" is "$(value slow errorText)" ""

run twobars "{\"insert\": \"end\", \"knownWidgetTypes\": [\"$METERS\"], \"panels\": [
  {\"listDelayMs\": 400, \"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$TRAY\", \"$QS\"]},
  {\"screen\": 1, \"listDelayMs\": 1800, \"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$QS\"]}]}" \
  "${ON[@]}" "wait 4500" "get errorText"
expect twobars "the first bar's meters are placed before quick settings" \
  is "$(panel twobars 1)" "top 0: appname clockpill systemtray meters quicksettings"
expect twobars "the second bar's, listed later, too" \
  is "$(panel twobars 2)" "top 1: appname clockpill meters quicksettings"
expect twobars "no error" is "$(value twobars errorText)" ""

run off "{\"panels\": [{\"widgets\": [\"$APPNAME\", \"$METERS\", \"$QS\"]}, {\"screen\": 1, \"widgets\": [\"$APPNAME\", \"$CLOCK\", \"$METERS\"]}]}" \
  waitshell "get systemMeters" "set systemMeters false" save "wait 300" "get errorText"
expect off "the switch read the meters as on" has "$(grep -m1 '^kcmctl: systemMeters=' "$work/off/kcmctl.log")" "=true"
expect off "every meters widget goes" is "$(cat "$work/off/panels")" "top 0: appname quicksettings
top 1: appname clockpill"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures failed"
  exit 1
fi
echo "PASS: the system meters switch"
