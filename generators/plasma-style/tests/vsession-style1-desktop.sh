# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# STYLE-1 desktop scenario for tools/vsession (sourced inside a private session; test use only).
# Seed: make-style1-seed.sh. Logical 1440x900 (1920x1200 with PFV_SCALE=1.3333333).
# Plasma Fusion Dark with the Global Theme layout, the desktop switched to Folder View (BACKLOG M1
# keys) with a folder, a file, a link to a file and a symlinked app (link emblem), single-click
# activation (so the selection markers show). Screenshots of hover, the markers (add, remove, their
# hover and pressed states), selected, selected+hover and the drag-selection band, in dark and in
# light; then an AccentColor change applied live (no shell restart), with the PC3 test pop-up.
# Coordinates (icon cell centres) come from $HOME/pf-tools/style1-coords.sh when present; PARTS there
# (default "dark light accent") limits the run.
exec 2>&1
set -x
T=$HOME/pf-tools
export QT_FORCE_STDERR_LOGGING=1
# First icon cell of the left column and the row pitch (logical px); the marker sits on the icon's
# top-left corner.
IX=48; IY=67; PITCH=107; MX=16; MY=50
PARTS="dark light accent"
[ -f "$T/style1-coords.sh" ] && . "$T/style1-coords.sh"
Y1=$((IY + PITCH)); Y2=$((IY + 2 * PITCH)); Y3=$((IY + 3 * PITCH))
has() { case " $PARTS " in *" $1 "*) return 0 ;; esac; return 1; }

restart_shell() { # $1 log name
  kquitapp6 plasmashell >/dev/null 2>&1
  for _ in $(seq 1 40); do qdbus-qt6 | grep -q org.kde.plasmashell || break; sleep 0.5; done
  plasmashell >"$OUT/$1" 2>&1 &
  wait_for_name org.kde.plasmashell
  sleep 8
}
inv() { qdbus-qt6 org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate widget $1"; }
dismiss_launcher() { kcalc >/dev/null 2>&1 & local kc=$!; sleep 4; kill $kc 2>/dev/null; sleep 2; }

kpackagetool6 -t Plasma/Applet -i "$HOME/pkg/org.plasmafusion.pstest" >/dev/null 2>&1
bash "$T/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc-install.log" 2>&1

# Desktop contents: a folder, a text file, a symlink to that file and a symlinked app entry.
mkdir -p "$HOME/Desktop/Projects"
printf 'Plasma Fusion notes\n' >"$HOME/Desktop/Notes.txt"
ln -sf "$HOME/Desktop/Notes.txt" "$HOME/Desktop/Notes link.txt"
ln -sf /usr/share/applications/org.kde.konsole.desktop "$HOME/Desktop/org.kde.konsole.desktop"

# Folder View with the BACKLOG M1 keys, single-click activation, the PC3 test widget in the top bar.
DID=$(evaljs - <<'JS' | tr -dc '0-9'
print(desktops()[0].id);
JS
)
PTID=$(evaljs - <<'JS' | tr -dc '0-9'
var ps = panels(); var top = null;
for (var i = 0; i < ps.length; i++) if (ps[i].location == "top") top = ps[i];
var pt = top.addWidget("org.plasmafusion.pstest"); pt.globalShortcut = "Ctrl+Alt+Shift+F4"; print(pt.id);
JS
)
kquitapp6 plasmashell >/dev/null 2>&1; sleep 3
A=plasma-org.kde.plasma.desktop-appletsrc
kwriteconfig6 --file $A --group Containments --group "$DID" --key plugin org.kde.plasma.folder
for kv in url=desktop:/ sortMode=-1 arrangement=1 alignment=0 iconSize=2 popups=false toolTips=false \
          selectionMarkers=true useTypeAhead=true locked=false; do
  kwriteconfig6 --file $A --group Containments --group "$DID" --group General --key "${kv%%=*}" "${kv#*=}"
done
kwriteconfig6 --file kdeglobals --group KDE --key SingleClick true
plasmashell >"$OUT/plasmashell-dark.log" 2>&1 &
SHELL_PID=$!
wait_for_name org.kde.plasmashell; sleep 10
dismiss_launcher

states() { # $1 variant
  local v=$1 pf
  pfinput 'move 700 450' 'sleep 0.6'; shot "$v-01-rest"
  pfinput "move $IX $IY" 'sleep 0.8'; shot "$v-02-hover-add"
  pfinput "move $MX $MY" 'sleep 0.8'; shot "$v-03-marker-add-hover"
  pfinput "move $MX $MY" 'down' 'sleep 1.6' 'up' & pf=$!
  sleep 0.9; shot "$v-04-marker-add-pressed"; wait "$pf"   # never a bare wait: plasmashell is a child too
  pfinput 'sleep 0.6'; shot "$v-05-selected-hover-remove"
  pfinput 'move 700 450' 'sleep 0.8'; shot "$v-06-selected"
  pfinput "move $IX $Y1" 'sleep 0.8'; shot "$v-07-hover-link-app"
  pfinput "move $IX $Y3" 'sleep 0.8'; shot "$v-08-hover-file"
  pfinput 'move 700 200' 'down' 'move 600 240' 'move 400 290' 'move 200 330' "move 20 $((Y2 + 20))" 'sleep 2.2' 'up' & pf=$!
  sleep 1.6; shot "$v-09-band"; wait "$pf"
  pfinput 'sleep 0.6' 'move 700 450' 'sleep 0.6'; shot "$v-10-band-selected"
  pfinput 'click 900 600' 'sleep 0.8'   # clear the selection
}

if has dark; then
  states dark
  # the PC3 controls pop-up (accent-coloured switch, slider, check box, progress, focus)
  inv "$PTID"; sleep 2.5; shot dark-11-controls; inv "$PTID"; sleep 1
fi
if has light; then
  bash "$T/fusion-config.sh" --light --keep-layout >"$OUT/fc-light.log" 2>&1
  sleep 6
  states light
  inv "$PTID"; sleep 2.5; shot light-11-controls; inv "$PTID"; sleep 1
fi
if has accent; then
  # AccentColor change, applied to the running session (no plasmashell restart)
  pfinput "move $IX $IY" 'sleep 0.3' "click $MX $MY" 'sleep 0.5' "move $IX $Y1" 'sleep 0.8'
  shot accent-01-before
  inv "$PTID"; sleep 2.5; shot accent-02-before-controls; inv "$PTID"; sleep 1
  plasma-apply-colorscheme --accent-color '#1f9e8f' >"$OUT/accent.log" 2>&1
  sleep 4
  pfinput "move $IX $IY" 'sleep 0.2' "move $IX $Y1" 'sleep 0.8'
  shot accent-03-teal
  inv "$PTID"; sleep 2.5; shot accent-04-teal-controls; inv "$PTID"; sleep 1
  pfv_alive "$SHELL_PID" && echo "plasmashell $SHELL_PID still running (not restarted)" >>"$OUT/accent.log"
  for k in "General AccentColor" "Colors:Selection BackgroundNormal" "Colors:Button DecorationFocus"; do
    echo "$k=$(kreadconfig6 --file kdeglobals --group "${k% *}" --key "${k#* }")" >>"$OUT/accent.log"
  done
fi

cp "$HOME/.config/$A" "$HOME/.config/kdeglobals" "$HOME/.config/plasmarc" "$OUT/" 2>/dev/null
ls -la "$HOME/Desktop" >"$OUT/desktop-files.txt"
true
