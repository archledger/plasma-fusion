#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# A login of a kept virtual-session HOME, between two tools/vsession runs: startplasma's
# environment-script step (plasma-sourceenv.sh with the system scripts, then the user's stub)
# before KWin starts. Runs on the test device against /var/tmp/pfv-NAME only (private runtime
# directory, no session bus: nothing reaches the logged-in session). Test tooling only.
#
#   login-sim.sh NAME ["pkg=version ..."]     the second argument fakes installed versions
set -u
NAME=${1:?name}
P=/var/tmp/pfv-$NAME
H=$P/home
[ -d "$H" ] || { echo "no $H" >&2; exit 2; }
mkdir -p "$P/run" && chmod 700 "$P/run"
env -i HOME="$H" USER="$(id -un)" PATH=/usr/local/bin:/usr/bin:/bin XDG_RUNTIME_DIR="$P/run" LANG=C.UTF-8 \
  XDG_SESSION_TYPE=wayland ${2:+PF_GATE_FAKE_VERSIONS="$2"} \
  /bin/sh /usr/libexec/plasma-sourceenv.sh /etc/xdg/plasma-workspace/env/*.sh "$H/.config/plasma-workspace/env/plasma-fusion-gate.sh" \
  >/dev/null 2>&1
echo "sourced: rc=$?"
grep -A12 "$(grep ' login: ' "$H/.local/state/plasma-fusion/gate.log" | tail -n1 | cut -c1-24)" "$H/.local/state/plasma-fusion/gate.log" | tail -n 12
left=0
for p in /proc/[0-9]*; do grep -qz "^XDG_RUNTIME_DIR=$P/run\$" "$p/environ" 2>/dev/null && left=$((left + 1)); done
echo "processes left from the simulated login: $left"
