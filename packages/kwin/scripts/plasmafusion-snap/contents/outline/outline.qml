/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window
// KWin 6.8 names its window class "Window" in org.kde.kwin (uncreatable), which shadows
// QtQuick's Window after the unqualified import below; create QtQuick's by its own name.
import QtQuick.Window as QtQuickWindow
import org.kde.kirigami as Kirigami
import org.kde.kwin
import "../ui/SnapGeometry.js" as SnapGeometry

// Snap-zone preview for KWin's outline (kwinrc [Outline] QmlPath=
// kwin/scripts/plasmafusion-snap/contents/outline/outline.qml). TabsSnap board "Drag to snap":
// a blue zone, fill rgba(91,157,255,.28), 2 px #5b9dff edge, radius 14, shown after the pointer
// has rested at the edge for 150 ms. KWin itself still snaps on release without the delay.
//
// Contract (KWin 6.7 src/outline.cpp): the root is a Window, the context property "outline"
// has geometry, visualParentGeometry, unifiedGeometry and active.
QtQuickWindow.Window {
    id: window

    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property bool fusionAccent: Math.abs(accent.r - 47 / 255) < 0.04
        && Math.abs(accent.g - 111 / 255) < 0.04 && Math.abs(accent.b - 223 / 255) < 0.04
    readonly property color edgeColor: fusionAccent ? (dark ? "#5b9dff" : "#2f6fdf") : accent
    readonly property color fillColor: fusionAccent
        ? (dark ? Qt.rgba(91 / 255, 157 / 255, 1, 0.28) : Qt.rgba(47 / 255, 111 / 255, 223 / 255, 0.20))
        : Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.28 : 0.20)
    property bool animated: false
    property var quickRoots: ({})
    property rect targetGeometry: outline.geometry

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint
    color: "transparent"

    x: Math.min(outline.unifiedGeometry.x, targetGeometry.x)
    y: Math.min(outline.unifiedGeometry.y, targetGeometry.y)
    width: Math.max(1, Math.max(outline.unifiedGeometry.x + outline.unifiedGeometry.width,
        targetGeometry.x + targetGeometry.width) - x)
    height: Math.max(1, Math.max(outline.unifiedGeometry.y + outline.unifiedGeometry.height,
        targetGeometry.y + targetGeometry.height) - y)

    visible: outline.active

    onSceneGraphError: (error, message) => {
        console.warn("plasmafusion outline: scene graph error:", message);
    }

    function rememberRoots() {
        for (const win of Workspace.stackingOrder) {
            const tile = win ? win.tile : null;
            if (!tile || !tile.parent || tile.parent.parent || !win.output) continue;
            const desktop = !win.onAllDesktops && win.desktops.length ? win.desktops[0] : Workspace.currentDesktop;
            const root = tile.parent;
            if (root.tiles.length === 8 && root !== Workspace.rootTile(win.output, desktop)) {
                quickRoots[win.output.name + "|" + (desktop ? desktop.id : "?")] = {root: root, output: win.output.name};
            }
        }
    }

    function equalRect(a, b) {
        return Math.abs(a.x - b.x) <= 1 && Math.abs(a.y - b.y) <= 1
            && Math.abs(a.width - b.width) <= 1 && Math.abs(a.height - b.height) <= 1;
    }

    function customMatches(tile, geometry, area) {
        if (!tile) return false;
        if (tile.tiles.length) {
            for (const child of tile.tiles) {
                if (customMatches(child, geometry, area)) return true;
            }
            return false;
        }
        return equalRect(SnapGeometry.tileRect(tile.absoluteGeometry, tile.relativeGeometry, tile.padding, area, false), geometry);
    }

    function previewRect(geometry) {
        const output = Workspace.screenAt(Qt.point(geometry.x + geometry.width / 2, geometry.y + geometry.height / 2));
        if (!output) return geometry;
        const area = Workspace.clientArea(Workspace.MaximizeArea, output, Workspace.currentDesktop);
        // The outline API supplies geometry, not the tiling mode. Preserve a matching custom
        // tile's preview when its shape coincides with a quick tile (e.g. custom 50/50 zones).
        if (customMatches(Workspace.rootTile(output, Workspace.currentDesktop), geometry, area)) return geometry;
        for (const key of Object.keys(quickRoots)) {
            const record = quickRoots[key];
            if (record.output !== output.name) continue;
            try {
                for (const tile of record.root.tiles) {
                    if (!tile.absoluteGeometry || !tile.relativeGeometry) continue;
                    const native = SnapGeometry.tileRect(tile.absoluteGeometry, tile.relativeGeometry, tile.padding, area, false);
                    if (equalRect(native, geometry)) {
                        const filled = SnapGeometry.tileRect(tile.absoluteGeometry, tile.relativeGeometry, tile.padding, area, true);
                        return Qt.rect(filled.x, filled.y, filled.width, filled.height);
                    }
                }
            } catch (e) {
                delete quickRoots[key]; // this screen/desktop's native tiles were removed
            }
        }
        return geometry; // Meta+Z already supplies the filled target; unknown outlines stay native
    }

    function place(geometry, animate, parentGeometry) {
        rememberRoots();
        targetGeometry = previewRect(outline.geometry);
        const g = parentGeometry ? geometry : previewRect(geometry);
        window.animated = animate;
        zone.x = g.x - window.x;
        zone.y = g.y - window.y;
        zone.width = g.width;
        zone.height = g.height;
        window.animated = true;
    }

    onVisibleChanged: {
        if (visible) {
            appear.stop();
            zone.opacity = 0;
            if (outline.visualParentGeometry.width > 0 && outline.visualParentGeometry.height > 0) {
                place(outline.visualParentGeometry, false, true);
                place(outline.geometry, true);
            } else {
                place(outline.geometry, false);
            }
            appear.start();
        } else {
            appear.stop();
            zone.opacity = 0;
        }
    }

    Connections {
        target: outline
        function onGeometryChanged() {
            if (window.visible) {
                window.place(outline.geometry, true);
            }
        }
        function onUnifiedGeometryChanged() {
            if (window.visible) {
                window.place(outline.geometry, false);
            }
        }
    }
    Connections {
        target: Workspace.activeWindow
        function onTileChanged() {
            window.rememberRoots();
        }
    }

    SequentialAnimation {
        id: appear
        // Durations from Plasma's animation speed (the Motion tokens' base: short 100 ms, long
        // 200 ms at speed 1; near 0 with animations off).
        PauseAnimation { duration: Math.round(Kirigami.Units.shortDuration * 1.5) }
        NumberAnimation { target: zone; property: "opacity"; to: 1; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: zone
        opacity: 0
        radius: 14
        color: window.fillColor
        border.width: 2
        border.color: window.edgeColor

        Behavior on x { enabled: window.animated; NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: window.animated; NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: window.animated; NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: window.animated; NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }
    }
}
