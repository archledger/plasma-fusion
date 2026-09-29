# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Virtual-session scenario (tools/vsession/remote.sh kw-N THIS SEED): snapping and dialogs.
# Meta+Z flyout (keyboard preview, then a zone), the picker for the other half, a drag to the
# left edge (snap-zone outline), Esc on the flyout, and a modal dialog attached to its window.
FI="python3 $HOME/pfk/fakeinput.py"
log() { echo "[$(date +%T)] $*"; }
# Runs a one-off KWin script (test helper) in this private session.
kwinjs() {
  local f=$PFV/helper-$RANDOM.js
  cat > "$f"
  local id
  id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$f" "pfk-helper-$RANDOM")
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 0.4
}
kbuildsycoca6 >/dev/null 2>&1
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1
sleep 1
log "scripts: snap=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap) attach=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-attach)"

dolphin --new-window "$HOME/.local/share/wallpapers" >/dev/null 2>&1 &
sleep 2
konsole >/dev/null 2>&1 &
sleep 2
kwrite >/dev/null 2>&1 &
sleep 3
kwinjs <<'JS'
workspace.activeWindow.frameGeometry = { x: 180, y: 110, width: 920, height: 640 };
JS
sleep 1
shot 20-windows

log "meta+z, keyboard to the right half, preview"
$FI down meta tap z up meta
sleep 1.2
shot 21-flyout
$FI tap right
sleep 0.9
shot 22-flyout-preview
log "enter: right half, then the picker on the left"
$FI tap enter
sleep 1.8
shot 23-picker
$FI tap right
sleep 0.4
shot 24-picker-next
$FI tap enter
sleep 1.6
shot 25-filled

log "meta+z on the left window, esc"
$FI down meta tap z up meta
sleep 1
shot 26-flyout-left
$FI tap esc
sleep 0.8
shot 27-esc

log "drag the third window to the left edge"
kwinjs <<'JS'
const ws = workspace.windowList().filter(w => w.normalWindow && w.moveable && !w.tile);
if (ws.length) { workspace.activeWindow = ws[0]; ws[0].frameGeometry = { x: 380, y: 220, width: 700, height: 460 }; }
JS
sleep 1
shot 28-third
$FI move 730 238 sleep 0.2 press left glide 600 300 0.4 glide 1 420 0.6 sleep 1.8 release left &
FIPID=$!
sleep 2.2
shot 29-edge-outline
wait $FIPID
sleep 1.8
shot 30-edge-snapped
$FI tap esc
sleep 0.8

log "modal dialog attached to kwrite"
kwinjs <<'JS'
const ws = workspace.windowList().filter(w => w.normalWindow && (w.resourceClass || "").indexOf("kwrite") >= 0);
if (ws.length) {
  const w = ws[0];
  if (w.tile) { w.tile.unmanage(w); }
  workspace.activeWindow = w;
  w.frameGeometry = { x: 260, y: 120, width: 900, height: 620 };
}
JS
sleep 1
$FI down ctrl tap o up ctrl
sleep 3
shot 31-dialog
kwinjs <<'JS'
const ws = workspace.windowList().filter(w => w.normalWindow && !w.modal && (w.resourceClass || "").indexOf("kwrite") >= 0);
if (ws.length) { const g = ws[0].frameGeometry; ws[0].frameGeometry = { x: g.x + 200, y: g.y + 60, width: g.width, height: g.height }; }
JS
sleep 1
shot 32-dialog-follows
$FI tap esc
sleep 1
log "done"
