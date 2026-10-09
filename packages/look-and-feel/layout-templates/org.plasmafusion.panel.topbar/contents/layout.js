/*
    "Add Panel > Plasma Fusion Top Bar": a top bar on the screen the menu was opened on: app name,
    the menu of this screen's windows, clock pill, status icons and quick settings (owner decisions
    8 and 2026-10-09: the status area on every screen). The pen menu only when no Plasma Fusion
    quick settings exists yet (it stays in the main bar); a tray elsewhere lends its settings
    (hidden and unloaded items) to the new one. Sizes as the Global Theme's layout script.

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
var otherTray = null;
for (var p = 0; p < panelIds.length; ++p) {
    var other = panelById(panelIds[p]);
    if (other && other.widgets("org.plasmafusion.quicksettings").length > 0) {
        hasQuickSettings = true;
        if (otherTray === null && other.widgets("org.kde.plasma.systemtray").length > 0) {
            otherTray = other.widgets("org.kde.plasma.systemtray")[0];
        }
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
var tray = add(panel, ["org.kde.plasma.systemtray"]);
if (tray && otherTray) {
    // The tray's item lists and its look. readConfig needs a default of the key's type (null
    // gives undefined): [] for the lists, "" for the others (their text, written back as is).
    var TRAY_LISTS = ["disabledStatusNotifiers", "hiddenItems", "knownItems", "extraItems", "shownItems"];
    var TRAY_VALUES = ["showAllItems", "scaleIconsToFit", "iconSpacing"];
    otherTray.currentConfigGroup = ["General"];
    tray.currentConfigGroup = ["General"];
    for (var k = 0; k < TRAY_LISTS.length; ++k) {
        var list = otherTray.readConfig(TRAY_LISTS[k], []);
        if (list && list.length > 0) {
            tray.writeConfig(TRAY_LISTS[k], list);
        }
    }
    for (var v = 0; v < TRAY_VALUES.length; ++v) {
        var text = otherTray.readConfig(TRAY_VALUES[v], "");
        if (text !== undefined && text !== null && String(text) !== "") {
            tray.writeConfig(TRAY_VALUES[v], text);
        }
    }
    otherTray.currentConfigGroup = [];
    tray.currentConfigGroup = [];
}
if (!hasQuickSettings) {
    add(panel, ["org.plasmafusion.pen"]);
}
add(panel, ["org.plasmafusion.quicksettings"]);
panel.currentConfigGroup = ["PlasmaFusion"];
panel.writeConfig("statusItems", true);
panel.currentConfigGroup = [];
