#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# The home screen's pin request is cleared for good (docs/parts/apppairs.md). The helper's save
# writes pinRequest through plasmashell's desktop scripting; when that script ends Plasma reads the
# applet's settings back from disk (plasma-workspace 6.7 Widget::~Widget -> reloadConfig ->
# Applet::configChanged -> KConfigLoader::load), and a clear the home screen made while the script
# ran is dropped: the pair is pinned, but the request stays there and is taken again at the next
# shell start. The home screen's layer loads in tablet posture.
#   1. the helper's save pins the pair on the home screen;
#   2. taken, the request leaves nothing behind in any home screen's settings;
#   3. no QML errors from the home screen or its pairs;
#   4. nothing of it is stored once the shell has quit.
# Run: tools/vsession/remote.sh pr-1 packages/apppairs/tests/vsession/scenario-pinreq.sh SEED 1440x900 300
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
A=$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
# What every home screen's settings hold for pinRequest: one "desktop ID screen N pinRequest
# 'VALUE'" line per home screen; nothing at all means no home screen answered.
live() {
  evaljs - 2>>"$OUT/errors.log" <<'JS'
desktops().forEach(function (d) { d.currentConfigGroup = ["General"];
  print("desktop " + d.id + " screen " + d.screen + " pinRequest '" + d.readConfig("pinRequest", "") + "'\n"); });
JS
}
# The non-empty pinRequest values stored on disk.
stored() { grep -a '^pinRequest=' "$A" | sed 's/^pinRequest=//' | grep -v '^$' || true; }

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || info "fusion-config rc=$?"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-tablet --key InternalOutputs "eDP,LVDS,DSI,Virtual"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion 99
pfv_restart_shell 12
pfv_tablet on; sleep 8
# ---- 1. the helper's save pins the pair on the home screen
id=$("$HOME/.local/libexec/plasma-fusion/plasma-fusion-app-pair" save org.kde.dolphin.desktop org.kde.kwrite.desktop 0.5 2>>"$OUT/helper.log" || true)
sleep 6
if [ -n "$id" ] && grep -aq "home: pair: pin applications:$id" "$PLOG"; then
  pass "1: the home screen pinned $id"
else
  fail "1: the home screen did not pin applications:$id"
fi

# ---- 2. taken, the request leaves nothing behind in any home screen's settings
raw=$(live || true)
if [ -z "$raw" ]; then
  fail "2: no home screen answered"
else
  left=$(sed -n "s/.*pinRequest '\(.*\)'$/\1/p" <<<"$raw" | grep -v '^$' | tr '\n' ' ' || true)
  if [ -z "${left// }" ]; then
    pass "2: the taken request leaves nothing behind"
  else
    fail "2: the request is still in the settings: '$left'"
  fi
fi

# ---- 3. no QML errors from the home screen or its pairs (before the shell quits below)
errs=$( { grep -aE 'HomeLayer.qml|FusionPairTile.qml|FusionPairs\.js' "$PLOG" || true; } | grep -aiE 'error|TypeError|ReferenceError|is not defined|Cannot' || true)
if [ -z "$errs" ]; then pass "3: no QML errors from the home screen or its pairs"; else fail "3: QML: $(echo "$errs" | head -3 | tr '\n' ' ')"; fi

# ---- 4. nothing of it is stored once the shell has quit (its settings are written back then).
# The session is disposable and ends here with the shell down.
kquitapp6 plasmashell >/dev/null 2>&1 || true
sleep 4
left=$(stored | tr '\n' ' ' || true)
if [ -z "${left// }" ]; then
  pass "4: nothing of the request is stored after the shell quit"
else
  fail "4: the request is still stored after the shell quit: '$left'"
fi
info "done"
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
