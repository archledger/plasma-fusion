# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Virtual-session scenario (test tooling): touch title bars in tablet mode (TABLET.md 4.9, the
# Windowed case: windows keep their title bars). Start the session in tablet mode:
#
#   PFV_TABLET=on tools/vsession/remote.sh o1dc-N packages/decoration-cpp/tests/vsession/scenario-tablet.sh SEED 1920x1200 420
#
# with PFV_SCALE=1.3333333 (1440x900 logical; the pointer coordinates below are logical px).
# Checks (kwin.log: PFCXGEOM title heights, PFCXFLYOUT, the decoration's "layout" lines with every
# hit area; scenario.log: times): 52 px title bars from the start, hit areas of 44 px and more
# (pointer probes at the hit-area edge), hover never opens the snap layouts in tablet mode, a
# touch long press does, a tap maximizes (44 px bar), ShowOnHover and LeftCircles, and live
# flips to laptop mode and back.
. "$HOME/pf-deco/params.sh"
# shellcheck source=lib.sh
. "$HOME/pf-deco/lib.sh"
AWAY='move 1320 760'
# System Settings at the board frame 549,263 650x504; tablet bar 52: button row y 263 + 26,
# close 26 px, maximize 70 px, minimize 114 px from the right edge (1199).
ROW=289
MAX_X=1129
CLOSE_X=1173

date "+%Y-%m-%d %H:%M:%S" >"$OUT/start.txt"
log "variant=$VARIANT kwinrc TabletMode=$(kreadconfig6 --file kwinrc --group Input --key TabletMode)"
log "KWin tablet mode: $(qdbus org.kde.KWin /org/kde/KWin org.kde.KWin.TabletModeManager.tabletMode)"
fusion_desktop
setdeco RightGlyphs default
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
systemsettings kcm_colors >"$OUT/systemsettings.log" 2>&1 &
konsole >"$OUT/konsole.log" 2>&1 &
sleep 10
place
check_plugin
geom tablet-start
pfinput "$AWAY" 'sleep 1.0'
shot 01-tablet-windowed

log "hit-area probes: 20 px right of the maximize centre (outside the 36 px circle), then 3 px below the bar's top"
pfinput "move $((MAX_X + 20)) $ROW" 'sleep 0.8'
shot 02-probe-maximize-right-edge
pfinput "move $MAX_X $((263 + 3))" 'sleep 0.8'
shot 03-probe-maximize-top-edge
pfinput "move $((CLOSE_X + 21)) $ROW" 'sleep 0.8'
shot 03b-probe-close-right-edge

log "hover in tablet mode, even with SnapLayoutsOnHover=true: no flyout"
setdeco RightGlyphs true
pfinput "$AWAY" 'sleep 0.4' "move $MAX_X $ROW" 'sleep 1.5'
flyout tablet-hover
shot 04-tablet-rest-no-flyout
setdeco RightGlyphs default
pfinput "$AWAY" 'sleep 0.5'

log "touch long press on maximize: flyout, window not maximized"
pfinput "tap $MAX_X $ROW 1.1" 'sleep 0.4'
flyout tablet-long-press
shot 05-tablet-long-press-flyout
geom after-long-press
pfinput 'key esc' 'sleep 0.6'
flyout after-esc

log "touch tap on maximize: maximized, 44 px bar"
pfinput "tap $MAX_X $ROW" 'sleep 1.2'
geom after-tap
shot 06-tablet-maximized
place
pfinput "$AWAY" 'sleep 0.5'

log "ShowOnHover: buttons visible without the pointer; LeftCircles"
setdeco ShowOnHover default
pfinput "$AWAY" 'sleep 0.6'
shot 07-tablet-showonhover
setdeco LeftCircles default
pfinput "$AWAY" 'sleep 0.6'
shot 08-tablet-leftcircles
setdeco RightGlyphs default

log "a dialog (kdialog) in tablet mode"
kdialog --title "Plasma Fusion" --msgbox "Tablet dialog" >"$OUT/kdialog.log" 2>&1 &
sleep 3
geom dialog
shot 09-tablet-dialog
kwinjs <<'JS'
for (const w of workspace.windowList()) { if ((w.resourceClass || "").indexOf("kdialog") >= 0) { w.closeWindow(); } }
JS

log "flip to laptop mode"
log "FLIP off"
pfv_tablet off
sleep 1.5
geom laptop
pfinput "$AWAY" 'sleep 0.3'
shot 10-laptop
log "FLIP on"
pfv_tablet on
sleep 1.5
geom tablet-again
shot 11-tablet-again
log "FLIP off"
pfv_tablet off
sleep 1.0
log "FLIP on"
pfv_tablet on
sleep 1.5
geom tablet-third
log "KWin tablet mode at the end: $(qdbus org.kde.KWin /org/kde/KWin org.kde.KWin.TabletModeManager.tabletMode)"
log "done"
