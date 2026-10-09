/*
    Plasma Fusion: a top bar on every screen (owner decision 8, ADAPTIVE 6). Run in plasmashell
    (org.kde.PlasmaShell.evaluateScript) by tools/device/fusion-config.sh --screens, by the Plasma
    Fusion settings and by the KWin script plasmafusion-snap at session start and when a screen is
    added. Nothing happens while plasmafusionrc [TopBar] EveryScreen is false (the settings page's
    "Top bar on every screen" switched off). Idempotent: a screen that already has a top panel gets
    no second one, and a bar is never removed (a screen that goes away takes its panels with it, and
    Plasma brings them back when it returns).

    A new bar holds the app name, the global menu of that screen's windows and the clock pill, like
    the bars the layout script puts on the other screens, and then the main bar's status area: its
    system tray (with the tray's settings: which items are hidden or not loaded) and quick settings
    (owner decision 2026-10-09: status icons, the bell and quick settings on every screen, as macOS
    shows its menu bar on each display). The pen menu stays in the main bar. A Plasma Fusion bar
    made before that (app name, menu and clock only) gets the status area once; the bar is marked
    ([PlasmaFusion] statusItems), so what the user removes later stays removed. The main bar is the
    Plasma Fusion top bar with quick settings or a tray on the lowest screen number (the primary
    screen is 0); with none (all top bars removed), the first bar made here gets Plasma Fusion's
    own status area and is the main bar for the others. Prints one line: "top bars: screens N,
    added M, completed K".

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// The layout script's tray lists (org.kde.plasma.desktop-layout.js explains them; the build checks
// they are the same), for a first bar's tray when no other bar has one to copy.
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

function ensureTopBarsTextScale() {  // identical to the layout script's textScale()
    var pt = NaN;
    var font = ConfigFile("kdeglobals", "General").readEntry("font");
    if (font !== undefined && font !== null && String(font) !== "") {
        pt = parseFloat(String(font).split(",")[1]);
    }
    var s = pt > 0 ? pt / 9.75 : gridUnit / 18;
    return Math.max(0.85, Math.min(1.6, s));
}

(function () {
    var QS = "org.plasmafusion.quicksettings", TRAY = "org.kde.plasma.systemtray";
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
    function has(panel, type) {
        return panel.widgets(type).length > 0;
    }
    function fusionBar(panel) {
        return has(panel, "org.plasmafusion.appname") || has(panel, "org.plasmafusion.clockpill");
    }
    function truthy(value) {
        return value === true || String(value) === "true";
    }
    if (String(ConfigFile("plasmafusionrc", "TopBar").readEntry("EveryScreen")) === "false") {
        print("top bars: off (plasmafusionrc [TopBar] EveryScreen=false)");
        return;
    }
    var ps = panels();
    // Only once plasmashell has loaded its layout: KWin runs this after its own start too, and a
    // plasmashell that answered before loading its panels got a second top bar (ThinkPad,
    // 2026-09-30). A top panel without a screen (not placed yet, or kept from a screen that went
    // away) may still be placed by Plasma, so no bar is added while one exists.
    if (ps.length === 0 || desktops().length === 0) {
        print("top bars: skipped, the layout is not loaded yet");
        return;
    }
    var unplaced = 0;
    // Screens with a top panel (any), and each screen's Plasma Fusion top bar (one with the status
    // area first): another top panel on the same screen must not hide the Fusion bar.
    var occupied = {};
    var fusionOn = {};
    var main = null;
    for (var i = 0; i < ps.length; ++i) {
        if (ps[i].location !== "top") {
            continue;
        }
        if (ps[i].screen < 0 || ps[i].screen >= screenCount) {
            unplaced++;
            continue;
        }
        occupied[ps[i].screen] = true;
        var chosen = fusionOn[ps[i].screen];
        if (fusionBar(ps[i]) && (chosen === undefined || (!has(chosen, QS) && has(ps[i], QS)))) {
            fusionOn[ps[i].screen] = ps[i];
        }
        if (fusionBar(ps[i]) && (has(ps[i], QS) || has(ps[i], TRAY)) && (main === null || ps[i].screen < main.screen)) {
            main = ps[i];
        }
    }
    if (unplaced > 0) {
        print("top bars: skipped, " + unplaced + " top panel(s) without a screen");
        return;
    }
    var mainTray = main !== null && has(main, TRAY) ? main.widgets(TRAY)[0] : null;
    var mainQs = main !== null && has(main, QS);
    // The tray's item lists and its look. readConfig needs a default of the key's type (null
    // gives undefined): [] for the lists, "" for the others (their text, written back as is).
    var TRAY_LISTS = ["disabledStatusNotifiers", "hiddenItems", "knownItems", "extraItems", "shownItems"];
    var TRAY_VALUES = ["showAllItems", "scaleIconsToFit", "iconSpacing"];
    function copyTray(from, to) {
        from.currentConfigGroup = ["General"];
        to.currentConfigGroup = ["General"];
        for (var k = 0; k < TRAY_LISTS.length; ++k) {
            var list = from.readConfig(TRAY_LISTS[k], []);
            if (list && list.length > 0) {
                to.writeConfig(TRAY_LISTS[k], list);
            }
        }
        for (var v = 0; v < TRAY_VALUES.length; ++v) {
            var text = from.readConfig(TRAY_VALUES[v], "");
            if (text !== undefined && text !== null && String(text) !== "") {
                to.writeConfig(TRAY_VALUES[v], text);
            }
        }
        from.currentConfigGroup = [];
        to.currentConfigGroup = [];
    }
    // As the layout script sets up a tray: the items quick settings replaces and the passive ones
    // hidden, the ones with no use (and Disks & Devices, which quick settings replaces) not loaded.
    function defaultTray(tray) {
        tray.currentConfigGroup = ["General"];
        var off = TRAY_ITEMS_HIDDEN.concat(TRAY_ITEMS_REPLACED);
        tray.writeConfig("disabledStatusNotifiers", off);
        tray.writeConfig("hiddenItems", off);
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
    // The main bar's tray and quick settings, after what the bar has (the pen menu stays in the
    // main bar); then the mark. With no main bar yet, a bar made here (all top bars were removed)
    // gets Plasma Fusion's own status area (tray set up as above, pen menu, quick settings) and
    // becomes the main bar for the next screens; an existing bar is left as it is and unmarked (a
    // layout the user made without a status area), to be completed once a main bar has one.
    // Returns how many widgets were added.
    function statusArea(bar, made) {
        var count = 0;
        if (main === null && !made) {
            return 0;
        }
        var founding = main === null;
        if ((founding || mainTray !== null) && !has(bar, TRAY)) {
            var tray = add(bar, [TRAY]);
            if (tray) {
                if (mainTray !== null) {
                    copyTray(mainTray, tray);
                } else {
                    defaultTray(tray);
                }
                count++;
            }
        }
        if (founding && !has(bar, "org.plasmafusion.pen")) {
            add(bar, ["org.plasmafusion.pen"]);
        }
        if ((founding || mainQs) && !has(bar, QS) && add(bar, [QS])) {
            count++;
        }
        if (founding) {
            main = bar;
            mainTray = has(bar, TRAY) ? bar.widgets(TRAY)[0] : null;
            mainQs = has(bar, QS);
        }
        bar.currentConfigGroup = ["PlasmaFusion"];
        bar.writeConfig("statusItems", true);
        bar.currentConfigGroup = [];
        return count;
    }
    var added = 0, completed = 0;
    for (var sc = 0; sc < screenCount; ++sc) {
        var bar = fusionOn[sc];
        if (bar !== undefined) {
            if (bar !== main) {
                bar.currentConfigGroup = ["PlasmaFusion"];
                var marked = truthy(bar.readConfig("statusItems", false));
                bar.currentConfigGroup = [];
                if (!marked && statusArea(bar, false) > 0) {
                    completed++;
                }
            }
            continue;
        }
        if (occupied[sc]) {
            continue;
        }
        bar = new Panel;
        bar.screen = sc;
        ConfigFile(ConfigFile("plasmashellrc", "PlasmaViews"), "Panel " + bar.id).writeEntry("floatingApplets", 1);
        bar.location = "top";
        bar.height = Math.round(34 * ensureTopBarsTextScale());
        bar.floating = false;
        bar.lengthMode = "fill";
        bar.alignment = "center";
        bar.hiding = "none";
        bar.opacity = "adaptive";
        add(bar, ["org.plasmafusion.appname", "org.kde.plasma.kickoff"]);
        var menu = add(bar, ["org.kde.plasma.appmenu"]);
        if (menu) {
            menu.currentConfigGroup = ["Appearance"];
            menu.writeConfig("allScreens", false);
            menu.currentConfigGroup = [];
        }
        add(bar, ["org.kde.plasma.panelspacer"]);
        if (!add(bar, ["org.plasmafusion.clockpill"])) {
            add(bar, ["org.kde.plasma.digitalclock"]);
        }
        add(bar, ["org.kde.plasma.panelspacer"]);
        statusArea(bar, true);
        added++;
    }
    print("top bars: screens " + screenCount + ", added " + added + ", completed " + completed);
})();
