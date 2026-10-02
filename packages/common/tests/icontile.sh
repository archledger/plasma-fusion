#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# FusionIconTile with the Plasma Fusion icon theme (offscreen): builds the themes into OUTDIR, adds a
# familiar tile for a made-up app, and checks the lookups by desktop id under PlasmaFusion and under
# Breeze (where nothing may change). Private bus without service activation (no portal orphans).
#   packages/common/tests/icontile.sh OUTDIR
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
OUT=$(mkdir -p "${1:?usage: icontile.sh OUTDIR}" && cd "$1" && pwd)
QML=${QML:-/usr/lib64/qt6/bin/qml}
rm -rf "$OUT/ui" "$OUT/data" "$OUT/cfg-fusion" "$OUT/cfg-breeze" "$OUT/cache"
mkdir -p "$OUT/ui" "$OUT/data/icons" "$OUT/cfg-fusion" "$OUT/cfg-breeze" "$OUT/cache"
bash "$ROOT/tools/build-lib/shared-qml.sh" install "$HERE" "$OUT/ui" >/dev/null
install -m 0644 "$HERE/IconTileTest.qml" "$OUT/ui/IconTileTest.qml"
python3 "$ROOT/generators/icons/gen_icons.py" --out "$OUT/data/icons" >/dev/null
cp "$OUT/data/icons/PlasmaFusion/art/tile-app-kate.svg" \
   "$OUT/data/icons/PlasmaFusion/apps/scalable/plasmafusion_app.org.example.Familiar_App.svg"
printf '[Icons]\nTheme=PlasmaFusion\n' >"$OUT/cfg-fusion/kdeglobals"
printf '[Icons]\nTheme=breeze\n' >"$OUT/cfg-breeze/kdeglobals"

run() {  # CONFIG
  env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY \
    dbus-run-session --config-file="$ROOT/packages/lockscreen/test/session-bus.conf" -- \
    env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=kde QT_FORCE_STDERR_LOGGING=1 QML_DISABLE_DISK_CACHE=1 \
    XDG_CONFIG_HOME="$OUT/$1" XDG_DATA_HOME="$OUT/data" XDG_CACHE_HOME="$OUT/cache/$1" \
    timeout 60 "$QML" "$OUT/ui/IconTileTest.qml" 2>&1 | sed -n 's/^.*CASE //p'
}
run cfg-fusion >"$OUT/fusion.txt"
run cfg-breeze >"$OUT/breeze.txt"
expect() {  # FILE LINE
  grep -qxF "$2" "$OUT/$1" || { echo "icontile: $1 lacks: $2" >&2; cat "$OUT/$1" >&2; exit 1; }
}
expect fusion.txt "org.kde.kdebugsettings ownTile=true familiar=false foreign=false glyph=org.kde.kdebugsettings"
expect fusion.txt "org.mozilla.firefox ownTile=true familiar=false foreign=false glyph=org.mozilla.firefox"
expect fusion.txt "org.example.Familiar-App ownTile=false familiar=true foreign=false glyph=plasmafusion_app.org.example.Familiar_App"
expect fusion.txt "org.example.Nothing ownTile=false familiar=false foreign=true glyph=some-icon"
expect breeze.txt "org.kde.kdebugsettings ownTile=false familiar=false foreign=false glyph=debug-run"
expect breeze.txt "org.example.Familiar-App ownTile=false familiar=false foreign=true glyph=/opt/example/icon.png"
echo "icontile: designed ids, familiar tiles and the neutral tile as expected (PlasmaFusion and Breeze)"
