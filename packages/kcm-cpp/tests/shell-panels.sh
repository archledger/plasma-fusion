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
#               it, and the bar on the screen gets the new opacity.
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
TRAY=org.kde.plasma.systemtray DOCK=org.plasmafusion.dock

# run CASE LAYOUT COMMANDS...: one module session against the stand-in shell. Leaves the kcmctl
# output in $work/CASE/kcmctl.log, the shell's in $work/CASE/fakeshell.log and the panels in
# $work/CASE/panels.
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
panel() { sed -n "$2p" "$work/$1/panels"; }
is() { [ "$1" = "$2" ]; }
alive() { ! grep -q "crashed" "$work/$1/fakeshell.log"; }

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

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures failed"
  exit 1
fi
echo "PASS: the module's panel changes"
