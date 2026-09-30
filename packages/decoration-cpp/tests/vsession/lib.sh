# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Helpers for the decoration's virtual-session scenarios (test tooling, not installed). make-seed.sh
# copies this file to SEED/pf-deco/lib.sh; a scenario sources it after params.sh. Uses the harness
# functions of tools/vsession (qdbus, shot, pfinput, wait_for_name) and $OUT, $PFV, $HOME.

log() { echo "[$(date +%T.%3N)] $*"; }

# Run a KWin script snippet from stdin.
kwinjs() {
  local f=$PFV/helper-$RANDOM.js id
  cat >"$f"
  id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$f" "pfcx-helper-$RANDOM")
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 0.5
}

# Window geometry and title-bar height as KWin sees them (client top minus frame top), into kwin.log.
geom() {
  kwinjs <<JS
const out = workspace.windowList().filter(w => (w.normalWindow || w.dialog || w.utility) && !w.minimized)
  .map(w => (w.resourceClass || "?") + " " + JSON.stringify(w.frameGeometry) + " title=" + (w.clientGeometry.y - w.frameGeometry.y)
       + " max=" + w.maximizeMode + " tile=" + (w.tile ? "yes" : "no") + " active=" + (w === workspace.activeWindow)
       + " output=" + (w.output ? w.output.name + ":" + w.output.geometry.width + "x" + w.output.geometry.height : "?"));
console.warn("PFCXGEOM $1 " + out.join(" | "));
JS
}

# setdeco STYLE HOVER: ButtonStyle and SnapLayoutsOnHover (true, false, or default = key removed)
setdeco() {
  kwriteconfig6 --file plasmafusionrc --group Decoration --key ButtonStyle "$1"
  if [ "$2" = default ]; then
    kwriteconfig6 --file plasmafusionrc --group Decoration --key SnapLayoutsOnHover --delete
  else
    kwriteconfig6 --file plasmafusionrc --group Decoration --key SnapLayoutsOnHover "$2"
  fi
  qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1
  sleep 1.2
}

# Applies the whole Plasma Fusion desktop from the seed's stage, restarts the shell, pins KWin's
# title font (see scenario.sh) and selects the C++ decoration.
fusion_desktop() {
  local opts=(--install "$HOME/pf-stage")
  [ "${VARIANT:-dark}" = light ] && opts+=(--light)
  bash "$HOME/pf-tools/device/fusion-config.sh" "${opts[@]}" >"$OUT/fusion-config.log" 2>&1
  log "fusion-config rc=$?"
  kquitapp6 plasmashell >/dev/null 2>&1
  sleep 2
  plasmashell >>"$OUT/plasmashell2.log" 2>&1 &
  wait_for_name org.kde.plasmashell
  sleep 10
  env -u XDG_CONFIG_DIRS kwriteconfig6 --file kdeglobals --group WM --key activeFont "Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0"
  env -u XDG_CONFIG_DIRS kwriteconfig6 --file kdeglobals --group General --key font "Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
  dbus-send --session --type=signal /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts
  sleep 1
  use_decoration cpp
}

# use_decoration cpp|aurorae|breeze
use_decoration() {
  case "$1" in
    cpp) kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.plasmafusion.decoration
         kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "" ;;
    aurorae) local v=Dark
             [ "${VARIANT:-dark}" = light ] && v=Light
             kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae.v2
             kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "__aurorae__svg__PlasmaFusion$v" ;;
    breeze) kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze
            kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Breeze ;;
  esac
  qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1
  sleep 1.5
  qdbus org.kde.KWin /KWin supportInformation >"$OUT/kwin-support-$1.txt" 2>&1
  log "decoration $1: $(grep -m1 '^Plugin:' "$OUT/kwin-support-$1.txt")"
}

# check_plugin: KWin must run THIS build from the seed (QT_PLUGIN_PATH), not an installed copy
# (1.0-2 is installed system-wide on the test device): the 1.0-3 debug line names the tablet state,
# which 1.0-2 never printed. (KWin's /proc maps are not readable: kwin_wayland has a file
# capability, so the process is not dumpable.)
check_plugin() {
  grep -q '^Plugin: org.plasmafusion.decoration' "$OUT/kwin-support-cpp.txt" \
    || log "ERROR: KWin did not load org.plasmafusion.decoration"
  grep -q 'org.plasmafusion.decoration: decoration for.*tablet' "$OUT/kwin.log" 2>/dev/null \
    && log "1.0-3 debug line present" || log "ERROR: no 1.0-3 debug line in kwin.log"
}

# flyout LABEL: whether the plasmafusion-snap flyout window is open, into kwin.log
flyout() {
  kwinjs <<JS
const f = workspace.windowList().filter(w => w.caption === "Snap layouts");
console.warn("PFCXFLYOUT $1 open=" + (f.length > 0));
JS
}

# place: System Settings (active) at the Main board's Appearance frame, Dolphin, Konsole.
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

# The session's own KWin: the scenario runs in inner.sh, which KWin started (--exit-with-session),
# so walk up the parent chain. (KWin's environment is not readable to match on: see check_plugin.)
kwin_pid() {
  local p=$$ _
  for _ in 1 2 3 4 5 6; do
    p=$(sed -E 's/^.*\) //' "/proc/$p/stat" 2>/dev/null | cut -d' ' -f2)
    [ -n "$p" ] && [ "$p" -gt 1 ] || return 1
    [ "$(cat "/proc/$p/comm" 2>/dev/null)" = kwin_wayland ] && { echo "$p"; return 0; }
  done
  return 1
}
