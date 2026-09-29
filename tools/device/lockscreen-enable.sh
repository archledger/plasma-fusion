#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Use the Plasma Fusion lock screen (shell package org.plasmafusion.lockshell) for the user
# running this script, from the next login on.
#
#   lockscreen-enable.sh [--dry-run] [--check]
#
#   --dry-run   print what would be written, change nothing
#   --check     only report whether the lock screen is installed and enabled
#
# How it works: kscreenlocker_greet loads the lock screen QML from the Plasma/Shell package
# named by plasmashellrc [Shell] ShellPackage, whose default is $PLASMA_DEFAULT_SHELL
# (kscreenlocker settings/shell_integration.cpp). On Wayland KWin starts the greeter with
# KWin's own start-up environment (kwin wayland_server.cpp -> KSldApp::setGreeterEnvironment).
# So the variable is set only for KWin, in a drop-in for plasma-kwin_wayland.service:
#
#   ~/.config/systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf
#     [Service]
#     Environment=PLASMA_DEFAULT_SHELL=org.plasmafusion.lockshell
#
# plasmashell does not see it (it reads the variable from its own unit), so the desktop
# layout stays on org.kde.plasma.desktop. Nothing is written to plasmashellrc.
#
# Takes effect after logging out and back in (KWin reads its environment at start).
# Undo: tools/device/lockscreen-disable.sh. If the lock screen ever fails to unlock, unlock
# the session from a TTY or over SSH with: loginctl unlock-session <session id>
set -euo pipefail

ID=org.plasmafusion.lockshell
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
DROPIN_DIR=$CONFIG_HOME/systemd/user/plasma-kwin_wayland.service.d
DROPIN=$DROPIN_DIR/plasma-fusion-lockscreen.conf
DRY=0
CHECK=0
for arg in "$@"; do
  case $arg in
    --dry-run) DRY=1 ;;
    --check) CHECK=1 ;;
    -h|--help) sed -n '5,31p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Find the installed package (user first, then system).
PKG=""
for base in "$DATA_HOME" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
  for dir in ${base//:/ }; do
    if [ -f "$dir/plasma/shells/$ID/contents/lockscreen/LockScreen.qml" ]; then
      PKG=$dir/plasma/shells/$ID
      break 2
    fi
  done
done

CONTENT="[Service]
Environment=PLASMA_DEFAULT_SHELL=$ID
"

shell_package=$(kreadconfig6 --file plasmashellrc --group Shell --key ShellPackage 2>/dev/null || true)

if [ "$CHECK" = 1 ]; then
  echo "package:  ${PKG:-not installed}"
  if [ -f "$DROPIN" ] && grep -q "PLASMA_DEFAULT_SHELL=$ID" "$DROPIN"; then
    echo "enabled:  yes ($DROPIN)"
  else
    echo "enabled:  no"
  fi
  # The unit's Environment= changes with daemon-reload; what counts is the environment the
  # running KWin was started with (its unit's main process, kwin_wayland_wrapper).
  pid=$(systemctl --user show plasma-kwin_wayland.service -p MainPID --value 2>/dev/null || true)
  if [ -n "$pid" ] && [ "$pid" != 0 ] && [ -r "/proc/$pid/environ" ]; then
    if tr '\0' '\n' <"/proc/$pid/environ" | grep -qx "PLASMA_DEFAULT_SHELL=$ID"; then
      echo "active:   yes (the running KWin has it)"
    else
      echo "active:   no (not in the running KWin's environment; a re-login applies a new setting)"
    fi
  else
    echo "active:   unknown (plasma-kwin_wayland.service is not running)"
  fi
  [ -n "$shell_package" ] && echo "note:     plasmashellrc [Shell] ShellPackage=$shell_package overrides PLASMA_DEFAULT_SHELL"
  exit 0
fi

if [ -z "$PKG" ]; then
  echo "error: $ID is not installed (expected $DATA_HOME/plasma/shells/$ID); install the Plasma Fusion build first" >&2
  exit 1
fi
python3 -c 'import json, sys; m = json.load(open(sys.argv[1])); assert m["KPackageStructure"] == "Plasma/Shell" and int(m["X-Plasma-APIVersion"]) >= 2' \
  "$PKG/metadata.json" || { echo "error: $PKG/metadata.json is not a valid Plasma/Shell package" >&2; exit 1; }

if [ -n "$shell_package" ] && [ "$shell_package" != "$ID" ]; then
  echo "warning: plasmashellrc [Shell] ShellPackage=$shell_package is set; it takes precedence over"
  echo "         PLASMA_DEFAULT_SHELL, so the lock screen will stay $shell_package's until that key is removed."
fi

if [ "$DRY" = 1 ]; then
  echo "would write $DROPIN:"
  printf '%s' "$CONTENT" | sed 's/^/  /'
  echo "would run: systemctl --user daemon-reload"
  exit 0
fi

mkdir -p "$DROPIN_DIR"
tmp=$(mktemp "$DROPIN_DIR/.plasma-fusion-lockscreen.XXXXXX")
printf '%s' "$CONTENT" >"$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$DROPIN"
systemctl --user daemon-reload 2>/dev/null || echo "note: systemctl --user daemon-reload failed; the drop-in is still read at the next login"

echo "Plasma Fusion lock screen enabled ($PKG)."
echo "Wrote $DROPIN"
echo "Log out and log back in for it to take effect (KWin starts the lock screen with its own environment)."
