#!/bin/bash
# Plasma styles plasma-fusion-dark and plasma-fusion-light
# -> $STAGE/.local/share/plasma/desktoptheme/plasma-fusion-{dark,light}/
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
out="$STAGE/.local/share/plasma/desktoptheme"
mkdir -p "$out"
rm -rf "$out/plasma-fusion-dark" "$out/plasma-fusion-light"
python3 -B "$ROOT/generators/plasma-style/gen_plasma_style.py" "$out" --variant all >/dev/null
# every package must have its metadata, the tier-1 surfaces and no stray files
for v in dark light; do
  d="$out/plasma-fusion-$v"
  for f in metadata.json plasmarc dialogs/background.svg translucent/dialogs/background.svg \
           translucent/widgets/panel-background.svg widgets/plasmoidheading.svg; do
    [ -s "$d/$f" ] || { echo "plasma-style: missing $d/$f" >&2; exit 1; }
  done
done
