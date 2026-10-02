#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Seed for the STYLE-1 scenarios (vsession-style1-*.sh; test use only): a stage HOME built with every
# part, the device tools, the test widgets, and optionally a second Plasma style build to switch to
# inside the session (PLAIN_THEMES: a directory holding plasma-fusion-dark/ and plasma-fusion-light/
# built with --south-frame plain --north-side-margin 0).
#
#   make-style1-seed.sh STAGE_HOME SEED_DIR [PLAIN_THEMES]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
STAGE=${1:?stage home}; S=${2:?seed dir}; PLAIN=${3:-}
[ -d "$STAGE/.local/share/plasma/desktoptheme/plasma-fusion-dark" ] || { echo "build all parts into $STAGE first" >&2; exit 1; }
rm -rf "$S"
mkdir -p "$S/pf-tools" "$S/pkg" "$S/pf-stage"
cp -a "$STAGE"/. "$S/pf-stage"/
cp -a "$ROOT/tools/device/." "$S/pf-tools/"
cp -r "$HERE/pstest-plasmoid" "$S/pkg/org.plasmafusion.pstest"
cp -r "$HERE/probe-plasmoid" "$S/pkg/org.plasmafusion.test.probe"
if [ -n "$PLAIN" ]; then
  mkdir -p "$S/pf-plain"
  cp -a "$PLAIN/plasma-fusion-dark" "$PLAIN/plasma-fusion-light" "$S/pf-plain/"
fi
echo "$S"
