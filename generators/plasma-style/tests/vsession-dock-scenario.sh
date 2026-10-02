# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Dock scenario for tools/vsession (test use only; seed with make-seed.sh): 88 px dock with stock
# icontasks, Konsole running and Dolphin active, screenshots in dark and light.
exec 2>&1
set -x
kpackagetool6 -t Plasma/Theme -i $HOME/pkg/plasma-fusion-dark
kpackagetool6 -t Plasma/Theme -i $HOME/pkg/plasma-fusion-light
plasma-apply-colorscheme PlasmaFusionDark
plasma-apply-desktoptheme plasma-fusion-dark
evaljs - <<JS
var ps = panels(); for (var i = 0; i < ps.length; i++) { ps[i].remove(); }
var d = desktops()[0];
d.wallpaperPlugin = "org.kde.image";
d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
d.writeConfig("Image", "file://$HOME/.local/share/wallpapers-test/wall-Main.png");
var top = new Panel("org.kde.panel");
top.location = "top"; top.height = 34; top.floating = false; top.lengthMode = "fill"; top.hiding = "none";
top.addWidget("org.kde.plasma.appmenu"); top.addWidget("org.kde.plasma.panelspacer"); top.addWidget("org.kde.plasma.digitalclock"); top.addWidget("org.kde.plasma.panelspacer"); top.addWidget("org.kde.plasma.systemtray");
var dock = new Panel("org.kde.panel");
dock.location = "bottom"; dock.height = 88; dock.floating = true; dock.lengthMode = "fit"; dock.alignment = "center"; dock.hiding = "dodgewindows"; dock.opacity = "translucent";
var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", "applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop,applications:systemsettings.desktop,applications:org.kde.discover.desktop");
JS
sleep 3
kquitapp6 plasmashell; sleep 2
QT_FORCE_STDERR_LOGGING=1 plasmashell >$OUT/plasmashell2.log 2>&1 &
wait_for_name org.kde.plasmashell; sleep 7
konsole >/dev/null 2>&1 & sleep 3
dolphin >/dev/null 2>&1 & sleep 5
cat > $HOME/place.js <<'KJS'
var ws = workspace.windowList();
for (var i = 0; i < ws.length; i++) {
  var w = ws[i];
  if (w.resourceClass == "org.kde.konsole" || w.resourceClass == "konsole") w.frameGeometry = {x: 900, y: 120, width: 480, height: 320};
  if (w.resourceClass == "org.kde.dolphin" || w.resourceClass == "dolphin") { w.frameGeometry = {x: 80, y: 80, width: 720, height: 460}; workspace.activeWindow = w; }
}
KJS
id=$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript $HOME/place.js pfplace); qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start; sleep 3
shot dark-dock-running
plasma-apply-colorscheme PlasmaFusionLight; plasma-apply-desktoptheme plasma-fusion-light
evaljs - <<JS
var d = desktops()[0]; d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"]; d.writeConfig("Image", "file://$HOME/.local/share/wallpapers-test/wall-MainLight.png");
JS
sleep 6
shot light-dock-running
