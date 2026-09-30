# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Icon-position test, session 1 of 3 (sourced inside tools/vsession; see tools/tests/icons/run.sh).
# Upgrade path (when the seed has ~/pf-stage-old and ~/pf-tools-old, run.sh --from-stage): installs
# that build first, as a user of it would have it, then upgrades. Installs Plasma Fusion from
# ~/pf-stage; the desktop is the layout's Folder View when the build ships one (BACKLOG M1), else the
# test turns it into Folder View with the M1 settings (not written to the Global Theme); puts 12
# files on it, drags six of them into a non-default pattern with real pointer input, saves that as
# the baseline, then runs the session events one by one and checks the positions, the desktop
# cards, open pop-ups and core dumps after each.
# shellcheck shell=bash
exec 2>&1
# shellcheck source=tools/tests/icons/lib.sh
source "$HOME/pf-tools/tests/icons/lib.sh"
mkdir -p "$HOME/Desktop"
for i in $(seq -w 1 12); do echo "Plasma Fusion icon test $i" >"$HOME/Desktop/file$i.txt"; done
if [ -d "$HOME/pf-stage-old" ] && [ -d "$HOME/pf-tools-old" ]; then
  log "session 1: install the previous build (upgrade path)"
  bash "$HOME/pf-tools-old/device/fusion-config.sh" --install "$HOME/pf-stage-old" >"$OUT/fusion-config-old.log" 2>&1
  log "previous fusion-config rc=$?"
  pfv_restart_shell 12
  icons state 00a-before-upgrade; shot 00a-before-upgrade
fi
log "session 1: install"
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fusion-config.log" 2>&1
log "fusion-config rc=$?"
if [ -d "$HOME/pf-stage-old" ]; then
  pfv_restart_shell 12
  icons state 00b-after-upgrade; shot 00b-after-upgrade
  icons upgrade 00a-before-upgrade 00b-after-upgrade >>"$OUT/steps.log" 2>&1 || log "upgrade check: FAIL"
fi

# Folder View on the primary desktop: the layout's (M1) when the build ships it, else written here
# with the M1 settings (plasmashell stopped while the file is edited).
read -r CID PLUGIN < <(icons desktop-id)
if ! [[ "$CID" =~ ^[0-9]+$ ]]; then log "SETUP FAIL: no desktop containment ($CID)"; return 0; fi
if [ "$PLUGIN" = org.kde.plasma.folder ]; then
  log "desktop containment $CID is the layout's Folder View"
  echo "folderview=layout" >"$OUT/folderview.txt"
  pfv_restart_shell 12
else
  log "desktop containment $CID ($PLUGIN) -> org.kde.plasma.folder (M1 settings written by the test)"
  echo "folderview=test" >"$OUT/folderview.txt"
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
fi
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
