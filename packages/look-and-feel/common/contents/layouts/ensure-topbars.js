/*
    Plasma Fusion: a top bar on every screen (owner decision 8, ADAPTIVE 6). Run in plasmashell
    (org.kde.PlasmaShell.evaluateScript) by tools/device/fusion-config.sh --screens, by the Plasma
    Fusion settings and by the KWin script plasmafusion-snap at session start and when a screen is
    added. Nothing happens while plasmafusionrc [TopBar] EveryScreen is false (the settings page's
    "Top bar on every screen" switched off). Idempotent: a screen that already has a top panel gets
    no second one, and a bar is never removed (a screen that goes away takes its panels with it, and
    Plasma brings them back when it returns).

    A new bar follows the settings page's Glass level and top-bar choice (plasmafusionrc [Effects]
    Glass, [TopBar] SolidNextToWindows: opaque for Reduced, else adaptive or translucent; its quick
    settings gets the glass key), as the layout script's bars do. It holds the app name, the global
    menu of that screen's windows and the clock pill, like the bars the layout script puts on the
    other screens, and then the main bar's status area: its system tray (with the tray's settings:
    which items are hidden or not loaded) and quick settings (owner decision 2026-10-09: status
    icons, the bell and quick settings on every screen, as macOS shows its menu bar on each
    display). The system meters come along when the main bar has them (the settings page's "System
    meters in the top bar" is read from the main bar and puts them right before quick settings in
    every top bar). The pen menu stays in the main bar. A Plasma Fusion bar made before that (app name,
    menu and clock only) gets the status area once; the bar is marked ([PlasmaFusion] statusItems),
    so what the user removes later stays removed. The main bar is the Plasma Fusion top bar with
    quick settings or a tray on the lowest screen number (the primary screen is 0); with none (all
    top bars removed), the first bar made here gets Plasma Fusion's own status area and is the main
    bar for the others. Prints one line: "top bars: screens N, added M, completed K".

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

// Tray items the live chips replace, hidden in a tray whose bar has them (the layout script's list).
var TRAY_ITEMS_REPLACED_BY_CHIPS = [
    "plasmashell_microphone",
    "org.kde.plasma.cameraindicator",
    "xdg-desktop-portal-kde",
    "Spectacle"
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

function ensureTopBarsLook() {  // identical to the layout script's fusionLook()
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

(function () {
    var QS = "org.plasmafusion.quicksettings", TRAY = "org.kde.plasma.systemtray", METERS = "org.plasmafusion.meters";
    var CHIPS = "org.plasmafusion.livechips";
    // The settings page's Glass level and top-bar choice (the layout script's fusionLook explains
    // them): a new bar and its quick settings follow them as the page's own bars do.
    var look = ensureTopBarsLook();
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
    var mainMeters = main !== null && has(main, METERS);
    var mainChips = main !== null && has(main, CHIPS);
    // The tray's item lists and its look. readConfig needs a default of the key's type (null
    // gives undefined): [] for the lists, "" for the others (their text, written back as is).
    var TRAY_LISTS = ["disabledStatusNotifiers", "hiddenItems", "knownItems", "extraItems", "shownItems"];
    var TRAY_VALUES = ["showAllItems", "scaleIconsToFit", "iconSpacing"];
    // readConfig's default for a list key that is not set (an empty default cannot tell it from
    // a list the user emptied).
    var UNSET = ["\u0001unset"];
    function copyTray(from, to) {
        from.currentConfigGroup = ["General"];
        to.currentConfigGroup = ["General"];
        for (var k = 0; k < TRAY_LISTS.length; ++k) {
            // A list the user emptied is copied as well (the new tray's own defaults would bring
            // the removed items back); only a list never set is left to the new tray.
            var list = from.readConfig(TRAY_LISTS[k], UNSET);
            if (list && !(list.length === 1 && list[0] === UNSET[0])) {
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
    // The items the live chips replace, added to a tray's hidden lists (what it hides already stays).
    function hideChipItems(tray) {
        tray.currentConfigGroup = ["General"];
        var keys = ["disabledStatusNotifiers", "hiddenItems"];
        for (var k = 0; k < keys.length; ++k) {
            var list = tray.readConfig(keys[k], []) || [];
            if (typeof list === "string") {
                list = list === "" ? [] : list.split(",");
            }
            list = list.slice();
            for (var i = 0; i < TRAY_ITEMS_REPLACED_BY_CHIPS.length; ++i) {
                if (list.indexOf(TRAY_ITEMS_REPLACED_BY_CHIPS[i]) === -1) {
                    list.push(TRAY_ITEMS_REPLACED_BY_CHIPS[i]);
                }
            }
            tray.writeConfig(keys[k], list);
        }
        tray.currentConfigGroup = [];
    }
    function defaultTray(tray, withChips) {
        tray.currentConfigGroup = ["General"];
        var off = TRAY_ITEMS_HIDDEN.concat(TRAY_ITEMS_REPLACED, withChips ? TRAY_ITEMS_REPLACED_BY_CHIPS : []);
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
        // The live chips right before the tray, as the main bar has them (a first bar: when they
        // are installed); before a tray the bar has already, at its place.
        if ((founding ? known.indexOf(CHIPS) !== -1 : mainChips) && !has(bar, CHIPS)) {
            var own = has(bar, TRAY) ? bar.widgets(TRAY)[0] : null;
            var tg = own ? own.geometry : null;
            var chips = tg ? bar.addWidget(CHIPS, Math.max(0, tg.x - 2), 1, -1, -1) : add(bar, [CHIPS]);
            if (chips && typeof chips === "object" && chips.type !== undefined) {
                count++;
                // The bar's own tray hides the items the chips replace, as a tray set up here does.
                if (own) {
                    hideChipItems(own);
                }
            }
        }
        if ((founding || mainTray !== null) && !has(bar, TRAY)) {
            var tray = add(bar, [TRAY]);
            if (tray) {
                if (mainTray !== null) {
                    copyTray(mainTray, tray);
                    // Next to the chips the copy hides the items they replace, as a tray set up
                    // here does (one the user shows again in the main tray included).
                    if (has(bar, CHIPS)) {
                        hideChipItems(tray);
                    }
                } else {
                    defaultTray(tray, has(bar, CHIPS));
                }
                count++;
            }
        }
        if (founding && !has(bar, "org.plasmafusion.pen")) {
            add(bar, ["org.plasmafusion.pen"]);
        }
        // The meters right before quick settings, as the settings page places them: added before
        // it in a bar that gets it here, else at its place (the panel inserts a widget added at a
        // position there).
        var meters = mainMeters && !has(bar, METERS) && known.indexOf(METERS) !== -1;
        if (meters && has(bar, QS)) {
            var g = bar.widgets(QS)[0].geometry;
            var made = g ? bar.addWidget(METERS, Math.max(0, g.x - 2), 1, -1, -1) : bar.addWidget(METERS);
            if (made && typeof made === "object" && made.type !== undefined) {
                count++;
            }
            meters = false;
        }
        if ((founding || mainQs) && !has(bar, QS)) {
            if (meters && add(bar, [METERS])) {
                count++;
            }
            var qs = add(bar, [QS]);
            if (qs) {
                if (look.glass !== "full") {
                    qs.currentConfigGroup = ["General"];
                    qs.writeConfig("glass", look.glass);
                    qs.currentConfigGroup = [];
                }
                count++;
            }
        }
        if (founding) {
            main = bar;
            mainTray = has(bar, TRAY) ? bar.widgets(TRAY)[0] : null;
            mainQs = has(bar, QS);
            mainChips = has(bar, CHIPS);
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
        bar.opacity = look.topOpacity;
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

/*
    A dock on every screen (plasmafusionrc [Dock] EveryScreen=true, the settings page's "Dock on
    every screen"; off by default: one dock, on the main screen, as the layout script makes it). A
    screen without a dock panel gets one like the layout script's (bottom, floating, fit, centred)
    with the main dock's height, hiding and opacity, a hidden launcher of its own (the dock's Start
    opens the launcher of its own panel, so on its own screen) and the main dock's and launcher's
    settings (every [General] key they have set, but the ones that ask for something once: the
    test hooks and requests; a key the power service holds while the battery is low gets the user's
    value from plasmafusionrc [Power] UserWidgetValues). Such a dock and its panel are marked as a
    copy ([PlasmaFusion] everyScreenCopy): when the switch goes off the settings page removes the
    copies' panels, and only those, so docks the user made stay; a copy's panel whose dock the user
    removed still counts for its screen. A dock panel of a screen that is not there is left as it
    is. Every dock then lists only its own screen's windows (showOnlyCurrentScreen); a
    dock that is not a copy keeps the value it had before in its [PlasmaFusion]
    onlyCurrentScreenBefore, which the settings page puts back. The main dock, the one copied, is
    the one on the lowest screen number that is not a copy. When the shell cannot make the dock or
    its launcher (addWidget gives an Error; or the launcher is not installed), the new panel is
    removed again. Idempotent; a dock is never removed
    here. Prints one line: "docks: screens N, added M" (", not made K" when some could not be).
*/
(function () {
    var DOCK = "org.plasmafusion.dock", LAUNCHER = "org.plasmafusion.launcher";
    // Keys of a list type (main.xml): copied as lists; a list read with a text default would come
    // back as one comma-joined entry.
    var LISTS = ["launchers", "launcherFallbacks", "favorites", "hiddenApplications"];
    // Keys that ask a widget for something once, or belong to the one widget.
    var SKIP = ["debugAction", "debugPointerX", "debugHoverIndex", "splitRequest", "activateRequest", "openRequest",
                "showOnlyCurrentScreen"];
    function truthy(value) {
        return value === true || String(value) === "true";
    }
    if (!truthy(ConfigFile("plasmafusionrc", "Dock").readEntry("EveryScreen"))) {
        print("docks: one (plasmafusionrc [Dock] EveryScreen is not true)");
        return;
    }
    if (knownWidgetTypes.indexOf(DOCK) === -1) {
        print("docks: the Plasma Fusion dock is not installed");
        return;
    }
    var ps = panels();
    if (ps.length === 0 || desktops().length === 0) {
        print("docks: skipped, the layout is not loaded yet");
        return;
    }
    // A widget's [PlasmaFusion] KEY ("" when not set).
    function mark(widget, key) {
        widget.currentConfigGroup = ["PlasmaFusion"];
        var value = String(widget.readConfig(key, ""));
        widget.currentConfigGroup = [];
        return value;
    }
    function setMark(widget, key, value) {
        widget.currentConfigGroup = ["PlasmaFusion"];
        widget.writeConfig(key, value);
        widget.currentConfigGroup = [];
    }
    var isCopy = function (dock) { return truthy(mark(dock, "everyScreenCopy")); };
    // A panel made here is marked too: a copy's panel whose dock the user removed is still that
    // screen's (no second panel for it), and goes when the switch is off.
    var copyPanel = function (p) { return truthy(mark(p, "everyScreenCopy")); };
    var onScreen = {}, main = null, unplaced = 0;
    for (var i = 0; i < ps.length; ++i) {
        var docks = ps[i].widgets(DOCK);
        var marked = copyPanel(ps[i]);
        if (docks.length === 0 && !marked) {
            continue;
        }
        // A dock panel of a screen that is not there (Plasma 6.8 keeps it on that screen) is left
        // as it is: its sizes cannot be read (they crash plasmashell), and it takes no screen here.
        if (ps[i].screen < 0 || ps[i].screen >= screenCount) {
            unplaced++;
            continue;
        }
        if (onScreen[ps[i].screen] === undefined) {
            onScreen[ps[i].screen] = ps[i];
        }
        if (docks.length === 0) {
            continue;
        }
        // An original before a copy, then the lowest screen.
        var copy = marked || isCopy(docks[0]);
        if (main === null || (main.copy && !copy) || (main.copy === copy && ps[i].screen < main.panel.screen)) {
            main = { panel: ps[i], copy: copy };
        }
    }
    if (main === null) {
        print("docks: no Plasma Fusion dock to follow");
        return;
    }
    main = main.panel;
    // While the battery is low the power service holds some keys (dock magnification, glass) and
    // keeps the user's values in plasmafusionrc [Power] UserWidgetValues ("WIDGET-ID/key=value,...",
    // plasma-fusion-powerfx): a copy gets the user's value, which the service then holds for it too.
    var held = {};
    String(ConfigFile("plasmafusionrc", "Power").readEntry("UserWidgetValues") || "").split(",").forEach(function (e) {
        var at = e.indexOf("=");
        if (at > 0) {
            held[e.slice(0, at)] = e.slice(at + 1);
        }
    });
    // FROM's [General] keys onto TO (but SKIP), lists as lists, held keys with the user's value.
    function copyKeys(from, to) {
        from.currentConfigGroup = ["General"];
        to.currentConfigGroup = ["General"];
        var keys = from.configKeys || [];
        for (var k = 0; k < keys.length; ++k) {
            var key = String(keys[k]);
            if (SKIP.indexOf(key) !== -1) {
                continue;
            }
            var user = held[from.id + "/" + key];
            if (user !== undefined) {
                to.writeConfig(key, user === "true" ? true : user === "false" ? false : user);
            } else {
                to.writeConfig(key, from.readConfig(key, LISTS.indexOf(key) !== -1 ? [] : ""));
            }
        }
        from.currentConfigGroup = [];
        to.currentConfigGroup = [];
    }
    function made(widget) {
        return widget && typeof widget === "object" && widget.type !== undefined;
    }
    // Lists only its own screen's windows; a dock that is not a copy remembers what it had (once:
    // "" too means not remembered, the settings page empties it when it puts the value back).
    function onlyThisScreen(dock) {
        dock.currentConfigGroup = ["General"];
        var before = dock.readConfig("showOnlyCurrentScreen", "");
        if (!truthy(before)) {
            dock.writeConfig("showOnlyCurrentScreen", true);
        }
        dock.currentConfigGroup = [];
        if (!isCopy(dock) && mark(dock, "onlyCurrentScreenBefore") === "") {
            setMark(dock, "onlyCurrentScreenBefore", truthy(before));
        }
    }
    var mainDock = main.widgets(DOCK)[0];
    var mainLaunchers = main.widgets(LAUNCHER);
    var added = 0, failed = 0;
    for (var sc = 0; sc < screenCount; ++sc) {
        if (onScreen[sc] !== undefined) {
            continue;
        }
        var dockPanel = new Panel;
        dockPanel.screen = sc;
        dockPanel.location = "bottom";
        dockPanel.height = main.height;
        dockPanel.floating = true;
        dockPanel.lengthMode = "fit";
        dockPanel.alignment = "center";
        dockPanel.hiding = main.hiding;
        dockPanel.opacity = main.opacity;
        setMark(dockPanel, "everyScreenCopy", true);
        // A launcher of its own: without one the dock's Start would open another screen's, or
        // none. When the shell cannot make it (or the launcher is not installed) there is no panel
        // either (a later run tries again).
        var launcher = knownWidgetTypes.indexOf(LAUNCHER) !== -1 ? dockPanel.addWidget(LAUNCHER) : null;
        if (!made(launcher)) {
            dockPanel.remove();
            failed++;
            continue;
        }
        if (mainLaunchers.length > 0) {
            copyKeys(mainLaunchers[0], launcher);
        }
        // Next to the Fusion dock the launcher has no button of its own; its pins are the shared
        // ones already (no first-run pins again).
        launcher.currentConfigGroup = ["General"];
        launcher.writeConfig("buttonStyle", "hidden");
        launcher.writeConfig("favoritesPortedToKAstats", true);
        launcher.currentConfigGroup = [];
        var dock = dockPanel.addWidget(DOCK);
        if (!made(dock)) {
            // No dock: no panel for it (a later run tries again).
            dockPanel.remove();
            failed++;
            continue;
        }
        copyKeys(mainDock, dock);
        setMark(dock, "everyScreenCopy", true);
        onlyThisScreen(dock);
        added++;
    }
    // Every dock lists its own screen's windows (a second dock of the user's on a screen too; one
    // of a screen that is not there is left as it is).
    var all = panels();
    for (var j = 0; j < all.length; ++j) {
        if (all[j].screen >= 0 && all[j].screen < screenCount) {
            all[j].widgets(DOCK).forEach(onlyThisScreen);
        }
    }
    print("docks: screens " + screenCount + ", added " + added + (failed > 0 ? ", not made " + failed : "")
          + (unplaced > 0 ? ", " + unplaced + " of a screen not there left as they are" : ""));
})();
