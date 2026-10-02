#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install the shared part of Plasma Fusion into a package's root: what tools/build.sh staged (themes,
# widgets, icons, fonts, KWin scripts, helpers), the Plymouth theme, the per-user templates, the
# setup tools, the plasma-fusion command and the documentation. Every channel calls it (the Fedora
# spec, the Arch PKGBUILD, Debian's rules, the Nix package), so the installed files are the same
# everywhere apart from the directories chosen below. Run from the top of a built source tree.
#
#   packaging/install-tree.sh --stage DIR --plymouth DIR [options]
#
#   --stage DIR        tools/build.sh's STAGE (its .local/share, .local/libexec and .config)
#   --plymouth DIR     generators/plymouth/build.sh's theme directory (…/plasma-fusion)
#   --destdir DIR      the package root files are written below (rpm's buildroot, makepkg's pkgdir,
#                      debian/<package>); empty for Nix, whose prefix is $out
#   --prefix P         /usr by default: data in P/share, the command in P/bin
#   --libexecdir D     P/libexec by default (Fedora, Debian); Arch: /usr/lib
#   --system-share S   where the other packages' data are on the running system: P/share by
#                      default; NixOS: /run/current-system/sw/share
#   --plymouth-theme   install the boot splash as P/share/plymouth/themes/plasma-fusion (NixOS's
#                      boot.plymouth.themePackages) instead of as the source that
#                      tools/system/plymouth-install.sh installs
#
# Files that name a directory of another package or of this one (the charge limit's helper and
# polkit action, the on-screen keyboard's desktop file, the icon names handed back to Breeze and
# hicolor, the Plymouth descriptor) get the chosen directories; each replacement must find its
# text, so a moved string fails the build instead of shipping a wrong path. Everything the build
# staged must be installed: a new part written below .local/share without a line here fails too.
set -euo pipefail
STAGE='' PLYMOUTH='' DESTDIR='' PREFIX=/usr LIBEXECDIR='' SYSSHARE='' PLYTHEME=0
while [ $# -gt 0 ]; do
  case $1 in
    --stage) STAGE=$2; shift ;;
    --plymouth) PLYMOUTH=$2; shift ;;
    --destdir) DESTDIR=$2; shift ;;
    --prefix) PREFIX=$2; shift ;;
    --libexecdir) LIBEXECDIR=$2; shift ;;
    --system-share) SYSSHARE=$2; shift ;;
    --plymouth-theme) PLYTHEME=1 ;;
    -h|--help) sed -n '5,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -d "$STAGE/.local/share" ] || { echo "--stage: no .local/share in '$STAGE' (run tools/build.sh)" >&2; exit 2; }
[ -s "$PLYMOUTH/plasma-fusion.plymouth" ] || { echo "--plymouth: no plasma-fusion.plymouth in '$PLYMOUTH'" >&2; exit 2; }
[ -f tools/build.sh ] && [ -f VERSION ] || { echo "run from the top of the Plasma Fusion source tree" >&2; exit 2; }
PREFIX=${PREFIX%/}
LIBEXECDIR=${LIBEXECDIR:-$PREFIX/libexec}
SYSSHARE=${SYSSHARE:-$PREFIX/share}
share=$STAGE/.local/share
dest=$DESTDIR$PREFIX/share
libexec=$DESTDIR$LIBEXECDIR/plasma-fusion

# replace FILE OLD NEW: every OLD becomes NEW; OLD must occur (nothing to do when they are equal).
replace() {
  [ "$2" != "$3" ] || return 0
  grep -qF -- "$2" "$1" || { echo "install-tree: '$2' not found in $1" >&2; exit 1; }
  python3 -c 'import sys, pathlib; p = pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace(sys.argv[2], sys.argv[3]))' "$1" "$2" "$3"
}

# Copy with the links as they are (the icon themes are mostly symbolic links).
TREES=()
copy_tree() { # $1 source below .local/share, $2 destination below share
  mkdir -p "$dest/$2"
  cp -a "$share/$1/." "$dest/$2/"
  TREES+=("$2")
}
copy_tree color-schemes color-schemes
for t in look-and-feel desktoptheme plasmoids shells layout-templates; do
  copy_tree "plasma/$t" "plasma/$t"
done
copy_tree icons icons
copy_tree aurorae/themes aurorae/themes
copy_tree wallpapers wallpapers
copy_tree kwin/tabbox kwin/tabbox
copy_tree kwin/scripts kwin/scripts
copy_tree konsole konsole
copy_tree org.kde.syntax-highlighting/themes org.kde.syntax-highlighting/themes
copy_tree fonts/plasma-fusion fonts/plasma-fusion
copy_tree plasma-fusion/backgrounds plasma-fusion/backgrounds
# Xournal++ templates of the pen menu; the power-tiers unit where fusion-config.sh looks for it
copy_tree plasma-fusion/pen plasma-fusion/pen
copy_tree plasma-fusion/powerfx plasma-fusion/powerfx
# The familiar app icons unit (fusion-config.sh enables it per user; the tool goes to libexec)
copy_tree plasma-fusion/appicons plasma-fusion/appicons
# The LibreOffice scale guard's desktop entry (HIDPI-1; fusion-config.sh installs it per user)
copy_tree plasma-fusion/compat plasma-fusion/compat
# The charge-limit helper's polkit action (the helper itself goes to libexec below)
copy_tree polkit-1/actions polkit-1/actions
# The helpers (power tiers, charge limit, keyboard keys, app icons, LibreOffice guard); the user
# units' ExecSearchPath lists /usr/libexec/plasma-fusion, /usr/lib/plasma-fusion and NixOS's
# system profile.
mkdir -p "$libexec"
cp -a "$STAGE/.local/libexec/plasma-fusion/." "$libexec/"

