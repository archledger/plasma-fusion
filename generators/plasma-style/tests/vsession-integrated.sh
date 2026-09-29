# Integrated Plasma style scenario for tools/vsession (sourced inside the private session; test
# use only). Seed with make-integrated-seed.sh. Applies Plasma Fusion Dark with the Global Theme
# layout (tools/device/fusion-config.sh), adds two test widgets to the top bar, then opens the
# system tray, quick settings, the clock pop-up, a pop-up full of PC3 controls, a notification,
# a rich tooltip, the volume OSD and KRunner; then the same in Plasma Fusion Light.
# VARIANTS="dark" or "light" limits the run (default: both). A file pf-tools/floating-applets in the
# seed sets plasmashellrc floatingApplets=1 on the top bar first.
exec 2>&1
set -x
T=$HOME/pf-tools
export XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg QT_FORCE_STDERR_LOGGING=1
VARIANTS=${VARIANTS:-"dark light"}
kpackagetool6 -t Plasma/Applet -i "$HOME/pkg/org.plasmafusion.pstest" >/dev/null 2>&1

merge_kdedefaults() {
  [ -f "$T/merge-kdedefaults.py" ] && python3 "$T/merge-kdedefaults.py" kwinrc kcminputrc >>"$OUT/merge.log" 2>&1
  qdbus-qt6 org.kde.KWin /KWin reconfigure
}

# The Fusion launcher may open itself when it is added to a panel; it closes when another
# window takes focus.
dismiss_launcher() { kcalc >/dev/null 2>&1 & local kc=$!; sleep 4; kill $kc 2>/dev/null; sleep 2; }

dump_layout() {
  evaljs - <<'JS'
var ps = panels(); var o = [];
for (var i = 0; i < ps.length; i++) {
  var p = ps[i];
  o.push("panel " + p.id + " loc=" + p.location + " h=" + p.height + " len=" + p.lengthMode + " float=" + p.floating + " hide=" + p.hiding);
  var ws = p.widgets(); for (var j = 0; j < ws.length; j++) o.push("   " + ws[j].id + " " + ws[j].type);
}
print(o.join("\n"));
JS
}

inv() { qdbus-qt6 org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate widget $1"; }

restart_shell() { # $1 log name
  kquitapp6 plasmashell >/dev/null 2>&1
  for _ in $(seq 1 40); do qdbus-qt6 | grep -q org.kde.plasmashell || break; sleep 0.5; done
  plasmashell >"$OUT/$1" 2>&1 &
  wait_for_name org.kde.plasmashell
  sleep 8
}

setup_test_widgets() {
  evaljs - <<'JS'
var ps = panels(); var top = null;
for (var i = 0; i < ps.length; i++) if (ps[i].location == "top") top = ps[i];
var find = function (p, t) { var ws = p.widgets(); for (var j = 0; j < ws.length; j++) if (ws[j].type == t) return ws[j]; return null; };
var pt = top.addWidget("org.plasmafusion.pstest");
var rt = top.addWidget("org.plasmafusion.pstest"); rt.currentConfigGroup = ["General"]; rt.writeConfig("mode", "richtip");
var tray = find(top, "org.kde.plasma.systemtray");
var qs = find(top, "org.plasmafusion.quicksettings");
var clk = find(top, "org.plasmafusion.clockpill") || find(top, "org.kde.plasma.digitalclock");
var keys = [[tray, "F1"], [qs, "F2"], [clk, "F3"], [pt, "F4"], [rt, "F5"]];
var out = "IDS";
for (var k = 0; k < keys.length; k++) {
  var w = keys[k][0];
  if (w) { w.globalShortcut = "Ctrl+Alt+Shift+" + keys[k][1]; out += " " + w.id; } else { out += " 0"; }
}
print(out);
JS
}

IDS=""
for v in $VARIANTS; do
  if [ "$v" = dark ]; then
    bash "$T/fusion-config.sh" --reset-layout >"$OUT/config-dark.log" 2>&1
  else
    bash "$T/fusion-config.sh" --light --keep-layout >"$OUT/config-light.log" 2>&1
  fi
  merge_kdedefaults
  if [ -z "$IDS" ]; then
    IDS=$(setup_test_widgets | grep -o 'IDS.*')
    echo "test widgets: $IDS"
    # optional: pop-ups of the top bar float below it with all corners rounded (the boards);
    # the Global Theme layout does not set this key yet (docs/parts/plasma-style.md)
    if [ -e "$T/floating-applets" ]; then
      TOPID=$(evaljs - <<'JS' | tr -dc '0-9'
var ps = panels(); for (var i = 0; i < ps.length; i++) if (ps[i].location == "top") print(ps[i].id);
JS
)
      kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $TOPID" --key floatingApplets 1
    fi
  fi
  # a fresh shell: test widgets read their configuration, and its log is ours
  restart_shell "plasmashell-$v.log"
  dismiss_launcher
  read -r _ TRAY QS CLK PT RT <<<"$IDS"
  dump_layout >"$OUT/layout-$v.txt" 2>&1
  sleep 2
  shot "$v-01-desktop"
  inv "$TRAY"; sleep 2.5; shot "$v-02-tray"; inv "$TRAY"; sleep 1
  inv "$QS"; sleep 2.5; shot "$v-03-quicksettings"; inv "$QS"; sleep 1
  inv "$CLK"; sleep 2.5; shot "$v-04-clock"; inv "$CLK"; sleep 1
  inv "$PT"; sleep 2.5; shot "$v-05-controls"; inv "$PT"; sleep 1
  notify-send -a Browser -i internet-web-browser "Download finished" "plasma-fusion.iso · 2.9 GB · Downloads"
  sleep 2; shot "$v-06-notification"
  qdbus-qt6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.volumeChanged 64 100
  sleep 0.8; shot "$v-08-osd"
  sleep 2
  # KRunner started here: D-Bus activation has no Wayland display in this session
  qdbus-qt6 | grep -q org.kde.krunner || { krunner >"$OUT/krunner-$v.log" 2>&1 & sleep 3; }
  qdbus-qt6 org.kde.krunner /App org.kde.krunner.App.display; sleep 2.5; shot "$v-09-krunner"
  qdbus-qt6 org.kde.krunner /App org.kde.krunner.App.toggleDisplay; sleep 1
  qdbus-qt6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu; sleep 2.5; shot "$v-10-launcher"
  dismiss_launcher
  # last: the test tooltip stays up until the shell restarts
  inv "$RT"; sleep 1.5; shot "$v-07-tooltip"
done
cp "$HOME"/.config/plasmashellrc "$HOME"/.config/plasmarc "$HOME"/.config/kwinrc "$HOME"/.config/plasma-org.kde.plasma.desktop-appletsrc "$OUT/" 2>/dev/null
cp "$HOME/.local/state/plasma-fusion/plasmashell.log" "$OUT/plasmashell-config.log" 2>/dev/null
true
