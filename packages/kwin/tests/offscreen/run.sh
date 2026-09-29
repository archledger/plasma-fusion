#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Offscreen render of a KWin QML package with a stand-in org.kde.kwin (test use only).
#
#   run.sh STAGE_HOME HARNESS.qml OUT.png [name=value ...]
#
# STAGE_HOME is a HOME tree from tools/build.sh (Plasma style and icons are taken from it). The
# render runs with a private HOME/XDG tree and a private Xvfb display (:97 unless PFK_DISPLAY is
# set), so it never touches the logged-in session. Pass dark=false for the light variant.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
STAGE=${1:?stage home}; HARNESS=${2:?harness}; OUT=${3:?out png}; shift 3
VARIANT=Dark; STYLE=plasma-fusion-dark; ICONS=PlasmaFusion-Dark
for a in "$@"; do [ "$a" = dark=false ] && { VARIANT=Light; STYLE=plasma-fusion-light; ICONS=PlasmaFusion; }; done

T=$(mktemp -d "${PFK_TMP:-${TMPDIR:-/tmp}}/pfk-render.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/data/fonts" "$T/config" "$T/cache"
ln -s "$STAGE/.local/share/plasma" "$T/data/plasma"
ln -s "$STAGE/.local/share/icons" "$T/data/icons"
cp "$ROOT"/fonts/manrope/*.ttf "$ROOT"/fonts/spacegrotesk/*.ttf "$T/data/fonts/"
COLORS=$STAGE/.local/share/color-schemes/PlasmaFusion$VARIANT.colors
[ -f "$COLORS" ] || COLORS=/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-colors-research/PlasmaFusion$VARIANT.colors
{
  cat "$COLORS"
  printf '\n[General]\nColorScheme=PlasmaFusion%s\nfont=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n' "$VARIANT"
  printf '\n[Icons]\nTheme=%s\n' "$ICONS"
} > "$T/config/kdeglobals"
printf '[Theme]\nname=%s\n' "$STYLE" > "$T/config/plasmarc"

DISP=${PFK_DISPLAY:-:97}
if ! [ -e "/tmp/.X11-unix/X${DISP#:}" ]; then
  Xvfb "$DISP" -screen 0 1440x900x24 -nolisten tcp >/dev/null 2>&1 &
  sleep 1.5
fi
env -i HOME="$T" PATH=/usr/bin:/bin XDG_DATA_HOME="$T/data" XDG_CONFIG_HOME="$T/config" \
  XDG_CACHE_HOME="$T/cache" XDG_DATA_DIRS=/usr/local/share:/usr/share XDG_RUNTIME_DIR="$T" \
  QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="js.debug=true;qml.debug=true" DISPLAY="$DISP" QT_QPA_PLATFORM=xcb QSG_RENDER_LOOP=basic LANG=en_US.UTF-8 \
  timeout -s KILL 60 python3 "$HERE/render.py" "$HARNESS" "$OUT" "$@"
