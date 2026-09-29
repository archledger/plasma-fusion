#!/bin/bash
# Snapshot the desktop configuration of the user running it, before Plasma Fusion changes it.
#
#   backup-profile.sh [DEST_DIR]      default: ~/.local/state/plasma-fusion/profile-backups
#
# Writes profile-<UTC timestamp>.tar.gz with every config file and data directory Plasma Fusion
# can touch, plus the output of `kscreen-doctor -j` (display scale) and a file list with SHA-256
# sums. Restore with restore-profile.sh <tarball>.
set -euo pipefail
DEST=${1:-$HOME/.local/state/plasma-fusion/profile-backups}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DEST"

CONFIG_FILES=(
  kdeglobals kwinrc kwinrulesrc kglobalshortcutsrc khotkeysrc kcminputrc kxkbrc ksplashrc
  kscreenlockerrc plasmarc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc
  plasma-localerc plasmanotifyrc breezerc klaunchrc kactivitymanagerdrc dolphinrc konsolerc
  katerc kwriterc spectaclerc systemsettingsrc kwinoutputconfig.json knighttimerc
  gtkrc gtkrc-2.0 Trolltech.conf xsettingsd
)
CONFIG_DIRS=(kdedefaults gtk-3.0 gtk-4.0 fontconfig systemd/user/plasma-kwin_wayland.service.d plasma-workspace/env autostart)
DATA_DIRS=(
  color-schemes plasma icons aurorae wallpapers fonts konsole org.kde.syntax-highlighting
  kwin kxmlgui5 plasma-fusion
)

cd "$HOME"
list=()
for f in "${CONFIG_FILES[@]}"; do [ -e ".config/$f" ] && list+=(".config/$f"); done
for d in "${CONFIG_DIRS[@]}"; do [ -e ".config/$d" ] && list+=(".config/$d"); done
for d in "${DATA_DIRS[@]}"; do [ -e ".local/share/$d" ] && list+=(".local/share/$d"); done
[ -e .gtkrc-2.0 ] && list+=(.gtkrc-2.0)

printf '%s\n' "${list[@]}" >"$WORK/paths.txt"
if [ ${#list[@]} -gt 0 ]; then
  find "${list[@]}" -type f -print0 | sort -z | xargs -0 -r sha256sum >"$WORK/sha256sums.txt"
fi
kscreen-doctor -j >"$WORK/kscreen.json" 2>/dev/null || true
{
  echo "created=$STAMP"
  echo "user=$(id -un)"
  echo "host=$(hostname)"
  echo "plasma=$(plasmashell --version 2>/dev/null || true)"
} >"$WORK/info.txt"

tar -czf "$DEST/profile-$STAMP.tar.gz" -C "$HOME" "${list[@]}" -C "$WORK" paths.txt sha256sums.txt kscreen.json info.txt
echo "$DEST/profile-$STAMP.tar.gz"
