#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of fusion-config.sh's desktop scripts that read the panels (fusion_layout_present,
# top_panel_ids, fix_panel_thickness) and of what --screens reads from ensure-topbars.js's answer
# (layout_made_widgets), taken out of fusion-config.sh as they are and run against
# scripting_model.js, a model of plasmashell's desktop scripting, instead of plasmashell. The
# layouts have a top bar of a monitor that was unplugged, still on its missing screen as Plasma
# 6.8 keeps it: reading its length mode, floating or height crashes plasmashell, and the model.
# Needs node. Test tooling only, not installed.
#
#   panel-scripts-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HERE/../fusion-config.sh
command -v node >/dev/null || { echo "panel-scripts-unit: node is needed" >&2; exit 2; }
rm -rf "${BASE:?}"
mkdir -p "$BASE"

# The functions, by name: from "NAME() {" to the "}" at the start of a line that a blank line
# follows (their desktop scripts have braces at the start of lines too, and no blank lines).
extract() {
  local name
  for name in "$@"; do
    awk -v n="$name" '$0 ~ "^" n "\\(\\) \\{" { on = 1 } on && $0 == "" && last ~ /^}/ { exit } on { print; last = $0 }' "$TOOL"
  done
}
LIB=$BASE/lib.sh
{
  extract fusion_layout_present top_panel_ids fix_panel_thickness layout_made_widgets
  # The shell is plasmashell's stand-in; the session is in laptop posture.
  echo 'has_name() { return 0; }'
  echo 'bus() { echo "b false"; }'
  # shellcheck disable=SC2016 # expanded where the library is sourced
  echo 'plasmashell_eval() { node "$MODEL" "$LAYOUT" "$1" 2>>"$LAYOUT.log" || true; }'
  echo 'layout_present() { if fusion_layout_present; then echo yes; else echo no; fi; }'
} >"$LIB"
grep -q 'fix_panel_thickness()' "$LIB" || { echo "FAIL: the functions were not found in fusion-config.sh"; exit 1; }

PASS=0 FAIL=0
# CASE DESCRIPTION LAYOUT_JSON FUNCTION WANTED: FUNCTION of the library runs; its output must be
# WANTED and the stand-in shell must not have crashed.
case_run() {
  local desc=$1 layout=$2 command=$3 want=$4 file got
  file=$BASE/layout-$((PASS + FAIL)).json
  printf '%s\n' "$layout" >"$file"
  got=$(MODEL=$HERE/scripting_model.js LAYOUT=$file bash -c '. "$1"; "$2"' _ "$LIB" "$command" 2>&1) || true
  if [ "$got" = "$want" ] && ! grep -q crashed "$file.log" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "PASS $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc: got '$got', want '$want'; shell: $(cat "$file.log" 2>/dev/null)"
  fi
}

TOP='{"id": 2, "screen": 0, "location": "top", "lengthMode": "fill", "floating": false, "height": 30}'
DOCK='{"id": 3, "screen": 0, "location": "bottom", "lengthMode": "fit", "floating": true, "height": 72}'
GONE='{"id": 9, "screen": 1, "location": "top", "lengthMode": "fill", "floating": false, "height": 30}'
FONT='"font": "Noto Sans,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"'
SIX_EIGHT="{\"screens\": 1, $FONT, \"panels\": [$TOP, $DOCK, $GONE]}"
SIX_SEVEN="{\"screens\": 1, $FONT, \"panels\": [$TOP, $DOCK, {\"id\": 9, \"screen\": -1, \"location\": \"top\", \"lengthMode\": \"fill\", \"height\": 30}]}"

case_run "6.8, a bar without a screen: the Fusion layout is found" "$SIX_EIGHT" \
  layout_present yes
case_run "6.8, a bar without a screen: the top bars on the screens" "$SIX_EIGHT" top_panel_ids 2
case_run "6.8, a bar without a screen: the bar on the screen is sized" "$SIX_EIGHT" fix_panel_thickness "set top bar 34"
case_run "6.7, a bar on screen -1: the Fusion layout is found" "$SIX_SEVEN" \
  layout_present yes
case_run "no screen at all: no layout, no crash" "{\"screens\": 0, \"panels\": [$TOP, $DOCK]}" \
  layout_present no
case_run "the stock layout is not taken for Fusion's" \
  "{\"screens\": 1, \"panels\": [{\"id\": 1, \"screen\": 0, \"location\": \"bottom\", \"lengthMode\": \"fill\", \"floating\": true, \"height\": 44}]}" \
  layout_present no

# What --screens reads from ensure-topbars.js's answer: new widgets, which the power service gives
# its tier only when it applies it again.
made() { # DESCRIPTION WANTED(yes|no) TEXT
  local got=no
  if bash -c '. "$1"; layout_made_widgets "$2"' _ "$LIB" "$3"; then got=yes; fi
  if [ "$got" = "$2" ]; then PASS=$((PASS + 1)); echo "PASS $1"; else FAIL=$((FAIL + 1)); echo "FAIL $1: got $got"; fi
}
made "--screens: a top bar made asks the power service" yes $'top bars: screens 2, added 1, completed 0\ndocks: one'
made "  a top bar completed too" yes $'top bars: screens 2, added 0, completed 1\ndocks: one'
made "  a dock made too (Dock on every screen)" yes $'top bars: screens 2, added 0, completed 0\ndocks: screens 2, added 1'
made "  nothing made: no" no $'top bars: screens 2, added 0, completed 0\ndocks: screens 2, added 0, not made 1'
made "  the layout not loaded: no" no 'top bars: skipped, the layout is not loaded yet'

echo "panel-scripts-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
