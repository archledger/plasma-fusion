#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of fusion-config.sh's config writes that must keep a user's choice, against a
# throw-away XDG_CONFIG_HOME: the key helpers (read_key, set_key, managed_key) and the hot-corner
# step are taken out of fusion-config.sh as they are and run with the real kreadconfig6 and
# kwriteconfig6. Test tooling only, not installed; never touches the caller's configuration.
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
  extract note read_key show set_key managed_key upgrade_log
  echo 'UPGRADE_LOG=()'
} >"$LIB"
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
case_hot "a later run sets an unset corner off" 2 0 unset 9
case_hot "a later run keeps the corner off" 2 0 9 9
case_hot "--hot-corner turns an off corner on" 2 1 9 7

echo "config-keys-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
