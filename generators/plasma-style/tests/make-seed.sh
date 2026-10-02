#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build a private-HOME seed for tools/vsession/remote.sh (test use only).
#
#   make-seed.sh STAGE_HOME SEED_DIR
#
# STAGE_HOME is a HOME tree from tools/build.sh. The seed carries the two Plasma styles as
# packages to install with kpackagetool6 (SEED/pkg), the test widget, the Fusion colour schemes
# (from the stage when the colours part is built, otherwise the research drafts), the fonts,
# the board wallpaper and a few settings. Then:
#   tools/vsession/remote.sh ps-N generators/plasma-style/tests/vsession-scenario.sh SEED_DIR
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
STAGE=${1:?stage home}; S=${2:?seed dir}
DT="$STAGE/.local/share/plasma/desktoptheme"
[ -d "$DT/plasma-fusion-dark" ] || { echo "build the plasma-style part into $STAGE first" >&2; exit 1; }
rm -rf "$S"
mkdir -p "$S/pkg" "$S/.config" "$S/.local/share/color-schemes" "$S/.local/share/fonts" "$S/.local/share/wallpapers-test"
cp -r "$DT/plasma-fusion-dark" "$DT/plasma-fusion-light" "$S/pkg/"
cp -r "$HERE/pstest-plasmoid" "$S/pkg/org.plasmafusion.pstest"
if [ -f "$STAGE/.local/share/color-schemes/PlasmaFusionDark.colors" ]; then
  cp "$STAGE"/.local/share/color-schemes/PlasmaFusion{Dark,Light}.colors "$S/.local/share/color-schemes/"
else
  echo "note: using the colour-scheme research drafts" >&2
  cp /mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-colors-research/PlasmaFusion{Dark,Light}.colors "$S/.local/share/color-schemes/"
fi
cp "$ROOT"/fonts/manrope/*.ttf "$ROOT"/fonts/spacegrotesk/*.ttf "$S/.local/share/fonts/"
python3 "$HERE/render-test-wallpapers.py" "$S/.local/share/wallpapers-test"
cat > "$S/.config/kdeglobals" <<'K'
[General]
font=Manrope,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
menuFont=Manrope,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
toolBarFont=Manrope,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
smallestReadableFont=Manrope,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
K
# blur values recommended for the Global Themes (see docs/parts/plasma-style.md)
printf '[Effect-blur]\nBlurStrength=12\nNoiseStrength=0\nSaturation=140\n' > "$S/.config/kwinrc"
printf '[Notifications]\nPopupPosition=TopRight\n' > "$S/.config/plasmanotifyrc"
echo "$S"
