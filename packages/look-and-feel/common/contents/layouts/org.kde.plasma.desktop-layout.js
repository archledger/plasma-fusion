/*
    Plasma Fusion desktop layout (identical in org.plasmafusion.dark.desktop and
    org.plasmafusion.light.desktop, so switching between dark and light never changes it).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Top bar: a 34 px, full-width, non-floating panel at the top edge:
        app name | global menu | spacer | clock pill | spacer | system tray | quick settings
    Dock: a floating, fit-content, centred panel at the bottom edge, 88 px thick
        (72 px of visible dock plus 16 px of transparent headroom that the Plasma style keeps
        clear, so magnified icons can grow above the dock), hidden when a window covers it.
    Desktop: the "Desktop" containment with weather, calendar and CPU/memory cards in a column
        on the right, drawn on the standard background so the wallpaper blur applies.

    Every Plasma Fusion widget falls back to a stock widget when it is not installed, so the
    layout is never left empty.
*/

var TOP_BAR_THICKNESS = 34;
var DOCK_THICKNESS = 88;

// Items the quick-settings widget replaces: the status pill, tiles and bell (first six), the
// keyboard-layout badge, phone and clipboard buttons it draws itself, and its media card.
// They stay loaded (notification popups, network secrets, battery warnings, Klipper and KDE
// Connect keep working) but move into the tray's hidden section.
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

/* ---------- top bar ---------- */

var topBar = new Panel;
topBar.location = "top";
topBar.height = TOP_BAR_THICKNESS;
topBar.floating = false;
topBar.lengthMode = "fill";
topBar.alignment = "center";
topBar.hiding = "none";
topBar.opacity = "translucent";

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
addFirst(topBar, ["org.kde.plasma.appmenu"]);
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

// Right: the stock tray for app status icons (keyboard layout, KDE Connect, clipboard...),
// then the quick-settings status pill.
var tray = addFirst(topBar, ["org.kde.plasma.systemtray"]);
var quickSettings = addFirst(topBar, ["org.plasmafusion.quicksettings"]);
if (tray && quickSettings) {
    tray.currentConfigGroup = ["General"];
    tray.writeConfig("hiddenItems", TRAY_ITEMS_REPLACED);
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

/* ---------- desktop ---------- */

// Desktop cards in a column on the right, as on the board: weather, calendar, CPU/memory.
// The desktop places widgets on a 16 px grid and never makes a widget smaller than it asks
// for, so the cards are sized from the stock widgets' own minimums plus the card background's
// padding, rounded up to whole cells, and stacked so they never collide:
//   width     21 grid units (the stock calendar's month view is 1.5 times its height)
//   weather   10 grid units high (the stock weather view's minimum)
//   calendar  14 grid units high (the stock month view's minimum)
//   monitor    6 grid units high (two horizontal bars with labels; smaller shows only an icon)
// The column keeps one cell (16 px) from the right edge and from the top bar.
// Widgets measure in Kirigami grid units (the UI font's line height: 18 px for Manrope 13 px);
// the scripting engine's own `gridUnit` is the height of an "M", so it is not used here.
var GRID_UNIT = 18;
var CELL = 16;
var CARD_PADDING = 14;  // margins of the Plasma style's card background (widgets/background)
function cells(px) { return Math.ceil(px / CELL) * CELL; }
var CARD_WIDTH = cells(GRID_UNIT * 21 + 2 * CARD_PADDING);
var CARDS = [
    { plugin: "org.kde.plasma.weather", height: cells(GRID_UNIT * 10 + 2 * CARD_PADDING) },
    { plugin: "org.kde.plasma.calendar", height: cells(GRID_UNIT * 14 + 2 * CARD_PADDING) },
    { plugin: "org.kde.plasma.systemmonitor", height: cells(GRID_UNIT * 6 + 2 * CARD_PADDING) }
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

var desktopsArray = desktopsForActivity(currentActivity());
var cardDesktop = null;
for (var j = 0; j < desktopsArray.length; j++) {
    var desktop = desktopsArray[j];
    desktop.wallpaperPlugin = "org.kde.image";
    // The wallpaper is left unset on purpose: Plasma then shows the Global Theme's default
    // (PlasmaFusion), and its light or dark image follows the Plasma style.
    if (desktop.type !== "org.kde.desktopcontainment") {
        print("Plasma Fusion layout: desktop " + desktop.id + " is " + desktop.type
              + "; restart plasmashell after applying the theme, then reset the layout");
    }
    // The cards go on the primary screen (screen 0), or the first screen there is.
    if (desktop.screen >= 0 && (cardDesktop === null || desktop.screen < cardDesktop.screen)) {
        cardDesktop = desktop;
    }
}

if (cardDesktop !== null) {
    var desktop = cardDesktop;
    // Coordinates are relative to the area left free by the top bar.
    var geometry = screenGeometry(desktop.screen);
    var x = Math.floor((geometry.width - CELL - CARD_WIDTH) / CELL) * CELL;
    var y = CELL;
    for (var c = 0; c < CARDS.length; ++c) {
        var card = CARDS[c];
        if (!installed(card.plugin)) {
            print("Plasma Fusion layout: " + card.plugin + " not installed, card skipped");
            continue;
        }
        var isMonitor = card.plugin === "org.kde.plasma.systemmonitor";
        // A new desktop widget's card takes exactly this rectangle (its padding is added later,
        // inside it).
        var widget = desktop.addWidget(card.plugin, x, y, CARD_WIDTH, card.height);
        if (!widget || typeof widget !== "object" || widget.type === undefined) {
            print("Plasma Fusion layout: could not add " + card.plugin);
            continue;
        }
        widget.userBackgroundHints = "StandardBackground";
        if (isMonitor) {
            configure(widget, MONITOR_CONFIG);
        }
        y += card.height + CELL;
    }
}
