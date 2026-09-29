/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kwin

// Plasma Fusion snapping (boards QuickSettings.dc.html "Snap layouts", TabsSnap.dc.html).
//
// - Meta+Z ("Plasma Fusion: Snap Layouts") opens a flyout near the active window's maximize
//   button with four layouts; a click on a zone places the window there.
// - After a window is snapped to the left or right half, the other half offers the remaining
//   windows ("Pick a window for this side"). Esc, a click elsewhere or any focus change
//   dismisses it; it also closes itself after a minute without input.
// - Snapped halves and quarters get the same gap as the Meta+T custom zones (6 px).
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
        if (!quickRoot || !setting("QuickTileGaps", true)) {
            return;
        }
        const g = gap();
        if (quickRoot.padding !== g) {
            quickRoot.padding = g;
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

    // Gap-aware geometry of a fraction of the work area, as KWin tiles compute it.
    function zoneRect(area, fx, fy, fw, fh, g) {
        const x0 = area.x + fx * area.width;
        const y0 = area.y + fy * area.height;
        const x1 = area.x + (fx + fw) * area.width;
        const y1 = area.y + (fy + fh) * area.height;
        const l = fx > 0.001 ? g / 2 : g;
        const t = fy > 0.001 ? g / 2 : g;
        const r = fx + fw < 0.999 ? g / 2 : g;
        const b = fy + fh < 0.999 ? g / 2 : g;
        return Qt.rect(Math.round(x0 + l), Math.round(y0 + t), Math.round(x1 - r - (x0 + l)), Math.round(y1 - b - (y0 + t)));
    }

    function thirdRect(area, i, g) {
        const w = (area.width - 4 * g) / 3;
        return Qt.rect(Math.round(area.x + g + i * (w + g)), Math.round(area.y + g), Math.round(w), Math.round(area.height - 2 * g));
    }

    // Layouts of the flyout (board order): zones as fractions [x, y, w, h], plus how to place.
    readonly property var layouts: [
        { name: "halves", zones: [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]], quick: [0, 1], h: 0.5, v: 0 },
        { name: "twoThirds", zones: [[0, 0, 2 / 3, 1], [2 / 3, 0, 1 / 3, 1]], quick: [0, 1], h: 2 / 3, v: 0 },
        { name: "quarters", zones: [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]], quick: [4, 5, 6, 7], h: 0.5, v: 0.5 },
        { name: "thirds", zones: [[0, 0, 1 / 3, 1], [1 / 3, 0, 1 / 3, 1], [2 / 3, 0, 1 / 3, 1]], quick: [], h: 0, v: 0 }
    ]

    function targetRect(win, layoutIndex, zoneIndex) {
        const area = Workspace.clientArea(Workspace.MaximizeArea, win);
        const layout = layouts[layoutIndex];
        const g = setting("QuickTileGaps", true) || layout.quick.length === 0 ? gap() : 0;
        if (layout.quick.length === 0) {
            return thirdRect(area, zoneIndex, g);
        }
        const z = layout.zones[zoneIndex];
        return zoneRect(area, z[0], z[1], z[2], z[3], g);
    }

    function placeInZone(win, layoutIndex, zoneIndex) {
        if (!usable(win)) {
            return;
        }
        const layout = layouts[layoutIndex];
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
            flyoutLoader.active = true;
        }
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
        active: false
        delegate: SnapFlyout {
            target: flyoutLoader.target
            layouts: root.layouts
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

    // Tile geometry minus padding, as Tile::windowGeometry computes it.
    function tileWindowRect(tile) {
        const a = tile.absoluteGeometry;
        const r = tile.relativeGeometry;
        const p = tile.padding;
        const l = r.x > 0.001 ? p / 2 : p;
        const t = r.y > 0.001 ? p / 2 : p;
        const rr = r.x + r.width < 0.999 ? p / 2 : p;
        const b = r.y + r.height < 0.999 ? p / 2 : p;
        return Qt.rect(a.x + l, a.y + t, a.width - l - rr, a.height - t - b);
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
        if ((index !== 0 && index !== 1) || win !== Workspace.activeWindow) {
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
        if (index !== 0 && index !== 1) {
            return;
        }
        const quickRoot = quickRootOf(win);
        const other = quickRoot.tiles[index === 0 ? 1 : 0];
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

    // One watcher per window for snaps and pair changes.
    Instantiator {
        model: WindowModel {}
        delegate: QtObject {
            id: watcher
            required property var window
            // Windows already in a half or quarter when the script starts get the gap too.
            Component.onCompleted: root.applyGap(root.quickRootOf(window))
            readonly property Connections connections: Connections {
                target: watcher.window
                function onTileChanged() {
                    root.windowSnapped(watcher.window);
                    root.pairTileChanged(watcher.window);
                }
                function onMinimizedChanged() {
                    root.pairMinimizedChanged(watcher.window);
                }
            }
        }
    }
}