# Everything the build staged must be installed.
not_copied=$(
  LC_ALL=C comm -23 <(cd "$share" && find . \( -type f -o -type l \) | LC_ALL=C sort) \
    <(cd "$dest" && find . \( -type f -o -type l \) | LC_ALL=C sort)
  LC_ALL=C comm -23 <(cd "$STAGE/.local/libexec/plasma-fusion" && find . \( -type f -o -type l \) | LC_ALL=C sort) \
    <(cd "$libexec" && find . \( -type f -o -type l \) | LC_ALL=C sort)
  cd "$STAGE" && find . -mindepth 1 -maxdepth 2 ! -path ./.local ! -path ./.local/share \
    ! -path ./.local/libexec ! -path ./.config ! -path './.config/*'
)
if [ -n "$not_copied" ]; then
  echo "staged by tools/build.sh but not installed:" >&2
  head -n 50 <<<"$not_copied" >&2
  exit 1
fi

# The icon themes hand some names back to Breeze and to apps' own hicolor icons with absolute links
# into /usr/share/icons (right for a per-user install in ~/.local/share). Where the system's icons
# are next to these (P/share), they become relative links that resolve inside whatever root the
# package is installed to; otherwise they point into the system's icon directory.
find "$dest/icons" -type l -lname '/usr/share/icons/*' -print0 |
  while IFS= read -r -d '' link; do
    target=$(readlink "$link")
    if [ "$SYSSHARE" = "$PREFIX/share" ]; then
      target=$PREFIX/share/icons/${target#/usr/share/icons/}
      ln -sfn "$(realpath -m -s --relative-to="$(dirname "${link#"$DESTDIR"}")" "$target")" "$link"
    else
      ln -sfn "$SYSSHARE/icons/${target#/usr/share/icons/}" "$link"
    fi
  done

# Paths of this package and of others in the files that name them.
replace "$dest/polkit-1/actions/org.plasmafusion.charge-limit.policy" \
  /usr/libexec/plasma-fusion/ "$LIBEXECDIR/plasma-fusion/"
qs=$dest/plasma/plasmoids/org.plasmafusion.quicksettings/contents/ui/services
replace "$qs/ChargeLimit.qml" /usr/libexec/plasma-fusion/ "$LIBEXECDIR/plasma-fusion/"
replace "$qs/ChargeLimit.qml" /usr/share/polkit-1/actions/ "$SYSSHARE/polkit-1/actions/"
replace "$qs/TabletPolicy.qml" '"/usr/share/applications/org.kde.plasma.keyboard.desktop"' \
  "\"$SYSSHARE/applications/org.kde.plasma.keyboard.desktop\""

# The boot splash: a source for tools/system/plymouth-install.sh (installing the package never
# changes the boot splash), or on NixOS a theme with its own path in the descriptor.
if [ "$PLYTHEME" = 1 ]; then
  mkdir -p "$dest/plymouth/themes"
  cp -a "$PLYMOUTH" "$dest/plymouth/themes/plasma-fusion"
  replace "$dest/plymouth/themes/plasma-fusion/plasma-fusion.plymouth" \
    /usr/share/plymouth/themes/plasma-fusion "$PREFIX/share/plymouth/themes/plasma-fusion"
else
  mkdir -p "$dest/plasma-fusion/plymouth"
  cp -a "$PLYMOUTH" "$dest/plasma-fusion/plymouth/plasma-fusion"
fi

# Per-user configuration from the build (GTK 3/4 stylesheets, the font fallback, user units), kept
# as templates for the per-user step; the package itself writes nothing into a home directory.
mkdir -p "$dest/plasma-fusion/config"
cp -a "$STAGE/.config/." "$dest/plasma-fusion/config/"

# Scripts: per-user setup (tools/device, with the login check in gate/ and the "My previous
# desktop" generator), the pen defaults (tools/pen) and root setup of the login greeter and the
# boot splash (tools/system).
for d in device device/gate pen system; do
  mkdir -p "$dest/plasma-fusion/tools/$d"
  for f in tools/"$d"/*.sh; do
    [ -e "$f" ] && install -m 0755 "$f" "$dest/plasma-fusion/tools/$d/"
  done
done
install -m 0755 tools/device/previous-theme.py "$dest/plasma-fusion/tools/device/"
# The Plasma series this version was tested with (the login check records no other as tested).
install -m 0644 packaging/tested-plasma.txt "$dest/plasma-fusion/tested-plasma.txt"
tr -d '[:space:]' <VERSION >"$dest/plasma-fusion/version"
echo >>"$dest/plasma-fusion/version"
# The package's own top-level entries below share/ (plasma-fusion drop-user-copy finds per-user
# copies of them that hide the package).
for d in "${TREES[@]}"; do
  (cd "$dest" && find "$d" -mindepth 1 -maxdepth 1)
done | LC_ALL=C sort >"$dest/plasma-fusion/items.txt"
# The command (setup, update, status, restore, drop-user-copy).
install -Dm 0755 tools/plasma-fusion "$DESTDIR$PREFIX/bin/plasma-fusion"

# Documentation.
mkdir -p "$dest/plasma-fusion/docs/parts"
install -m 0644 README.md docs/PLAN.md "$dest/plasma-fusion/docs/"
install -m 0644 docs/parts/*.md "$dest/plasma-fusion/docs/parts/"

# Plain permissions everywhere (links keep theirs), executable scripts only in tools/ and libexec.
find "$dest" -type d -exec chmod 0755 {} +
find "$dest" -type f -exec chmod 0644 {} +
find "$dest/plasma-fusion/tools" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod 0755 {} +
find "$libexec" -type f -exec chmod 0755 {} +
