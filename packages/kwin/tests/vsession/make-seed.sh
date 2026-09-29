#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Private-HOME seed for tools/vsession/remote.sh (test use only).
#
#   make-seed.sh STAGE_HOME SEED_DIR [dark|light]
#
# STAGE_HOME is a HOME tree from tools/build.sh with every part built. The seed has the Plasma
# Fusion data files, the settings the Global Theme and tools/device/fusion-config.sh would
# write (colours, style, icons, fonts, decoration) plus the KWin settings this part needs:
#   kwinrc [TabBox]/[TabBoxAlternative] LayoutName, DesktopMode=0, HighlightWindows=false
#   kwinrc [Plugins] plasmafusion-snapEnabled, plasmafusion-attachEnabled, sheetEnabled
#   kwinrc [Outline] QmlPath
# and a desktop file that lets tests/vsession/fakeinput.py use KWin's fake-input interface.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
STAGE=${1:?stage home}; S=${2:?seed dir}; VARIANT=${3:-dark}
case $VARIANT in
  dark) SCHEME=PlasmaFusionDark STYLE=plasma-fusion-dark ICONS=PlasmaFusion-Dark DECO=PlasmaFusionDark ;;
  light) SCHEME=PlasmaFusionLight STYLE=plasma-fusion-light ICONS=PlasmaFusion DECO=PlasmaFusionLight ;;
  *) echo "variant must be dark or light" >&2; exit 2 ;;
esac
mkdir -p "$S/.config" "$S/.local/share/applications" "$S/pfk"
rsync -a --delete "$STAGE/.local/share/" "$S/.local/share/" --exclude applications
cp "$HERE/fakeinput.py" "$HERE/manywindows.py" "$S/pfk/"
PY=$(ssh -o BatchMode=yes "${PFV_HOST:-thinkpad-fedora}" 'readlink -f /usr/bin/python3')
cat > "$S/.local/share/applications/pfk-fakeinput.desktop" <<D
[Desktop Entry]
Type=Application
Name=Plasma Fusion test input
Exec=$PY
X-KDE-Wayland-Interfaces=org_kde_kwin_fake_input
D
{
  cat "$STAGE/.local/share/color-schemes/$SCHEME.colors"
  cat <<K

[General]
ColorScheme=$SCHEME
font=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
menuFont=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
toolBarFont=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
smallestReadableFont=Manrope,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[Icons]
Theme=$ICONS

[KDE]
widgetStyle=Breeze

[WM]
activeFont=Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1
K
} > "$S/.config/kdeglobals"
printf '[Theme]\nname=%s\n' "$STYLE" > "$S/.config/plasmarc"
cat > "$S/.config/kwinrc" <<K
[Desktops]
Number=2
Rows=1
Name_1=Work
Name_2=Design

[Effect-blur]
BlurStrength=12
NoiseStrength=0
Saturation=140

[Effect-overview]
BorderActivate=9

[Outline]
QmlPath=kwin/scripts/plasmafusion-snap/contents/outline/outline.qml

[Plugins]
plasmafusion-attachEnabled=true
plasmafusion-snapEnabled=true
sheetEnabled=true

[TabBox]
DesktopMode=0
HighlightWindows=false
LayoutName=org.plasmafusion.switcher

[TabBoxAlternative]
DesktopMode=0
HighlightWindows=false
LayoutName=org.plasmafusion.switcher

[Windows]
Placement=Centered

[org.kde.kdecoration2]
BorderSize=None
BorderSizeAuto=false
library=org.kde.kwin.aurorae.v2
theme=__aurorae__svg__$DECO
K
echo "$S"
