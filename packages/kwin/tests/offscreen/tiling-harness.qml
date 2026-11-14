/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Offscreen harness for plasmafusion-placement's dynamic tiler (test use only): it loads the
    real main.qml with the stand-in org.kde.kwin module and a mock of the fork's
    TransientTilingApi facade, then drives the tiler through its native lifecycle - the
    shortcut toggle (createTile + admitTile before any stack geometry write), the stack column
    the script writes, a live window addition mid-session, the untoggle (floats back, the
    master's native restore, releaseTile), the native treeChanged teardown, a refused tree,
    a shortcut invoked on another desktop while a session lives (the untoggle's activation
    carries the current view back; the captured invocation must win), and - past the
    untoggles' quiet second - a manual move of an IgnoreApps stack member (it must leave the
    session) and the settle pass recording the joined windows' floats. The python driver
    (tiling_lifecycle_test.py) reads `problems`, `facadeCalls` and `snapshot`.
    A second scenario (scenario: "released") drives the master a native teardown released
    without restoring it - returned to its float, left where the user moved it, held while
    maximized, settled at the next toggle - and the admission's retries.
    Context properties from the driver: packagesRoot (a directory holding
    scripts/plasmafusion-placement), config prefill through the KWin context object.
*/

import QtQuick
import org.kde.kwin as KWinStubs

