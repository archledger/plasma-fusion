/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin
import "ensureTopBars.js" as EnsureTopBars
import "Panels.js" as Panels
import "Cycle.js" as Cycle
import "Groups.js" as Groups
import "SnapGeometry.js" as SnapGeometry

// Plasma Fusion snapping (boards QuickSettings.dc.html "Snap layouts", TabsSnap.dc.html).
//
// - Meta+Z ("Plasma Fusion: Snap Layouts") opens a flyout near the active window's maximize
//   button with four layouts; a click on a zone places the window there.
// - After a window is snapped to the left or right half, the other half offers the remaining
//   windows ("Pick a window for this side"). After a zone is chosen in the flyout, every other
//   empty zone of that layout is offered in turn (Snap Assist for every layout). Esc, a click
//   elsewhere or any focus change dismisses it; it also closes itself after a minute without
//   input.
// - Snapped halves and quarters meet with no gap (Gap: 0-48 px between them), with no work-area
//   edge inset.
// - Windows snapped together through the picker form a group (snap groups, Groups.js): they
//   minimise and restore together, and activating one brings the others up with it.
// - "Plasma Fusion: Snap Left/Right" (the setup gives them Meta+Left/Right): pressed again they
//   step the window through 1/2, 1/3 and 2/3 of that side (Cycle.js).
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
        return Math.max(0, Math.min(48, setting("Gap", 0)));
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

    // A quick tile is a direct child of KWin's quick-tile root, not of the custom (Meta+T) root
    // (SnapGeometry.isQuickRoot: by class name, else by shape).
    function quickRootOf(win) {
        const tile = win ? win.tile : null;
        if (!tile || !tile.parent || tile.parent.parent) {
            return null;
        }
        const quickRoot = tile.parent;
        if (!SnapGeometry.isQuickRoot(quickRoot, Workspace.rootTile(win.output, desktopOf(win)))) {
            return null;
        }
        quickRoots[keyFor(win.output, desktopOf(win))] = quickRoot;
        return quickRoot;
    }

    // Role of the window's quick tile: 0 left, 1 right, 2 top, 3 bottom, 4..7 quarters (from its
    // shape, SnapGeometry.quickRole).
    function quickIndexOf(win) {
        return quickRootOf(win) ? SnapGeometry.quickRole(win.tile) : -1;
    }

    function applyGap(quickRoot) {
        if (!quickRoot) {
            return;
        }
        // Keep native padding for the interactive resize controller's pointer compensation.
        // fitQuickTile removes only outer insets without changing the native shared edges.
        const g = setting("QuickTileGaps", true) ? gap() : 0;
        if (quickRoot.padding !== g) {
            quickRoot.padding = g;
        }
    }

    function setSplits(quickRoot, horizontal, vertical) {
        const left = SnapGeometry.quickTileFor(quickRoot, 0);
        const top = SnapGeometry.quickTileFor(quickRoot, 2);
        if (horizontal > 0 && left && Math.abs(left.relativeGeometry.width - horizontal) > 0.001) {
            left.relativeGeometry = Qt.rect(0, 0, horizontal, 1);
        }
        if (vertical > 0 && top && Math.abs(top.relativeGeometry.height - vertical) > 0.001) {
            top.relativeGeometry = Qt.rect(0, 0, 1, vertical);
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
            if (quickRoot && SnapGeometry.isQuickRoot(quickRoot, Workspace.rootTile(win.output, desktopOf(win)))) {
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
        const tile = SnapGeometry.quickTileFor(quickRoot, index);
        if (!tile) {
            return false;
        }
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

    // The flyout's zone choice: the window goes there, then the picker offers the layout's other
    // empty zones in turn (startFill). A window that was already in its quick tile (e.g. 2:1 ->
    // halves) gets no tileChanged, so the offer cannot wait for one.
    function placeInZone(win, layoutIndex, zoneIndex) {
        if (!usable(win)) {
            return;
        }
        // A layout choice is a new arrangement: the window leaves the group it was in (a move
        // between plain-geometry zones, or into the quick tile it already holds, changes no tile).
        leaveGroup(win);
        const layout = layoutsFor(win)[layoutIndex];
        let quick = false;
        if (layout.quick.length > 0) {
            quick = quickTile(win, layout.quick[zoneIndex], layout.h, layout.v);
            if (quick) {
                const quickRoot = quickRootOf(win);
                if (quickRoot) {
                    applyGap(quickRoot);
                }
            }
        }
        if (!quick) {
            // Thirds (and a fallback when tiling is refused): plain geometry.
            placeByGeometry(win, targetRect(win, layoutIndex, zoneIndex));
        }
        startFill(win, layoutIndex, zoneIndex, quick);
    }

    function placeByGeometry(win, rect) {
        if (win.tile) {
            win.tile.unmanage(win);
        }
        if (win.maximizeMode !== 0) {
            win.setMaximize(false, false);
        }
        win.frameGeometry = rect;
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
            root.endFill();
            flyoutLoader.target = win;
            flyoutLoader.layouts = root.layoutsFor(win);
            flyoutLoader.active = true;
            // The button side may have changed since the last look (System Settings).
            if (sideLoader.item) {
                sideLoader.item.refresh();
            }
        }
    }

    // ---------------------------------------------------------------- snap sizes from the keyboard

    // "Plasma Fusion: Snap Left/Right" have no key of their own: the setup moves Meta+Left/Right
    // to them from KWin's "Quick Tile Window to the Left/Right" (two actions cannot share a key).
    // Pressed again, the window steps through 1/2, 1/3 and 2/3 of that side; after 2/3 it goes to
    // the screen on that side when there is one (its facing half), as KWin's quick tile did on a
    // second press, else back to 1/2. The half is KWin's quick tile, as the key gave before (so the
    // picker still offers the other half); the thirds are plain geometry, as the flyout's thirds.
    ShortcutHandler {
        name: "Plasma Fusion: Snap Left"
        text: i18nd("plasmafusion", "Plasma Fusion: Snap Left (1/2, 1/3, 2/3)")
        onActivated: root.cycleSnap(Workspace.activeWindow, "left")
    }
    ShortcutHandler {
        name: "Plasma Fusion: Snap Right"
        text: i18nd("plasmafusion", "Plasma Fusion: Snap Right (1/2, 1/3, 2/3)")
        onActivated: root.cycleSnap(Workspace.activeWindow, "right")
    }

    function screenRect(output) {
        const g = output.geometry;
        return { x: g.x, y: g.y, width: g.width, height: g.height };
    }
    // The screen next to the window's on SIDE, or null.
    function neighbourScreen(win, side) {
        const screens = Array.from(Workspace.screens);
        const index = Cycle.neighbourOf(screens.map(screenRect), screenRect(win.output), side);
        return index >= 0 ? screens[index] : null;
    }

    // The step last asked of each window ({ side, step, at, from }, by internalId; FROM its rectangle
    // then): a client that has not drawn its new size yet still has that rectangle
    // (Cycle.currentStep); any other rectangle (the step drawn, a drag) is measured instead.
    property var cyclePending: ({})

    function cycleSnap(win, side) {
        if (!usable(win)) {
            return;
        }
        const area = Workspace.clientArea(Workspace.MaximizeArea, win);
        const g = win.frameGeometry;
        const id = String(win.internalId);
        const rect = { x: g.x, y: g.y, width: g.width, height: g.height };
        const pending = win.move || win.resize ? null : cyclePending[id] || null;
        const measured = Cycle.stepOf(rect, area, side, gap(), setting("QuickTileGaps", true) ? gap() : 0);
        const step = Cycle.nextStep(Cycle.currentStep(measured, pending, side, Date.now(), rect), neighbourScreen(win, side) !== null);
        // (After a move to another screen the window is on the far side there: nothing to keep.)
        const asked = Object.assign({}, cyclePending);
        if (step === "screen") {
            delete asked[id];
        } else {
            asked[id] = { side: side, step: step, at: Date.now(), from: rect };
        }
        cyclePending = asked;
        // A new arrangement, as a layout choice: the flyout closes, the window leaves its group.
        flyoutLoader.active = false;
        leaveGroup(win);
        // A half: KWin's quick tile, else its rectangle (KWin refused the tile).
        const half = (onLeft) => {
            if (!quickTile(win, onLeft ? 0 : 1, 0.5, 0)) {
                placeByGeometry(win, zoneRect(Workspace.clientArea(Workspace.MaximizeArea, win), onLeft ? 0 : 0.5, 0, 0.5, 1,
                                              setting("QuickTileGaps", true) ? gap() : 0));
            }
        };
        if (step === "screen") {
            Workspace.sendClientToScreen(win, neighbourScreen(win, side));
            // That screen's facing half, once the window is there.
            Qt.callLater(() => {
                if (usable(win)) {
                    half(side !== "left");
                }
            });
            return;
        }
        if (step === "half") {
            half(side === "left");
            return;
        }
        placeByGeometry(win, step === "third" ? thirdRect(area, side === "left" ? 0 : 2, gap(), false)
                                              : zoneRect(area, side === "left" ? 0 : 1 / 3, 0, 2 / 3, 1, gap()));
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

    // Windows that could go into the empty half, most recently used first - those of this desktop
    // and the current activity (a window of another activity placed here would stay hidden).
    function candidatesFor(snapped, desktop) {
        const list = [];
        const current = [String(Workspace.currentActivity)];
        const order = Workspace.stackingOrder;
        for (let i = order.length - 1; i >= 0; --i) {
            const w = order[i];
            if (w === snapped || !usable(w) || w.skipSwitcher || w.transient || !Groups.sharedActivity(activitiesOf(w), current)) {
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

    // Native shared edges, with outer edges filled and clipped to this window's work area.
    function tileWindowRect(tile, area) {
        if (!area) {
            area = Workspace.clientArea(Workspace.MaximizeArea, Workspace.activeScreen, Workspace.currentDesktop);
        }
        const p = setting("QuickTileGaps", true) ? gap() : 0;
        const g = SnapGeometry.tileRect(tile.absoluteGeometry, tile.relativeGeometry, p, area, true);
        return Qt.rect(g.x, g.y, g.width, g.height);
    }

    function fitQuickTile(win) {
        if (!usable(win) || win.move || win.maximizeMode !== 0 || quickIndexOf(win) < 0) {
            return;
        }
        const target = tileWindowRect(win.tile, Workspace.clientArea(Workspace.MaximizeArea, win));
        const current = win.frameGeometry;
        // Wayland clients round to device pixels; don't send the same configure endlessly.
        const tolerance = 1 / Math.max(1, win.output ? win.output.devicePixelRatio : 1);
        if (Math.abs(current.x - target.x) >= tolerance || Math.abs(current.y - target.y) >= tolerance
                || Math.abs(current.width - target.width) >= tolerance || Math.abs(current.height - target.height) >= tolerance) {
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
        // A flyout choice fills its whole layout (startFill) instead.
        if (fill && fill.anchor === win) {
            return;
        }
        const index = quickIndexOf(win);
        if (index < 0 || index > 3) {
            return;
        }
        const quickRoot = quickRootOf(win);
        // The other half: left/right (0, 1) or top/bottom (2, 3).
        const other = SnapGeometry.quickTileFor(quickRoot, index ^ 1);
        if (!other || other.windows.length > 0) {
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
        pickerLoader.area = tileWindowRect(other, Workspace.clientArea(Workspace.MaximizeArea, win));
        pickerLoader.candidates = candidates;
        pickerLoader.active = true;
    }

    Instantiator {
        id: pickerLoader
        property var snapped: null
        // The zone to fill: a quick tile, or for plain-geometry zones (thirds) its rectangle.
        property var tile: null
        property var zoneRect: null
        // Set by a pick: the picker hides as the picked window takes the focus, and the
        // dismissal that follows must not end a fill sequence that just moved on.
        property bool picked: false
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
                pickerLoader.picked = true;
                const tile = pickerLoader.tile;
                const zoneRect = pickerLoader.zoneRect;
                const snapped = pickerLoader.snapped;
                root.closePicker();
                root.fillWith(snapped, tile, zoneRect, win);
            }
            onDismissed: {
                if (!pickerLoader.picked) {
                    root.endFill();
                }
                root.closePicker();
            }
        }
        onActiveChanged: {
            if (active) {
                picked = false;
            } else {
                snapped = null;
                tile = null;
                zoneRect = null;
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
            root.endFill();
        }
        function onClosed() {
            pickerLoader.active = false;
            root.endFill();
        }
    }

    function fillWith(snapped, tile, zoneRect, win) {
        // A pick that cannot be placed (the window closed or changed while the picker was open, or
        // KWin refused the tile) ends a fill sequence: nothing would offer its next zone, and the
        // halves picker must not be held back for this window. A sequence that no longer stands
        // (fillStillValid) places nothing more either.
        const inSequence = fill !== null && fill.anchor === snapped;
        if ((!tile && !zoneRect) || !usable(win) || (inSequence && !fillStillValid(fill, false))) {
            if (inSequence) {
                endFill();
            }
            return;
        }
        // The offered zone filled while the picker was open (an app or a script put a window
        // there): nothing is placed over it - a sequence offers its next empty zone instead.
        if (tile ? zoneTileHeld(tile, win) : (inSequence && zoneHeld(fill.anchor, fill.layoutIndex, fill.current, false, win))) {
            if (inSequence) {
                fillSettle.restart();
            }
            return;
        }
        // The picked window belongs to this arrangement now: it leaves its old group before it is
        // restored, so restoring it does not bring the rest of that group back. Should KWin refuse
        // the placement, the old group is put back as it was, and the window minimised again.
        const before = { groups: groups, zones: memberZones };
        const wasMinimized = win.minimized;
        leaveGroup(win);
        if (wasMinimized) {
            win.minimized = false;
        }
        let placed = true;
        if (tile) {
            placed = tile.manage(win);
        } else {
            placeByGeometry(win, zoneRect);
        }
        if (!placed) {
            groups = before.groups;
            memberZones = before.zones;
            if (wasMinimized) {
                syncing = true;
                win.minimized = true;
                syncing = false;
            }
            if (inSequence) {
                endFill();
            }
            return;
        }
        Workspace.activeWindow = win;
        if (snapped && !snapped.deleted && setting("PairWindows", true)) {
            joinGroup(snapped, win, tile, zoneRect);
        }
        // A fill sequence goes on with its next zone once KWin has settled.
        if (inSequence && fill) {
            fill.placed.push(win);
            fill.filled.push(fill.current);
            fill.filledBy.push({ win: win, at: Date.now(), zone: { tile: tile, rect: tile ? null : zoneRect, place: fill.zone.place } });
            fillSettle.restart();
        }
    }

    function zoneTileHeld(tile, except) {
        for (let i = 0; i < tile.windows.length; ++i) {
            if (tile.windows[i] !== except) {
                return true;
            }
        }
        return false;
    }

    // ---------------------------------------------------------------- fill every zone

    // The sequence after a flyout choice: the anchor window, its layout and chosen zone, the zones
    // this sequence filled and the windows it placed (never offered again). The empty zones are
    // worked out again before every offer: a picked window may come out of another zone of the
    // layout, which is then empty and offered in its turn. Halves snapped by an edge drag or
    // Meta+Left/Right keep windowSnapped's single offer.
    //
    // Everything is asked again where it is used (fillStillValid before every offer and every
    // placement, Groups.holds for the zones): handlers end a sequence early and close its picker,
    // but a change no handler sees - an app or a script moving a window, a switch in the settle
    // between two offers - still counts.
    property var fill: null

    Timer {
        id: fillSettle
        interval: 220
        onTriggered: root.offerNextZone()
    }

    function endFill() {
        fill = null;
        fillSettle.stop();
    }

    // A placement is answered late by a Wayland client (its geometry is the old one until then):
    // a plain-geometry zone's rectangle is asked only once this has passed since the placement, or
    // when an interactive move ends.
    readonly property int placementSettleMillis: 1500

    function currentDesktopId() {
        return Workspace.currentDesktop ? String(Workspace.currentDesktop.id) : "";
    }

    function familyOf(win) {
        return layoutsFor(win) === rowLayouts ? "rows" : "columns";
    }

    function plainRect(r) {
        return { x: r.x, y: r.y, width: r.width, height: r.height };
    }

    function activitiesOf(win) {
        const list = [];
        for (let a = 0; a < win.activities.length; ++a) {
            list.push(String(win.activities[a]));
        }
        return list;
    }

    // The window as it is now, for Groups.holds/fillValid (since: when it was placed).
    function snapshotOf(win, since, moveEnded) {
        return {
            tile: win.tile,
            frame: plainRect(win.frameGeometry),
            place: placeOf(win),
            maximized: win.maximizeMode !== 0,
            fullScreen: win.fullScreen,
            settled: !win.move && !win.resize && (moveEnded || Date.now() - since >= placementSettleMillis)
        };
    }

    // Whether the sequence still stands (Groups.fillValid): its first window holds the chosen
    // zone, on the desktop, activity, work area and layout family the sequence started with.
    function fillStillValid(f, moveEnded) {
        if (!f || !f.anchor || f.anchor.deleted) {
            return false;
        }
        const now = snapshotOf(f.anchor, f.startedAt, moveEnded);
        now.desktop = currentDesktopId();
        now.activity = String(Workspace.currentActivity);
        now.area = plainRect(Workspace.clientArea(Workspace.MaximizeArea, f.anchor));
        now.family = familyOf(f.anchor);
        return Groups.fillValid({ zone: f.zone, desktop: f.desktop, activity: f.activity, area: f.area, family: f.family }, now);
    }

    // Whether zone z of the anchor's layout already holds a window other than `except`: a quick
    // tile with windows, or a plain-geometry zone a window of the desktop fills
    // (Groups.zoneOccupied - a window in a matching custom tile counts too).
    function zoneHeld(anchor, layoutIndex, z, quick, except) {
        const layout = layoutsFor(anchor)[layoutIndex];
        if (quick) {
            const quickRoot = quickRootOf(anchor) || cachedQuickRoot(anchor);
            const tile = quickRoot ? SnapGeometry.quickTileFor(quickRoot, layout.quick[z]) : null;
            if (!tile) {
                return false;
            }
            for (let i = 0; i < tile.windows.length; ++i) {
                if (tile.windows[i] !== except) {
                    return true;
                }
            }
            return false;
        }
        const frames = [];
        const others = occupantsOf(anchor, desktopOf(anchor));
        for (let i = 0; i < others.length; ++i) {
            if (others[i] !== except) {
                frames.push(plainRect(others[i].frameGeometry));
            }
        }
        return Groups.zoneOccupied(plainRect(targetRect(anchor, layoutIndex, z)), frames);
    }

    // Every window that can sit in a zone of the anchor's desktop on the current activity - not
    // only the picker's candidates: a window the switcher skips (a window rule) still holds its
    // zone, and so does a minimised one (it comes back to that spot, as a minimised window keeps
    // its quick tile). A window of another activity is not there to see; the current activity is
    // the reference, not the anchor's list (an anchor on all activities shares every activity).
    function occupantsOf(anchor, desktop) {
        const list = [];
        const current = [String(Workspace.currentActivity)];
        const order = Workspace.stackingOrder;
        for (let i = 0; i < order.length; ++i) {
            const w = order[i];
            // A popup is no arranged window - and KWin reports its own internal windows, this
            // script's picker included (it covers the offered zone), as normal ones.
            if (!w || w === anchor || w.deleted || !w.normalWindow || w.popupWindow) {
                continue;
            }
            let here = w.onAllDesktops;
            for (let d = 0; d < w.desktops.length && !here; ++d) {
                here = w.desktops[d] === desktop;
            }
            if (here && Groups.sharedActivity(activitiesOf(w), current)) {
                list.push(w);
            }
        }
        return list;
    }

    function startFill(win, layoutIndex, zoneIndex, quick) {
        endFill();
        if (pendingSnap === win) {
            pendingSnap = null;
            snapSettle.stop();
        }
        if (!setting("FillOtherHalf", true)) {
            return;
        }
        const anchorRect = quick ? null : targetRect(win, layoutIndex, zoneIndex);
        fill = {
            anchor: win,
            layoutIndex: layoutIndex,
            chosen: zoneIndex,
            quick: quick,
            anchorRect: anchorRect,
            zone: { tile: quick ? win.tile : null, rect: anchorRect, place: placeOf(win) },
            desktop: currentDesktopId(),
            activity: String(Workspace.currentActivity),
            area: plainRect(Workspace.clientArea(Workspace.MaximizeArea, win)),
            family: familyOf(win),
            startedAt: Date.now(),
            filled: [],
            filledBy: [],
            current: -1,
            placed: [win]
        };
        if (emptyZones(fill).length === 0) {
            fill = null;
            return;
        }
        fillSettle.restart();
    }

    // Something changed about the anchor (its tile, a move that ended, its geometry, maximized or
    // full screen, another desktop, screen or activity): a sequence that no longer stands ends now
    // and its picker closes. Its own placement happens before the sequence starts.
    function fillAnchorChanged(win, moveEnded) {
        const f = fill;
        if (!f || f.anchor !== win) {
            return;
        }
        if (!fillStillValid(f, moveEnded)) {
            pickerLoader.active = false;
            endFill();
        }
    }

    // The workspace changed under an open sequence (a desktop or activity switch, a screen change):
    // it ends.
    function workspaceChangedDuringFill() {
        if (fill) {
            pickerLoader.active = false;
            endFill();
        }
    }

    // The zones of the sequence's layout still to offer, in fill order: neither filled by this
    // sequence and still held by the window placed there nor holding another window. A window
    // placed by the sequence that closed or left its zone leaves the zone to be offered again.
    function emptyZones(f) {
        const count = layoutsFor(f.anchor)[f.layoutIndex].zones.length;
        const occupied = [];
        for (let z = 0; z < count; ++z) {
            occupied.push(filledStillHeld(f, z) || (z !== f.chosen && zoneHeld(f.anchor, f.layoutIndex, z, f.quick)));
        }
        return Groups.fillOrder(count, f.chosen, occupied);
    }

    function filledStillHeld(f, z) {
        const i = f.filled.lastIndexOf(z);
        if (i < 0) {
            return false;
        }
        const e = f.filledBy[i];
        return !!e.win && !e.win.deleted && Groups.holds(e.zone, snapshotOf(e.win, e.at, false));
    }

    function offerNextZone() {
        const f = fill;
        if (!f || flyoutLoader.active || pickerLoader.active || !fillStillValid(f, false)) {
            endFill();
            return;
        }
        const zones = emptyZones(f);
        const candidates = candidatesFor(f.anchor, desktopOf(f.anchor)).filter(w => f.placed.indexOf(w) < 0);
        if (zones.length === 0 || candidates.length === 0) {
            endFill();
            return;
        }
        const z = zones[0];
        f.current = z;
        const layout = layoutsFor(f.anchor)[f.layoutIndex];
        let tile = null;
        let rect = null;
        if (f.quick) {
            const quickRoot = quickRootOf(f.anchor) || cachedQuickRoot(f.anchor);
            tile = quickRoot ? SnapGeometry.quickTileFor(quickRoot, layout.quick[z]) : null;
            if (!tile) {
                endFill();
                return;
            }
        } else {
            rect = targetRect(f.anchor, f.layoutIndex, z);
        }
        pickerLoader.snapped = f.anchor;
        pickerLoader.tile = tile;
        pickerLoader.zoneRect = rect;
        pickerLoader.output = f.anchor.output;
        pickerLoader.desktop = desktopOf(f.anchor);
        pickerLoader.area = tile ? tileWindowRect(tile, Workspace.clientArea(Workspace.MaximizeArea, f.anchor)) : rect;
        pickerLoader.candidates = candidates;
        pickerLoader.active = true;
    }

    // ---------------------------------------------------------------- snap groups

    property var groups: []
    // internalId -> the zone a group member was placed in: {tile} for a quick tile, {rect} for a
    // plain-geometry zone, with its place and placement time. A member that leaves its zone
    // leaves its group.
    property var memberZones: ({})
    property bool syncing: false

    function keyOf(win) {
        return String(win.internalId);
    }

    // Where a window is: its screen, desktops and activities. A member sent to another desktop,
    // screen or activity has left the arrangement (a plain-geometry zone keeps the same rectangle
    // there).
    function placeOf(win) {
        const ids = [];
        for (let d = 0; d < win.desktops.length; ++d) {
            ids.push(String(win.desktops[d].id));
        }
        const desktops = win.onAllDesktops ? "*" : ids.sort().join(",");
        // An empty activity list means all activities.
        const activities = activitiesOf(win);
        return (win.output ? win.output.name : "?") + "|" + desktops + "|" + (activities.length > 0 ? activities.sort().join(",") : "*");
    }

    function zoneOf(win, tile, zoneRect) {
        const place = placeOf(win);
        const placedAt = Date.now();
        if (tile) {
            return { tile: tile, rect: null, place: place, placedAt: placedAt };
        }
        if (zoneRect) {
            return { tile: null, rect: plainRect(zoneRect), place: place, placedAt: placedAt };
        }
        return win.tile ? { tile: win.tile, rect: null, place: place, placedAt: placedAt }
                        : { tile: null, rect: plainRect(win.frameGeometry), place: place, placedAt: placedAt };
    }

    // A plain-geometry member moved by anything but the user (an app moving itself, another
    // script) leaves its zone too: its geometry is asked on every change once its placement has
    // settled. (A move within the settle is asked at the group's next use, validateGroupOf.)
    function geometryChangedMember(win) {
        const zone = win && !win.deleted ? memberZones[keyOf(win)] : undefined;
        if (zone && zone.rect) {
            checkMember(win, false);
        }
    }

    // Membership and zones change together (Groups.joined/left), so a window left alone by a
    // transfer (the last partner of a group of two) never keeps a zone that could stand for a
    // later arrangement.
    function joinGroup(anchor, win, tile, zoneRect) {
        const f = fill;
        const anchorZone = zoneOf(anchor, null, f && f.anchor === anchor ? f.anchorRect : null);
        const next = Groups.joined({ groups: groups, zones: memberZones }, anchor, win, anchorZone, zoneOf(win, tile, zoneRect), keyOf);
        memberZones = next.zones;
        groups = next.groups;
    }

    function leaveGroup(win) {
        const next = Groups.left({ groups: groups, zones: memberZones }, win, keyOf);
        memberZones = next.zones;
        groups = next.groups;
    }

    // A member stays while it holds its zone (Groups.holds): its quick tile, or for a
    // plain-geometry zone not tiled and in the rectangle once settled; on the screen, desktops and
    // activities it was placed on; not maximized or full screen.
    function checkMember(win, moveEnded) {
        if (!win || win.deleted || Groups.groupOf(groups, win) < 0) {
            return;
        }
        const zone = memberZones[keyOf(win)];
        if (!zone || !Groups.holds(zone, snapshotOf(win, zone.placedAt, moveEnded))) {
            leaveGroup(win);
        }
    }

    // A group action asks every member first, so a window that left its zone in a way no handler
    // saw (or within its placement's settle) is not taken along.
    function validateGroupOf(win) {
        const i = Groups.groupOf(groups, win);
        if (i < 0) {
            return;
        }
        const members = groups[i].slice();
        for (let k = 0; k < members.length; ++k) {
            checkMember(members[k], false);
        }
    }

    function groupMinimizedChanged(win) {
        if (syncing) {
            return;
        }
        validateGroupOf(win);
        const others = Groups.partners(groups, win);
        if (others.length === 0) {
            return;
        }
        syncing = true;
        for (let i = 0; i < others.length; ++i) {
            if (!others[i].deleted && others[i].minimized !== win.minimized) {
                others[i].minimized = win.minimized;
            }
        }
        syncing = false;
    }

    Connections {
        target: Workspace
        function onWindowActivated(win) {
            if (!win) {
                return;
            }
            root.validateGroupOf(win);
            const others = Groups.partners(root.groups, win);
            if (others.length === 0) {
                return;
            }
            for (let i = 0; i < others.length; ++i) {
                if (!others[i].deleted && !others[i].minimized) {
                    Workspace.raiseWindow(others[i]);
                }
            }
            Workspace.raiseWindow(win);
        }
        function onWindowRemoved(win) {
            root.leaveGroup(win);
            if (root.fill && root.fill.anchor === win) {
                root.endFill();
            }
            if (win === flyoutLoader.target) {
                flyoutLoader.active = false;
            }
        }
        function onCurrentDesktopChanged() {
            flyoutLoader.active = false;
            pickerLoader.active = false;
            root.endFill();
        }
        function onCurrentActivityChanged() {
            flyoutLoader.active = false;
            root.workspaceChangedDuringFill();
        }
    }

    // ---------------------------------------------------------------- screens come and go

    // After an output or geometry change every normal window must lie inside its screen's
    // maximize area (ADAPTIVE fix 24: a window opened in portrait ended below the landscape
    // screen); a window larger than the area is made to fit. Tiled, maximized and full-screen
    // windows are KWin's own business. And every screen gets its top bar (owner decision 8): the
    // Global Theme's ensure-topbars.js, run in plasmashell. The build puts its text into
    // ensureTopBars.js next to this file (tools/build.d/80-kwin.sh), so there is one source. It
    // also runs once when the script starts (the session's start): screens attached at login get
    // their bar, and bars made before 2026-10-09 their status area.
    Component.onCompleted: topBarsStart.start()
    Timer {
        id: topBarsStart
        interval: 5000
        onTriggered: topBarsCall.call()
    }
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
            const next = Panels.afterAnswer(line);
            // New widgets (a bar's quick settings and tray, a dock and its launcher) get the power
            // tier's keys only when the power service applies its tier again: its reload, which
            // does nothing when the service is not running. Also when the other part is asked again
            // (a dock made while the top bars' part was skipped).
            if (next.powerTier) {
                powerTierCall.call();
            }
            // At session start plasmashell can answer before it has loaded its layout, or before
            // it has put its panels on their screens ("skipped", the top bars' or the docks' part):
            // ask again, with a growing delay
            // for up to about three minutes (a slow start, the parity VM, took longer than 15 s).
            // Only the first skip of a burst is logged, and the give-up once: the answer repeats
            // identically (a laptop logged ~20 skip lines at every session start, 2026-10-12).
            if (next.retry) {
                askTopBarsAgain(line);
                return;
            }
            topBarsRetry.stop();
            topBarsRetry.tries = 0;
            console.info("plasmafusion-snap: " + line);
        }
        // plasmashell not on the bus yet (the session's start): ask again, as above.
        onFailed: askTopBarsAgain("plasmashell did not run the top-bar check")
    }
    function askTopBarsAgain(why: string): void {
        if (topBarsRetry.tries >= topBarsRetry.maxTries) {
            console.info("plasmafusion-snap: " + why + "; giving up after " + topBarsRetry.tries
                         + " tries (the next screen change asks again)");
            topBarsRetry.stop();
            topBarsRetry.tries = 0;
            return;
        }
        if (topBarsRetry.tries === 0) {
            console.info("plasmafusion-snap: " + why + " (asking again)");
        }
        topBarsRetry.tries++;
        // 3 s while a start is normally just slow, 6 s for the long tail: about 3 minutes total.
        topBarsRetry.interval = topBarsRetry.tries <= 10 ? 3000 : 6000;
        topBarsRetry.restart();
    }
    DBusCall {
        id: powerTierCall
        service: "org.freedesktop.systemd1"
        path: "/org/freedesktop/systemd1"
        dbusInterface: "org.freedesktop.systemd1.Manager"
        method: "ReloadOrTryRestartUnit"
        arguments: ["plasma-fusion-powerfx.service", "replace"]
        onFailed: console.info("plasmafusion-snap: the power service was not asked to apply its tier to the new panels")
    }
    Timer {
        id: topBarsRetry
        property int tries: 0
        readonly property int maxTries: 40
        interval: 3000
        onTriggered: topBarsCall.call()
    }
    Connections {
        target: Workspace
        function onScreensChanged() {
            root.workspaceChangedDuringFill();
            screensSettled.restart();
        }
        function onVirtualScreenGeometryChanged() {
            root.workspaceChangedDuringFill();
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

    // One watcher per window for snaps and snap-group changes.
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
                    root.checkMember(watcher.window, false);
                    root.fillAnchorChanged(watcher.window, false);
                    watcher.fit();
                }
                function onFrameGeometryChanged() {
                    watcher.fit();
                    root.geometryChangedMember(watcher.window);
                    root.fillAnchorChanged(watcher.window, false);
                }
                function onInteractiveMoveResizeFinished() {
                    watcher.fit();
                    root.checkMember(watcher.window, true);
                    root.fillAnchorChanged(watcher.window, true);
                }
                function onMaximizedChanged() {
                    root.checkMember(watcher.window, false);
                    root.fillAnchorChanged(watcher.window, false);
                }
                function onFullScreenChanged() {
                    root.checkMember(watcher.window, false);
                    root.fillAnchorChanged(watcher.window, false);
                }
                function onDesktopsChanged() {
                    root.checkMember(watcher.window, false);
                    root.fillAnchorChanged(watcher.window, false);
                }
                function onOutputChanged() {
                    root.checkMember(watcher.window, false);
                    root.fillAnchorChanged(watcher.window, false);
                }
                function onActivitiesChanged() {
                    root.checkMember(watcher.window, false);
                    root.fillAnchorChanged(watcher.window, false);
                }
                function onMinimizedChanged() {
                    root.groupMinimizedChanged(watcher.window);
                }
            }
        }
    }
}
