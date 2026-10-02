# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Test tooling (not installed). Sourced by the scenarios in this directory inside a virtual
# session (tools/vsession/vsession.sh): installs and applies Plasma Fusion from the seed, and
# provides helpers.
T=$HOME/pf-tools
source "$HOME/pf-params.sh"

# quit_app NAME: quit a program of this virtual session (kquitapp6 on the session bus) and wait
# until it is gone, so the next start is a new process (System Settings is a unique application).
# If it does not quit, only processes of THIS session are killed (matched by their private
# XDG_RUNTIME_DIR): pkill would also hit the logged-in user's own System Settings.
session_pids() {
  local p
  for p in /proc/[0-9]*; do
    [ "$(cat "$p/comm" 2>/dev/null)" = "$1" ] || continue
    grep -qz "^XDG_RUNTIME_DIR=$PFV/run\$" "$p/environ" 2>/dev/null && echo "${p#/proc/}"
  done
}
quit_app() {
  local i pids
  kquitapp6 "$1" >/dev/null 2>&1
  for i in $(seq 1 20); do
    [ -z "$(session_pids "$1")" ] && return 0
    sleep 0.25
  done
  pids=$(session_pids "$1")
  [ -n "$pids" ] && kill $pids
  sleep 1
}

# Integrated Fusion setup, as tools/device/fusion-config.sh does on a real session.
fusion_setup() {
  local args=(--install "$HOME/pf-stage")
  [ "$VARIANT" = light ] && args+=(--light)
  bash "$T/device/fusion-config.sh" "${args[@]}" >"$OUT/fusion-config.log" 2>&1
  kquitapp6 plasmashell >/dev/null 2>&1; sleep 2
  plasmashell >>"$OUT/plasmashell2.log" 2>&1 &
  wait_for_name org.kde.plasmashell; sleep 12
  qdbus org.kde.KWin /KWin reconfigure; sleep 2
}

# place CLASS X Y W H: frame geometry of the first window whose resource class contains CLASS
# (a one-shot KWin script), and activate it.
place() {
  local js=$PFV/place-$$.js
  cat >"$js" <<JS
for (const w of workspace.windowList()) {
    if (w.normalWindow && String(w.resourceClass).indexOf("$1") >= 0) {
        w.frameGeometry = { x: $2, y: $3, width: $4, height: $5 };
        workspace.activeWindow = w;
        break;
    }
}
JS
  qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript pfkmplace >/dev/null 2>&1
  local id
  id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js" pfkmplace)
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 1
  qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript pfkmplace >/dev/null 2>&1
}

# Window geometry (x y w h) of the first window whose resource class contains $1.
geometry() {
  local js=$PFV/geom-$$.js
  cat >"$js" <<JS
for (const w of workspace.windowList()) {
    if (w.normalWindow && String(w.resourceClass).indexOf("$1") >= 0) {
        print("PFGEOM " + w.frameGeometry.x + " " + w.frameGeometry.y + " " + w.frameGeometry.width + " " + w.frameGeometry.height + " " + w.clientGeometry.x + " " + w.clientGeometry.y);
        break;
    }
}
JS
  qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript pfkmgeom >/dev/null 2>&1
  local id
  id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js" pfkmgeom)
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 0.5
  qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript pfkmgeom >/dev/null 2>&1
}

