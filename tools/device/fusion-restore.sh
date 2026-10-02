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
# It gives the changed shortcuts their old keys back (the Windows-style set of owner decision 6,
# the quick-settings, pen and Meta+N notification keys), renames the workspaces and removes the
# ones fusion-config.sh created, for that backup's run and every later one (each run records only
# what it changed itself), undoes the pen defaults of those runs (tools/pen/pen-defaults.sh
# --restore), stops the user services they started (plasma-fusion-powerfx gives the power-tier
# values back when it stops), tells KWin the on-screen keyboard setting of the backup, puts every
# backed-up file back (the layout with the desktop containment, plasmashellrc, kwinrc with the
# tablet script, fonts.conf and the text-rendering keys, the session env file, the user
# services and their links; files that did not exist are removed, among them the lock-screen
# drop-in of lockscreen-enable.sh), loads the blur effect unless the restored kwinrc turns it
# off, then reloads KWin and restarts plasmashell. The login check (docs/parts/gate.md) is removed
# with its env stub, notify unit and state unless the restored backup had it installed; its log
# stays. The installed Plasma Fusion packages, the Global Theme "My previous desktop" among them,
# stay installed.
# Log out and back in afterwards so every application, the lock screen and the splash screen
# use the restored settings.
set -euo pipefail

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion
CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
GATE_STUB_REL=plasma-workspace/env/plasma-fusion-gate.sh
NOTIFY_COMPONENT=org.plasmafusion.notifications.desktop
HERE=$(cd "$(dirname "$0")" && pwd)
GATE_FILES=("$GATE_STUB_REL" systemd/user/plasma-fusion-gate-notify.service
  systemd/user/xdg-desktop-autostart.target.wants/plasma-fusion-gate-notify.service)
DRY=0 PICK=first-foreign BACKUP=
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --latest) PICK=latest ;;
    --list) PICK=list ;;
    -h|--help) sed -n '/^#   fusion-restore.sh/,/^# use the restored settings/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# Backups taken after this one, newest first. Each run of fusion-config.sh records only the
