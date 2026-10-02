/*
    Plasma Fusion desktop layout (identical in org.plasmafusion.dark.desktop and
    org.plasmafusion.light.desktop, so switching between dark and light never changes it).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Top bar: a 34 px, full-width, non-floating panel at the top edge (34 px at the design's
    9.75 pt UI font, scaled with the user's text size at layout time), solid next to a maximized
    window and frosted over the desktop (owner decision 5):
        app name | global menu | spacer | clock pill | spacer | system tray | pen | quick settings
    Every other screen gets its own top bar with the app name, the global menu of its own windows
    and the clock pill (owner decision 8; ensure-topbars.js does the same for screens added later).
    Dock: a floating, fit-content, centred panel at the bottom edge, 72 px thick (the visible
        dock; the Plasma style keeps 16 px of transparent headroom above it in the panel window,
        so magnified icons can grow above the dock), hidden when a window covers it.
    Desktop: a Folder View (desktop icons from ~/Desktop in the left column) with weather,
        calendar and CPU/memory cards in a column on the right, drawn on the standard background so
        the wallpaper blur applies; in portrait the first two cards sit side by side under the bar.

    Every Plasma Fusion widget falls back to a stock widget when it is not installed, so the
    layout is never left empty.
*/

// Text scale at layout time, as FusionMetrics computes it in the widgets (docs/parts/lookandfeel.md,
// "Text scale"): the UI font's point size against the design's 9.75 pt (Manrope 13 px), clamped
// to 0.85-1.6. A font without a point size (set in pixels) falls back to the scripting engine's
// grid unit, which is 18 at the design font (24 at 12.75 pt).
function textScale() {
    var pt = NaN;
    var font = ConfigFile("kdeglobals", "General").readEntry("font");
    if (font !== undefined && font !== null && String(font) !== "") {
        pt = parseFloat(String(font).split(",")[1]);
    }
    var s = pt > 0 ? pt / 9.75 : gridUnit / 18;
    return Math.max(0.85, Math.min(1.6, s));
}
var TS = textScale();

// The bar holds text: 34 px at the design font, scaled with it (whole logical px: the scripting
// engine does not know the screen's scale, so the widgets snap their own pills).
var TOP_BAR_THICKNESS = Math.round(34 * TS);
// The dock's tile is its own setting (48 px), not a text size.
var DOCK_THICKNESS = 72;

// Items the quick-settings widget replaces: the status pill, tiles and bell (first six), the
// keyboard-layout badge, phone and clipboard buttons it draws itself, and its media card.
// They stay loaded (the Notifications applet serves the pop-ups and Do Not Disturb, the Clipboard
// applet hosts Klipper; the quick-settings widget relies on both) but the tray shows them nowhere:
// listed in [General] disabledStatusNotifiers, which the 6.7.5 tray applies to every item id, a
// plasmoid's too (systemtraymodel.cpp calculateEffectiveStatus), they get the hidden status, so
// they are neither in the bar nor in the tray's pop-up and do not bring up its expander arrow.
// hiddenItems lists them as well, so a tray that ignored the first key would still only put them
// into its pop-up.
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

// Tray items not loaded at all: the tray's own weather report (enabled by default, passive and
// so behind the expander arrow until it has a location) repeats the desktop weather card and has
// no background duty. Marked as known so the tray does not enable it again.
var TRAY_ITEMS_UNLOADED = [
    "org.kde.plasma.weather"
];

// Tray items hidden the same way (disabledStatusNotifiers and hiddenItems), so the tray has no
// expander arrow (round 2): vaults, removable devices, display configuration and printers stay
// passive most of the time and would only sit behind the arrow; the input-method item because
// quick settings has its own keyboard button (TABLET 4.3). They stay loaded.
var TRAY_ITEMS_HIDDEN = [
    "org.kde.plasma.vault",
    "org.kde.plasma.devicenotifier",
    "org.kde.kscreen",
    "org.kde.plasma.printmanager",
    "org.kde.plasma.manage-inputmethod"
];

