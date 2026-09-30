# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
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
