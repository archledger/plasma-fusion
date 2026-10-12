/*
    "Add Panel > Plasma Fusion Dock": the dock as the Global Theme's layout script builds it: a
    floating, fit-content, centred bar at the bottom edge, 88 px thick (72 px of dock plus 16 px of
    headroom for magnified icons), hidden over windows, opaque with the settings page's Reduced
    glass. The centred launcher goes with it (no button of its own next to the Fusion dock).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
// The settings page's look (plasmafusionrc [Effects] Glass, [TopBar] SolidNextToWindows), as the
// Global Theme's layout script applies it (its fusionLook explains it;
// tools/build.d/60-lookandfeel.sh checks that the function is the same).
function fusionLook() {
    var glass = String(ConfigFile("plasmafusionrc", "Effects").readEntry("Glass")).toLowerCase();
    if (glass !== "reduced" && glass !== "solid") {
        glass = "full";
    }
    var solidNextToWindows = String(ConfigFile("plasmafusionrc", "TopBar").readEntry("SolidNextToWindows")) !== "false";
    return {
        glass: glass,
        topOpacity: glass === "reduced" ? "opaque" : solidNextToWindows ? "adaptive" : "translucent",
        dockOpacity: glass === "reduced" ? "opaque" : "translucent"
    };
}
var look = fusionLook();
function withGlass(widget) {
    if (widget && look.glass !== "full") {
        widget.currentConfigGroup = ["General"];
        widget.writeConfig("glass", look.glass);
        widget.currentConfigGroup = [];
    }
    return widget;
}
var known = knownWidgetTypes;
function add(container, candidates) {
    for (var i = 0; i < candidates.length; ++i) {
        if (known.indexOf(candidates[i]) !== -1) {
            var widget = container.addWidget(candidates[i]);
            if (widget && typeof widget === "object" && widget.type !== undefined) {
                return widget;
            }
        }
    }
    return null;
}
var panel = new Panel;
panel.location = "bottom";
panel.height = 88;
panel.floating = true;
panel.lengthMode = "fit";
panel.alignment = "center";
panel.hiding = "dodgewindows";
panel.opacity = look.dockOpacity;
var hasLauncherPanel = false;
for (var p = 0; p < panelIds.length; ++p) {
    var other = panelById(panelIds[p]);
    if (other && other.id !== panel.id && other.widgets("org.plasmafusion.launcher").length > 0) {
        hasLauncherPanel = true;
    }
}
if (!hasLauncherPanel && known.indexOf("org.plasmafusion.dock") !== -1) {
    var launcher = withGlass(add(panel, ["org.plasmafusion.launcher"]));
    if (launcher) {
        launcher.currentConfigGroup = ["General"];
        launcher.writeConfig("buttonStyle", "hidden");
        launcher.currentConfigGroup = [];
    }
}
if (!withGlass(add(panel, ["org.plasmafusion.dock"]))) {
    add(panel, ["org.kde.plasma.icontasks", "org.kde.plasma.taskmanager"]);
}
