/*
    "Add Panel > Plasma Fusion Top Bar": a top bar on the screen the menu was opened on. The full
    bar (status icons, pen menu, quick settings) when no Plasma Fusion quick settings exists yet,
    else the bar of the other screens: app name, the menu of this screen's windows, clock pill
    (owner decision 8). Sizes as the Global Theme's layout script.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
function textScale() {
    var pt = NaN;
    var font = ConfigFile("kdeglobals", "General").readEntry("font");
    if (font !== undefined && font !== null && String(font) !== "") {
        pt = parseFloat(String(font).split(",")[1]);
    }
    var s = pt > 0 ? pt / 9.75 : gridUnit / 18;
    return Math.max(0.85, Math.min(1.6, s));
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
var hasQuickSettings = false;
for (var p = 0; p < panelIds.length; ++p) {
    var other = panelById(panelIds[p]);
    if (other && other.widgets("org.plasmafusion.quicksettings").length > 0) {
        hasQuickSettings = true;
    }
}
var panel = new Panel;
ConfigFile(ConfigFile("plasmashellrc", "PlasmaViews"), "Panel " + panel.id).writeEntry("floatingApplets", 1);
panel.location = "top";
panel.height = Math.round(34 * textScale());
panel.floating = false;
panel.lengthMode = "fill";
panel.alignment = "center";
panel.hiding = "none";
panel.opacity = "adaptive";
add(panel, ["org.plasmafusion.appname", "org.kde.plasma.kickoff"]);
var menu = add(panel, ["org.kde.plasma.appmenu"]);
if (menu) {
    menu.currentConfigGroup = ["Appearance"];
    menu.writeConfig("allScreens", false);
    menu.currentConfigGroup = [];
}
add(panel, ["org.kde.plasma.panelspacer"]);
if (!add(panel, ["org.plasmafusion.clockpill"])) {
    add(panel, ["org.kde.plasma.digitalclock"]);
}
add(panel, ["org.kde.plasma.panelspacer"]);
if (!hasQuickSettings) {
    add(panel, ["org.kde.plasma.systemtray"]);
    add(panel, ["org.plasmafusion.pen"]);
    add(panel, ["org.plasmafusion.quicksettings"]);
}