// A string-list key of an applet's configuration as an array (the scripting engine returns a
// list, or a comma-separated string for a key it cannot type).
function readList(applet, key) {
    var value = applet.readConfig(key, []);
    if (value === undefined || value === null || value === "") {
        return [];
    }
    if (typeof value === "string") {
        return value.split(",");
    }
    var list = [];
    for (var i = 0; i < value.length; ++i) {
        list.push(String(value[i]));
    }
    return list;
}

var known = knownWidgetTypes;

function installed(pluginId) {
    return known.indexOf(pluginId) !== -1;
}

// Adds the first installed widget of `candidates` to `container`; returns it, or null.
function addFirst(container, candidates) {
    for (var i = 0; i < candidates.length; ++i) {
        if (installed(candidates[i])) {
            var widget = container.addWidget(candidates[i]);
            if (widget && typeof widget === "object" && widget.type !== undefined) {
                return widget;
            }
            print("Plasma Fusion layout: could not add " + candidates[i]);
        }
    }
    print("Plasma Fusion layout: none of " + candidates.join(", ") + " is installed");
    return null;
}

// The stock global menu shows the menu of the active window of its own screen only (its default,
// allScreens=true, puts the menu of a window on screen 2 into screen 1's bar; ADAPTIVE 6).
function appMenuForOwnScreen(menu) {
    if (menu) {
        menu.currentConfigGroup = ["Appearance"];
        menu.writeConfig("allScreens", false);
        menu.currentConfigGroup = [];
    }
    return menu;
}

/* ---------- top bar ---------- */

var topBar = new Panel;
// Stock pop-ups of the bar (system tray and its applets) float under it with every corner
// rounded, as on the boards, only with plasmashellrc [PlasmaViews][Panel <id>]
// floatingApplets=1; scripting has no property for it. The panel view reads it when its
// location is set (and at every start), so it is written first.
var topBarView = ConfigFile(ConfigFile("plasmashellrc", "PlasmaViews"), "Panel " + topBar.id);
topBarView.writeEntry("floatingApplets", 1);
topBar.location = "top";
topBar.height = TOP_BAR_THICKNESS;
topBar.floating = false;
topBar.lengthMode = "fill";
topBar.alignment = "center";
topBar.hiding = "none";
// Solid while a window is maximized or touches it, frosted over the desktop (owner decision 5).
topBar.opacity = "adaptive";

var hasAppName = installed("org.plasmafusion.appname");
var hasLauncher = installed("org.plasmafusion.launcher");
var hasDock = installed("org.plasmafusion.dock");
var launcherPlaced = false;

// Top-left: the Fusion logo button and the active application's name. Without it, the
// launcher (or Kickoff) takes the corner so the application menu stays one click away.
if (hasAppName) {
    addFirst(topBar, ["org.plasmafusion.appname"]);
} else {
    launcherPlaced = addFirst(topBar, ["org.plasmafusion.launcher", "org.kde.plasma.kickoff"]) !== null && hasLauncher;
}
appMenuForOwnScreen(addFirst(topBar, ["org.kde.plasma.appmenu"]));
addFirst(topBar, ["org.kde.plasma.panelspacer"]);

// Centre: workspace dots, date and time. Two expanding spacers keep it on the screen centre.
if (!addFirst(topBar, ["org.plasmafusion.clockpill"])) {
    addFirst(topBar, ["org.kde.plasma.pager"]);
    var clock = addFirst(topBar, ["org.kde.plasma.digitalclock"]);
    if (clock) {
        clock.currentConfigGroup = ["Appearance"];
        clock.writeConfig("showDate", true);
        clock.writeConfig("dateDisplayFormat", 1);  // beside the time
        clock.writeConfig("dateFormat", "custom");
        clock.writeConfig("customDateFormat", "ddd d MMM");
    }
}
addFirst(topBar, ["org.kde.plasma.panelspacer"]);

