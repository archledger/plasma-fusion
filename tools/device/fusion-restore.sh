#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Undo tools/device/fusion-config.sh from one of its backups. Run it inside the same user
# session (terminal, or SSH with the session's DBUS_SESSION_BUS_ADDRESS and XDG_RUNTIME_DIR).
#
#   fusion-restore.sh [BACKUP_DIR] [--latest] [--list] [--dry-run]
#
# Without BACKUP_DIR it uses the newest backup taken while Plasma Fusion was not yet the
# Global Theme, i.e. the state before Plasma Fusion was first configured. --latest takes the
# newest backup of any kind (undo only the last run). --list shows the backups.
#
# It gives the changed shortcuts their old keys back, renames the workspaces and removes the
# ones fusion-config.sh created, puts every backed-up configuration file back (files that did
# not exist are removed, among them the lock-screen drop-in of lockscreen-enable.sh), then
# reloads KWin and restarts plasmashell. The installed Plasma Fusion packages stay installed.
# Log out and back in afterwards so every application, the lock screen and the splash screen
# use the restored settings.
set -euo pipefail

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
DRY=0 PICK=first-foreign BACKUP=
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --latest) PICK=latest ;;
    --list) PICK=list ;;
    -h|--help) sed -n '/^#   fusion-restore.sh/,/^# splash/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) BACKUP=$1 ;;
  esac
  shift
done

die() { printf 'fusion-restore: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then note "would: $*"; else "$@"; fi; }
bus() { busctl --user "$@"; }
bus_json() { busctl --user --json=short "$@"; }

shopt -s nullglob
backups=("$STATE"/backup-*/)
shopt -u nullglob
if [ "$PICK" = list ]; then
  for b in "${backups[@]}"; do
    lnf=$(sed -n 's/^lookandfeel=//p' "$b/info")
    printf '%s  before: %s\n' "${b%/}" "${lnf:-<default>}"
  done
  exit 0
fi
if [ -z "$BACKUP" ]; then
  [ ${#backups[@]} -gt 0 ] || die "no backups in $STATE"
  if [ "$PICK" = latest ]; then
    BACKUP=${backups[-1]}
  else
    for b in "${backups[@]}"; do
      case $(sed -n 's/^lookandfeel=//p' "$b/info") in
        org.plasmafusion.*) ;;
        *) BACKUP=$b ;;
      esac
    done
    [ -n "$BACKUP" ] || BACKUP=${backups[-1]}
  fi
fi
BACKUP=${BACKUP%/}
[ -f "$BACKUP/manifest" ] && [ -f "$BACKUP/info" ] || die "$BACKUP is not a fusion-config.sh backup"
lnf=$(sed -n 's/^lookandfeel=//p' "$BACKUP/info")
echo "Restoring from $BACKUP (Global Theme before: ${lnf:-<default>})"
[ "$DRY" = 1 ] && echo "Dry run: nothing is changed."

# 1. Shortcuts, newest change first, through kglobalaccel (it lives inside KWin and would
#    overwrite a restored kglobalshortcutsrc).
echo "Shortcuts"
if [ -s "$BACKUP/shortcuts" ]; then
  tac "$BACKUP/shortcuts" | while IFS=$'\t' read -r comp action keys; do
    # shellcheck disable=SC2086
    set -- $keys
    note "$comp / $action -> ${keys:-none}"
    run bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setForeignShortcut asai 4 "$comp" "$action" "" "" $# "$@"
  done
fi

# 2. Workspaces: remove the ones fusion-config.sh created, give the others their old names.
echo "Workspaces"
while read -r id; do
  [ -n "$id" ] || continue
  note "remove workspace $id"
  run bus call org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager removeDesktop s "$id"
done <"$BACKUP/created-desktops"
python3 -c '
import json,sys
for d in json.load(open(sys.argv[1]))["data"]:
    print(d[1] + "\t" + d[2])' "$BACKUP/desktops.json" | while IFS=$'\t' read -r id name; do
  note "workspace $id -> \"$name\""
  run bus call org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager setDesktopName ss "$id" "$name"
done
if [ -s "$BACKUP/rows" ]; then
  run bus set-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager rows u "$(cat "$BACKUP/rows")"
fi

# 3. Configuration files. plasmashell writes its layout when it quits, so stop it first.
echo "Configuration files"
SHELL_UNIT=plasma-plasmashell.service
# Use the systemd unit only when it is this session's plasmashell (normal Plasma login).
shell_pid=$(bus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.kde.plasmashell 2>/dev/null | awk '{print $2}')
unit_pid=$(systemctl --user show -p MainPID --value "$SHELL_UNIT" 2>/dev/null || true)
shell_env=()
if [ "$DRY" = 0 ]; then
  if [ -n "$shell_pid" ] && [ "$shell_pid" = "$unit_pid" ]; then
    systemctl --user stop "$SHELL_UNIT"
  else
    SHELL_UNIT=
    # Run from outside the session (SSH, no display), the new shell gets the old one's environment.
    if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && [ -n "$shell_pid" ] && [ -r "/proc/$shell_pid/environ" ]; then
      mapfile -d '' shell_env <"/proc/$shell_pid/environ"
    fi
    kquitapp6 plasmashell >/dev/null 2>&1 || true
  fi
  sleep 2
fi
while read -r state path; do
  case $state in
    present)
      # kglobalshortcutsrc is restored through kglobalaccel above.
      [ "$path" = kglobalshortcutsrc ] && continue
      note "restore ~/.config/$path"
      run rm -rf "${CONFIG:?}/$path"
      run mkdir -p "$(dirname "$CONFIG/$path")"
      run cp -a "$BACKUP/config/$path" "$CONFIG/$path"
      ;;
    absent)
      [ "$path" = kglobalshortcutsrc ] && continue
      if [ -e "$CONFIG/$path" ]; then
        note "remove ~/.config/$path (it did not exist before)"
        run rm -rf "${CONFIG:?}/$path"
      fi
      ;;
    present-home)
      note "restore ~/$path"
      run cp -a "$BACKUP/gtkrc-2.0" "$HOME/$path"
      ;;
    absent-home)
      [ -e "$HOME/$path" ] && { note "remove ~/$path"; run rm -f "${HOME:?}/$path"; }
      ;;
  esac
done <"$BACKUP/manifest"

# 4. Reload.
if [ "$DRY" = 0 ]; then
  if grep -q "plasma-kwin_wayland.service.d/" "$BACKUP/manifest"; then
    rmdir --ignore-fail-on-non-empty "$CONFIG/systemd/user/plasma-kwin_wayland.service.d" 2>/dev/null || true
    # The lock-screen drop-in is read by systemd at the next login.
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  bus call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
  for effect in blur overview; do
    bus call org.kde.KWin /Effects org.kde.kwin.Effects reconfigureEffect s "$effect" >/dev/null 2>&1 || true
  done
  # Palette, style and fonts for running applications.
  dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 2>/dev/null || true
  dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:2 int32:0 2>/dev/null || true
  dbus-send --session --type=signal /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts 2>/dev/null || true
  if [ -n "$SHELL_UNIT" ]; then
    systemctl --user start "$SHELL_UNIT"
  elif [ ${#shell_env[@]} -gt 0 ]; then
    env -i "${shell_env[@]}" setsid -f plasmashell >/dev/null 2>&1 || true
  else
    setsid -f plasmashell >/dev/null 2>&1 || true
  fi
  echo "Restored. Log out and back in to finish."
else
  echo "Dry run finished."
fi
