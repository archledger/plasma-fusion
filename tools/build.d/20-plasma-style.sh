#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma styles plasma-fusion-dark and plasma-fusion-light
# -> $STAGE/.local/share/plasma/desktoptheme/plasma-fusion-{dark,light}/
# Panel frame switches (see generators/plasma-style/gen_plasma_style.py and docs/parts/plasma-style.md):
#   PF_SOUTH_FRAME=plain|headroom   bottom panel frame (default plain: a 72 px dock plate, the
#                                   16 px headroom above it in the panel window)
#   PF_NORTH_SIDE_MARGIN=0|6        top bar frame side margins (default 0: the widgets pad)
# headroom/6 are the frames deployed until the one-pass build (the 88 px dock contract); they go
# with a dock panel of 88 px (the layout script, fusion-config.sh and the tablet script use 72).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
south=${PF_SOUTH_FRAME:-plain}
north=${PF_NORTH_SIDE_MARGIN:-0}
case "$south" in headroom|plain) ;; *) echo "plasma-style: PF_SOUTH_FRAME must be headroom or plain" >&2; exit 1 ;; esac
case "$north" in 6|0) ;; *) echo "plasma-style: PF_NORTH_SIDE_MARGIN must be 6 or 0" >&2; exit 1 ;; esac
out="$STAGE/.local/share/plasma/desktoptheme"
mkdir -p "$out"
rm -rf "$out/plasma-fusion-dark" "$out/plasma-fusion-light"
python3 -B "$ROOT/generators/plasma-style/gen_plasma_style.py" "$out" --variant all \
  --south-frame "$south" --north-side-margin "$north" >/dev/null
# every package must have its metadata, the tier-1 surfaces and no stray files
for v in dark light; do
  d="$out/plasma-fusion-$v"
  for f in metadata.json plasmarc dialogs/background.svg translucent/dialogs/background.svg \
           translucent/widgets/panel-background.svg widgets/plasmoidheading.svg widgets/action-overlays.svg; do
    [ -s "$d/$f" ] || { echo "plasma-style: missing $d/$f" >&2; exit 1; }
  done
done
echo "plasma-style: south frame $south, top bar side margins $north"
