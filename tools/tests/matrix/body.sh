# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Adaptive test matrix, one configuration (ADAPTIVE.md section 11), sourced inside a tools/vsession
# session. run.sh puts MX_ID and MX_FLAGS in front of this file. The seed HOME holds the built
# Plasma Fusion HOME tree at ~/pf-stage and the tools tree at ~/pf-tools.
#
# MX_FLAGS (comma-separated): light, font=PT, anim=F, tablet (the session starts in tablet mode;
# PFV_TABLET), targets (touch-target dump), rotate (portrait and back), manyapps, screen2 (work on
# the second output), lid (first output disabled before the shell starts), hotplug (second output
# disabled before the shell starts, enabled after), mixed=S (second output at scale S),
# lnfswitch (Light and back to Dark with plasma-apply-lookandfeel).
# Every step writes state-STEP.json (mx.py) and a screenshot; check.py judges them on the laptop.
# shellcheck shell=bash
exec 2>&1
T=$HOME/pf-tools/tests
mx() { OUT=$OUT python3 "$T/matrix/mx.py" "$@"; }
log() { echo "[$(date +%T)] $*" >>"$OUT/steps.log"; }
has() { case ",${MX_FLAGS:-}," in *",$1,"*) return 0 ;; esac; return 1; }
val() { local f; for f in ${MX_FLAGS//,/ }; do case "$f" in "$1="*) echo "${f#*=}"; return 0 ;; esac; done; return 1; }
step() { log "step $1"; mx state "$1" >>"$OUT/mx.log" 2>&1 || log "state $1 failed"; shot "$1"; }
esc() { pfinput 'key esc' 'sleep 0.8'; }
log "config $MX_ID flags ${MX_FLAGS:-none}"

# 1. Install Plasma Fusion as a user would, with the configuration's own settings.
FL=(); has light && FL=(--light)
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" "${FL[@]}" >"$OUT/fusion-config.log" 2>&1
echo "fusion-config rc=$?" >>"$OUT/fusion-config.log"
v=$(val font) && { pfv_font "$v"; log "font $v pt"; }
v=$(val anim) && { pfv_anim "$v"; log "animation factor $v"; }
mapfile -t OUTS < <(mx outputs 2>>"$OUT/mx.log")
log "outputs ${OUTS[*]}"
if has lid; then kscreen-doctor "output.${OUTS[0]}.disable" >>"$OUT/kscreen.log" 2>&1; sleep 2; fi
if has hotplug; then kscreen-doctor "output.${OUTS[1]}.disable" >>"$OUT/kscreen.log" 2>&1; sleep 2; fi
v=$(val mixed) && { kscreen-doctor "output.${OUTS[1]}.scale.$v" >>"$OUT/kscreen.log" 2>&1; sleep 2; }
# A fresh plasmashell and a KWin reconfigure: what a new login gives.
pfv_restart_shell 14
qdbus org.kde.KWin /KWin reconfigure; sleep 2
if has hotplug; then
  step 00-login-one-output
  kscreen-doctor "output.${OUTS[1]}.enable" >>"$OUT/kscreen.log" 2>&1; sleep 8
fi
{
  kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Output|Geometry|Scale|Rotation|enabled|disabled' | cut -c1-160
  echo "tabletMode=$(qdbus org.kde.KWin /org/kde/KWin org.freedesktop.DBus.Properties.Get org.kde.KWin.TabletModeManager tabletMode)"
} >"$OUT/info.txt" 2>&1
read -r W H QSX QSY CLX CLY DX DY < <(mx geo 2>>"$OUT/mx.log")
log "geo ${W}x$H qs $QSX,$QSY clock $CLX,$CLY dock $DX,$DY"
MX=$((W / 2)); MY=$((H / 2))
pfinput "move $MX $MY" 'sleep 0.5'

# 2. Desktop, dock hover and leave, the shell pop-ups.
step 01-desktop
pfinput "move $DX $DY" 'sleep 1.3'
shot 02-dock-hover
pfinput "move $DX $((DY - 20))" 'sleep 0.1' "move $DX $((DY - 60))" 'sleep 0.1' "move $DX $((DY - 120))" 'sleep 0.1' \
  "move $((DX - 40)) $((DY - 200))" 'sleep 1.5'
step 02b-dock-after-leave
pfinput "move $MX $MY" 'sleep 0.5' 'key meta' 'sleep 1.8'
step 03-launcher
esc
pfinput "click $QSX $QSY" 'sleep 1.8'
step 04-quicksettings
esc
pfinput "click $CLX $CLY" 'sleep 1.6'
step 05-clock-popup
esc; pfinput "move $MX $MY"

# 3. Touch targets: the widgets print them when their debugDumpTargets key turns on (pop-ups when
# they open).
if has targets; then
  n=$(mx targets on 2>>"$OUT/mx.log"); log "debugDumpTargets on for $n widgets"
  sleep 2
  pfinput 'key meta' 'sleep 1.8'; esc
  pfinput "click $QSX $QSY" 'sleep 1.8'; esc
  pfinput "click $CLX $CLY" 'sleep 1.6'; esc
  mx targets off >>"$OUT/mx.log" 2>&1
fi

# 4. Apps, the window switcher, snap layouts, a notification.
dolphin >/dev/null 2>&1 &
sleep 6
step 06-dolphin
konsole >/dev/null 2>&1 &
sleep 5
step 07-konsole
pfinput 'keydown alt' 'key tab' 'sleep 4' 'keyup alt' &
PFI=$!; sleep 2.5; shot 08-alttab; wait "$PFI"
pfinput 'key meta+z' 'sleep 1.5'
step 09-snap-flyout
esc
notify-send -a "Plasma Fusion test" "Matrix $MX_ID" "A notification for the screenshot" >/dev/null 2>&1
sleep 2
step 10-notification

# 5. Configuration-specific steps.
if has screen2 && [ ${#OUTS[@]} -gt 1 ]; then
  read -r X2 Y2 W2 H2 < <(python3 -c 'import json,sys; o=json.load(open(sys.argv[1]))["kwin"]["outputs"][1]["geo"]; print(o["x"], o["y"], o["w"], o["h"])' "$OUT/state-10-notification.json")
  pfinput "move $((X2 + W2 / 2)) $((Y2 + H2 / 2))" 'sleep 0.5' 'key meta' 'sleep 1.8'
  step 11-launcher-on-screen2
  esc
fi
if has rotate; then
  pfv_rotate left; sleep 4
  step 12-portrait
  pfinput "move $((H / 2)) $((W / 2))" 'sleep 0.5' 'key meta' 'sleep 1.8'
  step 12b-portrait-launcher
  esc
  pfv_rotate normal; sleep 4
  step 13-landscape-again
fi
if has manyapps; then
  for a in kcalc okular ark kinfocenter kfind filelight; do $a >/dev/null 2>&1 & sleep 2.5; done
  sleep 3
  qdbus org.kde.KWin /KWin org.kde.KWin.showDesktop true >/dev/null 2>&1
  sleep 2
  step 14-many-apps
  read -r W H QSX QSY CLX CLY DX DY < <(mx geo 2>>"$OUT/mx.log")
  pfinput "move 60 $DY" 'sleep 1.3'; shot 14b-hover-left-end
  pfinput "move $((W - 60)) $DY" 'sleep 1.3'; shot 14c-hover-right-end
  pfinput "move $MX $MY"
fi
if has lnfswitch; then
  plasma-apply-lookandfeel -a org.plasmafusion.light.desktop >"$OUT/lnf-light.log" 2>&1; sleep 5
  step 15-light
  plasma-apply-lookandfeel -a org.plasmafusion.dark.desktop >"$OUT/lnf-dark.log" 2>&1; sleep 5
  step 16-dark-again
fi
step 99-end
