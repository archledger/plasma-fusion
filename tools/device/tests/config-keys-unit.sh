#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of fusion-config.sh's config writes that must keep a user's choice, against a
# throw-away XDG_CONFIG_HOME: the key helpers (read_key, set_key, managed_key), the hot-corner
# step, the on-screen keyboard step and the workspace step are taken out of fusion-config.sh as
# they are and run with the real kreadconfig6 and kwriteconfig6 (KWin's D-Bus calls are stubbed). Test tooling only, not installed; never touches the caller's configuration.
#
#   config-keys-unit.sh BASE
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
# The hot-corner step: from its comment up to the blur settings that follow it.
hot_corner_step() {
  awk '/^# Hot corner: / { on = 1 } on && /Effect-blur/ { exit } on { print }' "$TOOL"
}
LIB=$BASE/lib.sh
{
  grep -m1 '^UNSET=' "$TOOL"
  grep -m1 '^OSK_DESKTOP=' "$TOOL"
  extract note read_key show set_key managed_key upgrade_log keyboard_policy_touch
  echo 'UPGRADE_LOG=()'
} >"$LIB"
# The on-screen keyboard step: from its comment up to the accent pop-up setting that follows it.
osk_step() {
  awk '/^# On-screen keyboard \(TABLET T6\)/ { on = 1 } on && /^# plasma-keyboard \(6\.7 and later\)/ { exit } on { print }' "$TOOL"
}
STEP=$BASE/step.sh
hot_corner_step >"$STEP"
grep -q 'BorderActivate' "$STEP" || { echo "FAIL: the hot-corner step was not found in fusion-config.sh"; exit 1; }

PASS=0 FAIL=0
# CASE DESCRIPTION, PREV_VERSION, HOT_CORNER, the value before (or "unset"), the value wanted
case_hot() {
  local desc=$1 prev=$2 flag=$3 before=$4 want=$5 home got
  home=$BASE/home-$((PASS + FAIL))
  mkdir -p "$home"
  [ "$before" = unset ] || printf '[Effect-overview]\nBorderActivate=%s\n' "$before" >"$home/kwinrc"
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    DRY=0 CHANGES=0 PREV_VERSION=$2 CONFIG_VERSION=2 HOT_CORNER=$3
    . "$4" >/dev/null
    kreadconfig6 --file kwinrc --group Effect-overview --key BorderActivate' _ "$LIB" "$prev" "$flag" "$STEP" 2>/dev/null) || got="(error)"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); echo "PASS $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc: BorderActivate=$got, want $want"
  fi
}

case_hot "first run turns the corner off" 0 0 7 9
case_hot "first run with --hot-corner turns it on" 0 1 unset 7
case_hot "a later run keeps the corner the user turned on" 2 0 7 7
case_hot "a later run keeps more edges the user set" 2 0 "1,7" "1,7"
# An unset key is KWin's default, the top-left corner: System Settings > Screen Edges deletes the
# key when the user turns that corner on.
case_hot "a later run keeps an unset key (KWin's default corner, on)" 2 0 unset ""
case_hot "a later run keeps the corner off" 2 0 9 9
case_hot "--hot-corner turns an off corner on" 2 1 9 7

