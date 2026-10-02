#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Offscreen check of the styles with KSvg + Plasma Components 3 on the build host (no display).
#
#   run-harness.sh THEMES_DIR dark|light OUT.png
#
# THEMES_DIR holds plasma-fusion-dark/ and plasma-fusion-light/. Everything runs in a throwaway
# XDG sandbox; nothing touches the user's own configuration.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
THEMES=${1:?themes dir}; VAR=${2:?dark|light}; OUT=${3:?out.png}
SB=$(mktemp -d "${TMPDIR:-/tmp}/pf-ps-harness.XXXXXX")
mkdir -p "$SB/data/plasma/desktoptheme" "$SB/config" "$SB/cache" "$SB/data/fonts"
cp -r "$THEMES/plasma-fusion-$VAR" "$SB/data/plasma/desktoptheme/"
SCHEME="$THEMES/../../color-schemes/PlasmaFusion${VAR^}.colors"
[ -f "$SCHEME" ] || SCHEME=/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-colors-research/PlasmaFusion${VAR^}.colors
cp "$SCHEME" "$SB/config/kdeglobals"
printf '[General]\nfont=Manrope,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n' >> "$SB/config/kdeglobals"
printf '[Theme]\nname=plasma-fusion-%s\n' "$VAR" > "$SB/config/plasmarc"
cp "$ROOT"/fonts/manrope/*.ttf "$SB/data/fonts/"
env -i LANG=C.UTF-8 HOME="$SB" XDG_DATA_HOME="$SB/data" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" \
  XDG_RUNTIME_DIR="$SB" XDG_DATA_DIRS="$SB/data:/usr/share" PATH=/usr/bin \
  QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=org.kde.desktop QT_QPA_PLATFORMTHEME=kde \
  /usr/lib64/qt6/bin/qml "$HERE/harness.qml" -- "$VAR" "$OUT" 2>&1 | grep -v -E 'installEventFilter|platform plugin'
rm -rf "$SB"
