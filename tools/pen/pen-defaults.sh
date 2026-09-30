#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion pen defaults (docs/parts/pen.md, spec PEN.md section 2). Run it inside the user's
# session (a terminal, or SSH with the session's DBUS_SESSION_BUS_ADDRESS and XDG_RUNTIME_DIR).
#
#   pen-defaults.sh [--dry-run] [--no-install]
#   pen-defaults.sh --restore BACKUP_DIR
#
# Sets, for the first tablet tool KWin knows (the ThinkPad X13 Yoga Gen 4 "Wacom HID 534D Pen"):
#   - the pen's click button (BTN_STYLUS, evdev 331) gives a right click (kcminputrc
#     [ButtonRebinds][TabletTool][<pen name>] 331=MouseButton,273); unmapped, Qt and GTK treat it
#     as a middle click, which pastes the primary selection;
#   - the pen stays on the built-in panel when an external monitor is connected (KWin D-Bus
#     outputName; KWin stores OutputUuid itself); unmapped, a pen follows the active output;
#   - pen, touchpad and TrackPoint share one pointer (kcminputrc [Tablet] SyncWithMouse=true);
#   - Xournal++ is installed for notes and the whiteboard (dnf, needs sudo; --no-install skips it);
#   - on the X13 Yoga Gen 4 digitizer (056a:534d), which libwacom does not know, a per-user libwacom
#     description (~/.config/libwacom/, read by libinput when KWin adds the device, so from the
#     next login): it names the device and removes the left-handed option, which on a display pen
#     mirrors the pen's position.
# Every setting takes effect at once. Before changing anything it copies kcminputrc and the pen's
# current output, screen mapping and pressure curve to
# ~/.local/state/plasma-fusion/pen-backup-<UTC timestamp>/; --restore puts them back (the Xournal++
# package stays installed).
set -euo pipefail

DRY=0 INSTALL=1 RESTORE=
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --no-install) INSTALL=0 ;;
    --restore) RESTORE=${2:?--restore needs a backup directory}; shift ;;
    -h|--help) sed -n '/^#   pen-defaults.sh/,/^# back (the/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion
CLICK_CODE=331          # BTN_STYLUS
LIBWACOM_NAME=lenovo-x13-yoga-gen4-534d.tablet
LIBWACOM_DEVICE="Wacom HID 534D Pen"
# Checked with libwacom-list-local-devices on the device (PEN.md section 2). No Styli line until hand
# check V1 shows which buttons the pen sends: every isdv4-aes stylus has one button.
libwacom_file() {
  cat <<'TABLET'
# Lenovo ThinkPad X13 Yoga Gen 4 (21F3), integrated Wacom digitizer WACF2200 (i2c 056a:534d)
# Garaged Lenovo Integrated Pen (WG16): eraser tool, click button, 4096 pressure levels, tilt.
# Installed per user by Plasma Fusion (tools/pen/pen-defaults.sh); libwacom 2.19 does not know 534d.
[Device]
Name=Lenovo ThinkPad X13 Yoga Gen 4 Pen
ModelName=WACF2200
DeviceMatch=i2c|056a|534d
Class=ISDV4
Width=286
Height=179
IntegratedIn=Display;System

[Features]
Stylus=true
Reversible=false
Touch=true
NumRings=0
TABLET
}
CLICK_ACTION=MouseButton,273   # BTN_RIGHT
say() { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf 'pen-defaults: %s\n' "$*" >&2; exit 1; }
KWIN=org.kde.KWin
DEV_ROOT=/org/kde/KWin/InputDevice
DEV_IF=org.kde.KWin.InputDevice

busctl --user status "$KWIN" >/dev/null 2>&1 || die "KWin is not running on this session bus"

prop() { # $1 sysName, $2 property: prints the value without the type prefix
  busctl --user get-property "$KWIN" "$DEV_ROOT/$1" "$DEV_IF" "$2" 2>/dev/null | cut -d' ' -f2- | sed 's/^"\(.*\)"$/\1/'
}

# The pen: the first device with tabletTool=true (its sysName is e.g. event7).
PEN='' PEN_NAME=''
for d in $(busctl --user get-property "$KWIN" "$DEV_ROOT" org.kde.KWin.InputDeviceManager devicesSysNames 2>/dev/null | tr -d '"' | cut -d' ' -f3-); do
  if [ "$(prop "$d" tabletTool)" = true ]; then PEN=$d; PEN_NAME=$(prop "$d" name); break; fi
