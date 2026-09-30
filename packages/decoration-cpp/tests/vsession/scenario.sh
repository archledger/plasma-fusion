# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Virtual-session scenario for the C++ decoration (test tooling, not installed):
#
#   tests/vsession/make-seed.sh STAGE PLUGIN SEED cx-N dark|light [SCALE]
#   tools/vsession/remote.sh cx-N packages/decoration-cpp/tests/vsession/scenario.sh SEED 1440x900 420
#
# Applies the whole Plasma Fusion desktop (fusion-config.sh --install), switches KWin to
# org.plasmafusion.decoration, places System Settings (active, at the Main board's Appearance
# window: 549,263 650x504), Dolphin (inactive, the board's Files window) and Konsole, and then
# drives real pointer input (pfinput): hover / press states, the snap-layouts trigger (hover and
# hold on maximize), maximize, quick tiles, the other button styles, and a burst of odd states
# on several windows. Geometry dumps and the decoration's debug lines land in $OUT/kwin.log.
. "$HOME/pf-deco/params.sh"
log() { echo "[$(date +%T)] $*"; }
kwinjs() {
  local f=$PFV/helper-$RANDOM.js
  cat >"$f"
  local id
  id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$f" "pfcx-helper-$RANDOM")
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 0.5
}
geom() {
  kwinjs <<JS
const out = workspace.windowList().filter(w => w.normalWindow && !w.minimized)
  .map(w => (w.resourceClass || "?") + " " + JSON.stringify(w.frameGeometry) + " max=" + w.maximizeMode
       + " tile=" + (w.tile ? "yes" : "no") + " active=" + (w === workspace.activeWindow));
console.warn("PFCXGEOM $1 " + out.join(" | "));
JS
}
setdeco() { # ButtonStyle SnapLayoutsOnHover
  kwriteconfig6 --file plasmafusionrc --group Decoration --key ButtonStyle "$1"
  kwriteconfig6 --file plasmafusionrc --group Decoration --key SnapLayoutsOnHover "$2"
  qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1
  sleep 1.2
}
place() {
  kwinjs <<'JS'
function find(c) { return workspace.windowList().find(w => w.normalWindow && (w.resourceClass || "").toLowerCase().indexOf(c) >= 0); }
const d = find("dolphin"), s = find("systemsettings"), k = find("konsole");
for (const w of [d, s, k]) { if (w) { try { if (w.tile) { w.tile = null; } } catch (e) {} w.setMaximize(false, false); w.minimized = false; } }
if (k) { k.frameGeometry = {x: 200, y: 400, width: 620, height: 380}; workspace.activeWindow = k; }
if (d) { d.frameGeometry = {x: 65, y: 63, width: 758, height: 498}; workspace.activeWindow = d; }
if (s) { s.frameGeometry = {x: 549, y: 263, width: 650, height: 504}; workspace.activeWindow = s; }
console.warn("PFCX placed dolphin=" + !!d + " systemsettings=" + !!s + " konsole=" + !!k);
JS
  sleep 0.8
}
AWAY='move 1320 760'

date "+%Y-%m-%d %H:%M:%S" >"$OUT/start.txt"
log "variant=$VARIANT scale=${SCALE:-1}"
if [ -n "${SCALE:-}" ]; then
  output=$(kscreen-doctor -j | python3 -c 'import json, sys; print(json.load(sys.stdin)["outputs"][0]["name"])')
  kscreen-doctor "output.$output.scale.$SCALE" >"$OUT/kscreen.log" 2>&1
  sleep 3
fi
opts=(--install "$HOME/pf-stage")
[ "$VARIANT" = light ] && opts+=(--light)
bash "$HOME/pf-tools/device/fusion-config.sh" "${opts[@]}" >"$OUT/fusion-config.log" 2>&1
log "fusion-config rc=$?"
kquitapp6 plasmashell >/dev/null 2>&1
sleep 2
plasmashell >>"$OUT/plasmashell2.log" 2>&1 &
wait_for_name org.kde.plasmashell
sleep 10

# KWin's title font is kdeglobals [WM] activeFont, which the Global Theme writes to the kdedefaults
# layer only. Applied inside a running test session, KWin often keeps (or falls back to) Noto Sans
# afterwards (reproduced: tests/vsession notes in docs/parts/decoration-cpp.md). Put the theme's
# fonts into ~/.config/kdeglobals itself (without the kdedefaults layer, or kwriteconfig6 skips
# values equal to it) and ask for a font re-read the way the Fonts settings page does.
env -u XDG_CONFIG_DIRS kwriteconfig6 --file kdeglobals --group WM --key activeFont "Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0"
env -u XDG_CONFIG_DIRS kwriteconfig6 --file kdeglobals --group General --key font "Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
dbus-send --session --type=signal /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts
sleep 1
# The C++ decoration (contract: library=org.plasmafusion.decoration, theme empty).
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.plasmafusion.decoration
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme ""
setdeco RightGlyphs false
qdbus org.kde.KWin /KWin supportInformation >"$OUT/kwin-support-fusion.txt" 2>&1
grep -A12 -i "^Decoration" "$OUT/kwin-support-fusion.txt" | head -14
grep -q '^font: Manrope' "$OUT/kwin-support-fusion.txt" || log "WARNING: KWin title font is not Manrope"
grep -q '^Plugin: org.plasmafusion.decoration' "$OUT/kwin-support-fusion.txt" || log "ERROR: KWin did not load org.plasmafusion.decoration (QT_PLUGIN_PATH in .config/pfv-env?)"
log "snap script loaded: $(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap)"

dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
systemsettings kcm_colors >"$OUT/systemsettings.log" 2>&1 &
konsole >"$OUT/konsole.log" 2>&1 &
sleep 10
place
geom placed
pfinput "$AWAY" 'sleep 1.0'
shot 01-desktop

log "hover and press states (snap trigger off)"
pfinput 'move 1141 287' 'sleep 0.7'
shot 02-hover-maximize
pfinput 'move 1175 287' 'sleep 0.7'
shot 03-hover-close
pfinput "$AWAY" 'sleep 0.3' 'move 1107 287' 'sleep 0.3' 'down' 'sleep 1.4' 'move 900 287' 'sleep 0.2' 'up' &
PID=$!
sleep 1.3
shot 04-pressed-minimize
wait $PID
geom after-press-outside

log "snap layouts: hover 600 ms on maximize"
setdeco RightGlyphs true
pfinput "$AWAY" 'sleep 0.4' 'move 1141 287' 'sleep 1.4'
shot 05-snap-hover
# KWin's popup filter: a click outside an open popup only closes it, so the first click on
# maximize while the hover flyout is open does not maximize (documented behaviour).
pfinput 'click 1141 287' 'sleep 0.8'
geom click-while-flyout-open
shot 05b-click-while-flyout-open
place
pfinput "$AWAY" 'sleep 0.6'
log "inactive window (Dolphin): hovering its maximize does nothing"
pfinput 'move 765 87' 'sleep 1.4'
shot 05c-inactive-hover-no-flyout
pfinput "$AWAY" 'sleep 0.6'
log "snap layouts: hold maximize"
pfinput 'move 1141 287' 'down' 'sleep 1.8' 'up' 'sleep 0.3' &
PID=$!
sleep 1.3
shot 06-snap-hold
wait $PID
geom after-hold
pfinput 'key esc' 'sleep 0.4'
log "click maximize (quick)"
pfinput "$AWAY" 'sleep 0.4' 'click 1141 287' "$AWAY" 'sleep 1.2'
shot 07-maximized
geom after-click-maximize
pfinput 'move 1382 54' 'sleep 0.7'
shot 07b-maximized-hover-restore
pfinput 'key esc' 'sleep 0.3'

log "quick tiles"
place
kwinjs <<'JS'
const s = workspace.windowList().find(w => (w.resourceClass || "").indexOf("systemsettings") >= 0);
if (s) { workspace.activeWindow = s; workspace.slotWindowQuickTileLeft(); }
JS
sleep 1.2
pfinput 'key esc' 'sleep 0.5'
shot 08-tiled-left
kwinjs <<'JS'
const d = workspace.windowList().find(w => (w.resourceClass || "").indexOf("dolphin") >= 0);
if (d) { workspace.activeWindow = d; workspace.slotWindowQuickTileRight(); }
JS
sleep 1.5
pfinput 'key esc' 'sleep 0.3' "$AWAY" 'sleep 0.5'
shot 09-tiled-both
geom tiled

log "buttons on the left"
place
setdeco LeftCircles true
pfinput "$AWAY" 'sleep 0.6'
shot 10-left
pfinput 'move 587 287' 'sleep 0.7'
shot 11-left-hover
log "show on hover"
setdeco ShowOnHover true
pfinput "$AWAY" 'sleep 0.7'
shot 12-showonhover-away
pfinput 'move 850 287' 'sleep 0.7'
shot 13-showonhover-over
setdeco RightGlyphs true

log "odd states on many windows"
for i in 1 2 3; do konsole >>"$OUT/konsole-$i.log" 2>&1 & done
kdialog --title "Plasma Fusion" --msgbox "Modal message" >"$OUT/kdialog.log" 2>&1 &
sleep 5
for round in 1 2; do
  kwinjs <<'JS'
for (const w of workspace.windowList()) {
  if (!w.normalWindow && !w.dialog) { continue; }
  w.setMaximize(true, true);
}
JS
  sleep 0.8
  kwinjs <<'JS'
for (const w of workspace.windowList()) {
  if (!w.normalWindow) { continue; }
  w.setMaximize(false, false);
  w.keepAbove = !w.keepAbove;
  w.fullScreen = true;
}
JS
  sleep 0.8
  kwinjs <<'JS'
let i = 0;
for (const w of workspace.windowList()) {
  if (!w.normalWindow) { continue; }
  w.fullScreen = false;
  w.keepAbove = false;
  w.onAllDesktops = !w.onAllDesktops;
  w.frameGeometry = {x: 40 + 90 * i, y: 60 + 40 * i, width: 160 + 60 * (i % 3), height: 90 + 50 * (i % 2)};
  i++;
}
JS
  sleep 0.8
  kwinjs <<'JS'
for (const w of workspace.windowList()) {
  if (!w.normalWindow) { continue; }
  w.minimized = true;
  w.minimized = false;
  w.onAllDesktops = false;
}
JS
  sleep 0.8
done
pfinput "$AWAY" 'sleep 0.5'
shot 14-many-small
geom many
log "done"
