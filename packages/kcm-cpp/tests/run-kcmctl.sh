#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver (tests/CMakeLists.txt): loads the built settings module with kcmctl and reads every
# property, applies the defaults (in memory; nothing is saved) and reads them again. It runs in a
# scratch HOME with empty configuration, on a private D-Bus session without service activation
# (session-bus.conf) and without display variables, so it reads and changes nothing of a real
# session. Fails when the module does not load from PLUGIN_DIR, when kcmctl fails, or when the
# properties are not read.
#
#   run-kcmctl.sh KCMCTL PLUGIN_DIR WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kcmctl=$1 plugins=$2 work=$3

rm -rf "$work"
mkdir -p "$work/home" "$work/config" "$work/data" "$work/cache" "$work/state" "$work/runtime"
chmod 700 "$work/runtime"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache
export XDG_STATE_HOME=$work/state XDG_RUNTIME_DIR=$work/runtime
export QT_PLUGIN_PATH=$plugins QT_QPA_PLATFORM=offscreen

log=$work/kcmctl.log
status=0
printf '%s\n' waitshell dump defaults dump |
  dbus-run-session --config-file="$here/session-bus.conf" -- "$kcmctl" >"$log" 2>&1 || status=$?
cat "$log"
if [ "$status" -ne 0 ]; then
  echo "FAIL: kcmctl exited with $status"
  exit 1
fi
if ! grep -q "^kcmctl: plugin $plugins/" "$log"; then
  echo "FAIL: the module was not loaded from $plugins"
  exit 1
fi
values=$(grep -c '^kcmctl: [A-Za-z]*=' "$log" || true)
if [ "$values" -lt 40 ]; then
  echo "FAIL: $values property values read (two dumps should give more than 40)"
  exit 1
fi
echo "PASS: module loaded from $plugins, $values property values read"