OSKSTEP=$BASE/osk-step.sh
osk_step >"$OSKSTEP"
grep -q 'InputMethod' "$OSKSTEP" || { echo "FAIL: the on-screen keyboard step was not found in fusion-config.sh"; exit 1; }
# CASE DESCRIPTION, PREV_VERSION, the keyboard policy in the layout file, "live" (plasmashell
# answers with that policy; else it is not running), InputMethod before, InputMethod wanted
OSK=/usr/share/applications/org.kde.plasma.keyboard.desktop
case_osk() {
  local desc=$1 prev=$2 policy=$3 live=$4 before=$5 want=$6 home got
  home=$BASE/home-$((PASS + FAIL))
  mkdir -p "$home"
  printf '[Wayland]\nInputMethod=%s\n' "$before" >"$home/kwinrc"
  printf '[Containments][2][Applets][5]\nplugin=org.plasmafusion.quicksettings\n\n[Containments][2][Applets][5][General]\nkeyboardPolicy=%s\n' \
    "$policy" >"$home/plasma-org.kde.plasma.desktop-appletsrc"
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    DRY=0 CHANGES=0 PREV_VERSION=$2 CONFIG_VERSION=2 CONFIG=$HOME LIVE=$3 POLICY=$4
    bus() { echo "b false"; }
    system_data_path() { return 1; }
    has_name() { [ "$LIVE" = live ]; }
    plasmashell_eval() { if [ "$POLICY" = touch ]; then echo touch; else echo; fi; }
    . "$5" >/dev/null
    kreadconfig6 --file kwinrc --group Wayland --key InputMethod' _ "$LIB" "$prev" "$live" "$policy" "$OSKSTEP" 2>/dev/null) || got="(error)"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); echo "PASS $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc: InputMethod=$got, want $want"
  fi
}
case_osk "laptop posture, policy Tablet mode: the keyboard goes off" 2 tablet live "$OSK" ""
case_osk "laptop posture, policy On touch: the keyboard stays" 2 touch live "$OSK" "$OSK"
case_osk "policy On touch read from the layout file without plasmashell" 2 touch no "$OSK" "$OSK"
case_osk "policy Never: off" 2 never no "$OSK" ""
case_osk "another input method the user chose is kept" 2 tablet live /usr/share/applications/fcitx5.desktop /usr/share/applications/fcitx5.desktop

# The workspace step: from its header up to the shortcuts step that follows it.
workspaces_step() {
  awk '/^# ---------- 2\. virtual desktops ----------/ { on = 1 } on && /^# ---------- 3\. shortcuts/ { exit } on { print }' "$TOOL"
}
WSSTEP=$BASE/workspaces-step.sh
workspaces_step >"$WSSTEP"
grep -q 'createDesktop' "$WSSTEP" || { echo "FAIL: the workspace step was not found in fusion-config.sh"; exit 1; }
# CASE DESCRIPTION, kwinrc [Plugins] plasmafusion-workspacesEnabled (or "unset"), the workspaces
# KWin is asked to create ("position name;" each, empty for none). KWin has Work and Design.
case_ws() {
  local desc=$1 enabled=$2 want=$3 home got
  home=$BASE/home-$((PASS + FAIL))
  mkdir -p "$home/backup"
  [ "$enabled" = unset ] || printf '[Plugins]\nplasmafusion-workspacesEnabled=%s\n' "$enabled" >"$home/kwinrc"
  printf '{"type":"a(uss)","data":[[0,"id-1","Work"],[1,"id-2","Design"]]}\n' >"$home/backup/desktops.json"
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    DRY=0 CHANGES=0 BACKUP=$HOME/backup
    DESKTOP_NAMES=(Work Design Media Chat)
    say() { :; }
    bus_json() { cat "$BACKUP/desktops.json"; }
    bus() {
      case "$*" in
        *" rows") echo "u 1" ;;
        *createDesktop*) shift 5; echo "$2 $3;" >>"$HOME/created" ;;
        *) echo "$*" >>"$HOME/calls" ;;
      esac
    }
    . "$2" >/dev/null
    tr -d "\n" <"$HOME/created" 2>/dev/null || true' _ "$LIB" "$WSSTEP" 2>/dev/null) || got="(error)"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); echo "PASS $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc: created '$got', want '$want'"
  fi
}
case_ws "the missing named workspaces are created" unset "2 Media;3 Chat;"
case_ws "dynamic workspaces off: the same" false "2 Media;3 Chat;"
case_ws "dynamic workspaces on: none is created (the script would remove them again)" true ""

echo "config-keys-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
