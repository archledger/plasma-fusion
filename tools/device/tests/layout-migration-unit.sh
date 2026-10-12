#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of fusion-config.sh's in-place layout migration (migrate_layout, the step every later
# run uses on an existing Plasma Fusion layout), against a throw-away XDG_CONFIG_HOME: the function
# and its helpers are taken out of fusion-config.sh as they are and run with the real kreadconfig6
# and kwriteconfig6. Checks that a HOME an earlier release already brought to configuration
# version 2 keeps what the user changed since (the top bar's opacity, tray items shown, the pen
# menu, the desktop) and so needs no migration and no plasmashell restart, while a HOME from before
# version 2 is still migrated; and that the trays' Disks & Devices step runs once. Test tooling
# only, not installed; never touches the caller's configuration.
#
#   layout-migration-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HERE/../fusion-config.sh
rm -rf "${BASE:?}"
mkdir -p "$BASE"

# The functions, by name: a one-line "NAME() { ...; }", or from "NAME() {" to the first "}" at
# the start of a line.
extract() {
  local name
  for name in "$@"; do
    awk -v n="$name" '
      $0 ~ "^" n "\\(\\) \\{" { on = 1; print; if ($0 ~ /\}[[:space:]]*$/) exit; next }
      on { print } on && /^}/ { exit }' "$TOOL"
  done
}
LIB=$BASE/lib.sh
{
  grep -m1 '^PEN_WIDGET=' "$TOOL"
  grep -m1 '^DESKTOP_CONTAINMENT=' "$TOOL"
  awk '/^FOLDER_KEYS=\(/ { on = 1 } on { print } on && /\)$/ { exit }' "$TOOL"
  awk '/^FOLDER_PREVIEWS=\(/ { on = 1 } on { print } on && /\)$/ { exit }' "$TOOL"
  awk '/^TRAY_HIDE=\(/ { on = 1 } on { print } on && /\)$/ { exit }' "$TOOL"
  extract note installed_previews migrate_layout layout_needs_migration
} >"$LIB"
grep -q '^migrate_layout() {' "$LIB" || { echo "FAIL: migrate_layout was not found in fusion-config.sh"; exit 1; }

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }

# A Plasma Fusion layout as a run of an earlier release leaves it, then changed by the user as the
# case says: desktop 1, top bar 2 (app name 3, tray 4, quick settings 5, pen 6), dock 7.
# CASE NAME PREV_VERSION [OPTION...]: opacity2 (panelOpacity 2), solidoff ([TopBar]
# SolidNextToWindows=false), printers (the user set Printers to "Always shown": out of both lists),
# nopen (the pen menu removed), folder (the desktop is a plain Folder View), devices (Disks &
# Devices turned on again in the tray), marked ([Setup] TrayDevices=done). Leaves $H and $OUT
# (the dry run's notes) and $NEEDS (yes/no: layout_needs_migration).
make_case() {
  local name=$1 prev=$2 o hidden desktop=org.plasmafusion.desktop extra="" pen=1
  shift 2
  H=$BASE/$name
  mkdir -p "$H"
  hidden=org.kde.plasma.vault,org.kde.plasma.devicenotifier,org.kde.kscreen,org.kde.plasma.printmanager,org.kde.plasma.manage-inputmethod
  for o in "$@"; do
    case $o in
      printers) hidden=${hidden/org.kde.plasma.printmanager,/} ;;
      nopen) pen=0 ;;
      folder) desktop=org.kde.plasma.folder ;;
      devices) extra=org.kde.plasma.devicenotifier ;;
    esac
  done
  {
    printf '[Containments][1]\nplugin=%s\n\n' "$desktop"
    printf '[Containments][2]\nlocation=3\nplugin=org.kde.panel\n\n'
    printf '[Containments][2][Applets][3]\nplugin=org.plasmafusion.appname\n\n'
    printf '[Containments][2][Applets][4]\nplugin=org.kde.plasma.systemtray\n\n'
    printf '[Containments][2][Applets][4][General]\ndisabledStatusNotifiers=%s\nextraItems=%s\nhiddenItems=%s\nknownItems=org.kde.plasma.devicenotifier\n\n' \
      "$hidden" "$extra" "$hidden"
    printf '[Containments][2][Applets][5]\nplugin=org.plasmafusion.quicksettings\n\n'
    [ "$pen" = 0 ] || printf '[Containments][2][Applets][6]\nplugin=org.plasmafusion.pen\n\n'
    printf '[Containments][2][General]\nAppletOrder=3;4;%s5\n\n' "$([ "$pen" = 0 ] || echo '6;')"
    printf '[Containments][7]\nlocation=4\nplugin=org.kde.panel\n'
  } >"$H/plasma-org.kde.plasma.desktop-appletsrc"
  if printf '%s\n' "$@" | grep -qx opacity2; then
    printf '[PlasmaViews][Panel 2]\npanelOpacity=2\n' >"$H/plasmashellrc"
  fi
  : >"$H/plasmafusionrc"
  printf '%s\n' "$@" | grep -qx solidoff && printf '[TopBar]\nSolidNextToWindows=false\n' >>"$H/plasmafusionrc"
  printf '%s\n' "$@" | grep -qx marked && printf '[Setup]\nTrayDevices=done\n' >>"$H/plasmafusionrc"
  run() { # DRY
    env -i PATH="$PATH" HOME="$H" XDG_CONFIG_HOME="$H" bash -c '
      set -euo pipefail
      package_dir() { return 0; }
      . "$1"
      CONFIG=$HOME DRY=$3 CHANGES=0 PREV_VERSION=$2
      migrate_layout "" || exit 1
      if layout_needs_migration ""; then echo "NEEDS yes"; else echo "NEEDS no"; fi' _ "$LIB" "$prev" "$1" 2>&1
  }
  OUT=$(run 1) || { fail "$name: the migration failed: $OUT"; OUT=; }
  NEEDS=$(printf '%s\n' "$OUT" | sed -n 's/^NEEDS //p')
}
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
expect() { # DESCRIPTION CONDITION...
  local d=$1; shift
  if "$@"; then pass "$d"; else fail "$d"; printf '%s\n' "$OUT" | sed 's/^/    /'; fi
}

