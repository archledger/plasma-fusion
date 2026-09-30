#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The offscreen lock screen harness on a private D-Bus session without service activation
# (session-bus.conf), with the mock MPRIS player and notification server, and with no display
# variables, so nothing it starts can reach the desktop session it runs from.
#   test/run.sh OUTDIR [scenario...]      (scenarios: harness.py; env: PF_SIZE, PF_SCHEME, ...)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${1:?usage: run.sh OUTDIR [scenario...]}"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
export QT_QPA_PLATFORM=offscreen
exec dbus-run-session --config-file="$here/session-bus.conf" -- bash -c '
  here=$1; shift
  python3 "$here/mock_services.py" mpris notify & m=$!
  sleep 1
  rc=0; python3 "$here/harness.py" "$@" || rc=$?
  kill "$m" 2>/dev/null; wait "$m" 2>/dev/null
  exit "$rc"' run.sh "$here" "$@"
