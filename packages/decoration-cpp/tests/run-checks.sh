#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver for pfdeco-preview's checks (tests/CMakeLists.txt): one colour scheme, offscreen,
# with a scratch configuration and cache, on a private D-Bus session without service activation
# (session-bus.conf) and without display variables, so nothing it starts reaches a desktop session.
# The tool's output is kept in WORKDIR/preview.log; the exit status is the tool's, 0 when every
# check passed. Options after FONTS_DIR go to the tool (--fuzz: random scenes instead of the
# checks; PF_FUZZ_COUNT and PF_FUZZ_SEED in the environment reach it).
#
#   run-checks.sh PREVIEW PLUGIN WORKDIR NAME SCHEME OTHER_SCHEME [FONTS_DIR [OPTION...]]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
preview=$1 plugin=$2 work=$3 name=$4 scheme=$5 other=$6 fonts=${7:-}
shift $(($# < 7 ? $# : 7))

rm -rf "$work"
mkdir -p "$work/config" "$work/cache" "$work/out"
# The accent ring reads the colour scheme from kdeglobals.
cp "$scheme" "$work/config/kdeglobals"
args=(--decoration-plugin "$plugin" --out "$work/out" --name "$name" --scheme "$scheme" --other-scheme "$other")
if [ -n "$fonts" ] && [ -d "$fonts" ]; then
  args+=(--fonts "$fonts")
fi
args+=("$@")

unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS LANGUAGE LC_ALL LC_MESSAGES
# The tooltip check expects the English text.
export LANG=en_US.UTF-8
export XDG_CONFIG_HOME=$work/config XDG_CACHE_HOME=$work/cache QT_QPA_PLATFORM=offscreen
status=0
dbus-run-session --config-file="$here/session-bus.conf" -- "$preview" "${args[@]}" >"$work/preview.log" 2>&1 || status=$?
cat "$work/preview.log"
echo "$(grep -c '^PASS ' "$work/preview.log") checks passed, $(grep -c '^FAIL ' "$work/preview.log") failed, exit status $status"
exit "$status"
