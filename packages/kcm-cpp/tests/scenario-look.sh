# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed). The module as it opens: Plasma Fusion Dark or Light applied
# (make-seed.sh ... dark|light), System Settings at 180,60 1080x700 (as scenario-interact.sh) and
# kcmshell6; keyboard focus on the first controls; the loaded state.
exec 2>&1
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
fusion_setup
dump_state 00-initial

systemsettings kcm_plasmafusion >"$OUT/systemsettings.log" 2>&1 &
sleep 9
place systemsettings 180 60 1080 700
sleep 2
pfinput 'move 1150 660' 'sleep 0.5'
shot 01-systemsettings
# Keyboard: click the empty page, Tab to the first card, on to the Teal swatch, Space chooses it
# (pending until Apply; the module is closed without applying).
pfinput 'click 1150 660' 'sleep 0.3' 'key tab' 'sleep 0.6'
shot 02-focus-first
pfinput 'key tab' 'key tab' 'key tab' 'key tab' 'sleep 0.6'
shot 03-focus-teal
pfinput 'key space' 'sleep 0.6'
shot 04-space-chooses-teal
# Reset (nothing was applied), so closing does not ask about unsaved changes.
pfinput 'move 593 737' 'sleep 0.3' 'click 593 737' 'sleep 1'
shot 04b-reset
quit_app systemsettings
sleep 2

kcmshell6 kcm_plasmafusion >"$OUT/kcmshell.log" 2>&1 &
sleep 7
place kcmshell 380 150 680 620
sleep 2
pfinput 'move 1000 700' 'sleep 0.5'
shot 05-kcmshell
