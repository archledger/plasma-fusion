# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed). The page itself with real pointer input:
#   1. System Settings placed as in the 1.0.0-3 review (180,60 1080x700), for the board
#      comparison of the unchanged top part;
#   2. kcmshell6 on a tall output (1440x2400 at PFV_SCALE 1, or taller logical sizes), so the whole
#      page is on screen: screenshots of every section, then clicks on new controls (positions in
#      PF_CLICKS, "x,y" pairs measured on the screenshot of step 2), Apply, the keys read back.
# make-seed.sh ... dark|light. PF_CLICKS and PF_APPLY ("x,y" of Apply) come through the seed's
# pf-params.sh; without them only the screenshots are taken.
exec 2>&1
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT
click() { pfinput "move $1 $2" 'sleep 0.3' "click $1 $2" 'sleep 0.7'; }
park() { pfinput 'move 1400 20' 'sleep 0.4'; }

fusion_setup
folder_desktop 4
dump_state p00-initial

# 1. System Settings as in the 1.0.0-3 review.
systemsettings kcm_plasmafusion >>"$OUT/systemsettings.log" 2>&1 &
sleep 9
place systemsettings 180 60 1080 700
sleep 2
park
shot p01-systemsettings-top
quit_app systemsettings

# 2. The whole page in kcmshell6.
kcmshell6 kcm_plasmafusion >>"$OUT/kcmshell.log" 2>&1 &
sleep 8
place kcmshell6 0 0 720 2300
sleep 3
park
shot p02-kcmshell-full
if [ -n "${PF_CLICKS:-}" ]; then
  for xy in $PF_CLICKS; do
    click "${xy%,*}" "${xy#*,}"
  done
  park
  shot p03-pending
  click "${PF_APPLY%,*}" "${PF_APPLY#*,}"
  sleep 6
  park
  shot p04-applied
  dump_state p04-applied
  # Tab reaches the new controls too: Tab from the last click, Space.
  pfinput 'key tab' 'sleep 0.4' 'key tab' 'sleep 0.4'
  shot p05-keyboard-focus
fi
quit_app kcmshell6
