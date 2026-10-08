// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import org.kde.kwin as KW

Item {
    id: harness
    property bool done: false
    property int failures: 0
    property int checks: 0
    property var results: []
    property var script: null
    property var outlineWindow: null
    property var desktop: ({id: "desktop-1"})
    QtObject {
        id: quickRoot
        property var parent: null
        property var tiles: [tile, {}, {}, {}, {}, {}, {}, {}]
        property real padding: 6
    }
    QtObject {
        id: tile
        property var parent: quickRoot
        property rect relativeGeometry: Qt.rect(0, 0, 0.5, 1)
        property rect absoluteGeometry: Qt.rect(0, 34, 720, 866)
        property real padding: 6
        signal windowGeometryChanged()
    }
    QtObject {
        id: win
        property var tile: tile
        property var output: ({name: "Virtual-1", devicePixelRatio: 4 / 3})
        property var desktops: [desktop]
        property bool onAllDesktops: false
        property bool deleted: false
        property bool normalWindow: true
        property bool popupWindow: false
        property bool moveable: true
        property bool resizeable: true
        property bool fullScreen: false
        property bool specialWindow: false
        property bool move: false
        property bool resize: false
        property int maximizeMode: 0
        property bool minimized: false
        property rect frameGeometry: Qt.rect(6, 40, 711, 854.25)
        signal closed()
        signal interactiveMoveResizeFinished()
    }
    QtObject {
        id: outline
        property rect geometry: Qt.rect(0, 34, 720, 866)
        property rect visualParentGeometry: Qt.rect(100, 100, 700, 600)
        property rect unifiedGeometry: Qt.rect(0, 34, 800, 866)
        property bool active: false
    }

    function check(label, ok, detail) {
        checks++;
        if (!ok) failures++;
        results = results.concat([(ok ? "PASS " : "FAIL ") + label + (ok ? "" : " " + detail)]);
    }
    function equalRect(a, b) {
        return Math.abs(a.x - b.x) < 0.01 && Math.abs(a.y - b.y) < 0.01
            && Math.abs(a.width - b.width) < 0.01 && Math.abs(a.height - b.height) < 0.01;
    }
    function rectCheck(label, actual, expected) {
        check(label, equalRect(actual, expected), actual + " != " + expected);
    }

    Component.onCompleted: {
        KW.Workspace.windows = [win];
        KW.Workspace.currentDesktop = desktop;
        const base = "file://" + stageHome + "/.local/share/kwin/scripts/plasmafusion-snap/contents/";
        const component = Qt.createComponent(base + "ui/main.qml");
        if (component.status !== Component.Ready) {
            check("script loads", false, component.errorString());
            done = true;
            return;
        }
        script = component.createObject(harness);
        const outlineComponent = Qt.createComponent(base + "outline/outline.qml");
        if (outlineComponent.status !== Component.Ready) {
            check("outline loads", false, outlineComponent.errorString());
            done = true;
            return;
        }
        outlineWindow = outlineComponent.createObject(null);
        Qt.callLater(testGeometry);
    }

    function testGeometry() {
        const a = Qt.rect(0, 34, 1440, 866);
        for (const gap of [0, 6, 12, 48]) {
            rectCheck("left half gap=" + gap, script.zoneRect(a, 0, 0, 0.5, 1, gap), Qt.rect(0, 34, 720 - gap / 2, 866));
            rectCheck("right half gap=" + gap, script.zoneRect(a, 0.5, 0, 0.5, 1, gap), Qt.rect(720 + gap / 2, 34, 720 - gap / 2, 866));
            rectCheck("bottom-right quarter gap=" + gap, script.zoneRect(a, 0.5, 0.5, 0.5, 0.5, gap), Qt.rect(720 + gap / 2, 467 + gap / 2, 720 - gap / 2, 433 - gap / 2));
        }
        const offset = Qt.rect(-1440, 54, 1440, 846);
        rectCheck("offset output", script.zoneRect(offset, 0, 0, 0.5, 1, 6), Qt.rect(-1440, 54, 717, 846));
        const thirds = [0, 1, 2].map(i => script.thirdRect(a, i, 6, false));
        rectCheck("first third", thirds[0], Qt.rect(0, 34, 476, 866));
        rectCheck("middle third", thirds[1], Qt.rect(482, 34, 476, 866));
        rectCheck("last third", thirds[2], Qt.rect(964, 34, 476, 866));
        const rows = Qt.rect(40, 0, 866, 1440);
        rectCheck("last portrait third", script.thirdRect(rows, 2, 6, true), Qt.rect(40, 964, 866, 476));
        const odd = Qt.rect(20, 34, 1439, 865);
        const end = script.thirdRect(odd, 2, 7, false);
        check("odd third reaches right edge", end.x + end.width === 1459 && end.y + end.height === 899, end);
        rectCheck("picker matches tiled window", script.tileWindowRect(tile), Qt.rect(0, 34, 717, 866));
        // Startup watcher must correct a window that was already snapped when the script loaded.
        rectCheck("already tiled startup", win.frameGeometry, Qt.rect(0, 34, 717, 866));
        check("native padding cleared", quickRoot.padding === 0, quickRoot.padding);
        KWin.setConfig("QuickTileGaps", false);
        rectCheck("quick gap disabled preview", script.targetRect(win, 0, 0), Qt.rect(0, 34, 720, 866));
        script.fitQuickTile(win);
        rectCheck("quick gap disabled window", win.frameGeometry, Qt.rect(0, 34, 720, 866));
        KWin.setConfig("QuickTileGaps", true);
        KWin.setConfig("Gap", 12);
        script.fitQuickTile(win);
        rectCheck("configured inner gap", win.frameGeometry, Qt.rect(0, 34, 714, 866));
        KWin.setConfig("Gap", 6);
        win.frameGeometry = Qt.rect(0, 34, 717, 866.25);
        script.fitQuickTile(win);
        rectCheck("fractional device rounding stable", win.frameGeometry, Qt.rect(0, 34, 717, 866.25));
        win.maximizeMode = 3;
        win.frameGeometry = a;
        script.fitQuickTile(win);
        rectCheck("maximize left alone", win.frameGeometry, a);
        win.maximizeMode = 0;
        win.fullScreen = true;
        script.fitQuickTile(win);
        rectCheck("fullscreen left alone", win.frameGeometry, a);
        win.fullScreen = false;
        win.resize = true;
        win.frameGeometry = Qt.rect(0, 34, 900, 866);
        script.fitQuickTile(win);
        rectCheck("interactive resize left alone", win.frameGeometry, Qt.rect(0, 34, 900, 866));
        win.resize = false;
        if (outlineWindow) {
            outline.active = true;
            outlineWindow.place(a, false);
            const zone = outlineWindow.contentItem.children[0];
            rectCheck("outline keeps work-area edges", Qt.rect(zone.x + outline.unifiedGeometry.x,
                zone.y + outline.unifiedGeometry.y, zone.width, zone.height), a);
            outline.active = false;
        }
        win.frameGeometry = Qt.rect(6, 40, 711, 854.25);
        Qt.callLater(testNativeResize);
    }
    function testNativeResize() {
        rectCheck("native reconfigure reapplies edges", win.frameGeometry, Qt.rect(0, 34, 717, 866));
        tile.relativeGeometry = Qt.rect(0, 0, 2 / 3, 1);
        tile.absoluteGeometry = Qt.rect(0, 34, 960, 866);
        tile.windowGeometryChanged();
        Qt.callLater(testSplit);
    }
    function testSplit() {
        rectCheck("shared split resize keeps native tile", win.frameGeometry, Qt.rect(0, 34, 957, 866));
        check("native tile retained", win.tile === tile, win.tile);
        win.move = true;
        win.frameGeometry = Qt.rect(100, 100, 600, 400);
        Qt.callLater(testMoving);
    }
    function testMoving() {
        rectCheck("interactive move left alone", win.frameGeometry, Qt.rect(100, 100, 600, 400));
        win.move = false;
        win.interactiveMoveResizeFinished();
        Qt.callLater(testMoveFinished);
    }
    function testMoveFinished() {
        rectCheck("remaining tiled window after resize", win.frameGeometry, Qt.rect(0, 34, 957, 866));
        win.tile = null;
        win.frameGeometry = Qt.rect(140, 100, 700, 450);
        Qt.callLater(testUntiled);
    }
    function testUntiled() {
        rectCheck("untiled window left alone", win.frameGeometry, Qt.rect(140, 100, 700, 450));
        console.log("snap geometry: " + checks + " checks, " + failures + " failures");
        if (outlineWindow) outlineWindow.destroy();
        done = true;
    }
}