Item {
    id: harness

    property bool done: false
    // Set by the driver for a second run: the fork's facade as an older build has it, without
    // restoreWindow.
    property bool legacyFacade: false
    // The facade of a fork build that restores but cannot say what it keeps of a window (no
    // floatingFrame, no settleWindow).
    property bool interimFacade: false
    // Set by the driver for another run: "released" (runReleased).
    property string scenario: ""
    property var steps: []
    property int stepIndex: 0
    property var problems: []
    property var facadeCalls: []
    property var snapshot: ({})
    property var script: null
    property var tileShortcut: null
    property var stackWindows: []
    property var master: null
    property var winA: null
    property var winB: null
    property var winD: null
    property var firstDesktop: null

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

    function mk(over) {
        return fakeWindow.createObject(harness, over);
    }

    // The mock facade: every method the script can call, each one recorded in facadeCalls, and
    // no method the fork's facade does not have (kwin src/scripting/transienttilingapi.h) - a
    // call the mock answers and the compositor cannot is a failure only hardware would show.
    // createTile also snapshots the stack windows' geometry at call time - invariant 8 (the
    // native admission before any stack write) is checkable from that snapshot.
    QtObject {
        id: facade
        property bool refuseCreate: false
        property bool refuseAdmit: false
        // The native admission can land the window on the tile before it returns (a client
        // whose size already fits needs no configure): the mock then moves the window inside
        // admitTile.
        property bool landOnAdmit: false
        property bool treeAlive: false
        property int nextGeneration: 0
        property rect masterRect: Qt.rect(0, 34, 700, 866)
        // The native restore raises and focuses the restored window, which carries the active
        // window and screen to its view; onRestore lets a scenario add to that.
        property var onRestore: null
        // window internalId -> {target, floating, placedByUser}: the records of masters the
        // native layer released without restoring them (detach). A window with one cannot be
        // admitted (busy).
        property var heldRecords: ({})
        // window internalId -> the frame a window had when it was admitted: its record's
        // floating frame, until the record ends.
        property var floatings: ({})
        // window internalId -> the frame the admission landed the window on.
        property var landings: ({})
        // Where an admission lands the window when that is not the tile's rectangle: the fit
        // of a window in a tile that is off the output's pixels.
        property rect fitRect: Qt.rect(0, 0, 0, 0)
        // How many more settle questions find the window's geometry unsettled: the client
        // has that many configures left to answer.
        property int unsettledAnswers: 0
        // The next admissions' answers, in order (none left: accepted).
        property var admitAnswers: []
        // The window on the tile and the key it was admitted under. KWin's Window.tile is the
        // transient leaf for as long as the window is owned, through full screen and back.
        property var owned: null
        property string ownedKey: ""
        readonly property var leaf: ({ transient: true })
        // A tree that is gone holds no window, however the test ended it.
        onTreeAliveChanged: {
            if (!treeAlive) {
                vacate();
            }
        }
        signal treeChanged()
        function plain(r) {
            return { x: r.x, y: r.y, width: r.width, height: r.height };
        }
        // The mock's own state first, the window's tile after it: whoever the change reaches
        // finds the tile already vacated.
        function vacate() {
            const window = owned;
            owned = null;
            ownedKey = "";
            if (window) {
                window.tile = null;
            }
        }
        // internalId -> key: the windows the writer tracks. It tracks a window once.
        property var tracked: ({})
        // The output the tree was made for: the controller admits no window of another one.
        property var tileOutput: null
        // key -> the rectangle the writer has for the app. The writer grants an admission
        // only to a window whose floating frame is that rectangle (its reserve: the entry
        // must be the memory's image of the frame). The mock holds an admission to that when
        // entryRule is on: most steps here follow one another within the memory's quiet
        // second, in which nothing is recorded, and say nothing about the rule.
        property var entries: ({})
        property bool entryRule: false
        function image(r) {
            return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
        }
        // The facade's methods take a KWin::Window*: a reference to a destroyed window does
        // not convert, and the call throws (every property of such a reference is undefined).
        function window(w) {
            if (!w || w.internalId === undefined) {
                throw new TypeError("Passing incompatible arguments to C++ functions from JavaScript is not allowed.");
            }
            return w;
        }
        function same(a, b) {
            return a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;
        }
        // The native layer's detach-only release (a removed desktop or output, a second
        // window of the app, a move of the master, a re-check of the work area): the window
        // stays where it stands, its record is held, the tree ends.
        function detach(w) {
            const id = String(w.internalId);
            const held = heldRecords;
            held[id] = { target: landings[id] || plain(masterRect), floating: floatings[id], placedByUser: false };
            heldRecords = held;
            vacate();
            treeAlive = false;
            treeChanged();
        }
        // The user's own move or resize of a released window ended: the native record takes
        // its mark, and the window says so.
        function userDragEnded(w) {
            const held = heldRecords[String(w.internalId)];
            if (held) {
                held.placedByUser = true;
            }
            w.move = false;
            w.resize = false;
            w.interactiveMoveResizeFinished();
        }
        // As Window::settleReleasedTransientOwnership answers: 1 nothing to settle, 2 another
        // provider's, 3 not settled (a pending configure, a drag, or maximized, full screen or
        // tiled), 4 neither on its floating frame nor placed by the user, 0 settled.
        function settleWindow(w, token) {
            const id = String(window(w).internalId);
            const held = heldRecords[id];
            let result = 0;
            if (!held) {
                result = 1;
            } else if (token !== "harness-token") {
                result = 2;
            } else if (unsettledAnswers > 0) {
                unsettledAnswers -= 1;
                result = 3;
            } else if (w.fullScreen || w.maximizeMode !== 0 || w.tile || w.move || w.resize) {
                result = 3;
            } else if (!same(w.frameGeometry, held.floating) && !(held.placedByUser && !same(w.frameGeometry, held.target))) {
                result = 4;
            } else {
                const records = heldRecords;
                delete records[id];
                heldRecords = records;
                delete floatings[id];
            }
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "settleWindow", window: id, result: result }]);
            return result;
        }
        // The record's floating frame, owned or released; null without a record.
        function floatingFrame(w) {
            const f = floatings[String(window(w).internalId)];
            return f ? Qt.rect(f.x, f.y, f.width, f.height) : Qt.rect(0, 0, 0, 0);
        }
        function registerProvider(item) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "registerProvider" }]);
            return "harness-token";
        }
        function trackWindow(w, key) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "trackWindow", window: String(w.internalId), key: key }]);
            if (tracked[String(w.internalId)] !== undefined) {
                return false;
            }
            tracked[String(w.internalId)] = key;
            // A second live window under the key of the window on the tile: the writer reports
            // the conflict, the controller releases the owner at once (detach-only, its record
            // held) and the facade ends the vacated tree in a queued call - the tree's end
            // arrives after the script has finished with the window that just opened.
            if (owned && owned !== w && key === ownedKey && treeAlive) {
                const id = String(owned.internalId);
                const held = heldRecords;
                held[id] = { target: landings[id] || plain(masterRect), floating: floatings[id], placedByUser: false };
                heldRecords = held;
                vacate();
                queuedEnd.start();
            }
            return true;
        }
        function windowBinding(w) {
            const key = tracked[String(w.internalId)];
            return key === undefined ? "" : key;
        }
        function record(token, revision, w, rect, seq, origin) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "record", window: String(w.internalId), origin: origin,
                                                                x: rect.x, y: rect.y, width: rect.width, height: rect.height }]);
            const key = tracked[String(w.internalId)];
            if (key !== undefined) {
                entries[key] = plain(rect);
            }
            return 0; // Accepted
        }
        function snapshot() { return { entries: entries }; }
        function hasTree() { return treeAlive; }
        function masterWindowRect() { return masterRect; }
        // A record the native layer keeps of a window, which the script under test knows
        // nothing of: a release left the window where it stands before the script was loaded.
        function keepRecord(w, floating) {
            const id = String(w.internalId);
            floatings[id] = plain(floating);
            const held = heldRecords;
            held[id] = { target: plain(w.frameGeometry), floating: floatings[id], placedByUser: false };
            heldRecords = held;
        }
        function dropRecord(w) {
            const id = String(w.internalId);
            delete floatings[id];
            const held = heldRecords;
            delete held[id];
            heldRecords = held;
        }
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
            tileOutput = output && output.name !== undefined ? output : null;
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "createTile", generation: nextGeneration,
                                                                output: output && output.name !== undefined ? String(output.name) : "",
                                                                desktop: desktop && desktop.id !== undefined ? desktop.id : String(desktop),
                                                                x: rect.x, y: rect.y, width: rect.width, height: rect.height,
                                                                stackAtCreate: stackAtCreate }]);
            return { result: 0, generation: nextGeneration };
        }
        function admitTile(generation, w, key, token) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "admitTile", generation: generation,
                                                                window: String(window(w).internalId), key: key, token: token }]);
            if (heldRecords[String(w.internalId)]) {
                return 3; // Busy: the window still has its released record
            }
            if (admitAnswers.length > 0) {
                const answer = admitAnswers[0];
                admitAnswers = admitAnswers.slice(1);
                if (answer !== 0) {
                    return answer;
                }
            }
            if (refuseAdmit) {
                return 7; // Ineligible
            }
            if (tileOutput && w.output && w.output !== tileOutput) {
                return 7; // Ineligible: the window is on another output than the tree
            }
            for (const id in tracked) {
                if (id !== String(w.internalId) && tracked[id] === key) {
                    return 8; // Refused: another live window shares the key
                }
            }
            if (entryRule && (!entries[key] || !same(entries[key], image(w.frameGeometry)))) {
                return 8; // Refused: the app's remembered place is not this window's frame
            }
            floatings[String(w.internalId)] = plain(w.frameGeometry);
            owned = w;
            ownedKey = key;
            w.tile = leaf;
            if (landOnAdmit) {
                w.frameGeometry = fitRect.width > 0 ? fitRect : masterRect;
                landings[String(w.internalId)] = plain(w.frameGeometry);
            }
            return 0; // Accepted
        }
        function releaseTile(generation) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "releaseTile", generation: generation }]);
            // As the controller's clearTree does: the tree's end is reported before the call
            // returns, to the script that asked for it like to anyone else.
            vacate();
            treeAlive = false;
            treeChanged();
        }
        function restoreWindow(w) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "restoreWindow", window: String(w.internalId) }]);
            // The explicit restore returns the window to its floating frame and completes the
            // record. (The mock used to leave the window on the tile; the script's guard
            // against recording that rectangle then hid what a real restore does.)
            const back = floatings[String(w.internalId)];
            delete floatings[String(w.internalId)];
            if (owned === w) {
                vacate();
            }
            if (back) {
                w.frameGeometry = Qt.rect(back.x, back.y, back.width, back.height);
            }
            KWinStubs.Workspace.activeWindow = w;
            if (onRestore) {
                onRestore();
            }
        }
    }

    // The writer forgets a window when it is destroyed: after its close and whatever the
    // close recorded.
    property var closedWindows: []
    Connections {
        target: KWinStubs.Workspace
        function onWindowRemoved(w) {
            harness.closedWindows = harness.closedWindows.concat([String(w.internalId)]);
            forgetClosed.start();
        }
    }
    Timer {
        id: forgetClosed
        interval: 0
        onTriggered: {
            const tracked = facade.tracked;
            for (let i = 0; i < harness.closedWindows.length; ++i) {
                delete tracked[harness.closedWindows[i]];
            }
            facade.tracked = tracked;
            harness.closedWindows = [];
        }
    }

    // The facade's queued end of a tree its window has left (TransientTilingApi::endVacatedTree).
    Timer {
        id: queuedEnd
        interval: 0
        onTriggered: {
            if (facade.treeAlive && !facade.owned) {
                facade.treeAlive = false;
                facade.treeChanged();
            }
        }
    }

    // The facade of a fork build from before restoreWindow, or of one that has it (more):
    // every other answer is the mock's.
    function facadeWithoutRestore(more) {
        const older = { treeChanged: facade.treeChanged };
        const names = ["registerProvider", "trackWindow", "windowBinding", "record", "snapshot", "hasTree",
                       "masterWindowRect", "createTile", "admitTile", "releaseTile"].concat(more || []);
        for (let i = 0; i < names.length; ++i) {
            older[names[i]] = facade[names[i]];
        }
        return older;
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
            // The user's interactive move or resize in progress, and its end.
            property bool move: false
            property bool resize: false
            signal interactiveMoveResizeFinished()
            // KWin's request for the window (the fork's Window.requestedGeometry, with its
            // requestedGeometryChanged); null: the script reads no request and takes every
            // frame as settled.
            property var requestedGeometry: null
            signal maximizedAboutToChange(int mode)
            signal maximizedChanged()
        }
    }

    Component.onCompleted: {
        if (scenario === "released") {
            try {
                runReleased();
            } catch (e) {
                fail("harness threw: " + e);
                done = true;
            }
            return;
        }
        try {
            run();
        } catch (e) {
            fail("harness threw: " + e);
            done = true;
        }
        if (!done) {
            // The ignored-member phase needs the untoggles' quiet second to have passed: a
            // manual move inside it is indistinguishable from a float restore's late commit
            // (the script quieted the window for exactly that reason), so the hand that
            // must detach arrives after it.
            latePhase.start();
        }
    }

    Timer {
        id: latePhase
        interval: 1200
        onTriggered: {
            try {
                runLate();
            } catch (e) {
                fail("late harness threw: " + e);
            }
            done = true;
        }
    }

    // The scenario's steps: each runs once its own condition holds (the script's retry
    // timers fire in between), or fails after five seconds without it. A step waits for what
    // it checks, not for a fixed time, so a loaded machine only makes the run longer. (One
    // step is bound to the memory's quiet second, which the script does not let a test
    // shorten: it says so when it ran too late to check anything.)
    Timer {
        id: stepper
        interval: 20
        repeat: true
        onTriggered: harness.nextStep()
    }
    property double stepSince: 0

    function nextStep() {
        if (stepIndex >= steps.length) {
            stepper.stop();
            snapshot = ({ createTile: calls("createTile").length, admitTile: calls("admitTile").length,
                          settleWindow: calls("settleWindow").length });
            done = true;
            return;
        }
        const step = steps[stepIndex];
        try {
            if (step.until && !step.until()) {
                if (Date.now() - stepSince < 5000) {
                    return;
                }
                fail("released: step " + stepIndex + " waited five seconds for: " + step.name);
            }
            step.run();
        } catch (e) {
            fail("step " + stepIndex + " threw: " + e);
            stepper.stop();
            done = true;
            return;
        }
        stepIndex += 1;
        stepSince = Date.now();
    }

    // The view, the three windows and the real script; the master's app key, or "" on failure.
    function setup() {
        const ws = KWinStubs.Workspace;
        // The view: desktop {id: 11}, activity "a", the stub's single screen.
        const desktop = { id: 11 };
        firstDesktop = desktop;
        ws.desktops = [desktop];
        ws.currentDesktop = desktop;
        ws.currentActivity = "a";
        // A 133% output, as the ThinkPad's: the frames KWin lands are not the whole-pixel cells.
        ws.activeScreen = { name: "Virtual-1", geometry: Qt.rect(0, 0, 1440, 900), devicePixelRatio: 4 / 3 };
        const older = legacyFacade ? facadeWithoutRestore() : interimFacade ? facadeWithoutRestore(["restoreWindow"]) : null;
        ws.transientTilingImpl = function () { return older || facade; };

        // The windows, floats first (stacking order bottom first, like KWin): the master plus
        // two stack members-to-be.
        master = mk({ internalId: "master", resourceClass: "org.fusion.terminal",
                      desktopFileName: "org.fusion.terminal.desktop",
                      frameGeometry: Qt.rect(40, 80, 620, 420) });
        winA = mk({ internalId: "a", resourceClass: "org.fusion.editor",
                    desktopFileName: "org.fusion.editor.desktop",
                    frameGeometry: Qt.rect(700, 120, 300, 320) });
        winB = mk({ internalId: "b", resourceClass: "org.fusion.files",
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
            return "";
        }
        script = component.createObject(harness);
        const adopted = calls("trackWindow");
        if (adopted.length !== 3) {
            fail("the script adopted and tracked the three open windows (got " + adopted.length + ")");
            return "";
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
            return "";
        }
        return masterKey;
    }

    function run() {
        const ws = KWinStubs.Workspace;
        const masterKey = setup();
        if (masterKey === "") {
            return;
        }
        const desktop = firstDesktop;

        if (legacyFacade) {
            // ---- a facade without restoreWindow: no session, the memory's transport intact ----
            // The untoggle is that restore: a session the tiler could start it could not end.
            tileShortcut.activated();
            if (calls("createTile").length !== 0) {
                fail("a facade without restoreWindow starts no session");
            }
            if (calls("registerProvider").length !== 1) {
                fail("the placement memory still registered as the provider");
            }
            snapshot = ({ createTile: calls("createTile").length, registerProvider: calls("registerProvider").length,
                          trackWindow: calls("trackWindow").length });
            done = true;
            return;
        }

        if (interimFacade) {
            // ---- a fork build that cannot say what it keeps of a window: no record for the toggle ----
            // Whether a release left the window where it stands cannot be asked there, so the
            // toggle records nothing of it: the admission is asked from the memory as it is,
            // and refused where the app's place is another rectangle.
            facade.entryRule = true;
            facade.entries[masterKey] = { x: 900, y: 500, width: 300, height: 300 };
            tileShortcut.activated();
            const masterRecorded = calls("record").filter(c => c.window === "master");
            if (master.tile || masterRecorded.length !== 0 || calls("admitTile").length !== 1) {
                fail("a fork build that cannot say what it keeps of a window gets no record for the toggle (records "
                     + masterRecorded.length + ", admissions " + calls("admitTile").length + ")");
            }
            // And a session all the same where the memory has the window's own place.
            facade.entries[masterKey] = { x: 40, y: 80, width: 620, height: 420 };
            tileShortcut.activated();
            if (!master.tile || calls("record").filter(c => c.window === "master").length !== 0) {
                fail("the window is admitted from its own place there, with nothing recorded");
            }
            tileShortcut.activated();
            snapshot = ({ createTile: calls("createTile").length, admitTile: calls("admitTile").length,
                          restoreWindow: calls("restoreWindow").length });
            done = true;
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
        const restored = calls("restoreWindow");
        if (restored.length !== 1 || restored[0].window !== String(master.internalId)) {
            fail("the master's native restore ran once, for the master (got " + JSON.stringify(restored) + ")");
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
        facade.refuseCreate = false;

        // ---- a refused admission: the tree released, no session, no geometry write ----
        // What the ThinkPad answered every KDE window (7): the tree the toggle created must not
        // stay behind, and the tree's end that the release reports finds no session to end.
        facade.refuseAdmit = true;
        const releasedBefore = calls("releaseTile").length;
        tileShortcut.activated();
        if (calls("admitTile").length !== 4) {
            fail("the refused admission was asked once (got " + calls("admitTile").length + ")");
        }
        if (calls("releaseTile").length !== releasedBefore + 1 || facade.treeAlive) {
            fail("a refused admission releases the tree it created");
        }
        if (!rectIs(winA.frameGeometry, before.x, before.y, before.width, before.height)) {
            fail("a refused admission writes no geometry");
        }
        facade.refuseAdmit = false;

        // ---- the admission lands the master before it returns: nothing is recorded ----
        // The session is not active inside admitTile, and the master's frame is the tile by
        // then. A record there would put the tile into the memory (invariant 7) and move the
        // provider's revision under the admission.
        facade.landOnAdmit = true;
        const recordsBeforeLanding = calls("record").length;
        tileShortcut.activated();
        if (calls("record").length !== recordsBeforeLanding) {
            fail("the window being admitted is not recorded (got " + JSON.stringify(calls("record").slice(recordsBeforeLanding)) + ")");
        }
        if (!rectIs(master.frameGeometry, facade.masterRect.x, facade.masterRect.y, facade.masterRect.width, facade.masterRect.height)) {
            fail("the mock landed the master on the tile inside admitTile");
        }
        facade.landOnAdmit = false;
        tileShortcut.activated(); // untoggle it

        // ---- the invoked view survives the untoggle of another view's session ----
        // A session on the first desktop, then a second desktop with its own window; the
        // shortcut is invoked there. The untoggle activates the old master, and KWin's
        // activation can carry the current desktop back with it (the stub emulates that in
        // the restore hook) - the new session must still tile the invoked desktop, not the
        // one the teardown last looked at.
        const desktop2 = { id: 12 };
        const m2 = mk({ internalId: "m2", resourceClass: "org.fusion.help",
                        desktopFileName: "org.fusion.help.desktop",
                        frameGeometry: Qt.rect(60, 90, 500, 400) });
        m2.desktops = [desktop2];
        m2.output = ws.activeScreen;
        ws.desktops = [desktop, desktop2];
        ws.windows = [m2, winB, winA, master];
        ws.currentDesktop = desktop;
        ws.activeWindow = master;
        tileShortcut.activated(); // the session on the first desktop
        const desktop1Session = calls("createTile").length;
        ws.currentDesktop = desktop2;
        ws.activeWindow = m2;
        facade.onRestore = function () {
            ws.currentDesktop = desktop;
            ws.activeWindow = master;
        };
        tileShortcut.activated();
        const creates = calls("createTile");
        const lastCreate = creates[creates.length - 1];
        const admits = calls("admitTile");
        const lastAdmit = admits[admits.length - 1];
        if (creates.length !== desktop1Session + 1) {
            fail("the invocation on the other desktop started a new session");
        }
        if (lastCreate.desktop !== 12) {
            fail("the new session tiled the invoked desktop (got " + lastCreate.desktop + ")");
        }
        if (!lastAdmit || lastAdmit.window !== "m2") {
            fail("the invoked desktop's window became the master (got " + (lastAdmit ? lastAdmit.window : "none") + ")");
        }
        // the old master's restore took the focus; it is back on the window the user was in
        if (ws.activeWindow !== m2) {
            fail("the focus returned to the window the shortcut was invoked on");
        }
        facade.onRestore = null;
        ws.currentDesktop = desktop2;
        tileShortcut.activated(); // untoggle it (still the invoked view)

        // ---- a manual move of an ignored app's stack window detaches it (late phase) ----
        // org.fusion.files is in IgnoreApps: the memory never records it, but the tiler's
        // membership decision comes first - its move by hand must still leave the session,
        // or a later relayout would put it back in its cell over the user's move. The move
        // runs in the late phase, past the untoggles' quiet second (runLate).
        ws.currentDesktop = desktop;
        ws.activeWindow = master;
        tileShortcut.activated();
        winD = mk({ internalId: "d", resourceClass: "org.fusion.web",
                    desktopFileName: "org.fusion.web.desktop",
                    frameGeometry: Qt.rect(200, 300, 240, 200) });
        winD.desktops = [desktop];
        winD.output = ws.activeScreen;
    }


    // ---- the released master (scenario "released") ----
    // What the ThinkPad showed after a desktop removal: the stack restored, the master left
    // at the tile's size and refused (busy) by every later toggle until it closed.
    function settles(from) {
        return calls("settleWindow").slice(from).map(c => c.result);
    }
    function settledSince(from) {
        const results = settles(from);
        return results.length > 0 && results[results.length - 1] === 0;
    }
    function masterRecords() {
        return calls("record").filter(c => c.window === "master");
    }
    function lastMasterRecord() {
        const records = masterRecords();
        return records.length > 0 ? records[records.length - 1] : null;
    }
    function onTile(w) {
        return rectIs(w.frameGeometry, facade.masterRect.x, facade.masterRect.y, facade.masterRect.width, facade.masterRect.height);
    }
    // In a stack cell: the column's x past half the gap, its whole width (run() derives both).
    function inColumn(w) {
        return w.frameGeometry.x === 704 && w.frameGeometry.width === 736;
    }
    function maximize(w, mode, frame) {
        w.maximizedAboutToChange(mode);
        w.maximizeMode = mode;
        w.frameGeometry = frame;
        w.maximizedChanged();
    }
    // The master's records at a rectangle the native layer or the tiler put it on. One case
    // has the user put the window on the tile's own rectangle, where it floats: the records
    // made while that case runs (placedOnTile) are its floating place, not these.
    property var placedOnTile: ({ from: 0, to: 0 })
    function automaticRecords() {
        return masterRecords().filter((c, i) => (i < placedOnTile.from || i >= placedOnTile.to)
                                                && (rectIs(c, 0, 34, 700, 866) || rectIs(c, 0, 34, 700, 865.75)
                                                    || rectIs(c, 0, 34, 1440, 866) || rectIs(c, 300, 60, 700, 866)));
    }

    function runReleased() {
        const ws = KWinStubs.Workspace;
        if (setup() === "") {
            done = true;
            return;
        }
        // Fast retries: the pacing is the script's own property, the bounds stay bounds.
        script.settleRetryMillis = 20;
        script.settleRetryLimit = 5;
        script.admitRetryMillis = 20;
        script.admitRetryLimit = 3;
        facade.landOnAdmit = true;
        let mark = 0;
        let admits = 0;
        let creates = 0;
        let asked = 0;
        let since = 0;
        let twin = null;
        let twinMoves = 0;
        let floatA = null;
        let cellA = null;
        let late = null;
        let cellLate = null;
        let restores = 0;
        let releases = 0;
        let recordedAt = 0;
        let victim = null;
        let second = null;
        steps = [
            { run: function () {
                // ---- the explicit restore during a session: the native layer is restoring ----
                // Window Restore on the tiled master ends the tree while the client has not
                // committed the floating frame yet. The record completes by itself; a request
                // of the tiler's would replace the restoration.
                tileShortcut.activated();
                if (!onTile(master) || !inColumn(winA)) {
                    fail("released: the session started with the master on its tile");
                }
                mark = calls("settleWindow").length;
                delete facade.floatings.master; // the record is the restoration's from here
                facade.treeAlive = false;
                facade.treeChanged();
                if (JSON.stringify(settles(mark)) !== "[1]" || !onTile(master)) {
                    fail("released: a master the native layer is restoring is left to it (got " + JSON.stringify(settles(mark))
                         + ", " + JSON.stringify(master.frameGeometry) + ")");
                }
                if (!rectIs(winA.frameGeometry, 700, 120, 300, 320)) {
                    fail("released: the stack went back to its floats");
                }
                master.frameGeometry = Qt.rect(40, 80, 620, 420); // the restoration lands

                // ---- a detach-only release, the master on its fit in the tile: back to its float ----
                // The tile is off the output's pixels: the window stands a quarter pixel short.
                facade.fitRect = Qt.rect(0, 34, 700, 865.75);
                tileShortcut.activated();
                if (!rectIs(master.frameGeometry, 0, 34, 700, 865.75)) {
                    fail("released: the admission landed the master on its fit");
                }
                mark = calls("settleWindow").length;
                facade.unsettledAnswers = 2; // the release's configure, then the float's
                facade.detach(master);
                if (!rectIs(master.frameGeometry, 40, 80, 620, 420)) {
                    fail("released: the master went back to its float at once (got " + JSON.stringify(master.frameGeometry) + ")");
                }
                if (JSON.stringify(settles(mark)) !== "[3]") {
                    fail("released: the settle was asked first and found the window unsettled (got " + JSON.stringify(settles(mark)) + ")");
                }
                facade.fitRect = Qt.rect(0, 0, 0, 0);
            } },
            { name: "the returned master's record settled", until: () => settledSince(mark), run: function () {
                if (JSON.stringify(settles(mark)) !== "[3,3,0]") {
                    fail("released: the settle was asked again until the record was settled (got " + JSON.stringify(settles(mark)) + ")");
                }
                const record = lastMasterRecord();
                if (!record || !rectIs(record, 40, 80, 620, 420)) {
                    fail("released: the frame the master settled at is its record (got " + JSON.stringify(record) + ")");
                }
                // ---- the master the user moved: it stays, and its place is recorded ----
                tileShortcut.activated();
                if (!onTile(master)) {
                    fail("released: the settled master was admitted again");
                }
                master.move = true; // the drag's first step releases it
                master.frameGeometry = Qt.rect(500, 200, 600, 400);
                mark = calls("settleWindow").length;
                facade.detach(master);
                if (!rectIs(master.frameGeometry, 500, 200, 600, 400) || JSON.stringify(settles(mark)) !== "[3]") {
                    fail("released: a master in the user's hand is left there (got " + JSON.stringify(master.frameGeometry)
                         + ", " + JSON.stringify(settles(mark)) + ")");
                }
            } },
            { name: "the settle attempts during the drag used up", until: () => settles(mark).length >= 5, run: function () {
                // The drag is held still past the attempts; its end changes no geometry.
                asked = calls("settleWindow").length;
                facade.userDragEnded(master);
            } },
            { name: "the moved master's record settled", until: () => settledSince(mark), run: function () {
                if (calls("settleWindow").length !== asked + 1) {
                    fail("released: the end of the drag asked once more, and that settled it (got " + JSON.stringify(settles(mark)) + ")");
                }
                const record = lastMasterRecord();
                if (!rectIs(master.frameGeometry, 500, 200, 600, 400) || !record || !rectIs(record, 500, 200, 600, 400)) {
                    fail("released: the place the user chose is the master's floating placement (got " + JSON.stringify(record) + ")");
                }
                // ---- released onto another automatic rectangle: back to its float ----
                // A re-check of the work area asks the master for the tile's rectangle as it
                // is then; nothing says the user chose that frame.
                tileShortcut.activated();
                master.frameGeometry = Qt.rect(300, 60, 700, 866);
                mark = calls("settleWindow").length;
                facade.detach(master);
                if (JSON.stringify(settles(mark)) !== "[4]" || !rectIs(master.frameGeometry, 500, 200, 600, 400)) {
                    fail("released: a master on a frame of nobody's choice goes back to its float (got "
                         + JSON.stringify(settles(mark)) + ", " + JSON.stringify(master.frameGeometry) + ")");
                }
            } },
            { name: "the record settled on the float", until: () => settledSince(mark), run: function () {
                if (JSON.stringify(settles(mark)) !== "[4,0]") {
                    fail("released: settled once it stood on its float (got " + JSON.stringify(settles(mark)) + ")");
                }
                // ---- the user's resize in progress: the master is not taken out of the hand ----
                // The resize released it and has not changed the frame yet: it still stands
                // on its tile, and the tiler's return waits for the hand to let go.
                tileShortcut.activated();
                master.resize = true;
                mark = calls("settleWindow").length;
                facade.detach(master);
                if (JSON.stringify(settles(mark)) !== "[3]" || !onTile(master)) {
                    fail("released: a master the user is resizing is not moved (got " + JSON.stringify(settles(mark))
                         + ", " + JSON.stringify(master.frameGeometry) + ")");
                }
                facade.userDragEnded(master); // let go where it started
            } },
            { name: "the unresized master's record settled", until: () => settledSince(mark), run: function () {
                if (!rectIs(master.frameGeometry, 500, 200, 600, 400)) {
                    fail("released: left on its tile by the user, the master went back to its float (got "
                         + JSON.stringify(master.frameGeometry) + ")");
                }
                // ---- a maximized master: the record is held, then settled when it returns ----
                tileShortcut.activated();
                maximize(master, 3, Qt.rect(0, 34, 1440, 866));
                mark = calls("settleWindow").length;
                facade.detach(master);
            } },
            { name: "the settle attempts on the maximized master used up", until: () => settles(mark).length >= 5, run: function () {
                asked = calls("settleWindow").length;
                since = Date.now();
            } },
            { name: "the quiet second after the last float restore", until: () => Date.now() - since >= 1150, run: function () {
                if (calls("settleWindow").length !== asked || JSON.stringify(settles(mark)) !== "[3,3,3,3,3]") {
                    fail("released: a maximized master is asked about a bounded number of times (got " + JSON.stringify(settles(mark)) + ")");
                }
                if (!rectIs(master.frameGeometry, 0, 34, 1440, 866)) {
                    fail("released: a maximized master is left as it is");
                }
                // Unmaximized, it returns to the frame it had before: the tile's.
                mark = calls("settleWindow").length;
                maximize(master, 0, facade.masterRect);
            } },
            { name: "the unmaximized master's record settled", until: () => settledSince(mark), run: function () {
                if (JSON.stringify(settles(mark)) !== "[4,0]") {
                    fail("released: back on its tile, the held master was returned and settled (got " + JSON.stringify(settles(mark)) + ")");
                }
                if (!rectIs(master.frameGeometry, 500, 200, 600, 400)) {
                    fail("released: the held master went back to its float (got " + JSON.stringify(master.frameGeometry) + ")");
                }
                // ---- a held record is settled by the next toggle on the window ----
                tileShortcut.activated();
                master.move = true;
                master.frameGeometry = Qt.rect(520, 220, 600, 400);
                mark = calls("settleWindow").length;
                facade.detach(master);
                facade.userDragEnded(master);
                facade.unsettledAnswers = 100; // a client that does not answer
            } },
            { name: "the settle attempts on the unanswered master used up", until: () => settles(mark).length >= 6, run: function () {
                facade.unsettledAnswers = 0;
                admits = calls("admitTile").length;
                tileShortcut.activated();
                if (calls("admitTile").length !== admits + 1 || !onTile(master) || !inColumn(winA)) {
                    fail("released: the toggle settled the held record and admitted the window at once (admissions: "
                         + (calls("admitTile").length - admits) + ")");
                }
                const record = lastMasterRecord();
                if (!record || !rectIs(record, 520, 220, 600, 400)) {
                    fail("released: the place it was settled at is recorded (got " + JSON.stringify(record) + ")");
                }
                tileShortcut.activated(); // untoggle
                // ---- an admission refused for a state that passes is tried again ----
                master.frameGeometry = Qt.rect(40, 80, 620, 420);
                facade.admitAnswers = [7, 7];
                admits = calls("admitTile").length;
                tileShortcut.activated();
                if (calls("admitTile").length !== admits + 1 || inColumn(winA) || facade.treeAlive) {
                    fail("released: a refused admission starts no session and leaves no tree");
                }
            } },
            { name: "the third admission", until: () => calls("admitTile").length >= admits + 3, run: function () {
                if (calls("admitTile").length !== admits + 3 || !onTile(master) || !inColumn(winA)) {
                    fail("released: the admission was tried again until it was accepted (admissions: "
                         + (calls("admitTile").length - admits) + ")");
                }
                tileShortcut.activated(); // untoggle
                // ---- and the attempts are bounded ----
                master.frameGeometry = Qt.rect(40, 80, 620, 420);
                facade.admitAnswers = [7, 7, 7, 7, 7, 7, 7, 7];
                admits = calls("admitTile").length;
                tileShortcut.activated();
            } },
            { name: "the last admission attempt", until: () => calls("admitTile").length >= admits + 4, run: function () {
                since = Date.now();
            } },
            { name: "time for an attempt too many", until: () => Date.now() - since >= 300, run: function () {
                if (calls("admitTile").length !== admits + 4 || inColumn(winA) || facade.treeAlive) {
                    fail("released: the first attempt and three more, then the refusal stands (admissions: "
                         + (calls("admitTile").length - admits) + ")");
                }
                // ---- the shortcut again drops a start that is still being retried ----
                facade.admitAnswers = [7];
                creates = calls("createTile").length;
                tileShortcut.activated(); // refused, to be retried
                facade.refuseCreate = true;
                tileShortcut.activated(); // the newer intent, refused outright
                facade.refuseCreate = false;
                since = Date.now();
            } },
            { name: "time for the dropped retry", until: () => Date.now() - since >= 300, run: function () {
                if (calls("createTile").length !== creates + 2 || inColumn(winA)) {
                    fail("released: the retry of the earlier press was dropped (trees asked for: "
                         + (calls("createTile").length - creates) + ")");
                }
                facade.admitAnswers = [];
                // ---- a released master is not taken into another session's stack ----
                tileShortcut.activated();
                if (!onTile(master)) {
                    fail("released: the master was admitted");
                }
                mark = calls("settleWindow").length;
                facade.unsettledAnswers = 100;
                facade.detach(master); // returned at once; the client does not answer
                if (!rectIs(master.frameGeometry, 40, 80, 620, 420)) {
                    fail("released: the master went back to its float (got " + JSON.stringify(master.frameGeometry) + ")");
                }
                ws.activeWindow = winA;
                tileShortcut.activated(); // a session with another master
                if (!onTile(winA) || !inColumn(winB) || !rectIs(master.frameGeometry, 40, 80, 620, 420)) {
                    fail("released: the new session left the unsettled master alone (got " + JSON.stringify(master.frameGeometry) + ")");
                }
                tileShortcut.activated(); // untoggle
                winA.frameGeometry = Qt.rect(700, 120, 300, 320); // the restoration lands
                ws.activeWindow = master;
                facade.unsettledAnswers = 0;
                master.frameGeometry = Qt.rect(42, 82, 620, 420); // a move of the user's: asks again
                master.frameGeometry = Qt.rect(40, 80, 620, 420);
            } },
            { name: "the left-alone master's record settled", until: () => settledSince(mark), run: function () {
                // ---- a second window of the master's app does not take the master's place ----
                // The app's record is the master's float. A new window of the app is not
                // restored onto a spot one of its windows holds, and the master's spot is
                // where it floats, not the tile it stands on.
                // The window's arrival ends the session: the writer reports the key's second
                // window, the master is released at once, and the tree's end follows in a
                // queued call. In between the session still reads active, and the window that
                // just opened must not be given a cell of a stack that is about to go back -
                // on hardware the float it got an instant later had no configure of its own,
                // the answer to the cell landed after it, and a second later the cell was
                // recorded as the app's place.
                tileShortcut.activated();
                if (!onTile(master) || !master.tile) {
                    fail("released: the master is on its tile before its app's second window opens");
                }
                twin = mk({ internalId: "twin", resourceClass: "org.fusion.terminal",
                            desktopFileName: "org.fusion.terminal.desktop",
                            frameGeometry: Qt.rect(900, 500, 300, 300) });
                twin.desktops = [firstDesktop];
                twin.output = ws.activeScreen;
                twinMoves = 0;
                twin.frameGeometryChanged.connect(function () {
                    twinMoves += 1;
                });
                stackWindows = stackWindows.concat(twin);
                ws.windows = [twin, winB, winA, master];
                mark = calls("settleWindow").length;
                ws.windowAdded(twin);
                if (twinMoves !== 0 || !rectIs(twin.frameGeometry, 900, 500, 300, 300)) {
                    fail("released: the window whose arrival ends the session is given no cell (moved " + twinMoves
                         + " time(s), at " + JSON.stringify(twin.frameGeometry) + ")");
                }
            } },
            { name: "the session the second window ended went back and the master's record settled", until: () => settledSince(mark), run: function () {
                if (!rectIs(master.frameGeometry, 40, 80, 620, 420) || inColumn(winA) || inColumn(winB)) {
                    fail("released: a second window of the master's app: the master and the stack are back on their floats (master "
                         + JSON.stringify(master.frameGeometry) + ")");
                }
                since = Date.now();
            } },
            { name: "the second window's settle pass", until: () => Date.now() - since >= 1250, run: function () {
                if (twinMoves !== 0 || !rectIs(twin.frameGeometry, 900, 500, 300, 300)) {
                    fail("released: the app's second window keeps its own place, not the master's float and not a cell (moved "
                         + twinMoves + " time(s), at " + JSON.stringify(twin.frameGeometry) + ")");
                }
                const twinRecords = calls("record").filter(c => c.window === "twin");
                if (twinRecords.length !== 0) {
                    fail("released: the app's place stays the master's: its second window records nothing when it opens (got "
                         + JSON.stringify(twinRecords) + ")");
                }
                // ---- the app's remembered place is another window's: a toggle makes it the master's ----
                // The writer admits a window only from the place it has for the window's app
                // (facade.entryRule). The app's second window closes where it stood, and that
                // place is the app's now; on hardware every later toggle on the master was
                // refused (8) until the master moved. The toggle records the master's own
                // place first, by the memory's ordinary record.
                const key = "org.fusion.terminal";
                facade.entryRule = true;
                twin.deleted = true;
                ws.windows = [winB, winA, master];
                stackWindows = stackWindows.filter(w => w !== twin);
                ws.windowRemoved(twin);
                if (!facade.entries[key] || !rectIs(facade.entries[key], 900, 500, 300, 300)) {
                    fail("released: the app's place is where its second window closed (got " + JSON.stringify(facade.entries[key]) + ")");
                }
            } },
            // The writer tracks a closed window until it is destroyed, and admits no window
            // whose key a tracked one shares.
            { name: "the writer forgot the app's second window", until: () => facade.tracked["twin"] === undefined, run: function () {
                const key = "org.fusion.terminal";
                let recorded = masterRecords().length;
                ws.activeWindow = master;
                tileShortcut.activated();
                if (!onTile(master) || masterRecords().length !== recorded + 1 || !rectIs(lastMasterRecord(), 40, 80, 620, 420)) {
                    fail("released: a toggle records the window's own place first and is admitted from it (records "
                         + (masterRecords().length - recorded) + ", last " + JSON.stringify(lastMasterRecord())
                         + ", at " + JSON.stringify(master.frameGeometry) + ")");
                }
                tileShortcut.activated();
                if (!rectIs(master.frameGeometry, 40, 80, 620, 420) || master.tile) {
                    fail("released: the untoggle returned the master to its float (at " + JSON.stringify(master.frameGeometry) + ")");
                }
                // A window the user put on the tile's own rectangle floats there: that is its
                // place, recorded and admitted from like any other. A rectangle is no evidence
                // of an automatic placement.
                const tileRect = facade.plain(facade.masterRect);
                const placedFrom = masterRecords().length;
                master.frameGeometry = Qt.rect(tileRect.x, tileRect.y, tileRect.width, tileRect.height);
                facade.entries[key] = { x: 900, y: 500, width: 300, height: 300 };
                recorded = masterRecords().length;
                tileShortcut.activated();
                if (!master.tile || masterRecords().length !== recorded + 1 || !facade.same(lastMasterRecord(), tileRect)) {
                    fail("released: a window the user put on the tile's rectangle is recorded there and admitted (records "
                         + (masterRecords().length - recorded) + ", last " + JSON.stringify(lastMasterRecord())
                         + ", " + (master.tile ? "admitted" : "not admitted") + ")");
                }
                tileShortcut.activated();
                harness.placedOnTile = { from: placedFrom, to: masterRecords().length };
                if (masterRecords().slice(placedFrom).some(c => !facade.same(c, tileRect))) {
                    fail("released: while the window floats on the tile's rectangle that is the only place recorded (got "
                         + JSON.stringify(masterRecords().slice(placedFrom)) + ")");
                }
                // A window the native layer still has a record for: a release left it where it
                // stands and this script knows nothing of it (it was loaded afterwards).
                // Where it stands is nobody's choice and is not recorded, by the first attempt
                // or by one of the retries of an admission that answers busy.
                facade.entries[key] = { x: 900, y: 500, width: 300, height: 300 };
                facade.keepRecord(master, Qt.rect(40, 80, 620, 420));
                recordedAt = masterRecords().length;
                admits = calls("admitTile").length;
                tileShortcut.activated();
                if (master.tile || masterRecords().length !== recordedAt || calls("admitTile").length !== admits + 1) {
                    fail("released: a window the native layer keeps a record of is not recorded where it stands; the admission is asked (records "
                         + (masterRecords().length - recordedAt) + ", admissions " + (calls("admitTile").length - admits) + ")");
                }
            } },
            { name: "the busy admission's last attempt", until: () => calls("admitTile").length >= admits + 4, run: function () {
                since = Date.now();
            } },
            { name: "time for an attempt too many on the busy window", until: () => Date.now() - since >= 300, run: function () {
                if (master.tile || masterRecords().length !== recordedAt || calls("admitTile").length !== admits + 4) {
                    fail("released: no attempt records a window the native layer keeps a record of (records "
                         + (masterRecords().length - recordedAt) + ", admissions " + (calls("admitTile").length - admits) + ")");
                }
                facade.dropRecord(master);
                const key = "org.fusion.terminal";
                let recorded = 0;
                let admissions = 0;
                master.frameGeometry = Qt.rect(40, 80, 620, 420);
                // With another window of the app open the memory is left as it is: the native
                // layer refuses a key two windows share, and the record would be for nothing.
                const other = mk({ internalId: "twin2", resourceClass: "org.fusion.terminal",
                                   desktopFileName: "org.fusion.terminal.desktop",
                                   frameGeometry: Qt.rect(900, 500, 300, 300) });
                other.desktops = [firstDesktop];
                other.output = ws.activeScreen;
                ws.windows = [other, winB, winA, master];
                ws.windowAdded(other);
                facade.entries[key] = { x: 900, y: 500, width: 300, height: 300 };
                recorded = masterRecords().length;
                admissions = calls("admitTile").length;
                ws.activeWindow = master;
                tileShortcut.activated();
                if (master.tile || masterRecords().length !== recorded || calls("admitTile").length !== admissions + 1) {
                    fail("released: with another window of the app open nothing is recorded for the toggle (records "
                         + (masterRecords().length - recorded) + ", admissions " + (calls("admitTile").length - admissions) + ")");
                }
                // The writer holds a window under the key it was bound with. One that calls
                // itself something else since then still shares the master's key.
                other.resourceClass = "org.fusion.renamed";
                other.desktopFileName = "org.fusion.renamed.desktop";
                recorded = masterRecords().length;
                admissions = calls("admitTile").length;
                tileShortcut.activated();
                if (master.tile || masterRecords().length !== recorded || calls("admitTile").length !== admissions + 1) {
                    fail("released: a window the writer holds under the app's key counts as the app's, whatever it calls itself now (records "
                         + (masterRecords().length - recorded) + ", admissions " + (calls("admitTile").length - admissions) + ")");
                }
                facade.entryRule = false;
                other.deleted = true;
                ws.windows = [winB, winA, master];
                ws.windowRemoved(other);
            } },
            { name: "the writer forgot the app's other window", until: () => facade.tracked["twin2"] === undefined, run: function () {
                ws.activeWindow = master;
                // ---- in the window's quiet second a toggle records nothing ----
                // A released master goes back to its float under the restore's quiet second,
                // in which the memory records nothing of the window.
                tileShortcut.activated();
                if (!onTile(master)) {
                    fail("released: the master is admitted again once its app's other window is gone");
                }
                mark = calls("settleWindow").length;
                facade.detach(master);
                since = Date.now();
            } },
            { name: "the released master's record settled inside its quiet second", until: () => settledSince(mark), run: function () {
                if (Date.now() - since >= 900) {
                    fail("released: the step ran " + (Date.now() - since) + " ms after the release, too late to check the quiet second");
                }
                facade.entries["org.fusion.terminal"] = { x: 900, y: 500, width: 300, height: 300 };
                facade.entryRule = true;
                const recorded = masterRecords().length;
                const admissions = calls("admitTile").length;
                tileShortcut.activated();
                if (master.tile || masterRecords().length !== recorded || calls("admitTile").length !== admissions + 1) {
                    fail("released: in the window's quiet second a toggle records nothing; the admission is asked and refused (records "
                         + (masterRecords().length - recorded) + ", admissions " + (calls("admitTile").length - admissions) + ")");
                }
                facade.entryRule = false;
                ws.activeWindow = master;
                // ---- a float given back while the cell's configure is in flight ----
                // KWin applies a request for the size a window already has at once, with no
                // configure. The client's answer to the cell lands afterwards and KWin takes
                // it as the window's request: the window stands on a cell no session owns.
                // On hardware a second press of the shortcut 15 ms after the first did this,
                // three times out of three. The float is asked for once more then, once.
                floatA = facade.plain(winA.frameGeometry);
                tileShortcut.activated();
                if (!inColumn(winA)) {
                    fail("released: the stack window is in its cell");
                }
                cellA = facade.plain(winA.frameGeometry);
                tileShortcut.activated();
                if (!facade.same(winA.frameGeometry, floatA)) {
                    fail("released: the untoggle gave the stack window its float back");
                }
                since = Date.now();
            } },
            { name: "the quiet second after the stack's floats", until: () => Date.now() - since >= 1150, run: function () {
                // After the quiet second, where an ordinary frame would be recorded.
                const cellRecordsOf = function (id, cell) {
                    return calls("record").filter(c => c.window === id && facade.same(c, cell));
                };
                // While the float is still what KWin is asking for, the window is on its way
                // there (the cell's answer came first, the float's follows): left alone, and
                // the cell is no placement meanwhile.
                winA.requestedGeometry = Qt.rect(floatA.x, floatA.y, floatA.width, floatA.height);
                winA.frameGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                if (!facade.same(winA.frameGeometry, cellA) || cellRecordsOf("a", cellA).length !== 0) {
                    fail("released: a window still on its way to its float is not asked again, and its cell is not recorded (at "
                         + JSON.stringify(winA.frameGeometry) + ", cell records " + cellRecordsOf("a", cellA).length + ")");
                }
                // KWin takes the cell's answer as the request: nothing brings the float any
                // more. That change alone - the frame does not move - asks for the float.
                winA.requestedGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                if (!facade.same(winA.frameGeometry, floatA) || cellRecordsOf("a", cellA).length !== 0) {
                    fail("released: a late answer to the cell is followed by the float once more (at "
                         + JSON.stringify(winA.frameGeometry) + ", cell records " + cellRecordsOf("a", cellA).length + ")");
                }
                // Once: a window that lands there again is left where it is, and the cell is
                // still no placement of it.
                winA.frameGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                if (!facade.same(winA.frameGeometry, cellA) || cellRecordsOf("a", cellA).length !== 0) {
                    fail("released: the float is asked for once, not in a loop, and the cell stays unrecorded (at "
                         + JSON.stringify(winA.frameGeometry) + ", cell records " + cellRecordsOf("a", cellA).length + ")");
                }
                winA.requestedGeometry = null;
                winA.frameGeometry = Qt.rect(floatA.x, floatA.y, floatA.width, floatA.height);
                // Not while the window is in the user's hand: asked once the hand lets go.
                tileShortcut.activated();
                tileShortcut.activated();
                winA.move = true;
                winA.requestedGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                winA.frameGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                if (!facade.same(winA.frameGeometry, cellA)) {
                    fail("released: a window in the user's hand is not taken out of it (at " + JSON.stringify(winA.frameGeometry) + ")");
                }
                winA.move = false;
                winA.requestedGeometryChanged();
                if (!facade.same(winA.frameGeometry, floatA) || cellRecordsOf("a", cellA).length !== 0) {
                    fail("released: the float is asked for once the hand lets go (at " + JSON.stringify(winA.frameGeometry) + ")");
                }
                winA.requestedGeometry = null;
                // ---- moved since: a late answer to the cell is taken back to where the window stands ----
                // A slow client: the user has moved the window before its answer to the cell
                // lands. It is taken back to the place the user gave it, not to the float the
                // session saved.
                tileShortcut.activated();
                tileShortcut.activated();
                winA.frameGeometry = Qt.rect(300, 200, 420, 360);
                winA.requestedGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                winA.frameGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                if (!rectIs(winA.frameGeometry, 300, 200, 420, 360)) {
                    fail("released: a window moved since its float came back is returned to where it was moved (at "
                         + JSON.stringify(winA.frameGeometry) + ")");
                }
                winA.requestedGeometry = null;
                winA.frameGeometry = Qt.rect(floatA.x, floatA.y, floatA.width, floatA.height);
                // Only a frame the window has settled on is such a place: one that KWin's
                // request has not reached yet is on its way somewhere, and the late answer to
                // the cell is taken back to the last place the window stood on.
                tileShortcut.activated();
                tileShortcut.activated();
                winA.requestedGeometry = Qt.rect(500, 300, 400, 300);
                winA.frameGeometry = Qt.rect(480, 280, 410, 310);
                winA.requestedGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                winA.frameGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                if (!facade.same(winA.frameGeometry, floatA)) {
                    fail("released: a frame in flight is no place to take the window back to (at " + JSON.stringify(winA.frameGeometry) + ")");
                }
                winA.requestedGeometry = null;
                // ---- the next session's floats: where a window is going, not a cell ----
                // An off and an on in quick succession: the float's configure is in flight and
                // the window still stands on the cell. Saved as the float, the cell would be
                // where every later untoggle puts the window.
                tileShortcut.activated();
                tileShortcut.activated();
                winA.requestedGeometry = Qt.rect(floatA.x, floatA.y, floatA.width, floatA.height);
                winA.frameGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                tileShortcut.activated();
                tileShortcut.activated();
                if (!facade.same(winA.frameGeometry, floatA)) {
                    fail("released: a window that stood on the last session's cell brings that session's float (back at "
                         + JSON.stringify(winA.frameGeometry) + ")");
                }
                winA.requestedGeometry = null;
                // And a window KWin is still moving somewhere brings the place it is going to.
                const floatB = facade.plain(winB.frameGeometry);
                winB.requestedGeometry = Qt.rect(700, 420, 300, 300);
                tileShortcut.activated();
                tileShortcut.activated();
                if (!rectIs(winB.frameGeometry, 700, 420, 300, 300)) {
                    fail("released: a window on its way somewhere brings the place it is going to (back at "
                         + JSON.stringify(winB.frameGeometry) + ")");
                }
                winB.requestedGeometry = null;
                winB.frameGeometry = Qt.rect(floatB.x, floatB.y, floatB.width, floatB.height);
                // ---- a new session's cells are its members' own ----
                // On, off and on again: the answer to the first session's cell lands on a
                // window the second one manages, on the cell that session gave it.
                tileShortcut.activated();
                tileShortcut.activated();
                tileShortcut.activated();
                winA.requestedGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                if (!inColumn(winA) || !facade.same(winA.frameGeometry, cellA)) {
                    fail("released: a member of a new session is not taken off its cell (at " + JSON.stringify(winA.frameGeometry) + ")");
                }
                winA.requestedGeometry = null;
                tileShortcut.activated();
                if (!facade.same(winA.frameGeometry, floatA)) {
                    fail("released: the second session gave the stack window its float back");
                }
                // ---- an answer that comes too late is not taken back, and is no placement ----
                late = mk({ internalId: "late", resourceClass: "org.fusion.late",
                            desktopFileName: "org.fusion.late.desktop",
                            frameGeometry: Qt.rect(200, 200, 320, 240) });
                late.desktops = [firstDesktop];
                late.output = ws.activeScreen;
                stackWindows = stackWindows.concat(late);
                ws.windows = [late, winB, winA, master];
                ws.windowAdded(late);
                ws.activeWindow = master;
                script.staleCellMillis = 60;
                tileShortcut.activated();
                if (!inColumn(late)) {
                    fail("released: the late window is in its cell");
                }
                cellLate = facade.plain(late.frameGeometry);
                tileShortcut.activated();
                if (!rectIs(late.frameGeometry, 200, 200, 320, 240)) {
                    fail("released: the untoggle gave the late window its float back");
                }
                since = Date.now();
            } },
            { name: "the cell's answer can no longer be taken back", until: () => Date.now() - since >= 1250, run: function () {
                const cellRecords = function () {
                    return calls("record").filter(c => c.window === "late" && facade.same(c, cellLate));
                };
                late.requestedGeometry = Qt.rect(cellLate.x, cellLate.y, cellLate.width, cellLate.height);
                late.frameGeometry = Qt.rect(cellLate.x, cellLate.y, cellLate.width, cellLate.height);
                late.requestedGeometryChanged();
                if (!facade.same(late.frameGeometry, cellLate)) {
                    fail("released: an answer after the bound is not taken back (at " + JSON.stringify(late.frameGeometry) + ")");
                }
                if (cellRecords().length !== 0) {
                    fail("released: a cell the tiler took back is not recorded, after the quiet second either (got "
                         + JSON.stringify(cellRecords()) + ")");
                }
                // A press of the shortcut on it there: the admission's record of the window's
                // own place takes no cell either, and the native layer refuses the window (its
                // app's place is another rectangle).
                facade.entryRule = true;
                ws.activeWindow = late;
                const admissions = calls("admitTile").length;
                tileShortcut.activated();
                if (late.tile || cellRecords().length !== 0 || calls("admitTile").length !== admissions + 1) {
                    fail("released: a press on a window that stands on a cell the tiler took back records no cell and is refused (cell records "
                         + cellRecords().length + ", admissions " + (calls("admitTile").length - admissions) + ")");
                }
                facade.entryRule = false;
                ws.activeWindow = master;
                // The next session takes the window with the float the last one saved, not
                // with the cell it stands on: its untoggle puts the window back where it
                // floated.
                tileShortcut.activated();
                if (!inColumn(late)) {
                    fail("released: the next session takes the window that stood on the old cell");
                }
                cellLate = facade.plain(late.frameGeometry);
                tileShortcut.activated();
                if (!rectIs(late.frameGeometry, 200, 200, 320, 240)) {
                    fail("released: a window left on a cell the tiler took back goes into the next session with its float (back at "
                         + JSON.stringify(late.frameGeometry) + ")");
                }
                late.requestedGeometry = null;
                since = Date.now();
            } },
            { name: "the second cell's answer can no longer be taken back either", until: () => Date.now() - since >= 1250, run: function () {
                const cellRecords = function () {
                    return calls("record").filter(c => c.window === "late" && facade.same(c, cellLate));
                };
                late.requestedGeometry = Qt.rect(cellLate.x, cellLate.y, cellLate.width, cellLate.height);
                late.frameGeometry = Qt.rect(cellLate.x, cellLate.y, cellLate.width, cellLate.height);
                late.requestedGeometryChanged();
                if (!facade.same(late.frameGeometry, cellLate) || cellRecords().length !== 0) {
                    fail("released: the window stands on the cell again, unrecorded (at " + JSON.stringify(late.frameGeometry)
                         + ", cell records " + cellRecords().length + ")");
                }
                // It closes there: the app's place stays the one it had.
                late.deleted = true;
                ws.windows = [winB, winA, master];
                stackWindows = stackWindows.filter(w => w !== late);
                ws.windowRemoved(late);
                if (cellRecords().length !== 0) {
                    fail("released: a window that closes on a cell the tiler took back records nothing (got "
                         + JSON.stringify(cellRecords()) + ")");
                }
                script.staleCellMillis = 5000;
                // ---- a press between the master's release and the tree's end ----
                // The native layer has released the master (its app's second window) and the
                // tree's end is queued. The untoggle's explicit restore would find nothing it
                // owns and nobody would settle the master's record: the press is the native
                // teardown, taken now.
                master.frameGeometry = Qt.rect(40, 80, 620, 420);
                ws.activeWindow = master;
                tileShortcut.activated();
                if (!onTile(master) || !master.tile) {
                    fail("released: the master is on its tile before the press in the gap");
                }
                twin = mk({ internalId: "twin3", resourceClass: "org.fusion.terminal",
                            desktopFileName: "org.fusion.terminal.desktop",
                            frameGeometry: Qt.rect(900, 500, 300, 300) });
                twin.desktops = [firstDesktop];
                twin.output = ws.activeScreen;
                ws.windows = [twin, winB, winA, master];
                restores = calls("restoreWindow").length;
                releases = calls("releaseTile").length;
                mark = calls("settleWindow").length;
                ws.windowAdded(twin);
                tileShortcut.activated();
                if (calls("restoreWindow").length !== restores || calls("releaseTile").length !== releases + 1
                        || calls("settleWindow").length === mark) {
                    fail("released: a press in the gap is the native teardown: no explicit restore, the tree released, the record asked (restores "
                         + (calls("restoreWindow").length - restores) + ", releases " + (calls("releaseTile").length - releases)
                         + ", settles " + (calls("settleWindow").length - mark) + ")");
                }
            } },
            { name: "the master released in the gap settled", until: () => settledSince(mark), run: function () {
                if (!rectIs(master.frameGeometry, 40, 80, 620, 420) || calls("restoreWindow").length !== restores) {
                    fail("released: the master released in the gap is back on its float (at " + JSON.stringify(master.frameGeometry) + ")");
                }
                twin.deleted = true;
                ws.windows = [winB, winA, master];
                ws.windowRemoved(twin);
            } },
            { name: "the writer forgot the window that ended the session", until: () => facade.tracked["twin3"] === undefined, run: function () {
                ws.activeWindow = master;
                // ---- the screen a press tiles is the active window's own ----
                // The active screen is where the window was when it was activated. On
                // hardware the active window had been moved to the other screen by a script,
                // the tile was made on the screen it had left, and the admission of a window
                // of another screen was refused (7): the press did nothing.
                second = { name: "Virtual-2", geometry: Qt.rect(1440, 0, 1280, 800), devicePixelRatio: 1 };
                ws.screens = [ws.activeScreen, second];
                const home = master.output;
                master.output = second;
                master.frameGeometry = Qt.rect(1500, 100, 620, 420);
                tileShortcut.activated();
                const made = calls("createTile");
                if (made[made.length - 1].output !== "Virtual-2" || !master.tile || inColumn(winA) || inColumn(winB)) {
                    fail("released: a press tiles the screen its window is on, with that screen's windows (the tile on '"
                         + made[made.length - 1].output + "', the master " + (master.tile ? "admitted" : "not admitted") + ")");
                }
                tileShortcut.activated();
                master.output = home;
                master.frameGeometry = Qt.rect(40, 80, 620, 420);
                ws.activeWindow = master;
                // ---- sent to another output: back to the float the record carried along ----
                // The native record's floating frame follows the window; the frame the tiler
                // saved before the admission is on the screen the window left.
                tileShortcut.activated();
                master.output = second;
                master.frameGeometry = Qt.rect(1740, 34, 700, 866);
                facade.floatings.master = { x: 1500, y: 100, width: 620, height: 420 };
                mark = calls("settleWindow").length;
                facade.detach(master);
                if (JSON.stringify(settles(mark)) !== "[4]" || !rectIs(master.frameGeometry, 1500, 100, 620, 420)) {
                    fail("released: a master sent to another output goes to the record's floating frame there (got "
                         + JSON.stringify(settles(mark)) + ", " + JSON.stringify(master.frameGeometry) + ")");
                }
            } },
            { name: "the transferred master's record settled", until: () => settledSince(mark), run: function () {
                const record = lastMasterRecord();
                if (!record || !rectIs(record, 1500, 100, 620, 420)) {
                    fail("released: the float on the other output is the record now (got " + JSON.stringify(record) + ")");
                }
                // ---- a floating frame on a display that is gone is never applied ----
                master.output = ws.activeScreen;
                master.frameGeometry = Qt.rect(40, 80, 620, 420);
                tileShortcut.activated();
                ws.screens = [ws.activeScreen]; // the second display is unplugged
                master.frameGeometry = Qt.rect(300, 60, 700, 866);
                facade.floatings.master = { x: 1500, y: 100, width: 620, height: 420 };
                mark = calls("settleWindow").length;
                facade.detach(master);
            } },
            { name: "the settle attempts without a float to return to used up", until: () => settles(mark).length >= 5, run: function () {
                if (!rectIs(master.frameGeometry, 300, 60, 700, 866)) {
                    fail("released: a master whose float is on a display that is gone stays where it is (got "
                         + JSON.stringify(master.frameGeometry) + ")");
                }
                if (automaticRecords().length !== 0) {
                    fail("released: no automatic rectangle of the master was ever recorded (got " + JSON.stringify(automaticRecords()) + ")");
                }
                since = Date.now();
            } },
            { name: "the quiet second after the last float restore", until: () => Date.now() - since >= 1150, run: function () {
                // The display comes back: the master's next geometry change asks again, and
                // now there is a float to return it to.
                ws.screens = [ws.activeScreen, second];
                mark = calls("settleWindow").length;
                master.frameGeometry = Qt.rect(301, 60, 700, 866);
            } },
            { name: "the held master's record settled once its float's display is back", until: () => settledSince(mark), run: function () {
                if (!rectIs(master.frameGeometry, 1500, 100, 620, 420) || automaticRecords().length !== 0) {
                    fail("released: the held master went to its float on the display that came back (got "
                         + JSON.stringify(master.frameGeometry) + ")");
                }
                // ---- a released master that closes takes its entry with it ----
                // KWin marks a closing window deleted, reports it removed and destroys it. A
                // reference to the destroyed window is not null and reads "not deleted";
                // passed to the facade it throws, which would abort every later settle step
                // and the toggle that asked.
                victim = mk({ internalId: "victim", resourceClass: "org.fusion.notes",
                              desktopFileName: "org.fusion.notes.desktop",
                              frameGeometry: Qt.rect(120, 140, 500, 400) });
                victim.desktops = [firstDesktop];
                victim.output = ws.activeScreen;
                ws.windows = [victim, winB, winA, master];
                ws.windowAdded(victim);
                ws.activeWindow = victim;
                tileShortcut.activated();
                if (!onTile(victim)) {
                    fail("released: the victim was admitted as the master");
                }
                // Its floating frame is on no display: it cannot be returned and stands on
                // its tile, its record held, when it closes.
                facade.floatings.victim = { x: 3000, y: 100, width: 500, height: 400 };
                facade.detach(victim);
                if (!onTile(victim)) {
                    fail("released: the victim stands on its tile");
                }
                const before = calls("record").filter(c => c.window === "victim").length;
                victim.deleted = true;
                ws.windows = [winB, winA, master];
                ws.windowRemoved(victim);
                if (calls("record").filter(c => c.window === "victim").length !== before) {
                    fail("released: a released master that closes records nothing");
                }
                victim.destroy();
                since = Date.now();
            } },
            { name: "the victim's destruction", until: () => Date.now() - since >= 200, run: function () {
                // Another master is released: its settle step must not trip over the victim.
                master.output = ws.activeScreen;
                master.frameGeometry = Qt.rect(40, 80, 620, 420);
                ws.activeWindow = master;
                tileShortcut.activated();
                mark = calls("settleWindow").length;
                facade.detach(master);
                if (!rectIs(master.frameGeometry, 40, 80, 620, 420)) {
                    fail("released: the next released master went back to its float (got " + JSON.stringify(master.frameGeometry) + ")");
                }
            } },
            { name: "the next master's record settled", until: () => settledSince(mark), run: function () {
                // ---- the master closes while tiling: destroyed before the tree's end arrives ----
                // The facade ends the tree in a queued call; the window can be gone by then.
                victim = mk({ internalId: "victim2", resourceClass: "org.fusion.notes",
                              desktopFileName: "org.fusion.notes.desktop",
                              frameGeometry: Qt.rect(120, 140, 500, 400) });
                victim.desktops = [firstDesktop];
                victim.output = ws.activeScreen;
                ws.windows = [victim, winB, winA, master];
                ws.windowAdded(victim);
                ws.activeWindow = victim;
                tileShortcut.activated();
                victim.deleted = true;
                ws.windows = [winB, winA, master];
                ws.windowRemoved(victim);
                victim.destroy();
                since = Date.now();
            } },
            { name: "the closed master's destruction", until: () => Date.now() - since >= 200, run: function () {
                // A window that opens before the tree's end arrives is no member of a session
                // whose master is gone. (An app the memory has no place for: the window stays
                // where it opens.)
                late = mk({ internalId: "late2", resourceClass: "org.fusion.orphan",
                            desktopFileName: "org.fusion.orphan.desktop",
                            frameGeometry: Qt.rect(220, 220, 320, 240) });
                late.desktops = [firstDesktop];
                late.output = ws.activeScreen;
                ws.windows = [late, winB, winA, master];
                ws.windowAdded(late);
                if (!rectIs(late.frameGeometry, 220, 220, 320, 240)) {
                    fail("released: a window that opens after the master closed is given no cell (at "
                         + JSON.stringify(late.frameGeometry) + ")");
                }
                asked = calls("settleWindow").length;
                facade.treeAlive = false;
                facade.treeChanged();
                if (calls("settleWindow").length !== asked) {
                    fail("released: a closed master has nothing to settle (asked " + (calls("settleWindow").length - asked) + ")");
                }
                late.deleted = true;
                ws.windows = [winB, winA, master];
                ws.windowRemoved(late);
                ws.activeWindow = master;
                // ---- the script goes while a master's record is held: nothing stays connected ----
                // The window and the facade outlive the script. The end of a later drag, or a
                // tree's end, must not call into a script that is gone.
                script.destroy();
                since = Date.now();
            } },
            { name: "the script's deletion", until: () => Date.now() - since >= 200, run: function () {
                asked = calls("settleWindow").length;
                master.interactiveMoveResizeFinished();
                facade.treeChanged();
                if (calls("settleWindow").length !== asked) {
                    fail("released: a script that is gone asks nothing (asked " + (calls("settleWindow").length - asked) + ")");
                }
            } }
        ];
        stepSince = Date.now();
        stepper.start();
    }

    function runLate() {
        const ws = KWinStubs.Workspace;
        // ---- the cell as a fractional scale lands it is the tiler's own write ----
        // KWin snaps the frame to device pixels and gives the client a whole logical size, so
        // the client's commit of a cell is a fraction of a pixel off it (717.75 for 718 at
        // 133%). That is not the user's hand: the member stays, and the next relayout places
        // it on a whole-pixel cell again. (The ThinkPad detached every placed window.)
        const cellA = { x: winA.frameGeometry.x, y: winA.frameGeometry.y,
                        width: winA.frameGeometry.width, height: winA.frameGeometry.height };
        winA.frameGeometry = Qt.rect(cellA.x, cellA.y, cellA.width - 0.25, cellA.height + 0.5);
        const manualRect = Qt.rect(100, 600, 280, 240);
        winB.frameGeometry = manualRect;
        const creates = calls("createTile");
        stackWindows = [winA, winB, winD];
        ws.windows = [winD, winB, winA, master];
        ws.windowAdded(winD);
        if (winA.frameGeometry.width !== cellA.width || winA.frameGeometry.height !== Math.round(winA.frameGeometry.height)) {
            fail("a member whose cell landed a fraction of a pixel off stays a member (got "
                 + JSON.stringify(winA.frameGeometry) + ")");
        }
        if (calls("createTile").length !== creates.length) {
            fail("the ignored-member session still owns one tree");
        }
        if (!rectIs(winB.frameGeometry, manualRect.x, manualRect.y, manualRect.width, manualRect.height)) {
            fail("the ignored member's manual move stands after the relayout (got "
                 + JSON.stringify(winB.frameGeometry) + ")");
        }

        // ---- an ignored app that joins live records nothing, settle pass included ----
        // org.fusion.files is in IgnoreApps: opening another of its windows during the
        // session joins the stack (the tiler ignores the memory's list) and is settle
        // pushed like any join - but its float must not reach the memory; the policy that
        // nothing of an ignored app is recorded survives the tiler.
        const winE = mk({ internalId: "e", resourceClass: "org.fusion.files",
                          desktopFileName: "org.fusion.files.desktop",
                          frameGeometry: Qt.rect(320, 560, 220, 220) });
        winE.desktops = [firstDesktop];
        winE.output = ws.activeScreen;
        stackWindows = stackWindows.concat(winE);
        ws.windows = [winE, winD, winB, winA, master];
        ws.windowAdded(winE);

        // ---- a reflow's float restore quiets the starved member's late cell commit ----
        // A third join shrinks the placed cells below winA's minimum height: its saved
        // float goes back and it leaves the session. The client's late commit of the old
        // cell (a window without requestedGeometry support) must not then record the cell
        // as the window's floating placement - the restore quiets it, like the untoggle's.
        winA.minSize = { width: 1, height: 400 };
        const winG = mk({ internalId: "g", resourceClass: "org.fusion.chat",
                          desktopFileName: "org.fusion.chat.desktop",
                          frameGeometry: Qt.rect(430, 150, 260, 300) });
        winG.desktops = [firstDesktop];
        winG.output = ws.activeScreen;
        stackWindows = stackWindows.concat(winG);
        ws.windows = [winG, winE, winD, winB, winA, master];
        // a plain copy: a value-type property read through a QObject reference aliases the
        // window's live geometry, and the reflow's own write would mutate the capture
        const winACell = { x: winA.frameGeometry.x, y: winA.frameGeometry.y,
                           width: winA.frameGeometry.width, height: winA.frameGeometry.height };
        ws.windowAdded(winG);
        if (rectIs(winA.frameGeometry, winACell.x, winACell.y, winACell.width, winACell.height)) {
            fail("the starved member returned to its float (it kept its cell)");
        }
        winA.frameGeometry = Qt.rect(winACell.x, winACell.y, winACell.width, winACell.height); // the late commit
        // the python driver asserts, after the settle pass, that no record carries winA's
        // cell or anything of the ignored app's second window

        // the snapshot the python driver counts from: everything the run itself caused
        snapshot = ({ createTile: calls("createTile").length,
                      admitTile: calls("admitTile").length,
                      releaseTile: calls("releaseTile").length,
                      registerProvider: calls("registerProvider").length,
                      trackWindow: calls("trackWindow").length });
    }
}