# Every value the module reads or writes, to $OUT/state-$1.txt (without the scenario's set -x
# trace, which would otherwise land in the file too).
dump_state() {
  local trace=0
  case $- in *x*) trace=1; set +x ;; esac
  {
    for k in LookAndFeelPackage AutomaticLookAndFeel DefaultLightLookAndFeel DefaultDarkLookAndFeel; do
      echo "kdeglobals [KDE] $k=$(kreadconfig6 --file kdeglobals --group KDE --key $k)"
    done
    for k in ColorScheme AccentColor LastUsedCustomAccentColor accentColorFromWallpaper; do
      echo "kdeglobals [General] $k=$(kreadconfig6 --file kdeglobals --group General --key $k)"
    done
    echo "kdeglobals [Colors:Selection] BackgroundNormal=$(kreadconfig6 --file kdeglobals --group Colors:Selection --key BackgroundNormal)"
    echo "kdeglobals [Colors:View] DecorationFocus=$(kreadconfig6 --file kdeglobals --group Colors:View --key DecorationFocus)"
    for k in library theme ButtonsOnLeft ButtonsOnRight NoPlugin BorderSize BorderSizeAuto; do
      echo "kwinrc [org.kde.kdecoration2] $k=$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key $k)"
    done
    echo "kwinrc [Effect-overview] BorderActivate=$(kreadconfig6 --file kwinrc --group Effect-overview --key BorderActivate)"
    echo "plasmafusionrc [Decoration] ButtonStyle=$(kreadconfig6 --file plasmafusionrc --group Decoration --key ButtonStyle)"
    echo "plasmafusionrc [Decoration] SnapLayoutsOnHover=$(kreadconfig6 --file plasmafusionrc --group Decoration --key SnapLayoutsOnHover)"
    echo "plasmafusionrc [Effects] Glass=$(kreadconfig6 --file plasmafusionrc --group Effects --key Glass)"
    echo "plasmafusionrc [Motion] PreviousAnimationDurationFactor=$(kreadconfig6 --file plasmafusionrc --group Motion --key PreviousAnimationDurationFactor)"
    for k in LighterOnCritical Tier UserGlass UserDockMagnify; do
      echo "plasmafusionrc [Power] $k=$(kreadconfig6 --file plasmafusionrc --group Power --key $k)"
    done
    for k in EveryScreen SolidNextToWindows; do
      echo "plasmafusionrc [TopBar] $k=$(kreadconfig6 --file plasmafusionrc --group TopBar --key $k)"
    done
    for k in AnimationDurationFactor DndBehavior; do
      echo "kdeglobals [KDE] $k=$(kreadconfig6 --file kdeglobals --group KDE --key $k)"
    done
    echo "kwinrc [Plugins] blurEnabled=$(kreadconfig6 --file kwinrc --group Plugins --key blurEnabled)"
    echo "kwinrc [Input] TabletMode=$(kreadconfig6 --file kwinrc --group Input --key TabletMode)"
    for k in WindowMode DockHiding EdgeLeft EdgeRight; do
      echo "kwinrc [Script-plasmafusion-tablet] $k=$(kreadconfig6 --file kwinrc --group Script-plasmafusion-tablet --key $k)"
    done
    echo "kwin blur loaded=$(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur)"
    echo "kwin tabletMode=$(qdbus org.kde.KWin /org/kde/KWin org.kde.KWin.TabletModeManager.tabletMode)"
    echo "widgets: $(evaljs - <<'JS'
var out = [];
function keys(w, names) {
    w.currentConfigGroup = ["General"];
    var v = [];
    for (var i = 0; i < names.length; ++i) v.push(names[i] + "=" + w.readConfig(names[i], "<default>"));
    return v.join(",");
}
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    out.push("panel " + ps[i].id + " screen " + ps[i].screen + " " + ps[i].location + " opacity=" + ps[i].opacity);
    var ws = ps[i].widgets();
    for (var j = 0; j < ws.length; ++j) {
        var w = ws[j], t = w.type;
        if (t === "org.plasmafusion.dock") out.push("  dock " + keys(w, ["magnify", "magnifiedSize", "homeIndicator", "glass"]));
        else if (t === "org.plasmafusion.quicksettings") out.push("  quicksettings " + keys(w, ["keyboardPolicy", "glass"]) + " shortcut=" + w.globalShortcut);
        else if (t === "org.plasmafusion.launcher") out.push("  launcher " + keys(w, ["glass"]));
        else if (t === "org.plasmafusion.pen") out.push("  pen shortcut=" + w.globalShortcut);
    }
}
var ds = desktops();
for (var i = 0; i < ds.length; ++i) {
    var d = ds[i];
    out.push("desktop " + d.id + " " + d.type);
    if (d.type === "org.kde.plasma.folder" || d.type === "org.plasmafusion.desktop") out.push("  folder " + keys(d, ["filterMode", "filterPattern", "iconSize", "positions"]));
    var ws = d.widgets();
    for (var j = 0; j < ws.length; ++j) if (ws[j].type === "org.plasmafusion.systemcard") out.push("  systemcard " + keys(ws[j], ["glass"]));
}
print(out.join("\n"));
JS
)"
    echo "shell: $(evaljs - <<'JS'