// Right: the stock tray for application status icons (StatusNotifierItems, shown as usual),
// then the quick-settings status pill.
var tray = addFirst(topBar, ["org.kde.plasma.systemtray"]);
// The pen menu (PEN-1), hidden in laptop posture; its Meta+Shift+W is set by fusion-config.sh --pen,
// not here. Skipped while the pen widget is not installed.
if (installed("org.plasmafusion.pen")) {
    addFirst(topBar, ["org.plasmafusion.pen"]);
}
var quickSettings = addFirst(topBar, ["org.plasmafusion.quicksettings"]);
if (tray) {
    tray.currentConfigGroup = ["General"];
    var trayOff = TRAY_ITEMS_HIDDEN.concat(quickSettings ? TRAY_ITEMS_REPLACED : []);
    tray.writeConfig("disabledStatusNotifiers", trayOff);
    tray.writeConfig("hiddenItems", trayOff);
    // The tray may or may not have enabled its default items yet: either way the unloaded ones
    // end up known (never enabled again) and out of extraItems.
    var knownItems = readList(tray, "knownItems");
    var extraItems = readList(tray, "extraItems");
    var extraChanged = false;
    for (var u = 0; u < TRAY_ITEMS_UNLOADED.length; ++u) {
        if (knownItems.indexOf(TRAY_ITEMS_UNLOADED[u]) === -1) {
            knownItems.push(TRAY_ITEMS_UNLOADED[u]);
        }
        var at = extraItems.indexOf(TRAY_ITEMS_UNLOADED[u]);
        if (at !== -1) {
            extraItems.splice(at, 1);
            extraChanged = true;
        }
    }
    tray.writeConfig("knownItems", knownItems);
    if (extraChanged) {
        tray.writeConfig("extraItems", extraItems);
    }
    tray.currentConfigGroup = [];
}

/* ---------- dock ---------- */

var dock = new Panel;
dock.location = "bottom";
dock.height = DOCK_THICKNESS;
dock.floating = true;
dock.lengthMode = "fit";
dock.alignment = "center";
dock.hiding = "dodgewindows";
dock.opacity = "translucent";

// The centred launcher answers the Meta key and the dock's Start button only while it sits in
// a panel; the dock looks for it in its own panel. Next to the Fusion dock it has no button of
// its own (the dock draws Start); without the Fusion dock it is the Start tile.
if (hasLauncher && !launcherPlaced) {
    var launcher = addFirst(dock, ["org.plasmafusion.launcher"]);
    if (launcher && hasDock) {
        launcher.currentConfigGroup = ["General"];
        launcher.writeConfig("buttonStyle", "hidden");
        launcher.currentConfigGroup = [];
    }
} else if (!hasLauncher && hasAppName) {
    addFirst(dock, ["org.kde.plasma.kickoff"]);
}
if (!addFirst(dock, ["org.plasmafusion.dock"])) {
    addFirst(dock, ["org.kde.plasma.icontasks", "org.kde.plasma.taskmanager"]);
}

/* ---------- other screens ---------- */

// Every other screen gets a top bar of its own: app name, global menu, clock pill (owner decision 8).
// The primary screen keeps the tray, quick settings, the dock and the cards. The same bar is added
// to screens connected later by ensure-topbars.js (fusion-config.sh --screens).
// The primary screen is screen 0 in Plasma 6 (a panel created here has no screen yet: its
// `screen` is not 0 while the script runs, so it cannot tell which screen it is on).
for (var sc = 1; sc < screenCount; ++sc) {
    var bar = new Panel;
    bar.screen = sc;
    ConfigFile(ConfigFile("plasmashellrc", "PlasmaViews"), "Panel " + bar.id).writeEntry("floatingApplets", 1);
    bar.location = "top";
    bar.height = TOP_BAR_THICKNESS;
    bar.floating = false;
    bar.lengthMode = "fill";
    bar.alignment = "center";
    bar.hiding = "none";
    bar.opacity = "adaptive";
    addFirst(bar, ["org.plasmafusion.appname", "org.kde.plasma.kickoff"]);
    appMenuForOwnScreen(addFirst(bar, ["org.kde.plasma.appmenu"]));
    addFirst(bar, ["org.kde.plasma.panelspacer"]);
    if (!addFirst(bar, ["org.plasmafusion.clockpill"])) {
        addFirst(bar, ["org.kde.plasma.digitalclock"]);
    }
    addFirst(bar, ["org.kde.plasma.panelspacer"]);
}

/* ---------- desktop ---------- */