# ---- version 2 (0.2.0 to 0.4.x ran the migration already): the user's changes stay
make_case kcm-translucent 2 opacity2 solidoff
expect "v2: the settings page's translucent top bar is kept" has "top bar opacity: translucent (kept)"
expect "v2: nothing to migrate, so no plasmashell restart" [ "$NEEDS" = no ]
make_case translucent-by-hand 2 opacity2
expect "v2: a translucent top bar is the user's (no page key either)" has "top bar opacity: translucent (kept)"
make_case printers 2 printers marked
expect "v2: Printers set to \"Always shown\" stays out of the hidden lists" has "org.kde.plasma.printmanager left out (kept: the user's)"
expect "  and nothing to migrate" [ "$NEEDS" = no ]
make_case nopen 2 nopen marked
expect "v2: the pen menu the user removed is not added again" has "pen widget not in the top bar (kept: the user's)"
expect "  and nothing to migrate" [ "$NEEDS" = no ]
make_case folder 2 folder marked
expect "v2: a desktop the user switched to Folder View stays" has "desktop 1: org.kde.plasma.folder (kept: the user's)"
make_case all-kept 2 opacity2 solidoff printers nopen folder devices marked
expect "v2 with every change: no migration at all" [ "$NEEDS" = no ]

# ---- Disks & Devices (0.4.0): once
make_case devices-first 2 devices
expect "Disks & Devices: the first run takes it out of the tray's extra items" has "extraItems: org.kde.plasma.devicenotifier -> "
make_case devices-again 2 devices marked
expect "Disks & Devices: turned on again after that run, it stays" has "Disks & Devices: as the user has it (kept)"
expect "  and nothing to migrate" [ "$NEEDS" = no ]

# ---- before version 2 (no FusionConfigVersion yet): migrated
make_case old 1 opacity2 printers nopen folder
expect "v1: the earlier layout's translucent becomes adaptive" has "panelOpacity: 2 -> 0"
expect "v1: the hidden tray items are completed" has "hiddenItems: org.kde.plasma.vault"
expect "v1: the pen menu is added" has "plugin: <unset> -> org.plasmafusion.pen"
expect "v1: the desktop becomes the Plasma Fusion desktop" has "plugin: org.kde.plasma.folder -> org.plasmafusion.desktop"
make_case old-kcm 1 opacity2 solidoff
expect "v1: a translucent bar the settings page chose is kept" has "top bar opacity: translucent (kept)"

# ---- a real run writes what the dry run said
make_case write 1 opacity2
env -i PATH="$PATH" HOME="$H" XDG_CONFIG_HOME="$H" bash -c 'set -euo pipefail; package_dir() { return 0; }; . "$1"
  CONFIG=$HOME DRY=0 CHANGES=0 PREV_VERSION=1; migrate_layout "" >/dev/null' _ "$LIB"
got=$(env -i PATH="$PATH" HOME="$H" XDG_CONFIG_HOME="$H" kreadconfig6 --file plasmashellrc --group PlasmaViews --group "Panel 2" --key panelOpacity)
expect "v1, real run: panelOpacity written as 0" [ "$got" = 0 ]

echo "layout-migration-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
