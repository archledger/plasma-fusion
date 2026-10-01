/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window
// KWin 6.8 names its window class "Window" in org.kde.kwin (uncreatable), which shadows
// QtQuick's Window after the unqualified import below; create QtQuick's by its own name.
import QtQuick.Window as QtQuickWindow
import org.kde.kwin

// Two apps side by side in tablet posture (TABLET2 M1): a handle on the split between a window
// quick-tiled left and one tiled right, as on iPadOS. Drag it to resize both (KWin's quick-tile
// root keeps the two tiles together: resizing the left tile moves the right one); on release it
// snaps to 1/3, 1/2 or 2/3 of the work area (portrait: 1/2), skipping a split that would make a
// window smaller than its minimum size. Dragged into the outer 12 % it ends the split: the window
// on that side is minimized (not closed) and the other one is maximized. An internal KWin window
// (it takes touch through KWin's internal-window filter), shown only while the tablet window
// policy is applied and the active window is one of the pair. The window comes from an
// Instantiator: with an Item as visual parent (this script's items are in no window) QtQuick would
// never show it (as plasmafusion-snap's pop-ups).
Item {
    id: divider

    // The tablet script (main.qml): applied, internalOutput(), log().
    required property var script

    property var leftWindow: null
    property var rightWindow: null
    readonly property var leftTile: leftWindow && !leftWindow.deleted ? leftWindow.tile : null
    readonly property bool paired: leftTile !== null && rightWindow !== null && !rightWindow.deleted
    readonly property bool shown: paired && script.applied
    property rect area: Qt.rect(0, 0, 1, 1)
    readonly property bool portrait: area.height > area.width
    readonly property real splitX: leftTile ? leftTile.absoluteGeometry.x + leftTile.absoluteGeometry.width : 0

    property bool dragging: false
    property real fingerX: 0


    // ---- Which two windows form the split
    function isLeft(tile): bool {
        const g = tile ? tile.relativeGeometry : null;
        return g !== null && g.x < 0.01 && g.width < 0.99 && g.height > 0.99;
    }
    function isRight(tile): bool {
        const g = tile ? tile.relativeGeometry : null;
        return g !== null && g.x > 0.01 && g.x + g.width > 0.99 && g.height > 0.99;
    }
    function visibleOnDesktop(w): bool {
        return w && !w.deleted && w.normalWindow && !w.minimized && script.internalOutput(w.output)
            && (w.onAllDesktops || w.desktops.indexOf(Workspace.currentDesktop) >= 0);
    }
    function refresh(): void {
        if (dragging) {
            return;
        }
        const active = Workspace.activeWindow;
        let left = null, right = null;
        if (visibleOnDesktop(active) && active.tile && (isLeft(active.tile) || isRight(active.tile))) {
            const order = Workspace.stackingOrder;
            // the topmost window on the other side
            for (let i = order.length - 1; i >= 0; --i) {
                const w = order[i];
                if (w === active || !visibleOnDesktop(w) || w.output !== active.output || !w.tile) {
                    continue;
                }
                if (isLeft(active.tile) && isRight(w.tile)) {
                    left = active;
                    right = w;
                    break;
                }
                if (isRight(active.tile) && isLeft(w.tile)) {
                    left = w;
                    right = active;
                    break;
                }
            }
        }
        if (left !== leftWindow || right !== rightWindow) {
            leftWindow = left;
            rightWindow = right;
            if (left) {
                area = Workspace.clientArea(Workspace.MaximizeArea, left);
                script.log("split divider: " + left.resourceClass + " | " + right.resourceClass);
            }
        }
    }
    Connections {
        target: Workspace
        function onWindowActivated() {
            Qt.callLater(divider.refresh);
        }
        function onWindowAdded(w) {
            if (w && w.caption === "plasmafusion-split-divider") {
                w.skipTaskbar = true;
                w.skipSwitcher = true;
                w.skipPager = true;
                return;
            }
            Qt.callLater(divider.refresh);
        }
        function onWindowRemoved() {
            Qt.callLater(divider.refresh);
        }
        function onCurrentDesktopChanged() {
            Qt.callLater(divider.refresh);
        }
    }
    Connections {
        target: divider.leftWindow
        ignoreUnknownSignals: true
        function onTileChanged() {
            Qt.callLater(divider.refresh);
        }
        function onMinimizedChanged() {
            Qt.callLater(divider.refresh);
        }
    }
    Connections {
        target: divider.rightWindow
        ignoreUnknownSignals: true
        function onTileChanged() {
            Qt.callLater(divider.refresh);
        }
        function onMinimizedChanged() {
            Qt.callLater(divider.refresh);
        }
    }
    Connections {
        target: divider.script
        function onAppliedChanged() {
            Qt.callLater(divider.refresh);
        }
    }

    // ---- Resizing
    // Moves the split to global x (the left tile's right edge), within 20-80 % while dragging.
    function moveSplitTo(targetX: real): void {
        if (!leftTile) {
            return;
        }
        const min = area.x + 0.2 * area.width;
        const max = area.x + 0.8 * area.width;
        const delta = Math.max(min, Math.min(max, targetX)) - splitX;
        if (Math.abs(delta) >= 1) {
            leftTile.resizeByPixels(delta, Qt.RightEdge);
        }
    }
    function fits(fraction: real): bool {
        const leftWidth = fraction * area.width;
        const rightWidth = area.width - leftWidth;
        return leftWindow.minSize.width <= leftWidth - 8 && rightWindow.minSize.width <= rightWidth - 8;
    }
    function finish(): void {
        const f = (fingerX - area.x) / area.width;
        const left = leftWindow, right = rightWindow;
        dragging = false;
        if (f < 0.12 || f > 0.88) {
            // the window on that side leaves the split; the other one fills the screen
            const gone = f < 0.12 ? left : right;
            const kept = f < 0.12 ? right : left;
            script.log("split divider: " + gone.resourceClass + " leaves the split");
            gone.minimized = true;
            kept.setMaximize(true, true);
            Workspace.activeWindow = kept;
            return;
        }
        const candidates = portrait ? [0.5] : [1 / 3, 0.5, 2 / 3];
        let best = 0.5, bestDistance = 2;
        for (const c of candidates) {
            if (fits(c) && Math.abs(c - f) < bestDistance) {
                best = c;
                bestDistance = Math.abs(c - f);
            }
        }
        moveSplitTo(area.x + best * area.width);
        script.log("split divider: split at " + Math.round(best * 100) + " %");
    }
    Timer {
        // live resize while dragging, at most every 50 ms (each resize re-lays out both apps)
        id: liveResize
        interval: 50
        repeat: true
        running: divider.dragging
        onTriggered: divider.moveSplitTo(divider.fingerX)
    }

    Instantiator {
        active: divider.shown
        delegate: QtQuickWindow.Window {
            id: handle
            // KWin lists it as a normal window whatever the type; onWindowAdded marks it
            // skip-taskbar, -switcher and -pager by this title (the dock, Alt+Tab, the policy)
            title: "plasmafusion-split-divider"
            flags: Qt.FramelessWindowHint | Qt.BypassWindowManagerHint | Qt.WindowDoesNotAcceptFocus
            color: "transparent"
            width: 48
            height: 128
            x: Math.round((divider.dragging ? divider.fingerX : divider.splitX) - width / 2)
            y: Math.round(divider.area.y + (divider.area.height - height) / 2)
            visible: true

            Item {
                anchors.fill: parent
                Accessible.role: Accessible.Separator
                Accessible.name: i18nd("plasmafusion", "Split view divider")

                Rectangle {
                    id: pill
                    anchors.centerIn: parent
                    width: divider.dragging ? 8 : 6
                    height: divider.dragging ? 80 : 64
                    radius: width / 2
                    color: Qt.rgba(1, 1, 1, divider.dragging ? 1 : 0.88)
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.25)
                }

                DragHandler {
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    dragThreshold: 4
                    onActiveChanged: {
                        if (active) {
                            divider.fingerX = handle.x + centroid.scenePosition.x;
                            divider.dragging = true;
                        } else if (divider.dragging) {
                            divider.finish();
                        }
                    }
                    onCentroidChanged: {
                        if (active) {
                            divider.fingerX = handle.x + centroid.scenePosition.x;
                        }
                    }
                }
            }
        }
    }
}
