# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Virtual-session scenario (test tooling): 40 px title bars on a screen under 800 px high
# (ADAPTIVE.md 5.12), following rotation and tablet mode:
#
#   tools/vsession/remote.sh o1dc-N packages/decoration-cpp/tests/vsession/scenario-short.sh SEED 1366x768 300
#
# kwin.log: PFCXGEOM title heights (40 on 1366x768, 50 after rotating to portrait, 40 back, 44 in
# tablet mode) and the decoration's layout lines.
. "$HOME/pf-deco/params.sh"
# shellcheck source=lib.sh
. "$HOME/pf-deco/lib.sh"
AWAY='move 1300 700'

date "+%Y-%m-%d %H:%M:%S" >"$OUT/start.txt"
fusion_desktop
setdeco RightGlyphs default
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
systemsettings kcm_colors >"$OUT/systemsettings.log" 2>&1 &
sleep 10
kwinjs <<'JS'
function find(c) { return workspace.windowList().find(w => w.normalWindow && (w.resourceClass || "").toLowerCase().indexOf(c) >= 0); }
const d = find("dolphin"), s = find("systemsettings");
if (d) { d.frameGeometry = {x: 40, y: 60, width: 640, height: 420}; }
if (s) { s.frameGeometry = {x: 560, y: 180, width: 650, height: 480}; workspace.activeWindow = s; }
JS
check_plugin
geom short-start
pfinput "$AWAY" 'sleep 0.8'
shot 01-short-1366x768
kwinjs <<'JS'
const s = workspace.windowList().find(w => (w.resourceClass || "").indexOf("systemsettings") >= 0);
if (s) { s.setMaximize(true, true); }
JS
sleep 1
geom short-maximized
shot 02-short-maximized
kwinjs <<'JS'
const s = workspace.windowList().find(w => (w.resourceClass || "").indexOf("systemsettings") >= 0);
if (s) { s.setMaximize(false, false); }
JS
sleep 1

output=$(kscreen-doctor -j | python3 -c 'import json, sys; print(json.load(sys.stdin)["outputs"][0]["name"])')
log "rotate $output to portrait"
kscreen-doctor "output.$output.rotation.left" >"$OUT/kscreen-rotate.log" 2>&1
sleep 3
geom portrait
shot 03-portrait
log "rotate back"
kscreen-doctor "output.$output.rotation.none" >>"$OUT/kscreen-rotate.log" 2>&1
sleep 3
geom landscape-again
pfv_tablet on
sleep 1.5
geom short-tablet
pfinput "$AWAY" 'sleep 0.5'
shot 04-short-tablet
pfv_tablet off
sleep 1.5
geom short-laptop-again
log "done"
