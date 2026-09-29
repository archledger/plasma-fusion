#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed): a seed HOME for the foundation virtual-session tests.
#
#   generators/wallpapers/tests/make-seed.sh SEED_DIR          foundation part only
#   generators/wallpapers/tests/make-seed.sh --all SEED_DIR    every part + tools/device scripts
#   tools/vsession/remote.sh fd-1 generators/wallpapers/tests/scenario-dark.sh SEED_DIR 1440x900 240
#   tools/vsession/remote.sh fd-2 generators/wallpapers/tests/scenario-light.sh SEED_DIR 1440x900 240
#   tools/vsession/remote.sh fd-3 generators/wallpapers/tests/scenario-integrated.sh SEED_DIR 1440x900 240   (--all seed)
set -euo pipefail
ALL=0; [ "${1:-}" = --all ] && { ALL=1; shift; }
SEED=${1:?seed dir}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
rm -rf "$SEED"
mkdir -p "$SEED"
SEED=$(cd "$SEED" && pwd)
if [ $ALL = 1 ]; then
  bash "$ROOT/generators/look-and-feel/tests/make-seed.sh" "$SEED" >/dev/null
else
  STAGE=$SEED PF_WALLPAPER_SIZES=quick bash "$ROOT/tools/build.sh" foundation >/dev/null
fi
mkdir -p "$SEED/test" "$SEED/Pictures/Wallpapers"
cp "$HERE"/{gtk3-controls.py,adw-controls.py,demo.sh,sample.qml,scenario-common.sh} "$SEED/test/"
walls=$SEED/.local/share/wallpapers
cp "$walls/PlasmaFusion/contents/images_dark/1920x1200.png" "$SEED/Pictures/Wallpapers/dusk-ridge.png"
for n in CoralBay:coral-bay PineFog:pine-fog NightGrid:night-grid DesertNoon:desert-noon Lagoon:lagoon Glacier:glacier \
         Ember:ember Aurora:aurora PlumHills:plum-hills Meadow:meadow SlateRain:slate-rain; do
  cp "$walls/PlasmaFusion-${n%%:*}/contents/images/1920x1200.png" "$SEED/Pictures/Wallpapers/${n#*:}.png"
done
echo "seed: $SEED"
