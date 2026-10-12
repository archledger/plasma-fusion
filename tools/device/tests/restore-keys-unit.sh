#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of fusion-restore.sh's widget shortcuts step (3a): a widget's "activate widget N" key
# that kglobalaccel keeps after the widget is gone (given by the settings module's "Reset Fusion
# layout", or left by a layout rebuild) is released when the restored layout has no widget N, and a
# live widget's key is kept. The step is taken out of fusion-restore.sh as it is and run against a
# fake kglobalaccel (copytext_fakebus.py) in a throw-away HOME. Test tooling only, not installed.
#
#   restore-keys-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
RESTORE=$HERE/../fusion-restore.sh
rm -rf "${BASE:?}"
mkdir -p "$BASE"
STEP=$BASE/step.sh
awk '/^# 3a\. Widget shortcuts/ { on = 1 } /^# 3b\. / { exit } on { print }' "$RESTORE" >"$STEP"
grep -q 'activate widget' "$STEP" || { echo "FAIL: the widget shortcuts step was not found in fusion-restore.sh"; exit 1; }

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
META_A=$((0x10000000 + 0x41)) META_SHIFT_W=$((0x10000000 + 0x02000000 + 0x57)) ALT_F1=$((0x08000000 + 0x01000030))
# CASE NAME DRY: the restored layout has the stock Kickoff (widget 3); kglobalaccel still has the
# keys of the Fusion layout's quick settings (41) and pen menu (42), given by the settings module.
run_case() {
  CASE=$BASE/$1
  mkdir -p "$CASE/config" "$CASE/backup/config"
  printf '[Containments][1]\nplugin=org.kde.panel\n\n[Containments][1][Applets][3]\nplugin=org.kde.plasma.kickoff\n' \
    >"$CASE/backup/config/plasma-org.kde.plasma.desktop-appletsrc"
  printf 'present plasma-org.kde.plasma.desktop-appletsrc\n' >"$CASE/backup/manifest"
  # a real restore has put the file back by now
  [ "$2" = 1 ] || cp "$CASE/backup/config/plasma-org.kde.plasma.desktop-appletsrc" "$CASE/config/"
  printf '{"keys": {"plasmashell|activate widget 3": [%s], "plasmashell|activate widget 41": [%s], "plasmashell|activate widget 42": [%s], "plasmashell|show-on-mouse-pos": []}}\n' \
    "$ALT_F1" "$META_A" "$META_SHIFT_W" >"$CASE/state.json"
  env -i PATH="/usr/bin:/bin" HOME="$CASE" FAKE_STATE="$CASE/state.json" FAKEBUS="$HERE/copytext_fakebus.py" bash -c '
    set -euo pipefail
    bus() { python3 "$FAKEBUS" "$FAKE_STATE" plain "$@"; }
    note() { printf "  %s\n" "$*"; }
    run() { if [ "$DRY" = 1 ]; then note "would: $*"; else "$@"; fi; }
    DRY=$2 CONFIG=$HOME/config BACKUP=$HOME/backup
    . "$1"' _ "$STEP" "$2" >"$CASE/out.log" 2>&1 || bad "$1: the step failed: $(cat "$CASE/out.log")"
}
unregistered() { python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1])).get("unregistered", []))))' "$CASE/state.json"; }

run_case restore 0
[ "$(unregistered)" = "plasmashell|activate widget 41 plasmashell|activate widget 42" ] &&
  ok "the quick settings and pen keys of widgets the restored layout lacks are released" || bad "released: $(unregistered)"
grep -q 'activate widget 41: unregistered' "$CASE/out.log" && ok "  and the restore says so" || bad "  notes: $(cat "$CASE/out.log")"
run_case dry 1
[ -z "$(unregistered)" ] && grep -q 'activate widget 42: unregistered' "$CASE/out.log" && ! grep -q 'activate widget 3:' "$CASE/out.log" &&
  ok "a dry run says what it would release (from the backup's layout) and releases nothing" || bad "dry run: $(unregistered) / $(cat "$CASE/out.log")"

echo "restore-keys-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
