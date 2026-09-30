# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed). Changes every setting of the module with real pointer input
# (pfinput) in System Settings, presses Apply, and records the written values (state-*.txt) and
# the effect on the desktop (screenshots). Starts from Plasma Fusion Dark (make-seed.sh ... dark).
#
# System Settings is placed at 180,60 1080x700; the module's content starts at X0,Y0 below and
# every control is addressed from there (board layout: cards at y 26, swatches at 165,
# segmented control at 235, switch rows at 287/328/369, 560 px wide column).
exec 2>&1
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
X0=475 Y0=175
APPLY="1211 737" DEFAULTS="500 737" RESET="593 737"
at() { echo "$((X0 + $1)) $((Y0 + $2))"; }
click() { pfinput "move $1 $2" 'sleep 0.3' "click $1 $2" 'sleep 0.6'; }
# Rest the pointer on the empty part of the page (no hover effects anywhere).
park() { pfinput 'move 1150 660' 'sleep 0.4'; }
apply() { click $APPLY; sleep "${1:-4}"; park; }
open_settings() {
  systemsettings kcm_plasmafusion >>"$OUT/systemsettings.log" 2>&1 &
  sleep 9
  place systemsettings 180 60 1080 700
  sleep 2
  park
}

fusion_setup
dump_state 00-initial
# Dolphin behind System Settings: an application with a menu bar for the global menu checks.
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
sleep 5
place dolphin 40 90 760 520
open_settings
shot 01-open
pfinput 'move 720 848' 'sleep 1.2'
shot 01b-dock-hover-magnify-on
park

# 1. Accent teal: nothing is written before Apply; Reset brings the loaded value back.
click $(at 49 178)
dump_state 02a-teal-pending
shot 02a-teal-pending
click $(at 193 178)
click $RESET
sleep 1
shot 02b-after-reset
click $(at 49 178)
apply 5
dump_state 02c-teal-applied
shot 02c-teal-applied

# 2. Window buttons: left circles.
click $(at 277 252)
apply 4
dump_state 03-left-circles
shot 03-left-circles

# 3. Switches: magnify off, global menu off, hot corner on.
click $(at 540 307)
click $(at 540 348)
click $(at 540 389)
shot 04a-switches-pending
dump_state 04a-switches-pending
apply 4
dump_state 04b-switches-applied
shot 04b-switches-applied
pfinput 'move 720 848' 'sleep 1.2'
shot 04c-dock-hover-magnify-off
# KWin triggers a corner on the second push within 150-350 ms (the first one is pushed back).
pfinput 'move 0 0' 'sleep 0.2' 'move 0 0' 'sleep 1.5'
shot 04d-hot-corner
pfinput 'key esc' 'sleep 1.0'
park
place dolphin 40 90 760 520
sleep 1
shot 04e-dolphin-no-global-menu
place systemsettings 180 60 1080 700
park

# 4. Light (Global Theme), keeping teal and the left buttons.
click $(at 62 62)
apply 10
dump_state 05-light
shot 05-light

# 5. Accent from the wallpaper.
click $(at 303 178)
sleep 2
shot 06a-wallpaper-pending
dump_state 06a-wallpaper-pending
apply 6
dump_state 06b-wallpaper
shot 06b-wallpaper

# 6. Show on hover (Aurorae fallback keeps right-hand buttons; the choice is stored).
click $(at 461 252)
apply 4
dump_state 07-show-on-hover
shot 07-show-on-hover

# 7. Follow sunset: Plasma's automatic switching picks the variant for the time of day.
click $(at 334 62)
apply 12
dump_state 08-follow-sunset
shot 08-follow-sunset

# 8. The module loads what is set: close and open again.
quit_app systemsettings
open_settings
shot 09-reopened

# 9. Defaults + Apply: Dark, scheme accent, right glyphs, magnify on, global menu on, hot corner off.
click $DEFAULTS
sleep 1
shot 10a-defaults-pending
apply 10
dump_state 10b-defaults-applied
shot 10b-defaults-applied
place dolphin 40 90 760 520
sleep 1
shot 10c-dolphin-global-menu
quit_app systemsettings
shot 11-desktop-after
