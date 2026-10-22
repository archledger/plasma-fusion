#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# An update in a running session (the snap script of 0.5.0 loaded at login, without "Snap
# Left/Right"), in a private session with real keys (pfinput): the Fusion setup installs the new
# script over it and loads it again, then
#   1. the setup says it loaded the new script, and "Plasma Fusion: Snap Left" is registered with
#      Meta+Left;
#   2. Meta+Left twice gives the left third: the new script runs (0.5.0 has no thirds, and KWin's
#      quick tile gives none).
# KWin 6.7.5 keeps what its QML engine compiled by the file's path, so the script started again
# from where it was is the older one (the setup's snap_script_reload).
# The seed: tools/tests/lib/common.sh make_seed, plus the 0.5.0 script as released (from the
# plasma-fusion-0.5.0 package's /usr/share/kwin/scripts/plasmafusion-snap: the build generates its
# ensureTopBars.js) in ~/.local/share/kwin/scripts/plasmafusion-snap and kwinrc [Plugins]
# plasmafusion-snapEnabled=true.
# Run: tools/vsession/remote.sh sr-1 packages/kwin/tests/vsession/scenario-snapreload.sh SEED 1440x900 300
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
kwin_actions() {
  busctl --user --json=short call org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component shortcutNames 2>/dev/null || true
}
# The active window touches the left edge, spans the area's height and is SHARE of its width.
left_share() {
  local w
  w=$(K run "var c = workspace.activeWindow, g = c ? c.frameGeometry : null;
    var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
    report(g ? [g.x, g.y, g.width, g.height, a.x, a.y, a.width, a.height].join(' ') : '');" | tr -d '"')
  info "$1: $w"
  python3 - "$w" "$2" <<'PY'
import sys
x, y, w, h, ax, ay, aw, ah = (float(v) for v in sys.argv[1].split())
share = eval(sys.argv[2])
sys.exit(0 if abs(x - ax) <= 8 and h >= ah * 0.9 and abs(w / aw - share) <= 0.03 else 1)
PY
}

# ---- before: the 0.5.0 script runs, without Snap Left
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap)
if [ "$loaded" = true ] && kwin_actions | grep -q '"Plasma Fusion: Activate Dock Entry 1"' &&
  ! kwin_actions | grep -q '"Plasma Fusion: Snap Left"'; then
  pass "before: the 0.5.0 snap script runs (its dock entries), without Snap Left"
else
  fail "before: loaded=$loaded, actions $(kwin_actions | grep -o '"Plasma Fusion: Snap[^"]*"' | tr '\n' ' ')"
fi

# ---- the update: the setup installs the new script over it
kwriteconfig6 --file kwinrc --group Script-plasmafusion-snap --key LegacyWidthCycle true
fc_rc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc_rc=$?
info "fusion-config rc=$fc_rc"
grep -a "snap sizes" "$OUT/fc.log" | sed 's/^/INFO setup: /' >>"$CHK" || true
if grep -aq "snap sizes: the running snap script is an older one (loaded again from the installed files)" "$OUT/fc.log" &&
  ! grep -aq "snap sizes: the snap KWin script's actions are not registered" "$OUT/fc.log"; then
  pass "1: the setup loaded the new script again"
else
  fail "1: the setup did not load the new script"
fi
keys=$(busctl --user --json=short call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel shortcut \
  as 4 kwin "Plasma Fusion: Snap Left" "" "" 2>/dev/null || true)
info "Snap Left keys: $keys"
# Meta+Left: Qt's Meta (0x10000000) + Key_Left (0x01000012).
if printf '%s' "$keys" | grep -q "$((0x10000000 + 0x01000012))"; then
  pass "1: Snap Left is registered with Meta+Left"
else
  fail "1: Snap Left has no Meta+Left ($keys)"
fi

# ---- 2. Meta+Left twice: the left third
pfinput 'move 1400 520'
kwrite >/dev/null 2>&1 &
sleep 4
K run "var c = workspace.activeWindow; if (c) { if (c.tile) { c.tile.unmanage(c); } c.frameGeometry = {x: 300, y: 200, width: 700, height: 500}; } report(!!c);" >/dev/null
sleep 1
pfinput "key meta+left"
sleep 1.2
pfinput "key meta+left"
sleep 1.2
if left_share "2: Meta+Left twice" 1/3; then pass "2: Meta+Left twice: the left third (the new script runs)"
else fail "2: Meta+Left twice did not give the left third"; fi
shot 20-third
info "done"
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