// The desktop is the Plasma Fusion desktop (the Global Theme's defaults name org.plasmafusion.desktop:
// Folder View with the tablet home screen, TABLET2 H1; plain org.kde.plasma.folder is accepted too)
// showing ~/Desktop in the left column, as BACKLOG M1 decided: sorted by hand (sortMode -1), in columns
// from the top left, 48 px icons, no folder pop-ups or tooltips, selection markers and type-ahead.
// Thumbnails only from thumbnailers that are installed.
var FOLDER_KEYS = { url: "desktop:/", sortMode: -1, arrangement: 1, alignment: 0, iconSize: 2, popups: false,
                    toolTips: false, selectionMarkers: true, useTypeAhead: true };
var PREVIEWS = ["imagethumbnail", "jpegthumbnail", "svgthumbnail", "gsthumbnail", "opendocumentthumbnail", "ffmpegthumbs"];
var PLUGIN_DIRS = ["/usr/lib64/qt6/plugins", "/usr/lib/qt6/plugins", "/usr/lib/x86_64-linux-gnu/qt6/plugins",
                   "/run/current-system/sw/lib/qt-6/plugins"];
function installedPreviews() {
    var out = [];
    for (var i = 0; i < PREVIEWS.length; ++i) {
        for (var d = 0; d < PLUGIN_DIRS.length; ++d) {
            if (fileExists(PLUGIN_DIRS[d] + "/kf6/thumbcreator/" + PREVIEWS[i] + ".so")) {
                out.push(PREVIEWS[i]);
                break;
            }
        }
    }
    return out;
}

// Desktop cards in a column on the right, as on the board: weather, calendar, CPU/memory.
// The Plasma Fusion card widgets are drawn at the board's card size (192 px wide; 122, 188 and 92
// px high): a content box of 164 x 94, 164 x 160 and 164 x 64 that follows the text size, plus
// the style's 14 px frame on each side. The desktop places widgets on a 16 px grid, so each card
// is its size rounded up to whole cells: 192 x 128, 192 x 192 and 192 x 96 at the design font,
// 16 px apart (board: 12). Without them the stock widgets take their place, sized from their own
// minimums plus the card background's padding, rounded up to whole cells (they never shrink below
// that):
//   width     21 grid units (the stock calendar's month view is 1.5 times its height)
//   weather   10 grid units high (the stock weather view's minimum)
//   calendar  14 grid units high (the stock month view's minimum)
//   monitor    6 grid units high (two horizontal bars with labels; smaller shows only an icon)
// The column keeps one cell (16 px) from the right edge and from the top bar (board: 22).
// Widgets measure in Kirigami grid units: the UI font's line height, made even (18 px for
// Manrope 13 px), so it follows the text scale.
var GRID_UNIT = 2 * Math.round(9 * TS);
var CELL = 16;
var CARD_PADDING = 14;  // margins of the Plasma style's card background (widgets/background)
// The dock does not reserve space (it hides over windows), so the cards leave its area free by
// hand: the 72 px dock, its 16 px headroom and the 16 px floating gap (ADAPTIVE 5.9).
var DOCK_AREA = 104;
function cells(px) { return Math.ceil(px / CELL) * CELL; }
// A Fusion card: its content box at this text size plus the frame.
function cardSize(width, height) { return { width: cells(width * TS + 2 * CARD_PADDING), height: cells(height * TS + 2 * CARD_PADDING) }; }
var STOCK_WIDTH = cells(GRID_UNIT * 21 + 2 * CARD_PADDING);
var WEATHER_CARD = cardSize(164, 94);
var CALENDAR_CARD = cardSize(164, 160);
var SYSTEM_CARD = cardSize(164, 64);
var CARDS = [
    [{ plugin: "org.plasmafusion.weathercard", width: WEATHER_CARD.width, height: WEATHER_CARD.height },
     { plugin: "org.kde.plasma.weather", width: STOCK_WIDTH, height: cells(GRID_UNIT * 10 + 2 * CARD_PADDING) }],
    [{ plugin: "org.plasmafusion.calendarcard", width: CALENDAR_CARD.width, height: CALENDAR_CARD.height },
     { plugin: "org.kde.plasma.calendar", width: STOCK_WIDTH, height: cells(GRID_UNIT * 14 + 2 * CARD_PADDING) }],
    [{ plugin: "org.plasmafusion.systemcard", width: SYSTEM_CARD.width, height: SYSTEM_CARD.height, monitor: true },
     { plugin: "org.kde.plasma.systemmonitor", width: STOCK_WIDTH, height: cells(GRID_UNIT * 6 + 2 * CARD_PADDING), monitor: true }]
];

