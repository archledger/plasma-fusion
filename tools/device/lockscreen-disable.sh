#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Go back to Plasma's own lock screen: removes the plasma-kwin_wayland.service drop-in that
# lockscreen-enable.sh wrote. The shell package itself stays installed (it is inert without
# the drop-in) unless --remove-package is given.
#
#   lockscreen-disable.sh [--dry-run] [--remove-package]
#
# Takes effect after logging out and back in.
set -euo pipefail

ID=org.plasmafusion.lockshell
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
DROPIN_DIR=$CONFIG_HOME/systemd/user/plasma-kwin_wayland.service.d
DROPIN=$DROPIN_DIR/plasma-fusion-lockscreen.conf
PKG=$DATA_HOME/plasma/shells/$ID
DRY=0
REMOVE_PKG=0
for arg in "$@"; do
  case $arg in
    --dry-run) DRY=1 ;;
    --remove-package) REMOVE_PKG=1 ;;
    -h|--help) sed -n '5,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

run() {
  if [ "$DRY" = 1 ]; then echo "would run: $*"; else "$@"; fi
}

if [ -f "$DROPIN" ]; then
  run rm -f "$DROPIN"
  # Drop the directory too when nothing else is in it.
  run rmdir --ignore-fail-on-non-empty "$DROPIN_DIR"
  if [ "$DRY" = 1 ]; then
    echo "would run: systemctl --user daemon-reload"
  else
    systemctl --user daemon-reload 2>/dev/null || echo "note: systemctl --user daemon-reload failed; the change is still read at the next login"
  fi
  echo "Removed $DROPIN"
else
  echo "Not enabled ($DROPIN does not exist)."
fi

if [ "$REMOVE_PKG" = 1 ] && [ -d "$PKG" ]; then
  run rm -rf "$PKG"
  echo "Removed $PKG"
fi

echo "Log out and log back in to return to Plasma's own lock screen."
