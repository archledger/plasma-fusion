#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed). Build a HOME tree for a virtual session that shows the
# Plasma Fusion window decoration with real apps.
#
#   [SCALE=1.3333] generators/decoration/tests/make-seed.sh SEED_DIR dark|light [COLORS_DIR]
#   tools/vsession/remote.sh dc-1 generators/decoration/tests/scenario.sh SEED_DIR 1440x900 240
#
# Every part is built into SEED_DIR (tools/build.sh). Fonts come from the repository when no
# part installs them. COLORS_DIR (optional) holds PlasmaFusionDark/Light.colors when the colour
# scheme part is not built yet; they are merged into kdeglobals the way the Colours page does.
# SCALE makes the scenario set that output scale first (run the session at 1920x1200 for a
# 1440x900 logical desktop at 4/3, as on the ThinkPad).
set -euo pipefail
SEED=${1:?seed dir}
SCHEME=${2:?dark or light}
COLORS=${3:-}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
case $SCHEME in dark) Name=Dark ;; light) Name=Light ;; *) echo "dark or light" >&2; exit 2 ;; esac
rm -rf "$SEED"
mkdir -p "$SEED/.config" "$SEED/pf-deco"
STAGE=$SEED bash "$ROOT/tools/build.sh" >/dev/null
if [ ! -d "$SEED/.local/share/fonts" ]; then
  mkdir -p "$SEED/.local/share/fonts/plasma-fusion"
  cp "$ROOT"/fonts/*/*.ttf "$SEED/.local/share/fonts/plasma-fusion/"
fi
scheme_file=$SEED/.local/share/color-schemes/PlasmaFusion$Name.colors
if [ ! -f "$scheme_file" ] && [ -n "$COLORS" ]; then
  mkdir -p "$SEED/.local/share/color-schemes"
  cp "$COLORS/PlasmaFusion$Name.colors" "$scheme_file"
fi

cat >"$SEED/.config/kwinrc" <<EOF
[org.kde.kdecoration2]
library=org.kde.kwin.aurorae.v2
theme=__aurorae__svg__PlasmaFusion$Name
BorderSize=None
BorderSizeAuto=false
ButtonsOnLeft=M
ButtonsOnRight=IAX

[Windows]
Placement=Centered
EOF
cat >"$SEED/.config/kdeglobals" <<EOF
[General]
font=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0
menuFont=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0
toolBarFont=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0
smallestReadableFont=Manrope,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0

[WM]
activeFont=Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0

[Icons]
Theme=PlasmaFusion$([ "$SCHEME" = dark ] && echo -Dark)

[KDE]
widgetStyle=Breeze
EOF
if [ -f "$scheme_file" ]; then
  python3 - "$scheme_file" "$SEED/.config/kdeglobals" <<'PY'
import configparser, sys
src, dst = sys.argv[1], sys.argv[2]
def load(p):
    c = configparser.ConfigParser(interpolation=None, strict=False)
    c.optionxform = str
    c.read(p, encoding="utf-8")
    return c
s, d = load(src), load(dst)
for sec in s.sections():
    if sec.startswith("Colors:") or sec in ("WM", "KDE"):
        if not d.has_section(sec):
            d.add_section(sec)
        for k, v in s.items(sec):
            d.set(sec, k, v)
d.set("General", "ColorScheme", s.get("General", "ColorScheme", fallback="PlasmaFusion"))
with open(dst, "w", encoding="utf-8") as f:
    d.write(f, space_around_delimiters=False)
PY
fi
printf '[Theme]\nname=plasma-fusion-%s\n' "$SCHEME" >"$SEED/.config/plasmarc"
printf 'NAME=%s\nSCALE=%s\n' "$Name" "${SCALE:-}" >"$SEED/pf-deco/params.sh"
cp "$HERE/steps.qml.in" "$HERE/pointer.py" "$SEED/pf-deco/"
echo "seed: $SEED ($SCHEME)"
