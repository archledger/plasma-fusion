#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Test tooling (not installed). Seed for an integrated virtual session: every part as built by
# tools/build.sh, applied inside the session by tools/device/fusion-config.sh (Global Theme
# with its layout), then the window decoration is exercised by scenario-review.sh.
#
#   STAGE=<dir>/home tools/build.sh
#   [SCALE=1.3333333] generators/decoration/tests/make-review-seed.sh <dir>/home SEED_DIR dark|light
#   (cd <work dir> && tools/vsession/remote.sh rdc-N generators/decoration/tests/scenario-review.sh SEED_DIR 1440x900 270)
#
# With SCALE the scenario first sets that output scale (run the session at 1920x1200 for the
# ThinkPad's 1440x900 logical desktop at 4/3; positions stay in logical pixels).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
STAGE=${1:?stage home}; SEED=${2:?seed dir}; SCHEME=${3:?dark or light}
case $SCHEME in dark|light) ;; *) echo "dark or light" >&2; exit 2 ;; esac
[ -d "$STAGE/.local/share/aurorae/themes/PlasmaFusionDark" ] || { echo "build all parts into $STAGE first" >&2; exit 1; }
rm -rf "$SEED"
mkdir -p "$SEED"
cp -a "$STAGE"/. "$SEED"/
mkdir -p "$SEED/pf-tools" "$SEED/pf-deco"
cp "$ROOT"/tools/device/fusion-config.sh "$ROOT"/tools/device/fusion-restore.sh "$SEED/pf-tools/"
# A virtual session is not started by startplasma, so KWin never reads ~/.config/kdedefaults
# (where the Global Theme writes); the look-and-feel part's helper copies those keys over.
LNF_TESTS="$ROOT/generators/look-and-feel/tests"
[ -f "$LNF_TESTS/merge-kdedefaults.py" ] && cp "$LNF_TESTS/merge-kdedefaults.py" "$SEED/pf-tools/"
cp "$HERE/steps.qml.in" "$HERE/pointer.py" "$SEED/pf-deco/"
if [ ! -d "$SEED/.local/share/fonts" ]; then
  mkdir -p "$SEED/.local/share/fonts/plasma-fusion"
  cp "$ROOT"/fonts/*/*.ttf "$SEED/.local/share/fonts/plasma-fusion/"
fi
printf 'SCHEME=%s\nNAME=%s\nSCALE=%s\n' "$SCHEME" "$([ "$SCHEME" = dark ] && echo Dark || echo Light)" "${SCALE:-}" \
  >"$SEED/pf-deco/params.sh"
echo "seed: $SEED ($SCHEME)"
