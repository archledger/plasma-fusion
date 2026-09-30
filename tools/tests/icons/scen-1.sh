# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Icon-position test, session 1 of 3 (sourced inside tools/vsession; see tools/tests/icons/run.sh).
# Installs Plasma Fusion from ~/pf-stage, turns the desktop into Folder View (BACKLOG M1 settings,
# written here and not in the Global Theme), puts 12 files on it, drags six of them into a
# non-default pattern with real pointer input, saves that as the baseline, then runs the session
# events one by one and checks the positions, the desktop cards, open pop-ups and core dumps after
# each.
# shellcheck shell=bash
exec 2>&1
# shellcheck source=tools/tests/icons/lib.sh
source "$HOME/pf-tools/tests/icons/lib.sh"
log "session 1: install"
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fusion-config.log" 2>&1
log "fusion-config rc=$?"
mkdir -p "$HOME/Desktop"
for i in $(seq -w 1 12); do echo "Plasma Fusion icon test $i" >"$HOME/Desktop/file$i.txt"; done

# Folder View on the primary desktop (plasmashell stopped while the file is edited).
CID=$(icons desktop-id)
if ! [[ "$CID" =~ ^[0-9]+$ ]]; then log "SETUP FAIL: no desktop containment ($CID)"; return 0; fi
log "desktop containment $CID -> org.kde.plasma.folder"
kquitapp6 plasmashell >/dev/null 2>&1; sleep 2
A=plasma-org.kde.plasma.desktop-appletsrc
kwriteconfig6 --file "$A" --group Containments --group "$CID" --key plugin org.kde.plasma.folder
for kv in url=desktop:/ sortMode=-1 arrangement=1 alignment=0 iconSize=2 labelWidth=1 textLines=2 \
          previews=true popups=false toolTips=false selectionMarkers=true useTypeAhead=true locked=false; do
  kwriteconfig6 --file "$A" --group Containments --group "$CID" --group General --key "${kv%%=*}" "${kv#*=}"
done
plasmashell >>"$OUT/plasmashell.log" 2>&1 &
wait_for_name org.kde.plasmashell
sleep 12
icons state initial
shot 00-initial

log "drags"
pfinput 'move 700 450' 'sleep 0.3'
icons plan >"$OUT/drags.txt" 2>>"$OUT/steps.log"
while read -r d; do
  [ -n "$d" ] || continue
  log "pfinput $d"
  pfinput "$d" 'sleep 1.2'
done <"$OUT/drags.txt"
pfinput 'move 700 450' 'sleep 3'
# a click on an empty cell clears the selection the last drag left, so it is not in the baseline
pfinput 'click 700 450' 'sleep 1'
if icons pattern >"$OUT/pattern.json"; then log "pattern in place"; else log "SETUP FAIL: pattern not reached: $(cat "$OUT/pattern.json")"; fi
icons base >>"$OUT/steps.log"
shot 01-base

log "step: plasmashell restart"
pfv_restart_shell 12
check 02-plasmashell-restart

log "step: KWin reconfigure"
qdbus org.kde.KWin /KWin reconfigure; sleep 5
check 03-kwin-reconfigure

O=$(outputs | head -1)
log "step: scale 4/3 -> 1 -> 4/3 on $O"
kscreen "output.$O.scale.1"
icons state 04a-scale-1; shot 04a-scale-1
kscreen "output.$O.scale.${PFV_SCALE:-1.333333}"
check 04-scale-back

log "step: portrait and back on $O"
kscreen "output.$O.rotation.left"
icons state 05a-portrait; shot 05a-portrait
kscreen "output.$O.rotation.none"
check 05-rotation-back

log "step: dock hidden by a maximised window, then shown"
konsole >/dev/null 2>&1 &
sleep 4
pfkwin maximize org.kde.konsole >>"$OUT/steps.log" 2>&1; sleep 3
icons state 06a-dock-covered; shot 06a-dock-covered
pfkwin close org.kde.konsole >>"$OUT/steps.log" 2>&1; sleep 4
check 06-dock-dodge

log "step: dock auto-hide on, then back to dodge windows"
DOCK=$(dock_id)
evaljs - <<JS
panelById($DOCK).hiding = "autohide";
JS
sleep 5
icons state 07a-dock-autohide; shot 07a-dock-autohide
evaljs - <<JS
panelById($DOCK).hiding = "dodgewindows";
JS
sleep 5
check 07-dock-autohide-back
log "session 1 done"
