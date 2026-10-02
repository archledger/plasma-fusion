# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Virtual-session scenario (tools/vsession/remote.sh kw-N THIS SEED): window switcher.
# Opens four windows, then Alt+Tab (this workspace), A (all workspaces), Q (close window).
FI="python3 $HOME/pfk/fakeinput.py"
log() { echo "[$(date +%T)] $*"; }
kbuildsycoca6 >/dev/null 2>&1
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1
sleep 1
log "scripts: snap=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap) attach=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-attach)"

dolphin --new-window "$HOME/.local/share/wallpapers" >/dev/null 2>&1 &
sleep 2
konsole >/dev/null 2>&1 &
sleep 2
kwrite >/dev/null 2>&1 &
sleep 2
systemsettings kcm_colors >/dev/null 2>&1 &
sleep 6
shot 00-windows

log "alt+tab"
$FI down alt tap tab sleep 3.5 up alt &
FIPID=$!
sleep 1.8
shot 10-alttab
wait $FIPID
sleep 1

log "one window to workspace 2, then alt+tab and A"
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Window to Desktop 2" >/dev/null
sleep 1
$FI down alt tap tab sleep 1.2 tap a sleep 3 up alt &
FIPID=$!
sleep 0.9
shot 11-alttab-this
sleep 1.4
shot 12-alttab-all
wait $FIPID
sleep 1

log "alt+tab, shift+tab back, Q closes the selected window"
$FI down alt tap tab tap tab sleep 0.6 down shift tap tab up shift sleep 1 tap q sleep 2.5 up alt &
FIPID=$!
sleep 1.4
shot 13-alttab-back
sleep 1.6
shot 14-alttab-closed
wait $FIPID
sleep 1
shot 15-after
log "done"
