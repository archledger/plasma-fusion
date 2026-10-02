#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Snapshot the desktop configuration of the user running it, before Plasma Fusion changes it.
#
#   backup-profile.sh [DEST_DIR]      default: ~/.local/state/plasma-fusion/profile-backups
#
# Writes profile-<UTC timestamp>.tar.gz with every config file and data directory Plasma Fusion
# can touch, plus the display layout (kscreen.json from `kscreen-doctor -j`, only when the session's
# display can be reached; ~/.config/kwinoutputconfig.json is always in the tarball) and a file list
# with SHA-256 sums. Restore with restore-profile.sh <tarball>.
#
# Safe over plain SSH: no Qt or KDE program is started without the session's display. The display
# (WAYLAND_DISPLAY and friends) is taken from the running plasmashell of this user's own session
# bus (/run/user/UID/bus unless DBUS_SESSION_BUS_ADDRESS names another); without one, kscreen.json
# says why it is missing. The Plasma version comes from rpm (plasmashell --version offscreen as the
# fallback).
set -euo pipefail
DEST=${1:-$HOME/.local/state/plasma-fusion/profile-backups}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$DEST"
WORK=$(mktemp -d "$DEST/.profile-$STAMP.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

CONFIG_FILES=(
  kdeglobals kwinrc kwinrulesrc kglobalshortcutsrc khotkeysrc kcminputrc kxkbrc ksplashrc
  kscreenlockerrc plasmarc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc
  plasma-localerc plasmanotifyrc breezerc klaunchrc kactivitymanagerdrc dolphinrc konsolerc
  katerc kwriterc spectaclerc systemsettingsrc kwinoutputconfig.json knighttimerc krunnerrc
  plasmafusionrc gtkrc gtkrc-2.0 Trolltech.conf xsettingsd
  systemd/user/plasma-fusion-gate-notify.service systemd/user/plasma-fusion-powerfx.service
  systemd/user/plasma-fusion-pen-garage.service
)
CONFIG_DIRS=(
  kdedefaults gtk-3.0 gtk-4.0 fontconfig libwacom systemd/user/plasma-kwin_wayland.service.d
  systemd/user/graphical-session.target.wants systemd/user/xdg-desktop-autostart.target.wants
  plasma-workspace/env autostart
)
DATA_DIRS=(
  color-schemes plasma icons aurorae wallpapers fonts konsole org.kde.syntax-highlighting
  kwin kxmlgui5 kglobalaccel plasma-fusion
)
HOME_DIRS=(.local/libexec/plasma-fusion)

# The session's display, from the plasmashell on this user's session bus (as fusion-config.sh
# does), so kscreen-doctor can ask the compositor. Never over a display that is not there.
session_display() {
  local bus pid kv
  [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || return 0
  bus=${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus}
  pid=$(DBUS_SESSION_BUS_ADDRESS=$bus timeout 5 busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus GetConnectionUnixProcessID s org.kde.plasmashell 2>/dev/null | awk '{print $2}') || pid=
  [ -n "$pid" ] && [ -r "/proc/$pid/environ" ] || return 1
  while IFS= read -r -d '' kv; do
    case ${kv%%=*} in
      WAYLAND_DISPLAY | DISPLAY | XAUTHORITY | XDG_RUNTIME_DIR | XDG_SESSION_TYPE | QT_QPA_PLATFORM | DBUS_SESSION_BUS_ADDRESS)
        export "${kv?}" ;;
    esac
  done <"/proc/$pid/environ"
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]
}
display_reachable() {
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    case $WAYLAND_DISPLAY in /*) [ -S "$WAYLAND_DISPLAY" ] ;; *) [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/$WAYLAND_DISPLAY" ] ;; esac
  else
    [ -n "${DISPLAY:-}" ]
  fi
}

cd "$HOME"
list=()
for f in "${CONFIG_FILES[@]}"; do [ -e ".config/$f" ] && list+=(".config/$f"); done
for d in "${CONFIG_DIRS[@]}"; do [ -e ".config/$d" ] && list+=(".config/$d"); done
for d in "${DATA_DIRS[@]}"; do [ -e ".local/share/$d" ] && list+=(".local/share/$d"); done
for d in "${HOME_DIRS[@]}"; do [ -e "$d" ] && list+=("$d"); done
[ -e .gtkrc-2.0 ] && list+=(.gtkrc-2.0)

printf '%s\n' "${list[@]}" >"$WORK/paths.txt"
if [ ${#list[@]} -gt 0 ]; then
  find "${list[@]}" -type f -print0 | sort -z | xargs -0 -r sha256sum >"$WORK/sha256sums.txt"
fi
[ -e "$WORK/sha256sums.txt" ] || : >"$WORK/sha256sums.txt"

if session_display && display_reachable && command -v kscreen-doctor >/dev/null; then
  if ! timeout 15 kscreen-doctor -j >"$WORK/kscreen.json" 2>"$WORK/kscreen.err" || [ ! -s "$WORK/kscreen.json" ]; then
    printf '{"error": "kscreen-doctor -j failed: %s"}\n' "$(head -c 200 "$WORK/kscreen.err" | tr -d '"\\\n')" >"$WORK/kscreen.json"
  fi
else
  printf '{"error": "no session display reachable (run inside the Plasma session); see .config/kwinoutputconfig.json"}\n' >"$WORK/kscreen.json"
fi
rm -f "$WORK/kscreen.err"
# Plasma's version from the package database (rpm, pacman, dpkg; upstream version only), else from
# plasmashell itself.
plasma=$(rpm -q --qf '%{VERSION}\n' plasma-workspace 2>/dev/null | head -n 1) || plasma=
case $plasma in '' | *"not installed"*)
  if plasma=$(pacman -Q plasma-workspace 2>/dev/null) && [ -n "$plasma" ]; then
    plasma=${plasma#* }; plasma=${plasma#*:}; plasma=${plasma%-*}
  elif plasma=$(dpkg-query -W -f '${db:Status-Status} ${Version}' plasma-workspace 2>/dev/null) && [[ $plasma == "installed "* ]]; then
    plasma=${plasma#installed }; plasma=${plasma#*:}; plasma=${plasma%-*}
  else
    plasma=$(QT_QPA_PLATFORM=offscreen timeout 15 plasmashell --version 2>/dev/null) || plasma=
  fi ;;
esac
{
  echo "created=$STAMP"
  echo "user=$(id -un)"
  echo "host=$(hostname)"
  echo "plasma=$plasma"
} >"$WORK/info.txt"

tar -czf "$DEST/profile-$STAMP.tar.gz" -C "$HOME" "${list[@]}" -C "$WORK" paths.txt sha256sums.txt kscreen.json info.txt
echo "$DEST/profile-$STAMP.tar.gz"
