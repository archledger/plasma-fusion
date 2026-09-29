# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Virtual-session scenario (tools/vsession/remote.sh kw-N THIS SEED): evidence run on the Plasma
# Fusion desktop. Applies the Global Theme that matches the seed's colour scheme, then shows the
# window switcher, the Meta+Z flyout with a zone preview, the picker for the other half, the
# filled pair (and that it minimises together), the snap-zone outline and an attached dialog.
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
kbuildsycoca6 >/dev/null 2>&1
if grep -q '^ColorScheme=PlasmaFusionLight' "$HOME/.config/kdeglobals"; then LNF=org.plasmafusion.light.desktop; else LNF=org.plasmafusion.dark.desktop; fi
log "desktop layout and wallpaper of $LNF"
# Only the layout script and the wallpaper: plasma-apply-lookandfeel would move every setting to
# ~/.config/kdedefaults, which only a real Plasma session reads.
evaljs - <<'JS' >/dev/null 2>&1
panels().forEach(function (p) { p.remove(); });
JS
evaljs "$HOME/.local/share/plasma/look-and-feel/$LNF/contents/layouts/org.kde.plasma.desktop-layout.js" >"$OUT/layout.log" 2>&1
plasma-apply-wallpaperimage "$HOME/.local/share/wallpapers/PlasmaFusion" >>"$OUT/layout.log" 2>&1
sleep 5
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1
sleep 1
log "scripts: snap=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap) attach=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-attach)"

dolphin --new-window "$HOME/.local/share/wallpapers" >/dev/null 2>&1 &
sleep 2
konsole >/dev/null 2>&1 &
sleep 2
systemsettings kcm_colors >/dev/null 2>&1 &
sleep 4
okular >/dev/null 2>&1 &
sleep 3
kwrite >/dev/null 2>&1 &
sleep 3
kwinjs <<'JS'
const ws = workspace.windowList().filter(w => w.normalWindow && w.moveable);
const spots = [[70, 70, 760, 500], [560, 270, 650, 500], [120, 180, 900, 600], [640, 90, 700, 520], [300, 110, 920, 640]];
ws.forEach((w, i) => { const s = spots[i % spots.length]; w.frameGeometry = { x: s[0], y: s[1], width: s[2], height: s[3] }; });
JS
sleep 1.5
shot 00-desktop

log "alt+tab"
$FI down alt tap tab sleep 3 up alt &
FIPID=$!
sleep 1.8
shot 10-switcher
wait $FIPID
sleep 1
log "alt+tab, A for all workspaces"
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Window to Desktop 2" >/dev/null
sleep 1
$FI down alt tap tab sleep 1.2 tap a sleep 2.2 up alt &
FIPID=$!
sleep 2.4
shot 11-switcher-all
wait $FIPID
sleep 1

log "meta+z on the active window"
kwinjs <<'JS'
const w = workspace.activeWindow;
if (w) { w.frameGeometry = { x: 48, y: 60, width: 920, height: 722 }; }
JS
sleep 1
$FI down meta tap z up meta
sleep 1.2
shot 20-flyout
$FI tap right
sleep 0.9
shot 21-flyout-preview
$FI tap enter
sleep 1.8
shot 22-picker
$FI tap enter
sleep 1.6
shot 23-filled

log "pair minimises together"
kwinjs <<'JS'
const w = workspace.activeWindow;
if (w) { w.minimized = true; }
JS
sleep 1.2
shot 24-pair-minimized
kwinjs <<'JS'
const ws = workspace.windowList().filter(w => w.minimized && w.normalWindow);
if (ws.length) { ws[0].minimized = false; workspace.activeWindow = ws[0]; }
JS
sleep 1.2
shot 25-pair-restored

log "drag to the left edge: snap-zone outline"
kwinjs <<'JS'
const ws = workspace.windowList().filter(w => w.normalWindow && w.moveable && !w.tile && !w.minimized);
if (ws.length) { workspace.activeWindow = ws[0]; ws[0].frameGeometry = { x: 420, y: 230, width: 700, height: 460 }; }
JS
sleep 1
$FI move 770 250 sleep 0.2 press left glide 600 320 0.4 glide 1 440 0.6 sleep 1.8 release left &
FIPID=$!
sleep 2.2
shot 30-outline
wait $FIPID
sleep 1.8
shot 31-snapped
$FI tap esc
sleep 0.8

log "modal dialog attached to its window"
kwinjs <<'JS'
const ws = workspace.windowList().filter(w => w.normalWindow && (w.resourceClass || "").indexOf("kwrite") >= 0);
if (ws.length) {
  const w = ws[0];
  if (w.tile) { w.tile.unmanage(w); }
  if (w.minimized) { w.minimized = false; }
  workspace.activeWindow = w;
  w.frameGeometry = { x: 180, y: 90, width: 1000, height: 700 };
}
JS
sleep 1
$FI down ctrl tap o up ctrl
sleep 3
shot 40-dialog
kwinjs <<'JS'
const ws = workspace.windowList().filter(w => w.normalWindow && !w.modal && (w.resourceClass || "").indexOf("kwrite") >= 0);
if (ws.length) { const g = ws[0].frameGeometry; ws[0].frameGeometry = { x: g.x + 160, y: g.y + 50, width: g.width, height: g.height }; }
JS
sleep 1
shot 41-dialog-follows
$FI tap esc
sleep 1
log "done"
