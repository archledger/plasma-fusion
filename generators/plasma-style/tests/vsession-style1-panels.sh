# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# STYLE-1 panel-frame scenario for tools/vsession (sourced inside a private session; test use only).
# Seed: make-style1-seed.sh with a plain build (PLAIN_THEMES). Logical 1440x900.
# Phase H (the style as staged, --south-frame headroom): the Fusion layout at rest, then a user
# bottom panel of 44 px (not floating, then floating) holding the geometry probe, the stock task
# manager and a clock, each after a shell restart (PanelView clamps a panel to the frame's minimum
# drawing size when the shell starts). Phase P: the same with the plain build (--south-frame plain
# --north-side-margin 0), then the Fusion dock at 72 px (the plain-frame contract), its hover, and
# at 88 px (an unmigrated dock). The probe prints "o1st-probe" lines into the shell logs.
# PHASES in $HOME/pf-tools/style1-coords.sh (default "H P") limits the run.
exec 2>&1
set -x
T=$HOME/pf-tools
export QT_FORCE_STDERR_LOGGING=1
N=0
PHASES="H P"
[ -f "$T/style1-coords.sh" ] && . "$T/style1-coords.sh"
has() { case " $PHASES " in *" $1 "*) return 0 ;; esac; return 1; }
restart_shell() { # $1 label
  N=$((N + 1))
  kquitapp6 plasmashell >/dev/null 2>&1
  for _ in $(seq 1 40); do qdbus-qt6 | grep -q org.kde.plasmashell || break; sleep 0.5; done
  plasmashell >"$OUT/plasmashell-$N-$1.log" 2>&1 &
  wait_for_name org.kde.plasmashell
  sleep 9
}
dismiss_launcher() { kcalc >/dev/null 2>&1 & local kc=$!; sleep 4; kill $kc 2>/dev/null; sleep 2; }
dump_layout() { # $1 label
  { echo "== $1"; evaljs - <<'JS'
var ps = panels(); var o = [];
for (var i = 0; i < ps.length; i++) {
  var p = ps[i];
  o.push("panel " + p.id + " loc=" + p.location + " h=" + p.height + " len=" + p.lengthMode + " float=" + p.floating + " hide=" + p.hiding);
  var ws = p.widgets(); for (var j = 0; j < ws.length; j++) o.push("   " + ws[j].id + " " + ws[j].type);
}
print(o.join("\n"));
JS
  } 2>/dev/null | grep -v '^+' >>"$OUT/layout.txt"
}
add_top_probe() {
  evaljs - <<'JS'
var ps = panels(); for (var i = 0; i < ps.length; i++) if (ps[i].location == "top") ps[i].addWidget("org.plasmafusion.test.probe");
JS
}
user_panel() { # $1 floating true|false
  evaljs - <<JS
var ps = panels();
for (var i = 0; i < ps.length; i++) if (ps[i].location == "bottom") ps[i].remove();
var p = new Panel; p.location = "bottom"; p.height = 44; p.floating = $1; p.lengthMode = "fill"; p.hiding = "none";
p.addWidget("org.plasmafusion.test.probe"); p.addWidget("org.kde.plasma.icontasks"); p.addWidget("org.kde.plasma.digitalclock");
JS
}
set_floating() { # $1 true|false
  evaljs - <<JS
var ps = panels(); for (var i = 0; i < ps.length; i++) if (ps[i].location == "bottom") ps[i].floating = $1;
JS
}
dock_height() { # $1 px
  evaljs - <<JS
var ps = panels(); for (var i = 0; i < ps.length; i++) if (ps[i].location == "bottom") ps[i].height = $1;
JS
}

kpackagetool6 -t Plasma/Applet -i "$HOME/pkg/org.plasmafusion.test.probe" >/dev/null 2>&1
bash "$T/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc-install.log" 2>&1
add_top_probe
if has H; then
  restart_shell H-rest; dismiss_launcher; dump_layout H-rest
  pfinput 'move 700 450' 'sleep 0.5'; shot H-01-rest
  user_panel false
  restart_shell H-user; dump_layout H-user-panel; shot H-02-user-panel
  set_floating true
  restart_shell H-user-float; dump_layout H-user-panel-floating; shot H-03-user-panel-floating
fi

if has P; then
  # Phase P: the plain frames (the switch flipped)
  D=$HOME/.local/share/plasma/desktoptheme
  rm -rf "$D/plasma-fusion-dark" "$D/plasma-fusion-light"
  cp -a "$HOME/pf-plain/plasma-fusion-dark" "$HOME/pf-plain/plasma-fusion-light" "$D/"
  rm -f "$HOME"/.cache/plasma_theme_plasma-fusion-*.kcache "$HOME"/.cache/ksvg-elements*
  restart_shell P-rest; dismiss_launcher; dump_layout P-rest
  user_panel false      # a fresh 44 px panel: the H phase saved its clamped 64 px
  restart_shell P-user; dump_layout P-user-panel; shot P-02-user-panel
  set_floating true
  restart_shell P-user-float; dump_layout P-user-panel-floating; shot P-03-user-panel-floating
  bash "$T/fusion-config.sh" --reset-layout >"$OUT/fc-reset.log" 2>&1
  add_top_probe
  dock_height 72
  restart_shell P-dock72; dismiss_launcher; dump_layout P-dock72
  pfinput 'move 700 450' 'sleep 0.5'; shot P-01-rest-dock72
  pfinput 'move 700 846' 'sleep 1.2'; shot P-04-dock72-hover
  pfinput 'move 700 450' 'sleep 1.0'
  dock_height 88
  restart_shell P-dock88; dismiss_launcher; dump_layout P-dock88
  pfinput 'move 700 450' 'sleep 0.5'; shot P-05-dock88-unmigrated
fi
grep -h o1st-probe "$OUT"/plasmashell-*.log >"$OUT/probe.txt" 2>/dev/null
for f in "$OUT"/plasmashell-*.log; do echo "== $f"; grep -h o1st-probe "$f"; done >"$OUT/probe-by-phase.txt" 2>/dev/null
cp "$HOME/.config/plasmashellrc" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" "$OUT/" 2>/dev/null
true
