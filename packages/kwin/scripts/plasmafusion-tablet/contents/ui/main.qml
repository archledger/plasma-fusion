/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kwin

// Plasma Fusion tablet mode (TABLET.md 3 and 4.2): the single owner of window policy and panel
// geometry while the device is folded.
//
// - Posture comes from KWin's own TabletModeManager (FusionTablet: one D-Bus read, then its
//   signals). Nothing happens until KWin has answered, so a stale start value never moves windows.
// - At once on every change: the panel script in plasmashell (top bar round(44 x text scale),
//   dock 80 and its tablet hiding; the laptop values are kept in plasmashell's own config).
// - After 300 ms of a stable posture: window policy. Apps open maximized and without title bars
//   (placement "Maximizing", borderless maximized windows), eligible open windows are maximized,
//   tiled windows lose their title bar. Only while a built-in screen is the only screen, and only
//   with WindowMode = fullscreen.
// - Leaving: windows this script maximized are restored (KWin gives back their laptop geometry);
//   windows first opened in tablet mode get 70 % of the work area, centred; the options come back.
//   Windows the user un-maximized in tablet mode are not touched.
// - A KWin reconfigure reloads the options from kwinrc; they are set again at once (synchronously,
//   so KWin does not give every maximized window its frame back).
// - Disabling the script (the kill switch) leaves tablet mode for the windows first.
//
// Settings: kwinrc [Script-plasmafusion-tablet] (contents/config/main.xml). Other parts write
// them with kwriteconfig6 --notify and then invoke the shortcut "Plasma Fusion: Tablet Window
// Mode", which re-reads them. No timers run while idle.
//
// Split view (TABLET2 M1, SplitDivider.qml): while the policy is applied and the active window is
// quick-tiled left or right with another window on the other side, a handle on the split resizes
// both (snaps to 1/3, 1/2, 2/3; portrait 1/2; into the outer 12 % it ends the split).
Item {
    id: root

    FusionTablet {
        id: tabletState
    }

    // Two apps side by side: the handle on the split (TABLET2 M1).
    SplitDivider {
        script: root
    }

    // ---------------------------------------------------------------- settings

    function setting(key, fallback) {
        const value = KWin.readConfig(key, fallback);
        if (typeof fallback === "boolean") {
            return value === true || value === "true";
        }
        return value === undefined || value === null || String(value) === "" ? fallback : String(value);
    }
    function windowMode() {
        return setting("WindowMode", "fullscreen") === "windowed" ? "windowed" : "fullscreen";
    }
    function dockHiding() {
        // Tent posture (TABLET2 N2/N9, the dock writes TentPosture): the bottom edge rests on the
        // table, so the bottom swipe cannot bring the dock; it stays visible.
        if (setting("TentPosture", false)) {
            return "none";
        }
        return setting("DockHiding", "dodgewindows") === "none" ? "none" : "dodgewindows";
    }

    // ---------------------------------------------------------------- posture

    // Tablet posture as KWin reports it; false until KWin has answered.
    readonly property bool known: tabletState.fromKWin
    readonly property bool tablet: known && tabletState.tablet

    // Deferred: when KWin's first answer arrives, `known` and `tablet` change in the same turn;
    // Qt.callLater runs once, after both are settled (a direct handler saw a stale `tablet` first).
    onTabletChanged: Qt.callLater(postureChanged)
    onKnownChanged: Qt.callLater(postureChanged)

    function postureChanged() {
        if (!known) {
            return;
        }
        log("posture " + (tablet ? "tablet" : "laptop"));
        applyPanels();
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: root.sync()
    }

    function log(message) {
        console.info("plasmafusion-tablet: " + message);
    }

    // ---------------------------------------------------------------- window policy

    readonly property int placementMaximizing: 9 // KWin::PlacementPolicy::Maximizing

    // State while window policy is applied.
    property bool applied: false
    property bool busy: false
    property int laptopPlacement: -1
    property bool laptopBorderless: false
    property bool laptopMoveEnabled: true
    property bool moveChanged: false
    property var maximizedByUs: ({}) // internalId -> true: maximized by enter()
    property var openedInTablet: ({}) // internalId -> true: opened (maximized) while applied
    property var borderlessTiles: ({}) // internalId -> true: title bar removed from a tiled window
    property var tileHandlers: ({}) // internalId -> [window, handler]

    function key(w) {
        return String(w.internalId);
    }

    function internalOutput(output) {
        if (!output) {
            return false;
        }
        const name = String(output.name);
        const prefixes = setting("InternalOutputs", "eDP,LVDS,DSI").split(",");
        for (let i = 0; i < prefixes.length; ++i) {
            const p = prefixes[i].trim();
            if (p !== "" && name.startsWith(p)) {
                return true;
            }
        }
        return false;
    }

    // Window policy only while a built-in screen is the only screen (TABLET 3.5): with an external
    // monitor, tablet mode changes only the shell's sizes and touch behaviour.
    function policyAllowed() {
        const screens = Workspace.screens;
        return windowMode() === "fullscreen" && screens.length === 1 && internalOutput(screens[0]);
    }

    function eligible(w) {
        return w && !w.deleted && w.normalWindow && w.maximizable && !w.fullScreen && !w.minimized
            && !w.skipTaskbar && !w.transient && !w.modal && internalOutput(w.output);
    }

    // Whether the window may grow to the work area (placement "Maximizing" asks the same).
    function fitsMaximized(w) {
        const area = Workspace.clientArea(Workspace.MaximizeArea, w);
        return w.maxSize.width >= area.width && w.maxSize.height >= area.height;
    }

    // Placement "Maximizing" skips a window that comes with its own position (an X11 app with
    // position hints, e.g. Chrome restoring its last window: the owner's screencast of 2026-10-02
    // showed it opening at 743x606 in tablet posture). Such a window is maximized here like the
    // windows open when tablet posture starts, and gets its own geometry back in laptop posture.
    // Checked 200 ms after it appears: a Wayland window that placement maximized reports it once
    // the app has confirmed the new size.
    property var openedWindows: []
    Timer {
        id: openedCheck
        interval: 200
        onTriggered: {
            const list = root.openedWindows;
            root.openedWindows = [];
            for (let i = 0; i < list.length; ++i) {
                const w = list[i];
                if (root.applied && root.eligible(w) && w.maximizeMode !== 3 && !w.tile && root.fitsMaximized(w)) {
                    root.maximizedByUs[root.key(w)] = true;
                    w.setMaximize(true, true);
                    root.log("maximized on open: " + w.resourceClass);
                }
            }
        }
    }

    function sync() {
        const want = tablet && policyAllowed();
        if (want && !applied) {
            enter();
        } else if (!want && applied) {
            leave();
        }
    }

    function enter() {
        busy = true;
        laptopPlacement = Options.placement;
        laptopBorderless = Options.borderlessMaximizedWindows;
        Options.placement = placementMaximizing;
        Options.borderlessMaximizedWindows = true;
        moveChanged = setting("DisableWindowMove", false);
        if (moveChanged) {
            laptopMoveEnabled = Options.interactiveWindowMoveEnabled;
            Options.interactiveWindowMoveEnabled = false;
        }
        applied = true;
        const ws = Workspace.stackingOrder;
        let maximized = 0, tiles = 0;
        for (let i = 0; i < ws.length; ++i) {
            const w = ws[i];
            if (!eligible(w)) {
                continue;
            }
            follow(w);
            if (w.tile) {
                if (!w.noBorder) {
                    w.noBorder = true;
                    borderlessTiles[key(w)] = true;
                    tiles++;
                }
            } else if (w.maximizeMode !== 3) {
                maximizedByUs[key(w)] = true;
                w.setMaximize(true, true);
                maximized++;
            }
        }
        busy = false;
        log("enter: placement " + laptopPlacement + " -> " + Options.placement + ", borderless " + laptopBorderless
            + " -> true, maximized " + maximized + ", tiles without title bar " + tiles);
    }

    // 70 % of the work area, centred on the window's parent when it has one (dialogs), else on
    // the output: for windows that never had a laptop geometry.
    function restoreRect(w) {
        const area = Workspace.clientArea(Workspace.MaximizeArea, w);
        const width = Math.round(area.width * 0.7), height = Math.round(area.height * 0.7);
        let cx = area.x + area.width / 2, cy = area.y + area.height / 2;
        const parent = w.transient ? w.transientFor : null;
        if (parent && !parent.deleted) {
            const g = parent.frameGeometry;
            cx = g.x + g.width / 2;
            cy = g.y + g.height / 2;
        }
        const x = Math.round(Math.max(area.x, Math.min(cx - width / 2, area.x + area.width - width)));
        const y = Math.round(Math.max(area.y, Math.min(cy - height / 2, area.y + area.height - height)));
        return Qt.rect(x, y, width, height);
    }

    function leave() {
        busy = true;
        const ws = Workspace.stackingOrder;
        let restored = 0, placed = 0, tiles = 0;
        // Un-maximize first, while borderless is still on: KWin gives the title bar back on
        // un-maximize only while the option is set.
        for (let i = 0; i < ws.length; ++i) {
            const w = ws[i];
            if (!w || w.deleted) {
                continue;
            }
            const k = key(w);
            if (w.maximizeMode === 3 && maximizedByUs[k]) {
                w.setMaximize(false, false);
                restored++;
            } else if (w.maximizeMode === 3 && openedInTablet[k]) {
                w.setMaximize(false, false, restoreRect(w));
                placed++;
            }
            if (borderlessTiles[k] && w.noBorder) {
                w.noBorder = false;
                tiles++;
            }
        }
        unfollowAll();
        Options.placement = laptopPlacement;
        Options.borderlessMaximizedWindows = laptopBorderless;
        if (moveChanged) {
            Options.interactiveWindowMoveEnabled = laptopMoveEnabled;
            moveChanged = false;
        }
        // Windows still maximized (the user maximized them in tablet mode) get their title bar
        // back, as Workspace::slotReconfigure does when the option goes off.
        if (!laptopBorderless) {
            for (let i = 0; i < ws.length; ++i) {
                const w = ws[i];
                if (w && !w.deleted && w.maximizeMode === 3 && w.noBorder) {
                    w.noBorder = false;
                }
            }
        }
        maximizedByUs = ({});
        openedInTablet = ({});
        borderlessTiles = ({});
        applied = false;
        busy = false;
        log("leave: restored " + restored + ", placed " + placed + ", tiles with title bar " + tiles
            + ", placement " + Options.placement + ", borderless " + Options.borderlessMaximizedWindows);
    }

    // Tiled windows follow their tile while window policy is applied: quick-tiling a borderless
    // maximized window gives it its title bar back, so a tile gets noBorder again (TABLET 4.2).
    // Maximize changes are followed too: a window the user un-maximizes (the window card's
    // "Full screen" switch, LEAD-1 resolution 11) keeps its title bar and is left alone until
    // the next fold; one that never had a laptop geometry gets 70 % of the work area.
    function follow(w) {
        const k = key(w);
        if (tileHandlers[k]) {
            return;
        }
        const onTile = function () {
            root.tileChanged(w);
        };
        const onMaximize = function () {
            root.maximizeChanged(w);
        };
        w.tileChanged.connect(onTile);
        w.maximizedChanged.connect(onMaximize);
        tileHandlers[k] = [w, onTile, onMaximize];
    }
    function unfollowAll() {
        for (const k in tileHandlers) {
            const entry = tileHandlers[k];
            if (entry[0] && !entry[0].deleted) {
                entry[0].tileChanged.disconnect(entry[1]);
                entry[0].maximizedChanged.disconnect(entry[2]);
            }
        }
        tileHandlers = ({});
    }
    function tileChanged(w) {
        if (!applied || !w || w.deleted) {
            return;
        }
        const k = key(w);
        if (w.tile) {
            if (!w.noBorder) {
                w.noBorder = true;
            }
            borderlessTiles[k] = true;
        } else if (borderlessTiles[k] && w.maximizeMode !== 3) {
            w.noBorder = false;
            delete borderlessTiles[k];
        }
    }

    // Un-maximized by the user: settled after the event loop turn, so that a quick tile (which
    // un-maximizes first) has its tile by then and enter()/leave() are over.
    property var unmaximized: [] // windows un-maximized outside enter()/leave()
    function maximizeChanged(w) {
        if (!applied || busy || !w || w.deleted || w.maximizeMode === 3) {
            return;
        }
        unmaximized.push(w);
        Qt.callLater(settleUnmaximized);
    }
    function settleUnmaximized() {
        const list = unmaximized;
        unmaximized = [];
        for (let i = 0; i < list.length; ++i) {
            const w = list[i];
            if (!applied || !w || w.deleted || w.maximizeMode === 3 || w.tile) {
                continue;
            }
            const k = key(w);
            const placed = openedInTablet[k] === true;
            delete maximizedByUs[k];
            delete openedInTablet[k];
            if (placed) {
                w.frameGeometry = restoreRect(w);
            }
            log("windowed by the user: " + w.resourceClass + (placed ? ", placed at 70 %" : "") + ", title bar " + !w.noBorder);
        }
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) {
            if (!w) {
                return;
            }
            if (w.dock && String(w.resourceClass) === "plasmashell") {
                panelsAppeared.restart();
            }
            if (!root.applied) {
                return;
            }
            // Placement "Maximizing" opened it maximized (resizable dialogs and transients too,
            // owner decision 2): it has no laptop geometry to go back to.
            if (w.maximizeMode === 3) {
                root.openedInTablet[root.key(w)] = true;
            }
            if (root.eligible(w)) {
                root.follow(w);
                root.openedWindows.push(w);
                openedCheck.restart();
            }
        }
        function onWindowRemoved(w) {
            if (!w) {
                return;
            }
            const k = root.key(w);
            delete root.maximizedByUs[k];
            delete root.openedInTablet[k];
            delete root.borderlessTiles[k];
            delete root.tileHandlers[k];
        }
        function onScreensChanged() {
            // An external monitor switches window policy off (or on again when it goes).
            if (root.known) {
                debounce.restart();
            }
        }
    }

    // A KWin reconfigure reloads the options from kwinrc (also once about 0.2 s after every session
    // start): set the tablet values again at once, inside the change handler, so that
    // Workspace::slotReconfigure finds the borderless option unchanged. The reloaded values are the
    // user's laptop values.
    Connections {
        target: Options
        function onPlacementChanged() {
            if (root.applied && !root.busy && Options.placement !== root.placementMaximizing) {
                root.laptopPlacement = Options.placement;
                Options.placement = root.placementMaximizing;
                root.log("placement set again after a reconfigure (laptop value " + root.laptopPlacement + ")");
            }
        }
        function onBorderlessMaximizedWindowsChanged() {
            if (root.applied && !root.busy && !Options.borderlessMaximizedWindows) {
                root.laptopBorderless = false;
                Options.borderlessMaximizedWindows = true;
                root.log("borderless set again after a reconfigure");
            }
        }
        function onInteractiveWindowMoveEnabledChanged() {
            if (root.applied && !root.busy && root.moveChanged && Options.interactiveWindowMoveEnabled) {
                root.laptopMoveEnabled = true;
                Options.interactiveWindowMoveEnabled = false;
            }
        }
    }

    // ---------------------------------------------------------------- panels

    // The panel script (TABLET 3.6), run in plasmashell. Idempotent; never touches panels the user
    // added. The tablet top bar height uses the layout script's text scale. The laptop height is
    // saved once per panel and never as the tablet height (a plasmashell that restarted in tablet
    // posture must not make the tablet size the laptop size). TABLET 3.6 also switched the stock
    // appmenu's compactView here; that write crashed plasmashell 6.7.5 (the applet changes its
    // representation inside the scripting writeConfig while its layout is updated), so the
    // compact menu is left to the top-bar widgets.
    // The built-in screen's scale (the tablet heights are snapped to its device pixels).
    function internalScale() {
        const screens = Workspace.screens;
        for (let i = 0; i < screens.length; ++i) {
            if (internalOutput(screens[i])) {
                return screens[i].devicePixelRatio;
            }
        }
        return screens.length > 0 ? screens[0].devicePixelRatio : 1;
    }
    // Pixel grid (research H-hidpi 3.6, owner OK 2026-10-01): the tablet top bar and dock get the
    // smallest height at or above their size that is a whole number of device pixels at the screen's
    // scale, so their edges are crisp: at 4/3 the top bar 44 -> 45 (60 px), the dock 80 -> 81 (108 px)
    // and the dock's bottom strip 20 -> 21 (28 px; its config tabletStripHeight, as plasmashell's QML
    // only sees Wayland's rounded integer scale); at 1.25, 1.5 or 2 the sizes stay. The laptop sizes
    // are the boards' and stay as they are.
    function panelScript(isTablet, hiding) {
        return "var TABLET = " + (isTablet ? "true" : "false") + ", DOCK_HIDING = \"" + hiding + "\", SCALE = " + internalScale() + ";\n"
            + "function snap(h) {\n"
            + "    if (!(SCALE > 0)) return h;\n"
            + "    for (var x = h; x < h + 6; ++x) { var d = x * SCALE; if (Math.abs(d - Math.round(d)) < 0.01) return x; }\n"
            + "    return h;\n"
            + "}\n"
            + "var HEIGHT_DOCK = snap(80), STRIP = snap(20);\n"
            + "function textScale() {\n"
            + "    var pt = NaN, font = ConfigFile(\"kdeglobals\", \"General\").readEntry(\"font\");\n"
            + "    if (font !== undefined && font !== null && String(font) !== \"\") pt = parseFloat(String(font).split(\",\")[1]);\n"
            + "    var s = pt > 0 ? pt / 9.75 : gridUnit / 18;\n"
            + "    return Math.max(0.85, Math.min(1.6, s));\n"
            + "}\n"
            + "var HEIGHT_TOP = snap(Math.round(44 * textScale())), done = [];\n"
            + "panels().forEach(function (p) {\n"
            + "    var ws = p.widgets(), types = [];\n"
            + "    for (var i = 0; i < ws.length; ++i) types.push(ws[i].type);\n"
            + "    var isTop = types.indexOf(\"org.plasmafusion.quicksettings\") >= 0 || types.indexOf(\"org.plasmafusion.clockpill\") >= 0;\n"
            + "    var isDock = types.indexOf(\"org.plasmafusion.dock\") >= 0;\n"
            + "    if (!isTop && !isDock) return;\n"
            + "    p.currentConfigGroup = [\"PlasmaFusion\"];\n"
            + "    var applied = p.readConfig(\"tabletApplied\", false) === true || p.readConfig(\"tabletApplied\", \"\") === \"true\";\n"
            + "    var h = isTop ? HEIGHT_TOP : HEIGHT_DOCK, laptop = isTop ? Math.round(34 * textScale()) : 72;\n"
            + "    if (TABLET) {\n"
            + "        if (!applied) {\n"
            + "            p.writeConfig(\"laptopHeight\", p.height == h || (isDock && (p.height == 88 || p.height == 96)) ? laptop : p.height);\n"
            + "            p.writeConfig(\"laptopHiding\", p.hiding);\n"
            + "            p.writeConfig(\"tabletApplied\", true);\n"
            + "        }\n"
            + "        if (p.height != h) p.height = h;\n"
            + "        if (isDock && p.hiding != DOCK_HIDING) p.hiding = DOCK_HIDING;\n"
            + "        if (isDock) p.widgets(\"org.plasmafusion.dock\").forEach(function (w) {\n"
            + "            w.currentConfigGroup = [\"General\"];\n"
            + "            if (Number(w.readConfig(\"tabletStripHeight\", 20)) != STRIP) w.writeConfig(\"tabletStripHeight\", STRIP);\n"
            + "        });\n"
            + "    } else if (applied) {\n"
            + "        var saved = Number(p.readConfig(\"laptopHeight\", laptop));\n"
            + "        if (isDock && (saved == 88 || saved == 96)) saved = laptop;\n"
            + "        p.height = saved > 0 && saved != h ? saved : laptop;\n"
            + "        if (isDock) p.hiding = String(p.readConfig(\"laptopHiding\", \"dodgewindows\"));\n"
            + "        p.writeConfig(\"tabletApplied\", false);\n"
            + "    }\n"
            + "    p.currentConfigGroup = [];\n"
            + "    done.push((isTop ? \"top \" : \"dock \") + p.height + (isDock ? \" \" + p.hiding : \"\"));\n"
            + "});\n"
            + "print(done.join(\", \"));\n";
    }

    function applyPanels() {
        if (!known) {
            return;
        }
        panelCall.arguments = [panelScript(tablet, dockHiding())];
        panelCall.call();
    }

    DBusCall {
        id: panelCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: returnValue => root.log("panels: " + (returnValue.length > 0 ? returnValue[0] : ""))
        onFailed: root.log("panels: plasmashell did not run the panel script (not running?)")
    }

    // A plasmashell (re)start brings its panels back with the last saved thickness: apply the
    // posture once when its panel windows appear (several panels, one call).
    Timer {
        id: panelsAppeared
        interval: 500
        onTriggered: root.applyPanels()
    }

    // A scale change (Display Configuration, kscreen-doctor) keeps the screen list, so
    // onScreensChanged does not run: snap the panel heights to the new device pixels (STRESS-1:
    // 4/3 -> 1.5 in tablet posture had left the 45 px top bar at 67.5 device px).
    Instantiator {
        model: Workspace.screens
        delegate: Connections {
            required property var modelData
            target: modelData
            function onScaleChanged() {
                scaleSettled.restart();
            }
        }
    }
    Timer {
        id: scaleSettled
        interval: 400
        onTriggered: {
            root.log("screen scale " + root.internalScale().toFixed(4) + ": panels again");
            root.applyPanels();
        }
    }

    // ---------------------------------------------------------------- shortcut and edges

    // Other parts change WindowMode or DockHiding with kwriteconfig6 --notify, then invoke this.
    ShortcutHandler {
        name: "Plasma Fusion: Tablet Window Mode"
        text: "Plasma Fusion: Apply Tablet Window Mode"
        sequence: ""
        onActivated: {
            root.log("settings re-read: WindowMode " + root.windowMode() + ", DockHiding " + root.dockHiding());
            root.applyPanels();
            root.sync();
        }
    }

    ScreenEdgeHandler {
        edge: ScreenEdgeHandler.LeftEdge
        mode: ScreenEdgeHandler.Touch
        enabled: root.tablet && root.setting("EdgeLeft", false)
        onActivated: launcherCall.call()
    }
    DBusCall {
        id: launcherCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "activateLauncherMenu"
    }

    ScreenEdgeHandler {
        edge: ScreenEdgeHandler.RightEdge
        mode: ScreenEdgeHandler.Touch
        enabled: root.tablet && root.setting("EdgeRight", false)
        onActivated: {
            // Quick settings opens on an openRequest "<mode>:<nonce>" (the launcher's form).
            quickSettingsCall.arguments = ["panels().forEach(function (p) { p.widgets(\"org.plasmafusion.quicksettings\").forEach(function (w) {"
                + " w.currentConfigGroup = [\"General\"]; w.writeConfig(\"openRequest\", \"sheet:\" + Date.now()); }); });"];
            quickSettingsCall.call();
        }
    }
    DBusCall {
        id: quickSettingsCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
    }

    // ---------------------------------------------------------------- start and stop

    // KWin quitting (logout, --replace) destroys the scripts after the workspace: leave() would
    // touch windows that are gone (a KWin crash at exit, seen in private sessions that ended in
    // tablet mode). The session's windows go with it, so there is nothing to restore then.
    property bool quitting: false
    Connections {
        target: Qt.application
        function onAboutToQuit() {
            root.quitting = true;
        }
    }

    Component.onDestruction: {
        // Disabled (the kill switch): laptop options and windows first.
        if (applied && !quitting) {
            leave();
        }
    }
}