// CPU and memory card: horizontal bars, CPU in teal, memory in blue (board colours).
var MONITOR_CONFIG = {
    "Appearance": { chartFace: "org.kde.ksysguard.horizontalbars", title: "CPU and memory", showTitle: false },
    "Sensors": { highPrioritySensorIds: '["cpu/all/usage","memory/physical/usedPercent"]',
                 lowPrioritySensorIds: "[]", totalSensors: "[]" },
    "SensorColors": { "cpu/all/usage": "60,196,176", "memory/physical/usedPercent": "91,157,255" },
    "SensorLabels": { "cpu/all/usage": "CPU", "memory/physical/usedPercent": "Memory" },
    "FaceConfig": { rangeAuto: false, rangeFrom: 0, rangeTo: 100 }
};

// A system monitor added to a running desktop shows its bars only after plasmashell restarts:
// its QML reads Plasmoid.faceController before the applet has created it (plasma-workspace
// 6.7.5, systemmonitor FullRepresentation.qml). tools/device/fusion-config.sh restarts
// plasmashell after building this layout.
function configure(widget, groups) {
    for (var group in groups) {
        widget.currentConfigGroup = [group];
        for (var key in groups[group]) {
            widget.writeConfig(key, groups[group][key]);
        }
    }
    widget.currentConfigGroup = [];
}

// Card places for one screen shape (logical W x H of the whole screen): a right-hand column in
// landscape; in portrait the first two cards side by side under the bar, right-aligned, the rest
// under the right one. Coordinates are relative to the area below the top bar. A card that does not
// fit above the dock area is left out, the CPU/memory card first (ADAPTIVE 5.9): a desktop widget
// that collides is moved to any free spot by Plasma, which scattered the cards (c01).
function cardPlaces(cards, width, height) {
    var free = height - TOP_BAR_THICKNESS - DOCK_AREA - 2 * CELL;
    var list = cards.slice();
    function total(l, portrait) {
        if (!portrait) {
            var h = 0;
            for (var i = 0; i < l.length; ++i) h += l[i].height + (i > 0 ? CELL : 0);
            return h;
        }
        var first = Math.max(l[0] ? l[0].height : 0, l[1] ? l[1].height : 0), rest = 0;
        for (var j = 2; j < l.length; ++j) rest += CELL + l[j].height;
        return first + rest;
    }
    var portrait = height > width;
    while (list.length > 0 && total(list, portrait) > free) {
        var drop = -1;
        for (var k = list.length - 1; k >= 0; --k) if (list[k].monitor) { drop = k; break; }
        list.splice(drop >= 0 ? drop : list.length - 1, 1);
    }
    var places = [];
    if (!portrait) {
        var y = CELL;
        for (var c = 0; c < list.length; ++c) {
            places.push({ card: list[c], x: Math.floor((width - CELL - list[c].width) / CELL) * CELL, y: y });
            y += list[c].height + CELL;
        }
        return places;
    }
    var right = list.length > 1 ? list[1] : list[0];
    if (!right) {
        return places;
    }
    var xr = Math.floor((width - CELL - right.width) / CELL) * CELL;
    var yNext = CELL + right.height + CELL;
    if (list.length > 1) {
        var left = list[0];
        places.push({ card: left, x: Math.max(Math.floor((xr - CELL - left.width) / CELL) * CELL, 0), y: CELL });
        yNext = CELL + Math.max(left.height, right.height) + CELL;
    }
    places.push({ card: right, x: xr, y: CELL });
    for (var r = 2; r < list.length; ++r) {
        places.push({ card: list[r], x: Math.floor((width - CELL - list[r].width) / CELL) * CELL, y: yNext });
        yNext += list[r].height + CELL;
    }
    return places;
}
function geometries(places) {
    var value = "";
    for (var i = 0; i < places.length; ++i) {
        if (places[i].widget) {
            value += "Applet-" + places[i].widget.id + ":" + places[i].x + "," + places[i].y + ","
                   + places[i].card.width + "," + places[i].card.height + ",0;";
        }
    }
    return value;
}