var out = [], ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var ws = ps[i].widgets();
    var names = [];
    for (var j = 0; j < ws.length; ++j) {
        var w = ws[j];
        if (w.type === "org.plasmafusion.dock") { w.currentConfigGroup = ["General"]; names.push(w.type + "(magnify=" + w.readConfig("magnify", "<default>") + ")"); }
        else names.push(w.type);
    }
    out.push(ps[i].location + ": " + names.join(", "));
}
print(out.join(" | "));
JS
)"
    qdbus org.kde.KWin /KWin supportInformation | grep -E "^(Plugin|Theme):" | sed 's/^/kwin decoration /'
  } >"$OUT/state-$1.txt" 2>&1
  [ "$trace" = 1 ] && set -x
  return 0
}

# The module driven without a window: tests/kcmctl (commands on stdin, output to $OUT/kcmctl.log
# and to the scenario's log). The binary is in the seed (make-seed.sh with PF_KCMCTL).
kcm() {
  "$HOME/pf-kcmctl/kcmctl" 2>>"$OUT/kcmctl-stderr.log" | tee -a "$OUT/kcmctl.log"
}

# The desktop as a Folder View (BACKLOG M1 keys), as the layout part and DEVICE-1 will set it up:
# stop the shell, change the desktop containment's plugin and keys, start it again. $1: number of
# files to put into ~/Desktop first.
folder_desktop() {
  local n=${1:-12} i appletsrc=$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc ids id
  mkdir -p "$HOME/Desktop"
  for i in $(seq 1 "$n"); do printf 'file %s\n' "$i" >"$HOME/Desktop/note-$(printf %02d "$i").txt"; done
  kquitapp6 plasmashell >/dev/null 2>&1; sleep 3
  ids=$(grep -E '^\[Containments\]\[[0-9]+\]$' "$appletsrc" | sed -E 's/.*\]\[([0-9]+)\]$/\1/')
  for id in $ids; do
    [ "$(kreadconfig6 --file "$appletsrc" --group Containments --group "$id" --key plugin)" = org.kde.desktopcontainment ] || continue
    kwriteconfig6 --file "$appletsrc" --group Containments --group "$id" --key plugin org.kde.plasma.folder
    for kv in url=desktop:/ sortMode=-1 arrangement=1 alignment=0 iconSize=2 popups=false toolTips=false selectionMarkers=true useTypeAhead=true; do
      kwriteconfig6 --file "$appletsrc" --group Containments --group "$id" --group General --key "${kv%%=*}" "${kv#*=}"
    done
  done
  plasmashell >>"$OUT/plasmashell-folder.log" 2>&1 &
  wait_for_name org.kde.plasmashell; sleep 12
}

# The Folder View positions of the first folder desktop (the JSON Plasma stores).
positions() {
  evaljs - <<'JS'
var ds = desktops();
for (var i = 0; i < ds.length; ++i) {
    if (ds[i].type !== "org.kde.plasma.folder" && ds[i].type !== "org.plasmafusion.desktop") continue;
    ds[i].currentConfigGroup = ["General"];
    print(ds[i].readConfig("positions", ""));
    break;
}
JS
}

