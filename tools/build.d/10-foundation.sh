#!/bin/bash
# Foundation: colour schemes, fonts, wallpapers, startup backgrounds, Konsole and Kate/KWrite
# themes and the GTK additions, into the HOME tree $STAGE:
#   .local/share/color-schemes/PlasmaFusion{Dark,Light,HighContrast}.colors
#   .local/share/fonts/plasma-fusion/                     Manrope, Space Grotesk (+ OFL texts)
#   .config/fontconfig/conf.d/60-plasma-fusion-fallback.conf   Noto fallbacks for other scripts
#   .local/share/wallpapers/PlasmaFusion, PlasmaFusion-<Name>
#   .local/share/plasma-fusion/backgrounds/               dusk-ridge-dark-{dimmed,blurred,login,splash}.png
#   .local/share/konsole/PlasmaFusion{Dark,Light}.colorscheme, "Plasma Fusion.profile"
#   .local/share/org.kde.syntax-highlighting/themes/"Plasma Fusion {Dark,Light}.theme"
#   .config/gtk-3.0/{gtk.css,plasma-fusion.css}, .config/gtk-4.0/{gtk.css,plasma-fusion.css}
# PF_WALLPAPER_SIZES=quick renders only 1920x1200, 1920x1080 and 1200x1920 (for fast test builds).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

PKG=$ROOT/packages
GEN=$ROOT/generators/wallpapers
SHARE=$STAGE/.local/share

# Colour schemes: every pair of the Colors board must hold before anything is installed.
python3 -B "$PKG/color-schemes/check_contrast.py" "$PKG/color-schemes" >/dev/null
mkdir -p "$SHARE/color-schemes"
install -m 0644 "$PKG/color-schemes/PlasmaFusionDark.colors" "$PKG/color-schemes/PlasmaFusionLight.colors" \
  "$PKG/color-schemes/PlasmaFusionHighContrast.colors" "$SHARE/color-schemes/"

# Fonts: one static file per weight (generators/fonts/make_static.py). Qt synthesises bold on
# top of the variable files for weights of 700 and more, and Space Grotesk has no 600 instance.
fonts=$SHARE/fonts/plasma-fusion
rm -rf "$fonts"
mkdir -p "$fonts"
install -m 0644 "$ROOT"/fonts/manrope/static/*.ttf "$ROOT"/fonts/spacegrotesk/static/*.ttf "$fonts/"
install -m 0644 "$ROOT/fonts/manrope/OFL.txt" "$fonts/OFL-Manrope.txt"
install -m 0644 "$ROOT/fonts/spacegrotesk/OFL.txt" "$fonts/OFL-SpaceGrotesk.txt"
# Fallback fonts for the scripts Manrope and Space Grotesk lack (fontconfig must parse the file).
fcconf=$ROOT/generators/fonts/60-plasma-fusion-fallback.conf
python3 -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$fcconf"
mkdir -p "$STAGE/.config/fontconfig/conf.d"
install -m 0644 "$fcconf" "$STAGE/.config/fontconfig/conf.d/"

# Wallpapers: the checked-in SVG sources must match the generator, then render the packages.
python3 -B "$GEN/gen_wallpapers.py" check-svg "$GEN/svg"
walls=$SHARE/wallpapers
mkdir -p "$walls"
rm -rf "$walls/PlasmaFusion" "$walls"/PlasmaFusion-*
python3 -B "$GEN/gen_wallpapers.py" wallpapers "$walls" --sizes "${PF_WALLPAPER_SIZES:-all}" >/dev/null
rm -rf "$SHARE/plasma-fusion/backgrounds"
python3 -B "$GEN/gen_wallpapers.py" backgrounds "$SHARE/plasma-fusion/backgrounds" >/dev/null
for d in "$walls/PlasmaFusion" "$walls/PlasmaFusion-CoralBay"; do
  [ -s "$d/metadata.json" ] && [ -s "$d/contents/images/1920x1200.png" ] || { echo "foundation: missing $d" >&2; exit 1; }
done
[ -s "$walls/PlasmaFusion/contents/images_dark/1920x1200.png" ] || { echo "foundation: no dark Dusk Ridge" >&2; exit 1; }
# Every translucent Plasma-style surface over every shipped wallpaper (and white/black where it can
# sit over windows), and every Solid fallback: text 4.5:1, focus ring 3:1 (EFFECTS rule 6).
python3 -B "$PKG/color-schemes/check_contrast.py" "$PKG/color-schemes" --surfaces "$walls" >/dev/null

# Konsole colour schemes and profile.
mkdir -p "$SHARE/konsole"
install -m 0644 "$PKG/konsole/PlasmaFusionDark.colorscheme" "$PKG/konsole/PlasmaFusionLight.colorscheme" \
  "$PKG/konsole/Plasma Fusion.profile" "$SHARE/konsole/"

# Kate/KWrite (KTextEditor) colour themes.
themes=$SHARE/org.kde.syntax-highlighting/themes
mkdir -p "$themes"
for t in "Plasma Fusion Dark" "Plasma Fusion Light"; do
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$PKG/ktexteditor/$t.theme"
  install -m 0644 "$PKG/ktexteditor/$t.theme" "$themes/"
done

# GTK 3 and GTK 4: gtk.css imports kde-gtk-config's colors.css, then plasma-fusion.css.
# The CSS is parsed with GTK itself when PyGObject is installed (no display is opened).
for v in 3.0 4.0; do
  rc=0
  env -u DISPLAY -u WAYLAND_DISPLAY python3 -B "$PKG/gtk/check_css.py" "$v" "$PKG/gtk/gtk-$v/plasma-fusion.css" >/dev/null || rc=$?
  [ "$rc" != 1 ] || { echo "foundation: gtk-$v/plasma-fusion.css does not parse" >&2; exit 1; }
done
for v in gtk-3.0 gtk-4.0; do
  mkdir -p "$STAGE/.config/$v"
  install -m 0644 "$PKG/gtk/gtk.css" "$STAGE/.config/$v/gtk.css"
  install -m 0644 "$PKG/gtk/$v/plasma-fusion.css" "$STAGE/.config/$v/plasma-fusion.css"
done

find "$fonts" "$walls/PlasmaFusion" "$walls"/PlasmaFusion-* "$SHARE/plasma-fusion/backgrounds" -type d -exec chmod 0755 {} +
echo "foundation: colour schemes, fonts, $(ls -d "$walls"/PlasmaFusion* | wc -l) wallpaper packages, backgrounds, konsole, ktexteditor, gtk"
