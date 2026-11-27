#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver (tests/CMakeLists.txt): runs the test of the focus shortcut (shortcuttest) in a
# scratch HOME with empty configuration, on a private session bus without service activation
# (session-bus.conf) and without display variables. The class under test registers its actions
# with the global shortcut daemon: on the session bus of a real desktop it would reach the
# desktop's own shortcut settings, and with service activation it could start a daemon. The
# test refuses any other bus: it runs only with PF_SHORTCUT_TEST_BUS set, as here, and with no
# global shortcut daemon on the bus.
#
#   run-shortcut-test.sh TEST WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
test=$1 work=$2

rm -rf "$work"
mkdir -p "$work/home" "$work/config" "$work/data" "$work/cache" "$work/state" "$work/runtime"
chmod 700 "$work/runtime"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache
export XDG_STATE_HOME=$work/state XDG_RUNTIME_DIR=$work/runtime
export PF_SHORTCUT_TEST_BUS=1
dbus-run-session --config-file="$here/session-bus.conf" -- "$test"
