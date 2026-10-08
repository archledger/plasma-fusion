/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin
import "ensureTopBars.js" as EnsureTopBars

// Plasma Fusion snapping (boards QuickSettings.dc.html "Snap layouts", TabsSnap.dc.html).
//
// - Meta+Z ("Plasma Fusion: Snap Layouts") opens a flyout near the active window's maximize
//   button with four layouts; a click on a zone places the window there.
// - After a window is snapped to the left or right half, the other half offers the remaining
//   windows ("Pick a window for this side"). Esc, a click elsewhere or any focus change
//   dismisses it; it also closes itself after a minute without input.
// - Snapped halves and quarters get a 6 px inner gap, with no work-area edge inset.
// - Windows picked for the other half form a pair: they minimise and restore together.
//
// Halves, 2:1 and quarters use KWin's own quick tiles (so they stay tiled, share their edge
// when resized and restore their size when dragged out); thirds are placed by geometry.
Item {
    id: root

    // Settings: kwinrc [Script-plasmafusion-snap] (see contents/config/main.xml).
    function setting(key, fallback) {
        const value = KWin.readConfig(key, fallback);
        if (typeof fallback === "boolean") {
            return value === true || value === "true";
        }
        if (typeof fallback === "number") {
            const n = Number(value);
            return isNaN(n) ? fallback : n;
        }
        return value;
    }
    function gap() {
        return Math.max(0, Math.min(48, setting("Gap", 6)));
    }

    // ---------------------------------------------------------------- quick tiles

    // Quick-tile roots seen so far, per output and desktop (KWin does not expose them directly).
    property var quickRoots: ({})

    function keyFor(output, desktop) {
        return (output ? output.name : "?") + "|" + (desktop ? desktop.id : "?");
    }

    function desktopOf(win) {
        if (win && !win.onAllDesktops && win.desktops.length > 0) {
            return win.desktops[0];
        }
        return Workspace.currentDesktopForScreen(win ? win.output : Workspace.activeScreen) || Workspace.currentDesktop;
    }

    // A quick tile is a direct child of a root tile that is not the custom (Meta+T) root.
    function quickRootOf(win) {
        const tile = win ? win.tile : null;
        if (!tile || !tile.parent || tile.parent.parent) {
            return null;
        }
        const quickRoot = tile.parent;
        const custom = Workspace.rootTile(win.output, desktopOf(win));
        if (quickRoot === custom || quickRoot.tiles.length !== 8) {
            return null;
        }
        quickRoots[keyFor(win.output, desktopOf(win))] = quickRoot;
        return quickRoot;
    }

    // Index of the window's quick tile: 0 left, 1 right, 2 top, 3 bottom, 4..7 quarters.
    function quickIndexOf(win) {
        const quickRoot = quickRootOf(win);
        if (!quickRoot) {
            return -1;
        }
        const tiles = quickRoot.tiles;
        for (let i = 0; i < tiles.length; ++i) {
            if (tiles[i] === win.tile) {
                return i;
            }
        }
        return -1;
    }

    function applyGap(quickRoot) {
        if (!quickRoot) {
            return;
        }
        // KWin's scalar Tile.padding also insets screen edges. Keep its native tiles flush;
        // fitQuickTile applies only the inner gap without removing the tile association.
        if (quickRoot.padding !== 0) {
            quickRoot.padding = 0;
        }
    }

    function setSplits(quickRoot, horizontal, vertical) {
        const tiles = quickRoot.tiles;
        if (horizontal > 0 && Math.abs(tiles[0].relativeGeometry.width - horizontal) > 0.001) {
            tiles[0].relativeGeometry = Qt.rect(0, 0, horizontal, 1);
        }
        if (vertical > 0 && Math.abs(tiles[2].relativeGeometry.height - vertical) > 0.001) {
            tiles[2].relativeGeometry = Qt.rect(0, 0, 1, vertical);
        }
    }

    function quickSlot(index) {
        switch (index) {
        case 0: Workspace.slotWindowQuickTileLeft(); break;
        case 1: Workspace.slotWindowQuickTileRight(); break;
        case 2: Workspace.slotWindowQuickTileTop(); break;
        case 3: Workspace.slotWindowQuickTileBottom(); break;
        case 4: Workspace.slotWindowQuickTileTopLeft(); break;
        case 5: Workspace.slotWindowQuickTileTopRight(); break;
        case 6: Workspace.slotWindowQuickTileBottomLeft(); break;
        case 7: Workspace.slotWindowQuickTileBottomRight(); break;
        }
    }

    // A remembered quick-tile root, if it still exists (outputs and desktops come and go).
    function cachedQuickRoot(win) {
        const key = keyFor(win.output, desktopOf(win));
        const quickRoot = quickRoots[key];
        try {
            if (quickRoot && quickRoot.tiles && quickRoot.tiles.length === 8) {
                return quickRoot;
            }
        } catch (e) {
            // the tile is gone
        }
        delete quickRoots[key];
        return null;
    }

    // Puts win into quick tile `index` with the given splits (fractions, 0 = keep).
    function quickTile(win, index, horizontal, vertical) {
        let quickRoot = quickRootOf(win) || cachedQuickRoot(win);
        if (!quickRoot) {
            // First quick tile on this screen and desktop: let KWin tile it, then take over.
            if (Workspace.activeWindow !== win) {
                Workspace.activeWindow = win;
            }
            quickSlot(index);
            quickRoot = quickRootOf(win);
            if (!quickRoot) {
                return false;
            }
        }
        applyGap(quickRoot);
        setSplits(quickRoot, horizontal, vertical);
        const tile = quickRoot.tiles[index];
        if (win.tile !== tile) {
            return tile.manage(win);
        }
        return true;
    }

    // Only shared edges are inset; windows reach the work area's outer edges.
    function zoneRect(area, fx, fy, fw, fh, g) {
        const x0 = area.x + fx * area.width;
        const y0 = area.y + fy * area.height;
        const x1 = area.x + (fx + fw) * area.width;
        const y1 = area.y + (fy + fh) * area.height;
        const l = fx > 0.001 ? g / 2 : 0;
        const t = fy > 0.001 ? g / 2 : 0;
        const r = fx + fw < 0.999 ? g / 2 : 0;
        const b = fy + fh < 0.999 ? g / 2 : 0;
        return Qt.rect(Math.round(x0 + l), Math.round(y0 + t), Math.round(x1 - r - (x0 + l)), Math.round(y1 - b - (y0 + t)));
    }

    function thirdRect(area, i, g, rows) {
        const origin = rows ? area.y : area.x;
        const length = rows ? area.height : area.width;
        const size = (length - 2 * g) / 3;
        // Round endpoints, not a repeated width: odd work-area sizes still fill the last edge.
        const start = i === 0 ? origin : Math.round(origin + i * (size + g));
        const end = i === 2 ? origin + length : Math.round(origin + (i + 1) * size + i * g);
        return rows ? Qt.rect(area.x, start, area.width, end - start)
                    : Qt.rect(start, area.y, end - start, area.height);
    }

    // Layouts of the flyout (board order): zones as fractions [x, y, w, h], plus how to place.
    // An area taller than it is wide gets row layouts (ADAPTIVE 5.8): top/bottom halves, 2/3
    // over 1/3, quarters, three rows.
    readonly property var columnLayouts: [
        { name: "halves", zones: [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]], quick: [0, 1], h: 0.5, v: 0 },
        { name: "twoThirds", zones: [[0, 0, 2 / 3, 1], [2 / 3, 0, 1 / 3, 1]], quick: [0, 1], h: 2 / 3, v: 0 },
        { name: "quarters", zones: [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]], quick: [4, 5, 6, 7], h: 0.5, v: 0.5 },
        { name: "thirds", zones: [[0, 0, 1 / 3, 1], [1 / 3, 0, 1 / 3, 1], [2 / 3, 0, 1 / 3, 1]], quick: [], h: 0, v: 0 }
    ]
    readonly property var rowLayouts: [
        { name: "halves", zones: [[0, 0, 1, 0.5], [0, 0.5, 1, 0.5]], quick: [2, 3], h: 0, v: 0.5 },
        { name: "twoThirds", zones: [[0, 0, 1, 2 / 3], [0, 2 / 3, 1, 1 / 3]], quick: [2, 3], h: 0, v: 2 / 3 },
        { name: "quarters", zones: [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]], quick: [4, 5, 6, 7], h: 0.5, v: 0.5 },
        { name: "thirds", zones: [[0, 0, 1, 1 / 3], [0, 1 / 3, 1, 1 / 3], [0, 2 / 3, 1, 1 / 3]], quick: [], h: 0, v: 0, rows: true }
    ]
    function layoutsFor(win) {
        const area = Workspace.clientArea(Workspace.MaximizeArea, win);
        return area.height > area.width ? rowLayouts : columnLayouts;
    }

    function targetRect(win, layoutIndex, zoneIndex) {
        const area = Workspace.clientArea(Workspace.MaximizeArea, win);
        const layout = layoutsFor(win)[layoutIndex];
        const g = setting("QuickTileGaps", true) || layout.quick.length === 0 ? gap() : 0;
        if (layout.quick.length === 0) {
            return thirdRect(area, zoneIndex, g, layout.rows === true);
        }
        const z = layout.zones[zoneIndex];
        return zoneRect(area, z[0], z[1], z[2], z[3], g);
    }

    function placeInZone(win, layoutIndex, zoneIndex) {
        if (!usable(win)) {
            return;
        }
        const layout = layoutsFor(win)[layoutIndex];
        if (layout.quick.length > 0) {
            if (quickTile(win, layout.quick[zoneIndex], layout.h, layout.v)) {
                // A window that was already in this quick tile (e.g. 2:1 -> halves) gets no
                // tileChanged, but the other side may just have become free: offer it anyway.
                windowSnapped(win);
                return;
            }
        }
        // Thirds (and a fallback when tiling is refused): plain geometry.
        if (win.tile) {
            win.tile.unmanage(win);
        }
        if (win.maximizeMode !== 0) {
            win.setMaximize(false, false);
        }
        win.frameGeometry = targetRect(win, layoutIndex, zoneIndex);
    }

    function usable(win) {
        return win && !win.deleted && win.normalWindow && !win.popupWindow && win.moveable
            && win.resizeable && !win.fullScreen && !win.specialWindow;
    }

    // ---------------------------------------------------------------- dock entries

    // "Plasma Fusion: Activate Dock Entry N": the dock's app N (setup gives them Meta+Alt+1..9 in
    // the Windows-style set). Up to Plasma 6.7 plasmashell's "activate task manager entry N" did
    // this for any task manager in a panel, the dock included; Plasma 6.8 moved those actions into
    // the stock task manager, which the dock replaces, so they reach the dock from here: the dock
    // reacts to its activateRequest key "N:nonce", written through plasmashell's script interface.
    Instantiator {
        model: 9
        delegate: ShortcutHandler {
            required property int index
            name: "Plasma Fusion: Activate Dock Entry " + (index + 1)
            text: i18nd("plasmafusion", "Plasma Fusion: Activate Dock Entry %1", index + 1)
            onActivated: {
                dockEntryCall.arguments = ["panels().forEach(function (p) { p.widgets(\"org.plasmafusion.dock\").forEach(function (w) {"
                    + " w.currentConfigGroup = [\"General\"]; w.writeConfig(\"activateRequest\", \"" + (index + 1)
                    + ":" + Date.now() + "\"); }); });"];
                dockEntryCall.call();
            }
        }
    }
    DBusCall {
        id: dockEntryCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFailed: console.info("plasmafusion-snap: plasmashell did not take the dock entry request")
    }

    // ---------------------------------------------------------------- Meta+Z flyout

    ShortcutHandler {
        name: "Plasma Fusion: Snap Layouts"
        text: i18nd("plasmafusion", "Plasma Fusion: Snap Layouts")
        sequence: "Meta+Z"
        onActivated: {
            if (flyoutLoader.active) {
                flyoutLoader.active = false;
                return;
            }
            const win = Workspace.activeWindow;
            if (!root.usable(win)) {
                return;
            }
            pickerLoader.active = false;
            flyoutLoader.target = win;
            flyoutLoader.layouts = root.layoutsFor(win);
            flyoutLoader.active = true;
            // The button side may have changed since the last look (System Settings).
            if (sideLoader.item) {
                sideLoader.item.refresh();
            }
        }
    }

    // ---------------------------------------------------------------- the maximize button's side

    // The flyout hangs under the real maximize button (ADAPTIVE 5.8). A script cannot see the
    // decoration's buttons, so DecorationSide.qml reads the settings that decide their side. It
    // is loaded on its own: without its module the script still works, with the flyout on the
    // right.
    readonly property bool maximizeOnLeft: sideLoader.item !== null && sideLoader.item.onLeft === true
    Loader {
        id: sideLoader
        source: "DecorationSide.qml"
    }

    // Popups are closed on the next event-loop turn: never delete a window from its own signal.
    function closeFlyout() {
        Qt.callLater(() => { flyoutLoader.active = false; });
    }
    function closePicker() {
        Qt.callLater(() => { pickerLoader.active = false; });
    }

    // Instantiators (not Loaders): the popups must not have an Item as visual parent, since
    // this script's root item is in no window and QtQuick would never show them.
    Instantiator {
        id: flyoutLoader
        property var target: null
        property var layouts: root.columnLayouts
        active: false
        delegate: SnapFlyout {
            target: flyoutLoader.target
            layouts: flyoutLoader.layouts
            buttonsOnLeft: root.maximizeOnLeft
            onPreview: (layoutIndex, zoneIndex) => {
                if (layoutIndex < 0 || !root.usable(flyoutLoader.target)) {
                    Workspace.hideOutline();
                } else {
                    const r = root.targetRect(flyoutLoader.target, layoutIndex, zoneIndex);
                    Workspace.showOutline(r.x, r.y, r.width, r.height);
                }
            }
            onChosen: (layoutIndex, zoneIndex) => {
                const win = flyoutLoader.target;
                Workspace.hideOutline();
                root.closeFlyout();
                root.placeInZone(win, layoutIndex, zoneIndex);
            }
            onDismissed: {
                Workspace.hideOutline();
                root.closeFlyout();
            }
        }
        onActiveChanged: {
            if (!active) {
                target = null;
                Workspace.hideOutline();
            }
        }
    }

    // ---------------------------------------------------------------- fill the other half

    // Windows that could go into the empty half, most recently used first.
    function candidatesFor(snapped, desktop) {
        const list = [];
        const order = Workspace.stackingOrder;
        for (let i = order.length - 1; i >= 0; --i) {
            const w = order[i];
            if (w === snapped || !usable(w) || w.skipSwitcher || w.transient) {
                continue;
            }
            if (!w.onAllDesktops) {
                let here = false;
                for (let d = 0; d < w.desktops.length; ++d) {
                    if (w.desktops[d] === desktop) {
                        here = true;
                    }
                }
                if (!here) {
                    continue;
                }
            }
            list.push(w);
        }
        return list;
    }

    // Native quick-tile geometry with only the script's inner padding. Also used by the picker.
    function tileWindowRect(tile) {
        const a = tile.absoluteGeometry;
        const r = tile.relativeGeometry;
        const p = setting("QuickTileGaps", true) ? gap() : 0;
        const l = r.x > 0.001 ? p / 2 : 0;
        const t = r.y > 0.001 ? p / 2 : 0;
        const rr = r.x + r.width < 0.999 ? p / 2 : 0;
        const b = r.y + r.height < 0.999 ? p / 2 : 0;
        return Qt.rect(a.x + l, a.y + t, a.width - l - rr, a.height - t - b);
    }

    function fitQuickTile(win) {
        if (!usable(win) || win.move || win.resize || win.maximizeMode !== 0 || quickIndexOf(win) < 0) {
            return;
        }
        const target = tileWindowRect(win.tile);
        const current = win.frameGeometry;
        // Wayland clients round to device pixels; don't send the same configure endlessly.
        const tolerance = 1 / Math.max(1, win.output ? win.output.devicePixelRatio : 1);
        if (Math.abs(current.x - target.x) > tolerance || Math.abs(current.y - target.y) > tolerance
                || Math.abs(current.width - target.width) > tolerance || Math.abs(current.height - target.height) > tolerance) {
            win.frameGeometry = target;
        }
    }

    property var pendingSnap: null

    Timer {
        id: snapSettle
        interval: 220
        onTriggered: root.offerOtherHalf(root.pendingSnap)
    }

    function windowSnapped(win) {
        if (!setting("FillOtherHalf", true) && !setting("QuickTileGaps", true)) {
            return;
        }
        const quickRoot = quickRootOf(win);
        if (quickRoot) {
            applyGap(quickRoot);
        }
        if (!setting("FillOtherHalf", true)) {
            return;
        }
        const index = quickIndexOf(win);
        if (index < 0 || index > 3 || win !== Workspace.activeWindow) {
            return;
        }
        pendingSnap = win;
        snapSettle.restart();
    }

    function offerOtherHalf(win) {
        pendingSnap = null;
        if (!win || win.deleted || win.move || win.resize || flyoutLoader.active || pickerLoader.active) {
            return;
        }
        const index = quickIndexOf(win);
        if (index < 0 || index > 3) {
            return;
        }
        const quickRoot = quickRootOf(win);
        // The other half: left/right (0, 1) or top/bottom (2, 3).
        const other = quickRoot.tiles[index ^ 1];
        if (other.windows.length > 0) {
            return;
        }
        const candidates = candidatesFor(win, desktopOf(win));
        if (candidates.length === 0) {
            return;
        }
        pickerLoader.snapped = win;
        pickerLoader.tile = other;
        pickerLoader.output = win.output;
        pickerLoader.desktop = desktopOf(win);
        pickerLoader.area = tileWindowRect(other);
        pickerLoader.candidates = candidates;
        pickerLoader.active = true;
    }

    Instantiator {
        id: pickerLoader
        property var snapped: null
        property var tile: null
        // Kept after closing: the picker's wallpaper must never see a null screen.
        property var output: null
        property var desktop: null
        property rect area
        property var candidates: []
        active: false
        delegate: FillPicker {
            area: pickerLoader.area
            candidates: pickerLoader.candidates
            output: pickerLoader.output
            desktop: pickerLoader.desktop
            onPicked: win => {
                const tile = pickerLoader.tile;
                const snapped = pickerLoader.snapped;
                root.closePicker();
                root.fillWith(snapped, tile, win);
            }
            onDismissed: root.closePicker()
        }
        onActiveChanged: {
            if (!active) {
                snapped = null;
                tile = null;
                candidates = [];
            }
        }
    }

    // The snapped window changes its tile (leaves its half or moves to the other one, e.g.
    // Meta+Right), closes, or the workspace changes: drop the picker. A move to the other half
    // offers the picker again for the new empty half through windowSnapped().
    Connections {
        target: pickerLoader.snapped
        enabled: pickerLoader.active
        function onTileChanged() {
            pickerLoader.active = false;
        }
        function onClosed() {
            pickerLoader.active = false;
        }
    }

    function fillWith(snapped, tile, win) {
        if (!tile || !usable(win)) {
            return;
        }
        if (win.minimized) {
            win.minimized = false;
        }
        if (!tile.manage(win)) {
            return;
        }
        Workspace.activeWindow = win;
        if (snapped && setting("PairWindows", true)) {
            pairs = pairs.concat([{ a: snapped, b: win }]);
        }
    }

    // ---------------------------------------------------------------- pairs

    property var pairs: []
    property bool syncing: false

    function partnerOf(win) {
        for (let i = 0; i < pairs.length; ++i) {
            if (pairs[i].a === win) {
                return pairs[i].b;
            }
            if (pairs[i].b === win) {
                return pairs[i].a;
            }
        }
        return null;
    }

    function unpair(win) {
        const kept = pairs.filter(p => p.a !== win && p.b !== win);
        if (kept.length !== pairs.length) {
            pairs = kept;
        }
    }

    function pairMinimizedChanged(win) {
        const partner = partnerOf(win);
        if (!partner || syncing || partner.deleted) {
            return;
        }
        syncing = true;
        if (partner.minimized !== win.minimized) {
            partner.minimized = win.minimized;
        }
        syncing = false;
    }

    function pairTileChanged(win) {
        if (partnerOf(win) && quickIndexOf(win) < 0) {
            unpair(win);
        }
    }

    Connections {
        target: Workspace
        function onWindowActivated(win) {
            const partner = root.partnerOf(win);
            if (partner && !partner.deleted && !partner.minimized) {
                Workspace.raiseWindow(partner);
                Workspace.raiseWindow(win);
            }
        }
        function onWindowRemoved(win) {
            root.unpair(win);
            if (win === flyoutLoader.target) {
                flyoutLoader.active = false;
            }
        }
        function onCurrentDesktopChanged() {
            flyoutLoader.active = false;
            pickerLoader.active = false;
        }
    }

    // ---------------------------------------------------------------- screens come and go

    // After an output or geometry change every normal window must lie inside its screen's
    // maximize area (ADAPTIVE fix 24: a window opened in portrait ended below the landscape
    // screen); a window larger than the area is made to fit. Tiled, maximized and full-screen
    // windows are KWin's own business. And every screen gets its top bar (owner decision 8): the
    // Global Theme's ensure-topbars.js, run in plasmashell. The build puts its text into
    // ensureTopBars.js next to this file (tools/build.d/80-kwin.sh), so there is one source.
    Timer {
        id: screensSettled
        interval: 800
        onTriggered: {
            root.clampWindows();
            topBarsCall.call();
        }
    }
    function clampWindows() {
        const list = Workspace.stackingOrder;
        let moved = 0;
        for (let i = 0; i < list.length; ++i) {
            const w = list[i];
            if (!w || w.deleted || !w.normalWindow || w.fullScreen || w.minimized || w.tile || w.maximizeMode !== 0
                    || !w.moveable) {
                continue;
            }
            const area = Workspace.clientArea(Workspace.MaximizeArea, w);
            const g = w.frameGeometry;
            const width = w.resizeable ? Math.min(g.width, area.width) : g.width;
            const height = w.resizeable ? Math.min(g.height, area.height) : g.height;
            const x = Math.max(area.x, Math.min(g.x, area.x + area.width - width));
            const y = Math.max(area.y, Math.min(g.y, area.y + area.height - height));
            if (x !== g.x || y !== g.y || width !== g.width || height !== g.height) {
                w.frameGeometry = Qt.rect(x, y, width, height);
                moved++;
            }
        }
        console.info("plasmafusion-snap: screens changed, " + moved + " window(s) moved into their work area");
    }
    DBusCall {
        id: topBarsCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        arguments: [EnsureTopBars.script]
        onFinished: returnValue => {
            const line = String(returnValue.length > 0 ? returnValue[0] : "").trim();
            console.info("plasmafusion-snap: " + line);
            // At session start plasmashell can answer before it has loaded its layout: ask again.
            if (line.indexOf("not loaded yet") !== -1 && topBarsRetry.tries < 5) {
                topBarsRetry.tries++;
                topBarsRetry.restart();
            } else {
                topBarsRetry.tries = 0;
            }
        }
        onFailed: console.info("plasmafusion-snap: plasmashell did not run the top-bar check")
    }
    Timer {
        id: topBarsRetry
        property int tries: 0
        interval: 3000
        onTriggered: topBarsCall.call()
    }
    Connections {
        target: Workspace
        function onScreensChanged() {
            screensSettled.restart();
        }
        function onVirtualScreenGeometryChanged() {
            screensSettled.restart();
        }
    }

    // ---------------------------------------------------------------- three-finger swipes

    // Touchpad, three fingers (BACKLOG S15): up opens Overview, down closes it or, when it is
    // closed, shows the desktop. KWin's own three-finger vertical swipe only switches between
    // rows of virtual desktops; the Fusion layout has one row (hand check on the device).
    SwipeGestureHandler {
        direction: SwipeGestureHandler.Direction.Up
        fingerCount: 3
        deviceType: SwipeGestureHandler.Device.Touchpad
        onActivated: {
            console.info("plasmafusion-snap: three-finger swipe up");
            overviewCall.call();
        }
    }
    SwipeGestureHandler {
        direction: SwipeGestureHandler.Direction.Down
        fingerCount: 3
        deviceType: SwipeGestureHandler.Device.Touchpad
        onActivated: {
            console.info("plasmafusion-snap: three-finger swipe down");
            activeEffectsCall.call();
        }
    }
    DBusCall {
        id: overviewCall
        service: "org.kde.kglobalaccel"
        path: "/component/kwin"
        dbusInterface: "org.kde.kglobalaccel.Component"
        method: "invokeShortcut"
        arguments: ["Overview"]
    }
    DBusCall {
        id: activeEffectsCall
        service: "org.kde.KWin"
        path: "/Effects"
        dbusInterface: "org.freedesktop.DBus.Properties"
        method: "Get"
        arguments: ["org.kde.kwin.Effects", "activeEffects"]
        onFinished: returnValue => {
            const active = String(returnValue.length > 0 ? returnValue[0] : "");
            if (active.indexOf("overview") >= 0) {
                overviewCall.call();
            } else {
                Workspace.slotToggleShowDesktop();
            }
        }
        onFailed: Workspace.slotToggleShowDesktop()
    }

    // One watcher per window for snaps and pair changes.
    Instantiator {
        model: WindowModel {}
        delegate: QtObject {
            id: watcher
            required property var window
            // Windows already tiled at startup, and native resizes/reconfigures, keep the inner
            // gap. Defer past KWin's own geometry update; never configure from its signal stack.
            function fit() {
                Qt.callLater(() => root.fitQuickTile(watcher.window));
            }
            Component.onCompleted: {
                root.applyGap(root.quickRootOf(window));
                fit();
            }
            readonly property Connections tileConnections: Connections {
                target: watcher.window ? watcher.window.tile : null
                function onWindowGeometryChanged() {
                    watcher.fit();
                }
            }
            readonly property Connections connections: Connections {
                target: watcher.window
                function onTileChanged() {
                    root.windowSnapped(watcher.window);
                    root.pairTileChanged(watcher.window);
                    watcher.fit();
                }
                function onFrameGeometryChanged() {
                    watcher.fit();
                }
                function onInteractiveMoveResizeFinished() {
                    watcher.fit();
                }
                function onMinimizedChanged() {
                    root.pairMinimizedChanged(watcher.window);
                }
            }
        }
    }
}