# shortcuts and workspaces it changed itself (a later run can add one, such as the quick-settings
# Meta+N of a newer fusion-config.sh), and kglobalaccel and KWin keep those whatever files are put
# back, so their records are undone as well.
LATER=()
if [ "$(cd "$(dirname "$BACKUP")" && pwd -P)" = "$(cd "$STATE" 2>/dev/null && pwd -P)" ]; then
  for ((i = ${#backups[@]} - 1; i >= 0; i--)); do
    b=${backups[$i]%/}
    [[ "$(basename "$b")" > "$(basename "$BACKUP")" ]] && LATER+=("$b")
  done
fi
[ ${#LATER[@]} -eq 0 ] || echo "Also undoing the shortcuts and workspaces of ${#LATER[@]} later run(s)"

# 1. Shortcuts, newest change first, through kglobalaccel (it lives inside KWin and would
#    overwrite a restored kglobalshortcutsrc).
echo "Shortcuts"
for b in "${LATER[@]}" "$BACKUP"; do
  [ -s "$b/shortcuts" ] || continue
  tac "$b/shortcuts" | while IFS=$'\t' read -r comp action keys; do
    # shellcheck disable=SC2086
    set -- $keys
    note "$comp / $action -> ${keys:-none}"
    run bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setForeignShortcut asai 4 "$comp" "$action" "" "" $# "$@"
  done
done

# The Meta+N notification component (Windows-style set): its key went back to none above; the
# component goes with its desktop file (restored below when the backup had it).
if ! grep -qx "present-file .local/share/kglobalaccel/$NOTIFY_COMPONENT" "$BACKUP/manifest" &&
  [ -e "$DATA/kglobalaccel/$NOTIFY_COMPONENT" ]; then
  note "$NOTIFY_COMPONENT / _launch: unregistered"
  run bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel unregister ss "$NOTIFY_COMPONENT" _launch >/dev/null 2>&1 || true
fi

# 1b. Pen defaults (fusion-config.sh --pen), newest run first: each pen backup holds the values from
#     before its run; KWin reads them at once (pen-defaults.sh writes them with --notify).
PEN_TOOL=
for f in "$HERE/../pen/pen-defaults.sh" "$(dirname "$HERE")/pen/pen-defaults.sh"; do
  [ -f "$f" ] && { PEN_TOOL=$f; break; }
done
for b in "${LATER[@]}" "$BACKUP"; do
  [ -s "$b/pen-backup" ] || continue
  pb=$(head -n 1 "$b/pen-backup")
  [ -d "$pb" ] || { note "pen: backup $pb is gone (skipped)"; continue; }
  if [ -z "$PEN_TOOL" ]; then
    note "pen: tools/pen/pen-defaults.sh is missing; run it with --restore $pb by hand"
  elif [ "$DRY" = 1 ]; then
    note "would: pen-defaults.sh --restore $pb"
  else
    echo "Pen (from $pb)"
    bash "$PEN_TOOL" --restore "$pb" 2>&1 | sed 's/^/  /' || note "warning: pen-defaults.sh --restore failed"
  fi
done

# 1c. User services the runs started (plasma-fusion-powerfx gives the power-tier values back when
#     it stops: ExecStopPost=... --apply full). Stopped only in this session's own systemd manager;
#     without one, the service's program restores the values directly.
session_manager() {
  local addr
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || return 1
  addr=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
  [ -n "$addr" ] && [ "$addr" = "$DBUS_SESSION_BUS_ADDRESS" ]
}
UNITS=()
for b in "${LATER[@]}" "$BACKUP"; do
  [ -f "$b/services" ] || continue
  while IFS=$'\t' read -r kind unit; do
    [ "$kind" = unit ] && [[ $unit =~ ^plasma-fusion-[a-z-]+\.service$ ]] || continue
    case " ${UNITS[*]} " in *" $unit "*) ;; *) UNITS+=("$unit") ;; esac
  done <"$b/services"
done
for unit in "${UNITS[@]}"; do
  grep -qx "present systemd/user/$unit" "$BACKUP/manifest" && grep -qx "present systemd/user/graphical-session.target.wants/$unit" "$BACKUP/manifest" && continue
  note "stop $unit"
  if session_manager; then
    run systemctl --user stop "$unit" 2>/dev/null || true
  elif [ "$unit" = plasma-fusion-powerfx.service ] && [ -x "$HOME/.local/libexec/plasma-fusion/plasma-fusion-powerfx" ]; then
    run "$HOME/.local/libexec/plasma-fusion/plasma-fusion-powerfx" --apply full || true
  fi
done

# 1d. The on-screen keyboard setting as the backup had it, told to KWin (it follows kwinrc
#     [Wayland] InputMethod only on a notified change; a restored file alone changes nothing).
old_im=$(kreadconfig6 --file "$BACKUP/config/kwinrc" --group Wayland --key InputMethod --default __plasma_fusion_unset__ 2>/dev/null ||
  echo __plasma_fusion_unset__)
cur_im=$(kreadconfig6 --file "$CONFIG/kwinrc" --group Wayland --key InputMethod --default __plasma_fusion_unset__ 2>/dev/null ||
  echo __plasma_fusion_unset__)
if [ "$old_im" != "$cur_im" ]; then
  if [ "$old_im" = __plasma_fusion_unset__ ]; then
    note "kwinrc [Wayland] InputMethod: removed (the system's default keyboard)"
    run kwriteconfig6 --notify --file kwinrc --group Wayland --key InputMethod --delete
  else
    note "kwinrc [Wayland] InputMethod: ${old_im:-<empty>}"
    run kwriteconfig6 --notify --file kwinrc --group Wayland --key InputMethod -- "$old_im"
  fi
fi

# 1e. The on-screen keyboard's terminal keys: Plasma Fusion's layouts out of the data directory, so
#     plasma-keyboard reads its own again (only a directory the tool built; docs/parts/keyboard.md).
if [ -e "$HOME/.local/share/plasma/keyboard/layouts/.plasma-fusion" ] &&
  [ -x "$HOME/.local/libexec/plasma-fusion/plasma-fusion-keyboard-keys" ]; then
  note "on-screen keyboard: plasma-keyboard's own layouts again"
  run "$HOME/.local/libexec/plasma-fusion/plasma-fusion-keyboard-keys" remove || true
  # not "removed on request": a later fusion-config.sh run builds them again
  run rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion/keyboard-keys"
fi

# 1f. Familiar app icons: the drawn icons out of ~/.local/share/icons (any of the user's own icons
#     they replaced come back; docs/parts/app-icons.md). The service was stopped above.
if [ -e "${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion/app-icons.json" ] &&
  [ -x "$HOME/.local/libexec/plasma-fusion/plasma-fusion-app-icons" ]; then
  note "app icons: the familiar icons removed"
  run "$HOME/.local/libexec/plasma-fusion/plasma-fusion-app-icons" remove || true
  run rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion/app-icons.json"
fi

# 2. Workspaces: remove the ones fusion-config.sh created, give the others their old names.
echo "Workspaces"
for b in "${LATER[@]}" "$BACKUP"; do
  [ -f "$b/created-desktops" ] || continue
  while read -r id; do
    [ -n "$id" ] || continue
    note "remove workspace $id"
    run bus call org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager removeDesktop s "$id"
  done <"$b/created-desktops"
done
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
      # -L too: a wants link whose unit was removed a line earlier no longer "exists".
      if [ -e "$CONFIG/$path" ] || [ -L "$CONFIG/$path" ]; then
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
    present-file)
      case $path in /* | *..*) continue ;; esac
      note "restore ~/$path"
      run rm -rf "${HOME:?}/$path"
      run mkdir -p "$(dirname "$HOME/$path")"
      run cp -a "$BACKUP/home/$path" "$HOME/$path"
      ;;
    absent-file)
      case $path in /* | *..*) continue ;; esac
      if [ -e "$HOME/$path" ] || [ -L "$HOME/$path" ]; then
        note "remove ~/$path (it did not exist before)"
        run rm -rf "${HOME:?}/$path"
      fi
      ;;
  esac
done <"$BACKUP/manifest"

# 3b. The login check. Backups made before it existed do not list its files, so it goes whenever
#     the restored state does not have its stub; its records are moot once the files are back.
GATE_REMOVED=0
if ! grep -qx "present $GATE_STUB_REL" "$BACKUP/manifest"; then
  for path in "${GATE_FILES[@]}"; do
    if [ -e "$CONFIG/$path" ] || [ -L "$CONFIG/$path" ]; then
      note "remove ~/.config/$path (login check)"
      run rm -f "${CONFIG:?}/$path"
      GATE_REMOVED=1
    fi
  done
  if [ -d "$DATA/plasma-fusion/gate" ]; then
    note "remove $DATA/plasma-fusion/gate (login check)"
    run rm -rf "${DATA:?}/plasma-fusion/gate"
    GATE_REMOVED=1
  fi
  if [ -d "$STATE/gate" ]; then
    note "remove $STATE/gate (the login check's records; gate.log stays)"
    run rm -rf "${STATE:?}/gate"
    GATE_REMOVED=1
  fi
  if [ "$DRY" = 0 ]; then
    for d in plasma-workspace/env plasma-workspace systemd/user/xdg-desktop-autostart.target.wants; do
      rmdir --ignore-fail-on-non-empty "$CONFIG/$d" 2>/dev/null || true
    done
    [ "$GATE_REMOVED" = 0 ] || printf '%s restore: login check removed by fusion-restore.sh (%s)\n' \
      "$(date +%Y-%m-%dT%H:%M:%S%z)" "$BACKUP" >>"$STATE/gate.log" 2>/dev/null || true
  fi
fi

# 4. Reload.
if [ "$DRY" = 0 ]; then
  if [ "$GATE_REMOVED" = 1 ] || grep -q "plasma-fusion-gate-notify.service" "$BACKUP/manifest"; then
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  if grep -q "plasma-kwin_wayland.service.d/" "$BACKUP/manifest"; then
    rmdir --ignore-fail-on-non-empty "$CONFIG/systemd/user/plasma-kwin_wayland.service.d" 2>/dev/null || true
    # The lock-screen drop-in is read by systemd at the next login.
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  if grep -Eq "^(present|absent) (systemd/user/plasma-fusion-(powerfx|pen-garage)\.service|systemd/user/graphical-session\.target\.wants/)" "$BACKUP/manifest"; then
    session_manager && systemctl --user daemon-reload 2>/dev/null || true
    rmdir --ignore-fail-on-non-empty "$CONFIG/systemd/user/graphical-session.target.wants" 2>/dev/null || true
  fi
  bus call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
  for effect in blur overview; do
    bus call org.kde.KWin /Effects org.kde.kwin.Effects reconfigureEffect s "$effect" >/dev/null 2>&1 || true
  done
  # Directories these runs created and the restore emptied.
  for d in "$CONFIG/fontconfig" "$CONFIG/plasma-workspace/env" "$CONFIG/plasma-workspace" \
    "$CONFIG/systemd/user/graphical-session.target.wants" "$CONFIG/systemd/user" "$CONFIG/systemd" \
    "$DATA/kglobalaccel" "$HOME/.local/libexec"; do
    [ -d "$d" ] && rmdir --ignore-fail-on-non-empty "$d" 2>/dev/null || true
  done
  # The power service unloads blur at critical battery; back on unless the restored kwinrc turns it off.
  if [ "$(kreadconfig6 --file kwinrc --group Plugins --key blurEnabled --default true)" != false ]; then
    bus call org.kde.KWin /Effects org.kde.kwin.Effects loadEffect s blur >/dev/null 2>&1 || true
  fi
  # Text rendering (fonts.conf) for applications started from now on.
  command -v fc-cache >/dev/null && fc-cache >/dev/null 2>&1 || true
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
