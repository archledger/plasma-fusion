#!/bin/bash
# Build a private-HOME seed with every Plasma Fusion part for tools/vsession/remote.sh
# (test use only). The Global Theme layout is applied inside the session by
# tools/device/fusion-config.sh, so the Plasma style is seen together with the real top bar,
# dock, quick settings, launcher and desktop cards.
#
#   make-integrated-seed.sh STAGE_HOME SEED_DIR
#   tools/vsession/remote.sh rps-N generators/plasma-style/tests/vsession-integrated.sh SEED_DIR 1440x900 240
#
# STAGE_HOME is a HOME tree from `STAGE=... tools/build.sh` (all parts).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
STAGE=${1:?stage home}; S=${2:?seed dir}
[ -d "$STAGE/.local/share/plasma/desktoptheme/plasma-fusion-dark" ] || { echo "build all parts into $STAGE first" >&2; exit 1; }
rm -rf "$S"
mkdir -p "$S"
cp -a "$STAGE"/. "$S"/
mkdir -p "$S/pf-tools" "$S/pkg"
cp "$ROOT"/tools/device/fusion-config.sh "$ROOT"/tools/device/fusion-restore.sh "$S/pf-tools/"
# KWin reads the Global Theme's kdedefaults only in a real login; the look-and-feel part's test
# helper copies those keys (optional: the scenario skips it when absent)
LNF_TESTS="$ROOT/generators/look-and-feel/tests"
[ -f "$LNF_TESTS/merge-kdedefaults.py" ] && cp "$LNF_TESTS/merge-kdedefaults.py" "$S/pf-tools/"
cp -r "$HERE/pstest-plasmoid" "$S/pkg/org.plasmafusion.pstest"
if [ ! -d "$S/.local/share/fonts" ]; then
  mkdir -p "$S/.local/share/fonts/plasma-fusion"
  cp "$ROOT"/fonts/*/*.ttf "$S/.local/share/fonts/plasma-fusion/"
fi
echo "$S"