var desktopsArray = desktopsForActivity(currentActivity());
var cardDesktop = null;
var previews = installedPreviews();
for (var j = 0; j < desktopsArray.length; j++) {
    var desktop = desktopsArray[j];
    desktop.wallpaperPlugin = "org.kde.image";
    // The wallpaper is left unset on purpose: Plasma then shows the Global Theme's default
    // (PlasmaFusion), and its light or dark image follows the Plasma style.
    if (desktop.type !== "org.plasmafusion.desktop" && desktop.type !== "org.kde.plasma.folder") {
        print("Plasma Fusion layout: desktop " + desktop.id + " is " + desktop.type
              + "; restart plasmashell after applying the theme, then reset the layout");
    }
    desktop.currentConfigGroup = ["General"];
    for (var fk in FOLDER_KEYS) {
        desktop.writeConfig(fk, FOLDER_KEYS[fk]);
    }
    if (previews.length > 0) {
        desktop.writeConfig("previewPlugins", previews);
    }
    desktop.currentConfigGroup = [];
    // The cards go on the primary screen (screen 0), or the first screen there is.
    if (desktop.screen >= 0 && (cardDesktop === null || desktop.screen < cardDesktop.screen)) {
        cardDesktop = desktop;
    }
}

if (cardDesktop !== null) {
    var desktop = cardDesktop;
    var geometry = screenGeometry(desktop.screen);
    var chosen = [];
    for (var c = 0; c < CARDS.length; ++c) {
        var card = null;
        for (var k = 0; k < CARDS[c].length && card === null; ++k) {
            if (installed(CARDS[c][k].plugin)) {
                card = CARDS[c][k];
            }
        }
        if (card === null) {
            print("Plasma Fusion layout: none of the card widgets " + CARDS[c].map(function (e) { return e.plugin; }).join(", ")
                  + " is installed, card skipped");
            continue;
        }
        chosen.push(card);
    }
    var W = Math.round(geometry.width), H = Math.round(geometry.height);
    var here = cardPlaces(chosen, W, H);
    for (var h = 0; h < here.length; ++h) {
        // A new desktop widget's card takes exactly this rectangle (its padding is added later,
        // inside it).
        var widget = desktop.addWidget(here[h].card.plugin, here[h].x, here[h].y, here[h].card.width, here[h].card.height);
        if (!widget || typeof widget !== "object" || widget.type === undefined) {
            print("Plasma Fusion layout: could not add " + here[h].card.plugin);
            continue;
        }
        here[h].widget = widget;
        widget.userBackgroundHints = "StandardBackground";
        if (here[h].card.monitor && here[h].card.plugin === "org.kde.plasma.systemmonitor") {
            configure(widget, MONITOR_CONFIG);
        }
    }
    // Places for the other orientation and for the ThinkPad X13's panel (1440 x 900 at 4/3), under
    // the containment's per-size keys and its landscape/portrait fallbacks (desktop containment
    // main.qml: ItemGeometries-WxH, then ItemGeometriesHorizontal / ItemGeometriesVertical). A card
    // left out for one shape has no entry there and keeps its last place.
    function placesFor(w, hh) {
        var p = cardPlaces(chosen, w, hh);
        for (var i = 0; i < p.length; ++i) {
            for (var n = 0; n < here.length; ++n) {
                if (here[n].card === p[i].card) {
                    p[i].widget = here[n].widget;
                }
            }
        }
        return p;
    }
    var landscape = W >= H ? [W, H] : [H, W];
    var shapes = [[landscape[0], landscape[1]], [landscape[1], landscape[0]], [1440, 900], [900, 1440]];
    desktop.currentConfigGroup = [];
    for (var sh = 0; sh < shapes.length; ++sh) {
        var value = geometries(placesFor(shapes[sh][0], shapes[sh][1]));
        desktop.writeConfig("ItemGeometries-" + shapes[sh][0] + "x" + shapes[sh][1], value);
        if (sh === 0) {
            desktop.writeConfig("ItemGeometriesHorizontal", value);
        } else if (sh === 1) {
            desktop.writeConfig("ItemGeometriesVertical", value);
        }
    }
}
