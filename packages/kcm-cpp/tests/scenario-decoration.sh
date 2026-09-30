# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed). The window-button choice with the Plasma Fusion decoration
# (org.plasmafusion.decoration) installed: seed from make-seed.sh with DECO_PLUGIN_DIR. Starts
# from Plasma Fusion Dark with the Aurorae title bars the Global Theme sets.
# at() prints "X Y"; click takes them as two words on purpose.
# shellcheck disable=SC2046
exec 2>&1
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
X0=475 Y0=175
APPLY="1211 737" DEFAULTS="500 737"
at() { echo "$((X0 + $1)) $((Y0 + $2))"; }
click() { pfinput "move $1 $2" 'sleep 0.3' "click $1 $2" 'sleep 0.6'; }
park() { pfinput 'move 1150 660' 'sleep 0.4'; }
apply() { click $APPLY; sleep "${1:-4}"; park; }

fusion_setup
dump_state 00-initial
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
sleep 5
place dolphin 40 90 760 520
systemsettings kcm_plasmafusion >>"$OUT/systemsettings.log" 2>&1 &
sleep 9
place systemsettings 180 60 1080 700
sleep 2
park
shot 01-open-aurorae

# "Use It" under the window buttons (shown while another decoration is in use).
click $(at 519 296)
apply 4
dump_state 02-use-it
shot 02-fusion-decoration-right

click $(at 277 252)
apply 4
dump_state 03-left-circles
shot 03-left-circles

click $(at 461 252)
apply 4
dump_state 04-show-on-hover
shot 04a-show-on-hover-away
pfinput 'move 720 84' 'sleep 1.2'
shot 04b-show-on-hover-title
park

click $(at 62 62)
apply 10
dump_state 05-light
shot 05-light

click $DEFAULTS
sleep 1
apply 10
dump_state 06-defaults
shot 06-defaults
