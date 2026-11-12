/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Offscreen harness for plasmafusion-placement's dynamic tiler (test use only): it loads the
    real main.qml with the stand-in org.kde.kwin module and a mock of the fork's
    TransientTilingApi facade, then drives the tiler through its native lifecycle - the
    shortcut toggle (createTile + admitTile before any stack geometry write), the stack column
    the script writes, a live window addition mid-session, the untoggle (floats back, the
    master's native restore, releaseTile), the native treeChanged teardown, and a refused tree.
    The python driver (tiling_lifecycle_test.py) reads `problems`, `facadeCalls` and the counts.
    Context properties from the driver: packagesRoot (a directory holding
    scripts/plasmafusion-placement), config prefill through the KWin context object.
*/

import QtQuick
import org.kde.kwin as KWinStubs

Item {
    id: harness

    property bool done: false
    property var problems: []
    property var facadeCalls: []
    property var script: null
    property var tileShortcut: null
    property var stackWindows: []

    // The workspace view the stub provides: activeScreen Virtual-1 at (0,0 1440x900), the
    // stub's maximizeArea (0,34 1440x866) is the tiler's area; the facade's master rect puts
    // the divider at x=700, so the stack column is x=700..1440 (740 wide).
    readonly property rect column: Qt.rect(700, 34, 740, 866)

    function fail(message) {
        problems = problems.concat([message]);
    }
    function calls(op) {
        const out = [];
        for (let i = 0; i < facadeCalls.length; ++i) {
            if (facadeCalls[i].op === op) {
                out.push(facadeCalls[i]);
            }
        }
        return out;
    }
    function rectIs(r, x, y, width, height) {
        return r.x === x && r.y === y && r.width === width && r.height === height;
    }

    // The mock facade: every method the script can call, each one recorded in facadeCalls.
    // createTile also snapshots the stack windows' geometry at call time - invariant 8 (the
    // native admission before any stack write) is checkable from that snapshot.
    QtObject {
        id: facade
        property bool refuseCreate: false
        property bool treeAlive: false
        property int nextGeneration: 0
        property rect masterRect: Qt.rect(0, 34, 700, 866)
        signal treeChanged()
        function registerProvider(item) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "registerProvider" }]);
            return "harness-token";
        }
        function trackWindow(w, key) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "trackWindow", window: String(w.internalId), key: key }]);
            return true;
        }
        function windowBinding(w) { return ""; }
        function record(token, revision, w, rect, seq, origin) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "record", window: String(w.internalId), origin: origin }]);
            return 0; // Accepted
        }
        function snapshot() { return { entries: {} }; }
        function hasTree() { return treeAlive; }
        function masterWindowRect() { return masterRect; }
        function createTile(output, desktop, rect) {
            const stackAtCreate = [];
            for (let i = 0; i < harness.stackWindows.length; ++i) {
                const g = harness.stackWindows[i].frameGeometry;
                stackAtCreate.push({ window: String(harness.stackWindows[i].internalId),
                                     x: g.x, y: g.y, width: g.width, height: g.height });
            }
            if (refuseCreate) {
                harness.facadeCalls = harness.facadeCalls.concat([{ op: "createTile", refused: true }]);
                return { result: 1, generation: 0 };
            }
            nextGeneration += 1;
            treeAlive = true;
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "createTile", generation: nextGeneration,
                                                                x: rect.x, y: rect.y, width: rect.width, height: rect.height,
                                                                stackAtCreate: stackAtCreate }]);
            return { result: 0, generation: nextGeneration };
        }
        function admitTile(generation, w, key, token) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "admitTile", generation: generation,
                                                                window: String(w.internalId), key: key, token: token }]);
            return 0; // Accepted
        }
        function releaseTile(generation) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "releaseTile", generation: generation }]);
            treeAlive = false;
        }
    }

    // A stand-in KWin Window: every property the placement script and the tiler read, with the
    // auto property-change signals the script connects to, KWin's two non-property maximize
    // signals, and the fork's requestedGeometryChanged.
    Component {
        id: fakeWindow
        QtObject {
            property string internalId
            property rect frameGeometry
            property bool deleted: false
            property bool normalWindow: true
            // "transient" is a reserved QML identifier and cannot be declared: the script
            // reads !w.transient, and an undeclared property reads as undefined (falsely
            // transient never - every harness window is a normal window).
            property bool modal: false
            property bool moveable: true
            property bool resizeable: true
            property bool minimized: false
            property bool fullScreen: false
            property var tile: null
            property int maximizeMode: 0
            property bool onAllDesktops: false
            property var desktops: []
            property var activities: []
            property var output: null
            property string resourceClass: ""
            property string desktopFileName: ""
            property string caption: ""
            property var minSize: ({ width: 1, height: 1 })
            signal maximizedAboutToChange(int mode)
            signal maximizedChanged()
            signal requestedGeometryChanged()
        }
    }

    Component.onCompleted: {
        try {
            run();
        } catch (e) {
            fail("harness threw: " + e);
        }
        done = true;
    }

    function run() {
        const ws = KWinStubs.Workspace;
        // The view: desktop {id: 11}, activity "a", the stub's single screen.
        const desktop = { id: 11 };
        ws.desktops = [desktop];
        ws.currentDesktop = desktop;
        ws.currentActivity = "a";
        ws.transientTilingImpl = function () { return facade; };

        // The windows, floats first (stacking order bottom first, like KWin): the master plus
        // two stack members-to-be.
        const mk = (over) => fakeWindow.createObject(harness, over);
        const master = mk({ internalId: "master", resourceClass: "org.fusion.terminal",
                            desktopFileName: "org.fusion.terminal.desktop",
                            frameGeometry: Qt.rect(40, 80, 620, 420) });
        const winA = mk({ internalId: "a", resourceClass: "org.fusion.editor",
                          desktopFileName: "org.fusion.editor.desktop",
                          frameGeometry: Qt.rect(700, 120, 300, 320) });
        const winB = mk({ internalId: "b", resourceClass: "org.fusion.files",
                          desktopFileName: "org.fusion.files.desktop",
                          frameGeometry: Qt.rect(760, 480, 300, 300) });
        const windows = [master, winA, winB];
        for (let i = 0; i < windows.length; ++i) {
            windows[i].desktops = [desktop];
            windows[i].output = ws.activeScreen;
        }
        stackWindows = [winA, winB];
        ws.windows = [winB, winA, master];
        ws.activeWindow = master;

        // The real script (staged or checkout): its onCompleted adopts the open windows.
        const base = "file://" + packagesRoot + "/scripts/plasmafusion-placement/contents/ui/";
        const component = Qt.createComponent(base + "main.qml");
        if (component.status !== Component.Ready) {
            fail("main.qml did not load: " + component.errorString());
            return;
        }
        script = component.createObject(harness);
        const adopted = calls("trackWindow");
        if (adopted.length !== 3) {
            fail("the script adopted and tracked the three open windows (got " + adopted.length + ")");
            return;
        }
        const masterKey = adopted.find(c => c.window === "master").key;

        for (let i = 0; i < script.data.length; ++i) {
            const child = script.data[i];
            if (child && child.name === "Plasma Fusion: Tile Workspace") {
                tileShortcut = child;
            }
        }
        if (!tileShortcut) {
            fail("the Tile Workspace shortcut was not registered");
            return;
        }

        // ---- toggle on: the native admission, then the column ----
        tileShortcut.activated();
        const created = calls("createTile");
        if (created.length !== 1) {
            fail("one createTile for the toggle (got " + created.length + ")");
            return;
        }
        if (created[0].refused) {
            fail("createTile was refused although the mock accepts");
            return;
        }
        const admitted = calls("admitTile");
        if (admitted.length !== 1) {
            fail("one admitTile for the toggle (got " + admitted.length + ")");
            return;
        }
        if (admitted[0].window !== "master" || admitted[0].key !== masterKey) {
            fail("the master was admitted under its app key (got " + admitted[0].window + "/" + admitted[0].key + ")");
        }
        if (admitted[0].token !== "harness-token") {
            fail("admitTile carried the provider token (got " + admitted[0].token + ")");
        }
        if (admitted[0].generation !== created[0].generation) {
            fail("admitTile carried the created generation");
        }
        // invariant 8: at createTile time the stack windows were still at their floats
        if (created[0].stackAtCreate.length !== 2) {
            fail("the create snapshot saw both stack windows");
        } else {
            const a = created[0].stackAtCreate.find(w => w.window === "a");
            const b = created[0].stackAtCreate.find(w => w.window === "b");
            if (!a || !rectIs(a, 700, 120, 300, 320) || !b || !rectIs(b, 760, 480, 300, 300)) {
                fail("the stack was still at its floats when the tree was created");
            }
        }
        // the configured fraction reached the native tile (MasterFraction 0.4 from the driver)
        if (created[0].width !== 0.4 || created[0].x !== 0 || created[0].y !== 0 || created[0].height !== 1) {
            fail("the tile rect is the configured fraction of the output (got " + created[0].x + "," + created[0].y
                 + " " + created[0].width + "x" + created[0].height + ")");
        }
        // the column the script wrote: divider 700 (the facade's master rect), the stub's
        // maximize area (0,34 1440x866), gap 8 - the column starts ceil(8/2)=4 right of the
        // divider and runs to the area's right edge (740-4=736 wide), two cells of
        // (866 - 8) / 2 = 429 each, the first at the area's top, the second 4 below the
        // first's end (stackRects' endpoint-gap discipline)
        if (!rectIs(winA.frameGeometry, 704, 34, 736, 429)) {
            fail("the top stack window took the first cell (got " + JSON.stringify(winA.frameGeometry) + ")");
        }
        if (!rectIs(winB.frameGeometry, 704, 471, 736, 429)) {
            fail("the second stack window took the second cell (got " + JSON.stringify(winB.frameGeometry) + ")");
        }
        if (calls("releaseTile").length !== 0) {
            fail("releaseTile before any untoggle");
        }

        // ---- a live window joins mid-session ----
        const winC = mk({ internalId: "c", resourceClass: "org.fusion.mail",
                          desktopFileName: "org.fusion.mail.desktop",
                          frameGeometry: Qt.rect(300, 500, 260, 260) });
        winC.desktops = [desktop];
        winC.output = ws.activeScreen;
        stackWindows = [winA, winB, winC];
        ws.windows = [winC, winB, winA, master];
        ws.windowAdded(winC);
        if (calls("createTile").length !== 1) {
            fail("a live addition reuses the session's tree");
        }
        if (winC.frameGeometry.x < column.x || winC.frameGeometry.x + winC.frameGeometry.width > column.x + column.width) {
            fail("the joined window was placed in the column (got " + JSON.stringify(winC.frameGeometry) + ")");
        }
        // the three cells cover the column without overlap (stackRects' endpoint discipline)
        const cells = [winA.frameGeometry, winB.frameGeometry, winC.frameGeometry].sort((p, q) => p.y - q.y);
        if (cells[0].y !== column.y || cells[2].y + cells[2].height !== column.y + column.height || cells[0].y + cells[0].height > cells[1].y || cells[1].y + cells[1].height > cells[2].y) {
            fail("the relaid column covers the area without overlap: " + JSON.stringify(cells));
        }

        // ---- untoggle: the floats back, the master's native restore, the tree released ----
        tileShortcut.activated();
        if (!rectIs(winA.frameGeometry, 700, 120, 300, 320) || !rectIs(winB.frameGeometry, 760, 480, 300, 300)
                || !rectIs(winC.frameGeometry, 300, 500, 260, 260)) {
            fail("the untoggle restored the saved floats (got " + JSON.stringify(winA.frameGeometry) + " "
                 + JSON.stringify(winB.frameGeometry) + " " + JSON.stringify(winC.frameGeometry) + ")");
        }
        if (ws.activeWindow !== master) {
            fail("the master was activated for the native restore");
        }
        if (ws.slotWindowRestoreCalls !== 1) {
            fail("the master's native restore ran once (got " + ws.slotWindowRestoreCalls + ")");
        }
        const released = calls("releaseTile");
        if (released.length !== 1 || released[0].generation !== admitted[0].generation) {
            fail("the untoggle released the session's tree (got " + JSON.stringify(released) + ")");
        }

        // ---- the native teardown: treeChanged with no live tree ends the session ----
        tileShortcut.activated();
        if (calls("createTile").length !== 2) {
            fail("the second toggle started a second session");
        }
        facade.treeAlive = false;
        facade.treeChanged();
        if (!rectIs(winA.frameGeometry, 700, 120, 300, 320) || !rectIs(winB.frameGeometry, 760, 480, 300, 300)) {
            fail("the native teardown restored the stack floats");
        }
        if (calls("releaseTile").length !== 1) {
            fail("the native teardown does not release an already-ended tree");
        }
        // the session is gone: the next toggle starts a session instead of un-toggling
        tileShortcut.activated();
        if (calls("createTile").length !== 3) {
            fail("a toggle after the native teardown lays out again (the session had ended)");
        }
        tileShortcut.activated(); // untoggle the third session (cleanup)
        if (calls("releaseTile").length !== 2) {
            fail("the third session released its tree");
        }

        // ---- a refused tree: no session, no geometry write ----
        facade.refuseCreate = true;
        const before = winA.frameGeometry;
        tileShortcut.activated();
        if (calls("admitTile").length !== 3) {
            fail("a refused tree admits nothing");
        }
        if (!rectIs(winA.frameGeometry, before.x, before.y, before.width, before.height)) {
            fail("a refused tree writes no geometry");
        }
    }
}
