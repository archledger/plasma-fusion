# Plasma style scenario for tools/vsession (sourced inside the private session; test use only).
# Seed with make-seed.sh. Builds a 34 px top bar and an 88 px floating dock with stock widgets,
# then screenshots pop-ups, the tray, the calendar, a notification, tooltips and the OSD in
# plasma-fusion-dark and plasma-fusion-light.
exec 2>&1
set -x
VARIANTS=${VARIANTS:-"dark light"}
kpackagetool6 -t Plasma/Theme -i $HOME/pkg/plasma-fusion-dark
kpackagetool6 -t Plasma/Theme -i $HOME/pkg/plasma-fusion-light
kpackagetool6 -t Plasma/Applet -i $HOME/pkg/org.plasmafusion.pstest
fc-cache -f >/dev/null 2>&1

inv() { qdbus-qt6 org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate widget $1"; }

apply_variant() {
  local v=$1 wall=$2 scheme=$3
  plasma-apply-colorscheme $scheme
  plasma-apply-desktoptheme plasma-fusion-$v
  evaljs - <<JS
var d = desktops()[0];
d.wallpaperPlugin = "org.kde.image";
d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
d.writeConfig("Image", "file://$HOME/.local/share/wallpapers-test/$wall");
JS
}

LAYOUT=$(evaljs - <<'JS'
var ps = panels(); for (var i = 0; i < ps.length; i++) { ps[i].remove(); }
var d = desktops()[0];
var w = d.widgets(); for (var i = 0; i < w.length; i++) { w[i].remove(); }
var top = new Panel("org.kde.panel");
top.location = "top"; top.height = 34; top.floating = false; top.lengthMode = "fill"; top.hiding = "none"; top.opacity = "translucent";
top.addWidget("org.kde.plasma.kickoff");
top.addWidget("org.kde.plasma.appmenu");
top.addWidget("org.kde.plasma.panelspacer");
var clk = top.addWidget("org.kde.plasma.digitalclock");
top.addWidget("org.kde.plasma.panelspacer");
var rt = top.addWidget("org.plasmafusion.pstest"); rt.currentConfigGroup = ["General"]; rt.writeConfig("mode", "richtip");
var pt = top.addWidget("org.plasmafusion.pstest");
var tray = top.addWidget("org.kde.plasma.systemtray");
var dock = new Panel("org.kde.panel");
dock.location = "bottom"; dock.height = 88; dock.floating = true; dock.lengthMode = "fit"; dock.alignment = "center"; dock.hiding = "dodgewindows"; dock.opacity = "translucent";
var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop,applications:systemsettings.desktop,applications:org.kde.discover.desktop,applications:org.kde.spectacle.desktop");
var dt = dock.addWidget("org.plasmafusion.pstest"); dt.currentConfigGroup = ["General"]; dt.writeConfig("mode", "tip");
var cal = d.addWidget("org.kde.plasma.calendar", 1180, 60, 230, 230);
var cpu = d.addWidget("org.kde.plasma.systemmonitor.cpu", 1180, 310, 230, 140);
clk.globalShortcut = "Ctrl+Alt+Shift+F1"; tray.globalShortcut = "Ctrl+Alt+Shift+F2";
rt.globalShortcut = "Ctrl+Alt+Shift+F3"; pt.globalShortcut = "Ctrl+Alt+Shift+F4"; dt.globalShortcut = "Ctrl+Alt+Shift+F5";
print("IDS " + clk.id + " " + tray.id + " " + rt.id + " " + pt.id + " " + dt.id + " " + top.id + " " + dock.id);
JS
)
echo "layout: $LAYOUT"
read -r _ CLK TRAY RT PT DT TOPID DOCKID <<<"$(echo "$LAYOUT" | grep -o 'IDS.*')"
sleep 2
# restart the shell: widget configs are read fresh and QML warnings go to a log we keep
kquitapp6 plasmashell; sleep 2
[ "${FLOATING_APPLETS:-1}" = 1 ] && kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $TOPID" --key floatingApplets 1
QT_FORCE_STDERR_LOGGING=1 plasmashell >$OUT/plasmashell2.log 2>&1 &
wait_for_name org.kde.plasmashell; sleep 8

for v in $VARIANTS; do
  case $v in
    dark) apply_variant dark wall-Main.png PlasmaFusionDark ;;
    light) apply_variant light wall-MainLight.png PlasmaFusionLight ;;
    breeze) plasma-apply-colorscheme BreezeDark; plasma-apply-desktoptheme breeze-dark ;;
  esac
  sleep 7
  shot $v-01-desktop
  inv $PT; sleep 2.5; shot $v-02-popup; inv $PT; sleep 1
  inv $TRAY; sleep 2.5; shot $v-03-tray; inv $TRAY; sleep 1
  inv $CLK; sleep 2.5; shot $v-04-calendar; inv $CLK; sleep 1
  notify-send -a Browser -i internet-web-browser "Download finished" "plasma-fusion.iso · 2.9 GB · Downloads"
  sleep 2; shot $v-05-notification
  inv $RT; sleep 1.5; shot $v-06-tooltip-rich
  inv $DT; sleep 1.5; shot $v-07-tooltip-dock
  qdbus-qt6 org.kde.plasmashell /org/kde/osdService org.kde.osdService.volumeChanged 64 100
  sleep 0.8; shot $v-08-osd
  sleep 5
done
cp $HOME/.config/plasmashellrc $HOME/.config/plasmarc $HOME/.config/plasma-org.kde.plasma.desktop-appletsrc $OUT/ 2>/dev/null
grep -i -E 'plasma-fusion|desktoptheme|svg|qml|warn|error' $OUT/plasmashell2.log | grep -v -i 'kf.kirigami' | head -80 > $OUT/plasmashell-filtered.txt
