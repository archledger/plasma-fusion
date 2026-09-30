#!/bin/bash
# Plasma styles plasma-fusion-dark and plasma-fusion-light
# -> $STAGE/.local/share/plasma/desktoptheme/plasma-fusion-{dark,light}/
# Panel frame switches (see generators/plasma-style/gen_plasma_style.py and docs/parts/plasma-style.md):
#   PF_SOUTH_FRAME=headroom|plain   bottom panel frame (default headroom: the 88 px dock contract)
#   PF_NORTH_SIDE_MARGIN=6|0        top bar frame side margins (default 6)
# The defaults are the frames deployed since round 2; the plain/0 pair lands together with the dock,
# top bar and quick-settings changes that pad for it.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
south=${PF_SOUTH_FRAME:-headroom}
north=${PF_NORTH_SIDE_MARGIN:-6}
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