done
# A restore works without the pen too (the keys; the device's own values need it).
[ -n "$PEN" ] || [ -n "$RESTORE" ] || { say "No pen (tablet tool) is known to KWin: nothing to do."; exit 0; }

# The built-in panel: a connected DRM connector named eDP*, LVDS* or DSI* (sysfs, so no Qt tool
# has to run; the connector name without the card prefix is KWin's output name).
INTERNAL=
for c in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-* /sys/class/drm/card*-DSI-*; do
  [ -e "$c/status" ] && [ "$(cat "$c/status")" = connected ] || continue
  INTERNAL=${c##*/}; INTERNAL=${INTERNAL#card*-}; break
done

if [ -n "$RESTORE" ]; then
  [ -f "$RESTORE/keys" ] || die "$RESTORE is not a pen backup"
  say "Restore from $RESTORE"
  # Each line: <unset|set> TAB <group path joined by />, TAB <key> TAB <old value>. Written back with
  # --notify so KWin (button rebinds, SyncWithMouse) picks the old values up at once.
  while IFS=$'\t' read -r state gpath key value; do
    args=()
    IFS=/ read -r -a groups <<<"$gpath"
    for g in "${groups[@]}"; do args+=(--group "$g"); done
    if [ "$state" = unset ]; then
      note "kcminputrc ${gpath} $key: delete"
      kwriteconfig6 --notify --file kcminputrc "${args[@]}" --key "$key" --delete
    else
      note "kcminputrc ${gpath} $key: -> $value"
      kwriteconfig6 --notify --file kcminputrc "${args[@]}" --key "$key" "$value"
    fi
  done <"$RESTORE/keys"
  # The click button and the one-pointer setting may have been changed since, from the pen menu's
  # settings page (PEN.md 3.4): both go back to the backup's kcminputrc copy (deleted when it had
  # none), with --notify so KWin drops a live rebind at once.
  [ -n "$PEN_NAME" ] || PEN_NAME=$(cat "$RESTORE/pen-name" 2>/dev/null || echo "$LIBWACOM_DEVICE")
  for spec in "ButtonRebinds/TabletTool/$PEN_NAME:$CLICK_CODE" "Tablet:SyncWithMouse"; do
    gpath=${spec%:*} key=${spec##*:} args=()
    IFS=/ read -r -a groups <<<"$gpath"
    for g in "${groups[@]}"; do args+=(--group "$g"); done
    old=
    [ ! -f "$RESTORE/kcminputrc" ] || old=$(kreadconfig6 --file "$RESTORE/kcminputrc" "${args[@]}" --key "$key" 2>/dev/null || true)
    cur=$(kreadconfig6 --file kcminputrc "${args[@]}" --key "$key" 2>/dev/null || true)
    [ "$cur" != "$old" ] || continue
    if [ -z "$old" ]; then
      note "kcminputrc $gpath $key: delete"
      kwriteconfig6 --notify --file kcminputrc "${args[@]}" --key "$key" --delete
    else
      note "kcminputrc $gpath $key: -> $old"
      kwriteconfig6 --notify --file kcminputrc "${args[@]}" --key "$key" "$old"
    fi
  done
  if [ -f "$RESTORE/libwacom.absent" ]; then
    note "remove ~/.config/libwacom/$LIBWACOM_NAME (from the next login)"
    rm -f "$CONFIG/libwacom/$LIBWACOM_NAME"
  elif [ -f "$RESTORE/$LIBWACOM_NAME" ]; then
    cp "$RESTORE/$LIBWACOM_NAME" "$CONFIG/libwacom/$LIBWACOM_NAME"
  fi
  if [ -z "$PEN" ]; then
    say "Done (no pen known to KWin now: its screen and pressure settings were left as they are)."
    exit 0
  fi
  old_output=$(cat "$RESTORE/pen-output" 2>/dev/null || true)
  note "pen output: -> ${old_output:-<active screen>}"
  busctl --user set-property "$KWIN" "$DEV_ROOT/$PEN" "$DEV_IF" outputName s "$old_output"
  # The pen menu's settings page can change these two as well (PEN.md 3.4); a backup from before
  # they were recorded gets KWin's defaults (the pen on one screen, linear pressure).
  old_map=$(cat "$RESTORE/pen-map" 2>/dev/null || echo false)
  note "pen on all screens: -> $old_map"
  busctl --user set-property "$KWIN" "$DEV_ROOT/$PEN" "$DEV_IF" mapToWorkspace b "$old_map"
  if [ -f "$RESTORE/pen-pressure" ]; then old_curve=$(cat "$RESTORE/pen-pressure"); else old_curve="0,0;1,1;"; fi
  if [ "$(prop "$PEN" pressureCurve)" != "$old_curve" ]; then
    note "pressure curve: -> ${old_curve:-<default>}"
    busctl --user set-property "$KWIN" "$DEV_ROOT/$PEN" "$DEV_IF" pressureCurve s "$old_curve"
  fi
  say "Done. Xournal++ stays installed (sudo dnf remove xournalpp to remove it)."
  exit 0
fi

say "Pen: $PEN_NAME ($PEN)"
if [ "$DRY" = 0 ]; then
  BACKUP=$STATE/pen-backup-$(date -u +%Y%m%dT%H%M%SZ)
  mkdir -p "$BACKUP"
  [ ! -f "$CONFIG/kcminputrc" ] || cp -a "$CONFIG/kcminputrc" "$BACKUP/kcminputrc"
  : >"$BACKUP/keys"
  prop "$PEN" outputName >"$BACKUP/pen-output"
  prop "$PEN" mapToWorkspace >"$BACKUP/pen-map"
  prop "$PEN" pressureCurve >"$BACKUP/pen-pressure"
  printf '%s\n' "$PEN_NAME" >"$BACKUP/pen-name"
  say "backup: $BACKUP"
fi

set_key() { # $1 group path joined by "/", $2 key, $3 value
  local gpath=$1 key=$2 value=$3 cur args=() groups g
  IFS=/ read -r -a groups <<<"$gpath"
  for g in "${groups[@]}"; do args+=(--group "$g"); done
  cur=$(kreadconfig6 --file kcminputrc "${args[@]}" --key "$key" 2>/dev/null || true)
  if [ "$cur" = "$value" ]; then note "kcminputrc [$gpath] $key = $value (unchanged)"; return; fi
  note "kcminputrc [$gpath] $key: ${cur:-<unset>} -> $value"
  [ "$DRY" = 1 ] && return
  if [ -z "$cur" ]; then
    printf 'unset\t%s\t%s\t\n' "$gpath" "$key" >>"$BACKUP/keys"
  else
    printf 'set\t%s\t%s\t%s\n' "$gpath" "$key" "$cur" >>"$BACKUP/keys"
  fi
  kwriteconfig6 --notify --file kcminputrc "${args[@]}" --key "$key" "$value"
}

set_key "ButtonRebinds/TabletTool/$PEN_NAME" "$CLICK_CODE" "$CLICK_ACTION"
set_key Tablet SyncWithMouse true

cur_output=$(prop "$PEN" outputName)
if [ -z "$INTERNAL" ]; then
  note "no built-in panel found: the pen keeps following the active screen"
elif [ "$cur_output" = "$INTERNAL" ]; then
  note "pen output = $INTERNAL (unchanged)"
else
  note "pen output: ${cur_output:-<active screen>} -> $INTERNAL"
  [ "$DRY" = 1 ] || busctl --user set-property "$KWIN" "$DEV_ROOT/$PEN" "$DEV_IF" outputName s "$INTERNAL"
fi

if [ "$PEN_NAME" = "$LIBWACOM_DEVICE" ]; then
  dest=$CONFIG/libwacom/$LIBWACOM_NAME
  if [ -f "$dest" ] && cmp -s <(libwacom_file) "$dest"; then
    note "libwacom description $dest (unchanged)"
  else
    note "libwacom description $dest (takes effect at the next login)"
    if [ "$DRY" = 0 ]; then
      if [ -f "$dest" ]; then cp -a "$dest" "$BACKUP/"; else : >"$BACKUP/libwacom.absent"; fi
      mkdir -p "$CONFIG/libwacom"
      libwacom_file >"$dest"
    fi
  fi
fi

if [ "$INSTALL" = 1 ]; then
  if rpm -q xournalpp >/dev/null 2>&1; then
    note "Xournal++ installed (unchanged)"
  else
    note "install Xournal++ (sudo dnf install --setopt=install_weak_deps=False xournalpp)"
    # Without weak dependencies: its optional LaTeX tool would pull in about 260 MB of TeX Live.
    [ "$DRY" = 1 ] || sudo dnf install -y --setopt=install_weak_deps=False xournalpp >/dev/null
  fi
fi
[ "$DRY" = 1 ] && say "Dry run: nothing was changed." || say "Done. Undo with: $0 --restore $BACKUP"
