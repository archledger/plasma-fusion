#!/bin/bash
# Cursor themes PlasmaFusion-cursors (dark fill, white outline; the default) and
# PlasmaFusion-Light-cursors (white fill, #1b2031 outline) -> $STAGE/.local/share/icons/.
# Each theme has KWin SVG cursors (cursors_scalable/) and Xcursor files (cursors/) rendered with
# QtSvg; needs python3 and PySide6 (python3-pyside6). See docs/parts/cursors.md.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
out="$STAGE/.local/share/icons"
mkdir -p "$out"
rm -rf "$out/PlasmaFusion-cursors" "$out/PlasmaFusion-Light-cursors"
QT_QPA_PLATFORM=offscreen python3 -B "$ROOT/generators/cursors/gen_cursors.py" --out "$out"
for t in PlasmaFusion-cursors PlasmaFusion-Light-cursors; do
  for f in index.theme cursors/left_ptr cursors/default cursors_scalable/default/metadata.json \
           cursors_scalable/wait/metadata.json; do
    [ -e "$out/$t/$f" ] || { echo "cursors: missing $t/$f" >&2; exit 1; }
  done
done
