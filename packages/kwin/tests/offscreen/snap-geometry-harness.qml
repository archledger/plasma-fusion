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
    // KWin's quick-tile root with its eight children (quicktile.cpp order: halves, then quarters).
    QuickRootTile {
        id: quickRoot
        tiles: [tile].concat(harness.quickShapes.slice(1).map(r => harness.shapeTile(r)))
    }
    readonly property var quickShapes: [Qt.rect(0, 0, 0.5, 1), Qt.rect(0.5, 0, 0.5, 1),
        Qt.rect(0, 0, 1, 0.5), Qt.rect(0, 0.5, 1, 0.5), Qt.rect(0, 0, 0.5, 0.5),
        Qt.rect(0.5, 0, 0.5, 0.5), Qt.rect(0, 0.5, 0.5, 0.5), Qt.rect(0.5, 0.5, 0.5, 0.5)]
    function shapeTile(r) {
        return {relativeGeometry: r, absoluteGeometry: Qt.rect(r.x * 1440, 34 + r.y * 866, r.width * 1440, r.height * 866),
                padding: 6, windows: [], parent: null};
    }
    Component {
        id: quickRootType
        QuickRootTile {}
    }
    Component {
        id: customRootType
        RootTile {}
    }
    Component {
        id: plainRootType
        QtObject {
            property var parent: null
            property var tiles: []
        }
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
    // Snap sizes from the keyboard: a window on a screen of its own (no quick root cached there, so
    // the halves fall back to their rectangles), and a second screen to the right of it.
    readonly property var screenA: ({name: "Virtual-9", geometry: Qt.rect(0, 0, 1440, 900)})
    readonly property var screenB: ({name: "Virtual-10", geometry: Qt.rect(1440, 0, 1440, 900)})
    QtObject {
        id: cycleWin
        property var tile: null
        property var output: harness.screenA
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
        property rect frameGeometry: Qt.rect(0, 34, 720, 866)
        property string internalId: "{cycle}"
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
        // The geometry checks measure a 6 px gap; the default (none) has its own checks.
        KWin.setConfig("Gap", 6);
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
        // Until its settings are read (moments after KWin starts it), the outline has no gap.
        check("before reading its settings the outline has no gap",
            !outlineWindow.settingsLoaded && outlineWindow.configuredGap === 0, outlineWindow.configuredGap);
        outlineWindow.settingsLoadedChanged.connect(() => {
            if (outlineWindow.settingsLoaded) Qt.callLater(testQuickRoots);
        });
    }

    // A window on a given tile of a stand-in root.
    function windowOn(rootTile, role) {
        const t = rootTile.tiles.find(c => c.relativeGeometry && Math.abs(c.relativeGeometry.x - quickShapes[role].x) < 0.001
            && Math.abs(c.relativeGeometry.y - quickShapes[role].y) < 0.001
            && Math.abs(c.relativeGeometry.width - quickShapes[role].width) < 0.001
            && Math.abs(c.relativeGeometry.height - quickShapes[role].height) < 0.001);
        if (t) t.parent = rootTile;
        return {tile: t, output: win.output, desktops: [desktop], onAllDesktops: false};
    }
    function quickChildren(order) {
        return order.map(i => shapeTile(quickShapes[i]));
    }

    // KWin's quick-tile root is found by its class name, else by its shape; its tiles by their
    // shape, not their place among the children (survey B12: the script asked for exactly eight
    // children in quicktile.cpp's order, which KWin does not document).
    function testQuickRoots() {
        check("quick root of a tiled window", script.quickRootOf(win) === quickRoot, script.quickRootOf(win));
        check("left half is role 0", script.quickIndexOf(win) === 0, script.quickIndexOf(win));
        const shuffled = quickRootType.createObject(harness, {tiles: quickChildren([7, 3, 5, 1, 0, 6, 2, 4])});
        check("children in another order: roles from the shape",
            [0, 1, 2, 3, 4, 5, 6, 7].every(role => script.quickIndexOf(windowOn(shuffled, role)) === role),
            [0, 1, 2, 3, 4, 5, 6, 7].map(role => script.quickIndexOf(windowOn(shuffled, role))));
        const nine = quickRootType.createObject(harness, {tiles: quickChildren([0, 1, 2, 3, 4, 5, 6, 7]).concat([shapeTile(Qt.rect(0.25, 0, 0.5, 1))])});
        check("a ninth child does not hide the quick root", script.quickRootOf(windowOn(nine, 1)) === nine, script.quickRootOf(windowOn(nine, 1)));
        const unnamed = plainRootType.createObject(harness, {tiles: quickChildren([0, 1, 2, 3, 4, 5, 6, 7])});
        check("an unnamed root with the quick tiles' shape is the quick root", script.quickRootOf(windowOn(unnamed, 5)) === unnamed,
            script.quickRootOf(windowOn(unnamed, 5)));
        const columns = plainRootType.createObject(harness, {tiles: [shapeTile(Qt.rect(0, 0, 0.5, 1)), shapeTile(Qt.rect(0.5, 0, 0.5, 1))]});
        check("an unnamed root of side-by-side zones is not", script.quickRootOf(windowOn(columns, 0)) === null, script.quickRootOf(windowOn(columns, 0)));
        const otherCustom = customRootType.createObject(harness, {tiles: quickChildren([0, 1, 2, 3, 4, 5, 6, 7])});
        check("another desktop's custom root is never the quick root, whatever its children",
            script.quickRootOf(windowOn(otherCustom, 0)) === null, script.quickRootOf(windowOn(otherCustom, 0)));
        KW.Workspace.stackingOrder = [windowOn(shuffled, 3)];
        outlineWindow.quickRoots = ({});
        outlineWindow.rememberRoots();
        const record = outlineWindow.quickRoots["Virtual-1|desktop-1"];
        check("the outline remembers a quick root in another order", record && record.root === shuffled, record);
        KW.Workspace.stackingOrder = [windowOn(otherCustom, 0)];
        outlineWindow.quickRoots = ({});
        outlineWindow.rememberRoots();
        check("the outline does not take a custom root for one", Object.keys(outlineWindow.quickRoots).length === 0,
            JSON.stringify(Object.keys(outlineWindow.quickRoots)));
        KW.Workspace.stackingOrder = KW.Workspace.windows;
        tile.parent = quickRoot;
        outlineWindow.quickRoots = ({});
        Qt.callLater(testOutlineSettings);
    }

    // The outline reads the gap settings once and again when KWin reloads its configuration,
    // not each time it shows (survey B12: a shell and two kreadconfig6 inside KWin per show).
    function testOutlineSettings() {
        testFiles.writeKwinrc("[Script-plasmafusion-snap]\nGap=12\n");
        // Later, shown and hidden twice, as KWin does when the pointer reaches an edge.
        settingsWait.next = () => {
            for (let i = 0; i < 2; ++i) {
                outlineWindow.visible = true;
                outlineWindow.visible = false;
            }
            outlineWindow.visible = Qt.binding(() => outline.active);
            settingsWait.next = checkShown;
            settingsWait.restart();
        };
        settingsWait.restart();
    }
    function checkShown() {
        settingsWait.next = () => {
            check("showing the outline does not read the settings again", outlineWindow.configuredGap === 0, outlineWindow.configuredGap);
            KW.Options.configChanged();
            settingsWait.next = () => {
                check("KWin reloading its configuration reads them again", outlineWindow.configuredGap === 12, outlineWindow.configuredGap);
                testFiles.writeKwinrc("");
                KW.Options.configChanged();
                settingsWait.next = () => {
                    check("and back to the default", outlineWindow.configuredGap === 0, outlineWindow.configuredGap);
                    testGeometry();
                };
                settingsWait.restart();
            };
            settingsWait.restart();
        };
        settingsWait.next();
    }
    Timer {
        id: settingsWait
        property var next: null
        interval: 2500
        onTriggered: next()
    }

    function testGeometry() {
        check("actual outline config reader loads enabled default", outlineWindow.quickGaps, outlineWindow.quickGaps);
        check("actual outline config reader loads default gap (none)", outlineWindow.configuredGap === 0, outlineWindow.configuredGap);
        outlineWindow.applySettings("true\nwide\n");
        check("a gap that is not a number is none", outlineWindow.configuredGap === 0, outlineWindow.configuredGap);
        outlineWindow.applySettings("true\n0\n");
        KWin.unsetConfig("Gap");
        check("the script's default gap is none", script.gap() === 0, script.gap());
        KWin.setConfig("Gap", 6);
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
        const oddArea = Qt.rect(0, 34, 1439, 865);
        const trailingTile = {absoluteGeometry: Qt.rect(720, 467, 720, 433),
                              relativeGeometry: Qt.rect(0.5, 0.5, 0.5, 0.5), padding: 6};
        const trailingRect = script.tileWindowRect(trailingTile, oddArea);
        check("odd quick tile stays inside work-area right", trailingRect.x + trailingRect.width === 1439, trailingRect);
        check("odd quick tile stays inside work-area bottom", trailingRect.y + trailingRect.height === 899, trailingRect);
        // Startup watcher must correct a window that was already snapped when the script loaded.
        rectCheck("already tiled startup", win.frameGeometry, Qt.rect(0, 34, 717, 866));
        check("native inner padding retained", quickRoot.padding === 6, quickRoot.padding);
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
        win.frameGeometry = Qt.rect(6, 40, 711, 854);
        script.fitQuickTile(win);
        rectCheck("interactive resize outer edges filled", win.frameGeometry, Qt.rect(0, 34, 717, 866));
        check("interactive resize shared edge unchanged", win.frameGeometry.x + win.frameGeometry.width === 717, win.frameGeometry);
        win.resize = false;
        if (outlineWindow) {
            // The outline's checks measure the same 6 px gap (its default is none, checked above).
            outlineWindow.applySettings("true\n6\n");
            outline.active = true;
            outlineWindow.place(a, false);
            const zone = outlineWindow.contentItem.children[0];
            rectCheck("outline keeps work-area edges", Qt.rect(zone.x + outline.unifiedGeometry.x,
                zone.y + outline.unifiedGeometry.y, zone.width, zone.height), a);
            outline.geometry = Qt.rect(6, 40, 711, 854);
            outline.unifiedGeometry = outline.geometry;
            outlineWindow.place(outline.geometry, false);
            rectCheck("native padded outline matches filled target", Qt.rect(zone.x + outlineWindow.x,
                zone.y + outlineWindow.y, zone.width, zone.height), Qt.rect(0, 34, 717, 866));
            // A newly created outline has no remembered root when every window is untiled.
            KW.Workspace.windows = [];
            outlineWindow.quickRoots = ({});
            rectCheck("first native padded preview fills outer edges",
                outlineWindow.previewRect(Qt.rect(6, 40, 711, 854)), Qt.rect(0, 34, 717, 866));
            rectCheck("first zero-padding preview keeps configured inner gap",
                outlineWindow.previewRect(Qt.rect(0, 34, 720, 866)), Qt.rect(0, 34, 717, 866));
            outlineWindow.applySettings("true\n12\n");
            rectCheck("first preview follows nondefault configured gap",
                outlineWindow.previewRect(Qt.rect(6, 40, 711, 854)), Qt.rect(0, 34, 714, 866));
            outlineWindow.applySettings("false\n12\n");
            rectCheck("first preview follows disabled quick gaps",
                outlineWindow.previewRect(Qt.rect(6, 40, 711, 854)), Qt.rect(0, 34, 720, 866));
            outlineWindow.applySettings("true\n6\n");
            rectCheck("unknown outline stays unchanged",
                outlineWindow.previewRect(Qt.rect(80, 90, 500, 300)), Qt.rect(80, 90, 500, 300));
            const secondDesktop = {id: "desktop-2"};
            const secondOutput = {name: "Virtual-2", geometry: Qt.rect(1440, 0, 1440, 900)};
            const secondTile = {tiles: [], absoluteGeometry: Qt.rect(1440, 34, 720, 866),
                relativeGeometry: Qt.rect(0, 0, 0.5, 1), padding: 6};
            KW.Workspace.outlineScreen = secondOutput;
            KW.Workspace.outputDesktops = {"Virtual-2": secondDesktop};
            KW.Workspace.maximizeArea = Qt.rect(1440, 34, 1440, 866);
            KW.Workspace.customRoots = {"Virtual-2|desktop-2": {tiles: [secondTile]}};
            outlineWindow.quickRoots = {"Virtual-2|desktop-1": {root: {tiles: [secondTile]}, output: "Virtual-2"}};
            rectCheck("outline preserves target output desktop custom tile",
                outlineWindow.previewRect(Qt.rect(1446, 40, 711, 854)), Qt.rect(1446, 40, 711, 854));
            KW.Workspace.customRoots = ({});
            KW.Workspace.desktopAreas = {"desktop-1": Qt.rect(1440, 70, 1440, 830),
                                        "desktop-2": Qt.rect(1440, 34, 1440, 866)};
            outlineWindow.quickRoots = {"Virtual-2|desktop-2": {root: {tiles: [secondTile]}, output: "Virtual-2"}};
            rectCheck("native outline uses target output desktop work area",
                outlineWindow.previewRect(Qt.rect(1446, 40, 711, 854)), Qt.rect(1440, 34, 717, 866));
            const staleTile = {absoluteGeometry: Qt.rect(1440, 34, 960, 866),
                relativeGeometry: Qt.rect(0, 0, 2 / 3, 1), padding: 6};
            outlineWindow.quickRoots = {"Virtual-2|desktop-1": {root: {tiles: [staleTile]}, output: "Virtual-2"}};
            rectCheck("another desktop cached split is not used",
                outlineWindow.previewRect(Qt.rect(1446, 40, 951, 854)), Qt.rect(1446, 40, 951, 854));
            KW.Workspace.outlineScreen = null;
            KW.Workspace.outputDesktops = ({});
            KW.Workspace.desktopAreas = ({});
            KW.Workspace.customRoots = ({});
            KW.Workspace.maximizeArea = a;
            KW.Workspace.windows = [win];
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
        Qt.callLater(testCycle);
    }
    // Snap Left/Right (the setup's Meta+Left/Right) from the left half, with the 6 px gap.
    function testCycle() {
        KW.Workspace.windows = [win, cycleWin];
        KW.Workspace.screens = [screenA];
        KW.Workspace.activeWindow = cycleWin;
        script.cycleSnap(cycleWin, "left");
        rectCheck("Snap Left on the left half: the left third", cycleWin.frameGeometry, Qt.rect(0, 34, 476, 866));
        script.cycleSnap(cycleWin, "left");
        rectCheck("  again: the left two thirds", cycleWin.frameGeometry, Qt.rect(0, 34, 957, 866));
        script.cycleSnap(cycleWin, "left");
        rectCheck("  again, one screen: the left half", cycleWin.frameGeometry, Qt.rect(0, 34, 717, 866));
        script.cycleSnap(cycleWin, "right");
        rectCheck("Snap Right from the left half: the right half", cycleWin.frameGeometry, Qt.rect(723, 34, 717, 866));
        script.cycleSnap(cycleWin, "right");
        rectCheck("  again: the right third", cycleWin.frameGeometry, Qt.rect(964, 34, 476, 866));
        script.cycleSnap(cycleWin, "right");
        rectCheck("  again: the right two thirds", cycleWin.frameGeometry, Qt.rect(483, 34, 957, 866));
        KW.Workspace.screens = [screenA, screenB];
        script.cycleSnap(cycleWin, "right");
        check("  again with a screen to the right: the window goes there", KW.Workspace.sentTo === screenB,
              KW.Workspace.sentTo ? KW.Workspace.sentTo.name : "nothing");
        cycleWin.frameGeometry = Qt.rect(300, 200, 600, 400);
        script.cycleSnap(cycleWin, "left");
        rectCheck("Snap Left on a window elsewhere: the left half", cycleWin.frameGeometry, Qt.rect(0, 34, 717, 866));
        // A client that has not drawn its new size yet: the third was asked, the window still shows
        // the half; the next press goes on to the two thirds, not to the third again.
        script.cycleSnap(cycleWin, "left");
        cycleWin.frameGeometry = Qt.rect(0, 34, 717, 866);
        script.cycleSnap(cycleWin, "left");
        rectCheck("  pressed again before the client drew the third: the two thirds", cycleWin.frameGeometry, Qt.rect(0, 34, 957, 866));
        // The largest gap on a small work area: the steps the script made are still known.
        KWin.setConfig("Gap", 48);
        KW.Workspace.maximizeArea = Qt.rect(0, 34, 1024, 700);
        cycleWin.frameGeometry = Qt.rect(300, 200, 400, 300);
        script.cyclePending = ({});
        script.cycleSnap(cycleWin, "left");
        script.cyclePending = ({});
        script.cycleSnap(cycleWin, "left");
        script.cyclePending = ({});
        script.cycleSnap(cycleWin, "left");
        rectCheck("a 48 px gap on a 1024 px area: half, third, then the two thirds", cycleWin.frameGeometry, Qt.rect(0, 34, 659, 700));
        KWin.setConfig("Gap", 6);
        KW.Workspace.maximizeArea = Qt.rect(0, 34, 1440, 866);
        Qt.callLater(testEnd);
    }
    function testEnd() {
        console.log("snap geometry: " + checks + " checks, " + failures + " failures");
        if (outlineWindow) outlineWindow.destroy();
        done = true;
    }
}
