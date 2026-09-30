# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Virtual-session scenario (test tooling): the window shadow on a 200 % screen. One window over
# the desktop, screenshot with and without it (minimized), so shadow-alpha.py can recover the
# shadow's alpha on any background: a = (without - with) / (without - shadow colour).
#
#   PFV_SCALE=2 tools/vsession/remote.sh o1dc-N packages/decoration-cpp/tests/vsession/scenario-hidpi.sh SEED 2880x1800 300
#
# Use the light variant (a bright background keeps the 8-bit screenshots precise).
. "$HOME/pf-deco/params.sh"
# shellcheck source=lib.sh
. "$HOME/pf-deco/lib.sh"
AWAY='move 1420 40'

date "+%Y-%m-%d %H:%M:%S" >"$OUT/start.txt"
fusion_desktop
setdeco RightGlyphs default
systemsettings kcm_colors >"$OUT/systemsettings.log" 2>&1 &
sleep 10
kwinjs <<'JS'
const s = workspace.windowList().find(w => (w.resourceClass || "").indexOf("systemsettings") >= 0);
if (s) { s.frameGeometry = {x: 395, y: 120, width: 650, height: 430}; workspace.activeWindow = s; }
JS
check_plugin
geom hidpi
pfinput "$AWAY" 'sleep 1.5'
shot 01-with-window
kwinjs <<'JS'
const s = workspace.windowList().find(w => (w.resourceClass || "").indexOf("systemsettings") >= 0);
if (s) { s.minimized = true; }
JS
sleep 2
shot 02-without-window
kwinjs <<'JS'
const s = workspace.windowList().find(w => (w.resourceClass || "").indexOf("systemsettings") >= 0);
if (s) { s.minimized = false; workspace.activeWindow = s; }
JS
sleep 2
shot 03-with-window-again
log "done"
