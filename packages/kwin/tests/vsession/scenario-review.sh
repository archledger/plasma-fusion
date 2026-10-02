# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Virtual-session scenario (tools/vsession/remote.sh NAME THIS SEED): edge cases on the Plasma
# Fusion desktop. Switcher with no windows, with many windows (grid scrolls) and a long workspace
# name; Meta+Z 2:1, quarters and thirds; the picker when the snapped window moves to the other
# half (Meta+Right); many picker candidates with keyboard navigation; a click outside the flyout.
# KWin's PID goes to $OUT/kwin.pid so its journal lines can be read afterwards; geometry dumps
# from the helper scripts are printed to the journal with the prefix PFKGEOM.
FI="python3 $HOME/pfk/fakeinput.py"
log() { echo "[$(date +%T)] $*"; }
kwinjs() {
  local f=$PFV/helper-$RANDOM.js
  cat > "$f"
  local id
  id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$f" "pfk-helper-$RANDOM")
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 0.4
}
dumpgeom() {
  kwinjs <<JS
const out = workspace.windowList().filter(w => w.normalWindow && !w.minimized)
  .map(w => (w.resourceClass || "?") + " " + JSON.stringify(w.frameGeometry) + " tile=" + (w.tile ? "yes" : "no"));
console.warn("PFKGEOM $1 " + out.join(" | "));
JS
}
echo "$PPID" > "$OUT/kwin.pid"
date "+%Y-%m-%d %H:%M:%S" > "$OUT/start.txt"
kbuildsycoca6 >/dev/null 2>&1
if grep -q '^ColorScheme=PlasmaFusionLight' "$HOME/.config/kdeglobals"; then LNF=org.plasmafusion.light.desktop; else LNF=org.plasmafusion.dark.desktop; fi
evaljs - <<'JS' >/dev/null 2>&1
panels().forEach(function (p) { p.remove(); });
JS
evaljs "$HOME/.local/share/plasma/look-and-feel/$LNF/contents/layouts/org.kde.plasma.desktop-layout.js" >"$OUT/layout.log" 2>&1
plasma-apply-wallpaperimage "$HOME/.local/share/wallpapers/PlasmaFusion" >>"$OUT/layout.log" 2>&1
sleep 4
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1
sleep 1
log "scripts: snap=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap) attach=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-attach)"

log "alt+tab without windows"
$FI down alt tap tab sleep 1.6 up alt &
FIPID=$!
sleep 1.1
shot r01-switcher-empty
wait $FIPID
sleep 0.6

log "long workspace name, 16 windows"
kwinjs <<'JS'
workspace.desktops[0].name = "Quarterly planning and a much longer workspace name than usual";
JS
python3 "$HOME/pfk/manywindows.py" 16 100 >/dev/null 2>&1 &
MANY=$!
sleep 4
$FI down alt tap tab sleep 1.4 tap tab tap tab tap tab tap tab tap tab tap tab tap tab tap tab tap tab tap tab tap tab tap tab sleep 1.6 up alt &
FIPID=$!
sleep 1.2
shot r02-switcher-many
sleep 1.2
shot r03-switcher-many-scrolled
wait $FIPID
sleep 0.5

log "picker with many candidates: meta+z, 1, enter, then down down down"
$FI down meta tap z up meta sleep 0.8 tap 1 sleep 0.3 tap enter
sleep 1.6
shot r04-picker-many
$FI tap down sleep 0.2 tap down sleep 0.2 tap down sleep 0.2 tap down
sleep 0.8
shot r05-picker-many-scrolled
$FI tap esc
sleep 0.6
kill $MANY 2>/dev/null
sleep 1.5

log "normal windows"
kwinjs <<'JS'
workspace.desktops[0].name = "Work";
JS
dolphin --new-window "$HOME/.local/share/wallpapers" >/dev/null 2>&1 &
sleep 2
konsole >/dev/null 2>&1 &
sleep 2
kwrite >/dev/null 2>&1 &
sleep 3
kwinjs <<'JS'
const w = workspace.activeWindow;
if (w) { w.frameGeometry = { x: 180, y: 110, width: 920, height: 640 }; }
JS
sleep 0.8

log "meta+z, 2 (2:1), enter: left two thirds, picker on the right third"
$FI down meta tap z up meta sleep 0.8 tap 2
sleep 0.8
shot r10-flyout-21-preview
$FI tap enter
sleep 1.6
shot r11-21-picker
dumpgeom two-thirds
$FI tap esc
sleep 0.6

log "meta+right while the picker is open: picker moves to the new empty half"
$FI down meta tap z up meta sleep 0.8 tap 1 sleep 0.3 tap enter
sleep 1.6
shot r12-picker-right
$FI down meta tap right up meta
sleep 1.6
shot r13-after-meta-right
dumpgeom after-meta-right
$FI tap esc
sleep 0.6

log "quarters (top right) and thirds (right)"
$FI down meta tap z up meta sleep 0.8 tap 3 sleep 0.2 tap right sleep 0.5 tap enter
sleep 1.2
dumpgeom quarter-top-right
kwinjs <<'JS'
const ws = workspace.windowList().filter(w => w.normalWindow && (w.resourceClass || "").indexOf("konsole") >= 0);
if (ws.length) { workspace.activeWindow = ws[0]; }
JS
$FI down meta tap z up meta sleep 0.8 tap 4 sleep 0.2 tap right sleep 0.2 tap right sleep 0.5 tap enter
sleep 1.2
shot r14-quarter-and-third
dumpgeom third-right

log "click outside the flyout closes it"
$FI down meta tap z up meta
sleep 0.9
shot r15-flyout-open
$FI move 700 600 click left
sleep 0.8
shot r16-flyout-clicked-away
log "done"
