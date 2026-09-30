# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed). "Follow sunset" after "Left · circles": when Plasma's automatic
# switching applies the other Global Theme, that theme brings its own window decoration; the
# module (still open) puts the chosen window buttons back. Starts from Plasma Fusion Dark, so the
# re-apply only shows while it is day (Plasma switches to Light); after dusk Plasma keeps Dark and
# nothing needs to be put back.
exec 2>&1
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
X0=475 Y0=175
APPLY="1211 737"
at() { echo "$((X0 + $1)) $((Y0 + $2))"; }
click() { pfinput "move $1 $2" 'sleep 0.3' "click $1 $2" 'sleep 0.6'; }
park() { pfinput 'move 1150 660' 'sleep 0.4'; }
apply() { click $APPLY; sleep "${1:-4}"; park; }

fusion_setup
systemsettings kcm_plasmafusion >>"$OUT/systemsettings.log" 2>&1 &
sleep 9
place systemsettings 180 60 1080 700
sleep 2
park
# With the Plasma Fusion decoration installed the "Use It" note sits under the segmented control.
if ls "$HOME"/pf-deco/org.kde.kdecoration3/*.so >/dev/null 2>&1; then
  click $(at 519 296)
fi
click $(at 277 252)
apply 4
dump_state 01-left-circles
shot 01-left-circles
click $(at 334 62)
apply 2
dump_state 02-sunset-2s
sleep 18
dump_state 03-sunset-20s
shot 03-sunset-20s
