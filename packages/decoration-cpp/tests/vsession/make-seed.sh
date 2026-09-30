#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Seed HOME for a virtual session that tests the C++ decoration (test tooling, not installed).
#
#   make-seed.sh STAGE_HOME PLUGIN.so SEED_DIR VSESSION_NAME dark|light [SCALE]
#
# STAGE_HOME is a tools/build.sh output (all parts), copied to SEED/pf-stage and applied inside the
# session with tools/device/fusion-config.sh --install. The plugin goes to SEED/pf-plugins/
# org.kde.kdecoration3/ and QT_PLUGIN_PATH (SEED/.config/pfv-env) points KWin at it; nothing is
# installed system-wide. SCALE (e.g. 1.3333333) makes the scenario set that output scale first.
# PFV_BASE (default /var/tmp, as tools/vsession/remote.sh) is where the session HOME lives on the
# test device; QT_PLUGIN_PATH must name it literally. SEED_PARAMS adds KEY=VALUE lines to
# pf-deco/params.sh (read by the scenarios, e.g. MEMDECO=aurorae). The helpers of lib.sh go to
# pf-deco/lib.sh; Qt log lines carry wall-clock times (QT_MESSAGE_PATTERN) for latency checks.
set -euo pipefail
STAGE=${1:?stage home}; PLUGIN=${2:?plugin}; SEED=${3:?seed dir}; NAME=${4:?vsession name}
VARIANT=${5:-dark}; SCALE=${6:-}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
rm -rf "$SEED"
mkdir -p "$SEED/.config" "$SEED/pf-plugins/org.kde.kdecoration3" "$SEED/pf-deco"
rsync -a "$STAGE/" "$SEED/pf-stage/"
rsync -a "$ROOT/tools/" "$SEED/pf-tools/"
cp "$PLUGIN" "$SEED/pf-plugins/org.kde.kdecoration3/"
printf 'QT_PLUGIN_PATH=%s/pfv-%s/home/pf-plugins\nQT_LOGGING_RULES=org.plasmafusion.decoration.debug=true\n' "${PFV_BASE:-/var/tmp}" "$NAME" >"$SEED/.config/pfv-env"
# shellcheck disable=SC2016  # Qt's own placeholders, not shell variables
printf 'QT_MESSAGE_PATTERN=%s\n' '%{time yyyy-MM-ddTHH:mm:ss.zzz} %{if-category}%{category}: %{endif}%{message}' >>"$SEED/.config/pfv-env"
printf 'VARIANT=%s\nSCALE=%s\n' "$VARIANT" "$SCALE" >"$SEED/pf-deco/params.sh"
[ -n "${SEED_PARAMS:-}" ] && printf '%s\n' "$SEED_PARAMS" >>"$SEED/pf-deco/params.sh"
cp "$HERE/lib.sh" "$SEED/pf-deco/lib.sh"
# The Global Theme's fonts before KWin starts, as in a real login: KWin caches its title font at
# start-up and does not always pick up the one applied later inside the test session.
printf '[General]\nfont=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0\n\n[WM]\nactiveFont=Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0\n' >"$SEED/.config/kdeglobals"
echo "seed: $SEED ($VARIANT${SCALE:+, scale $SCALE})"
