/*
    "Add Panel > Plasma Fusion Top Bar": a top bar on the screen the menu was opened on: app name,
    the menu of this screen's windows, clock pill, status icons and quick settings (owner decisions
    8 and 2026-10-09: the status area on every screen). The pen menu only when no Plasma Fusion
    quick settings exists yet (it stays in the main bar); a tray elsewhere lends its settings
    (hidden and unloaded items) to the new one. Sizes, and the settings page's Glass level and
    top-bar choice, as the Global Theme's layout script; the main bar's hiding.

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
// The layout script's tray lists (packages/look-and-feel/common/contents/layouts/
// org.kde.plasma.desktop-layout.js, which explains them; tools/build.d/60-lookandfeel.sh checks that
// they are the same), for the first top bar, which has no other tray to copy from.
var TRAY_ITEMS_REPLACED = [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.volume",
    "org.kde.plasma.battery",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.brightness",
    "org.kde.plasma.notifications",
    "org.kde.plasma.keyboardlayout",
    "org.kde.kdeconnect",
    "org.kde.plasma.clipboard",
    "org.kde.plasma.mediacontroller"
];
var TRAY_ITEMS_UNLOADED = [
    "org.kde.plasma.weather"
];
var TRAY_ITEMS_UNLOADED_WITH_QUICK_SETTINGS = [
    "org.kde.plasma.devicenotifier"
];
var TRAY_ITEMS_HIDDEN = [
    "org.kde.plasma.vault",
    "org.kde.plasma.devicenotifier",
    "org.kde.kscreen",
    "org.kde.plasma.printmanager",
    "org.kde.plasma.manage-inputmethod"
];
// Tray items the live chips replace, hidden in a tray whose bar has them (the layout script's list).
var TRAY_ITEMS_REPLACED_BY_CHIPS = [
    "plasmashell_microphone",
    "org.kde.plasma.cameraindicator",
    "xdg-desktop-portal-kde",
    "Spectacle"
];

var hasQuickSettings = false;
var otherTray = null;
// The main bar's hiding (the settings page's "Hide the top bar automatically", board
// Island.dc.html), in tablet posture the one it goes back to: the new bar takes it, from the first
// Fusion top bar on a screen (the app name, the clock pill or quick settings, the settings page's
// test; plasmashell reads a missing screen's from an invalid config and crashes).
var otherHiding = "none", hidingFound = false;
for (var p = 0; p < panelIds.length; ++p) {
    var other = panelById(panelIds[p]);
    if (!other) {
        continue;
    }
    if (other.widgets("org.plasmafusion.quicksettings").length > 0) {
        hasQuickSettings = true;
        if (otherTray === null && other.widgets("org.kde.plasma.systemtray").length > 0) {
            otherTray = other.widgets("org.kde.plasma.systemtray")[0];
        }
    }
    var fusionBar = other.widgets("org.plasmafusion.appname").length > 0 || other.widgets("org.plasmafusion.clockpill").length > 0
        || other.widgets("org.plasmafusion.quicksettings").length > 0;
    if (fusionBar && !hidingFound && other.screen >= 0 && other.screen < screenCount) {
        other.currentConfigGroup = ["PlasmaFusion"];
        var otherTablet = other.readConfig("tabletApplied", false) === true || String(other.readConfig("tabletApplied", "")) === "true";
        otherHiding = String(otherTablet ? other.readConfig("laptopHiding", "none") : other.hiding) === "autohide" ? "autohide" : "none";
        other.currentConfigGroup = [];
        hidingFound = true;
    }
}
var panel = new Panel;
ConfigFile(ConfigFile("plasmashellrc", "PlasmaViews"), "Panel " + panel.id).writeEntry("floatingApplets", 1);
panel.location = "top";
panel.height = Math.round(34 * textScale());
panel.floating = false;
panel.lengthMode = "fill";
panel.alignment = "center";
panel.hiding = otherHiding;
panel.opacity = look.topOpacity;
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
// The live chips at the start of the right cluster, right before the tray.
var chips = add(panel, ["org.plasmafusion.livechips"]);
var tray = add(panel, ["org.kde.plasma.systemtray"]);
if (tray && otherTray) {
    // The tray's item lists and its look. readConfig needs a default of the key's type (null
    // gives undefined): [] for the lists, "" for the others (their text, written back as is).
    var TRAY_LISTS = ["disabledStatusNotifiers", "hiddenItems", "knownItems", "extraItems", "shownItems"];
    var TRAY_VALUES = ["showAllItems", "scaleIconsToFit", "iconSpacing"];
    // readConfig's default for a list key that is not set (an empty default cannot tell it from
    // a list the user emptied).
    var UNSET = ["\u0001unset"];
    otherTray.currentConfigGroup = ["General"];
    tray.currentConfigGroup = ["General"];
    for (var k = 0; k < TRAY_LISTS.length; ++k) {
        // A list the user emptied is copied as well (the new tray's own defaults would bring
        // the removed items back); only a list never set is left to the new tray.
        var list = otherTray.readConfig(TRAY_LISTS[k], UNSET);
        var copied = list && !(list.length === 1 && list[0] === UNSET[0]);
        // This bar has the live chips: its tray hides the items they replace, whether the other
        // tray did (a bar with chips) or not (a bar from before them, or without them).
        if (chips && (TRAY_LISTS[k] === "disabledStatusNotifiers" || TRAY_LISTS[k] === "hiddenItems")) {
            var items = [];
            for (var i = 0; copied && i < list.length; ++i) {
                items.push(String(list[i]));
            }
            for (var c = 0; c < TRAY_ITEMS_REPLACED_BY_CHIPS.length; ++c) {
                if (items.indexOf(TRAY_ITEMS_REPLACED_BY_CHIPS[c]) === -1) {
                    items.push(TRAY_ITEMS_REPLACED_BY_CHIPS[c]);
                }
            }
            list = items;
            copied = true;
        }
        if (copied) {
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
} else if (tray) {
    // The first top bar: the items quick settings replaces and the passive ones hidden, the ones
    // with no use (and Disks & Devices, which quick settings replaces) known and not loaded.
    tray.currentConfigGroup = ["General"];
    var trayOff = TRAY_ITEMS_HIDDEN.concat(TRAY_ITEMS_REPLACED, chips ? TRAY_ITEMS_REPLACED_BY_CHIPS : []);
    tray.writeConfig("disabledStatusNotifiers", trayOff);
    tray.writeConfig("hiddenItems", trayOff);
    var knownItems = tray.readConfig("knownItems", []) || [];
    var extraItems = tray.readConfig("extraItems", []) || [];
    var unloaded = TRAY_ITEMS_UNLOADED.concat(TRAY_ITEMS_UNLOADED_WITH_QUICK_SETTINGS);
    for (var u = 0; u < unloaded.length; ++u) {
        if (knownItems.indexOf(unloaded[u]) === -1) {
            knownItems.push(unloaded[u]);
        }
        extraItems = extraItems.filter(function (item) { return item !== unloaded[u]; });
    }
    tray.writeConfig("knownItems", knownItems);
    tray.writeConfig("extraItems", extraItems);
    tray.currentConfigGroup = [];
}
if (!hasQuickSettings) {
    add(panel, ["org.plasmafusion.pen"]);
}
withGlass(add(panel, ["org.plasmafusion.quicksettings"]));
panel.currentConfigGroup = ["PlasmaFusion"];
panel.writeConfig("statusItems", true);
panel.currentConfigGroup = [];