# check LABEL ACTUAL EXPECTED: one PASS or FAIL line in $OUT/checks.txt.
check() {
  local trace=0 result=FAIL
  case $- in *x*) trace=1; set +x ;; esac
  [ "$2" = "$3" ] && result=PASS
  printf '%s %s: %s (expected %s)\n' "$result" "$1" "$2" "$3" >>"$OUT/checks.txt"
  [ "$trace" = 1 ] && set -x
  return 0
}
# ck FILE GROUP KEY: a configuration value (empty when the key is missing).
ck() { kreadconfig6 --file "$1" --group "$2" --key "$3"; }
# wkey PLUGIN KEY: the [General] KEY of the first PLUGIN widget in a panel or on a desktop.
wkey() {
  evaljs - <<JS
var cs = [panels(), desktops()], v = "<none>";
for (var k = 0; k < cs.length && v === "<none>"; ++k)
    for (var i = 0; i < cs[k].length && v === "<none>"; ++i) {
        var ws = cs[k][i].widgets("$1");
        if (ws.length > 0) { ws[0].currentConfigGroup = ["General"]; v = String(ws[0].readConfig("$2", "")); }
    }
print(v);
JS
}
# fkey KEY: the [General] KEY of the first Folder View desktop.
fkey() {
  evaljs - <<JS
var ds = desktops(), v = "<none>";
for (var i = 0; i < ds.length; ++i) if (ds[i].type === "org.kde.plasma.folder" || ds[i].type === "org.plasmafusion.desktop") { ds[i].currentConfigGroup = ["General"]; v = String(ds[i].readConfig("$1", "")); break; }
print(v);
JS
}
# popacity top|dock: the opacity of the first top bar (panel with the app name) or dock panel.
popacity() {
  evaljs - <<JS
var ps = panels(), v = "<none>";
for (var i = 0; i < ps.length; ++i) {
    var hit = "$1" === "top" ? ps[i].widgets("org.plasmafusion.appname").length > 0 : ps[i].widgets("org.plasmafusion.dock").length > 0;
    if (hit) { v = String(ps[i].opacity); break; }
}
print(v);
JS
}
# wshortcut PLUGIN: the global shortcut of the first PLUGIN widget in a panel.
wshortcut() {
  evaljs - <<JS
var ps = panels(), v = "<none>";
for (var i = 0; i < ps.length && v === "<none>"; ++i) { var ws = ps[i].widgets("$1"); if (ws.length > 0) v = String(ws[0].globalShortcut); }
print(v);
JS
}
blur_loaded() { qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur; }
# lastget NAME: the value of the last "get NAME" (or dump line) kcmctl printed.
lastget() { grep "^kcmctl: $1=" "$OUT/kcmctl.log" | tail -1 | cut -d= -f2-; }
# gets NAME: every value kcmctl printed for NAME so far, space-separated.
gets() { grep "^kcmctl: $1=" "$OUT/kcmctl.log" | cut -d= -f2- | tr '\n' ' ' | sed 's/ $//'; }
# same_positions A B: "same" when two positions JSON dumps place every file in the same cell (the
# stripe/position entries; the header, which Plasma recomputes from the current row count and grid
# at every save, is not compared), otherwise the differences.
same_positions() {
  python3 - "$1" "$2" <<'PY'
import json, sys
def entries(path):
    try:
        doc = json.loads(open(path).read().strip() or "{}")
    except ValueError:
        return None
    out = {}
    for res, flat in doc.items():
        for i in range(2, len(flat) - 2, 3):
            out[(res, flat[i])] = (flat[i + 1], flat[i + 2])
    return out
a, b = entries(sys.argv[1]), entries(sys.argv[2])
if a is None or b is None or not a:
    print("unreadable or empty")
elif a == b:
    print("same")
else:
    print(" ".join("%s:%s->%s" % (k[1], a.get(k), b.get(k)) for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)))
PY
}
