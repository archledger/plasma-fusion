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
    A third (scenario: "unload") unloads the script mid-session as KWin unloads a declarative
    script: the driver makes it in a context of its own and deletes that context first
    (KWinScript in tiling_lifecycle_test.py). Another (scenario: "refused-provider") has the
    writer refuse the provider registration with the fork's null UUID, and one
    ("late-memory") has it answer the memory's first read with nothing; "provider-rules"
    checks the layout provider's own rules without the script. Every run follows the
    script's layout provider (LayoutProvider.qml) - online, capable, the session and its view,
    one revision per change - and the driver checks that order and that no two runs share a
    lifetime label.
    Context properties from the driver: packagesRoot (a directory holding
    scripts/plasmafusion-placement), config prefill through the KWin context object.
*/

import QtQuick
import org.kde.kwin as KWinStubs
import org.kde.plasma.workspace.dbus as DBusStubs

Item {
    id: harness

    property bool done: false
    // The "unload" scenario (runUnload): the harness asks for the script with its URL
    // (scriptWanted) and the driver makes it as KWin makes a declarative script (kwinScript);
    // the harness asks for the unload (unloadWanted) and the driver unloads it as KWin does
    // (unloaded).
    property string scriptWanted: ""
    property var kwinScript: null
    property bool unloadWanted: false
    property bool unloaded: false
    // Set by the driver for the unload's second run: the native layer has released the master
    // when the script goes (a detach-only release, the tree's end on its way).
    property bool unloadVacated: false
    // The "stranded" scenario (runStranded): whether the fork lets the current provider settle
    // a record an earlier one admitted (plasma-fusion#175), and whether the user moved the
    // stranded window where it stands.
    property bool strandedSuccessor: true
    property bool strandedPlaced: false
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
    // The facade's read-only calls, apart: the runs' exact facadeCalls lists stay as they are.
    property var readCalls: []
    // The script's layout provider (LayoutProvider.qml), its states as they moved - the one
    // it started with, then one entry per revision - and its lifetime label (trackProvider;
    // the driver checks the order and that no two runs share a label).
    property var provider: null
    property var providerStates: []
    property string providerLabel: ""
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

    // The mock facade: every method the script can call, each one recorded - in facadeCalls, or
    // in readCalls for the read-only ones (floatingFrame, windowBinding, snapshot, hasTree,
    // masterWindowRect) - and no method the fork's facade does not have (kwin
    // src/scripting/transienttilingapi.h) - a call the mock answers and the compositor cannot is
    // a failure only hardware would show.
    // createTile also snapshots the stack windows' geometry at call time - invariant 8 (the
    // native admission before any stack write) is checkable from that snapshot.
    QtObject {
        id: facade
        property bool refuseCreate: false
        property bool refuseAdmit: false
        // The token the mock grants, as the fork writes one (a braced UUID), and what
        // registerProvider answers: that token, or the fork's refusal (scenario
        // "refused-provider").
        readonly property string grantedToken: "{5d3c9a1e-7b2f-4c6d-8e9a-0b1c2d3e4f5a}"
        property string providerAnswer: grantedToken
        // How many snapshot() calls the writer leaves unanswered, as at load time before its
        // snapshot is ready (scenario "late-memory").
        property int snapshotSilences: 0
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
        // window internalId -> {target, floating, placedByUser, provider}: the records of
        // masters the native layer released without restoring them (detach). A window with one
        // cannot be admitted (busy). provider: the token of the provider that admitted the
        // window, when that was an earlier one (a record the script finds at its start).
        property var heldRecords: ({})
        // Whether the current provider may settle a record an earlier, retired provider
        // admitted (the fork from plasma-fusion#175 on); without, only the admitting one may.
        property bool successorSettle: true
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
            } else if (token !== grantedToken) {
                result = 2;
            } else if (held.provider !== undefined && held.provider !== token && !successorSettle) {
                result = 2; // a fork that keeps the record to the provider that admitted the window
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
            harness.readCalls = harness.readCalls.concat([{ op: "floatingFrame" }]);
            const f = floatings[String(window(w).internalId)];
            return f ? Qt.rect(f.x, f.y, f.width, f.height) : Qt.rect(0, 0, 0, 0);
        }
        function registerProvider(item) {
            harness.facadeCalls = harness.facadeCalls.concat([{ op: "registerProvider" }]);
            return providerAnswer;
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
            harness.readCalls = harness.readCalls.concat([{ op: "windowBinding" }]);
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
        function snapshot() {
            harness.readCalls = harness.readCalls.concat([{ op: "snapshot" }]);
            if (snapshotSilences > 0) {
                snapshotSilences -= 1;
                return null;
            }
            return { entries: entries };
        }
        function hasTree() {
            harness.readCalls = harness.readCalls.concat([{ op: "hasTree" }]);
            return treeAlive;
        }
        function masterWindowRect() {
            harness.readCalls = harness.readCalls.concat([{ op: "masterWindowRect" }]);
            return masterRect;
        }
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
        if (scenario === "publication") {
            try {
                runPublication();
            } catch (e) {
                fail("harness threw: " + e);
                done = true;
            }
            return;
        }
        if (scenario === "read-pipeline") {
            try {
                runReadPipeline();
            } catch (e) {
                fail("harness threw: " + e);
                done = true;
            }
            return;
        }
        if (scenario === "provider-rules") {
            try {
                runProviderRules();
            } catch (e) {
                fail("harness threw: " + e);
                done = true;
            }
            return;
        }
        if (scenario === "late-memory") {
            try {
                runLateMemory();
            } catch (e) {
                fail("harness threw: " + e);
                done = true;
            }
            return;
        }
        if (scenario === "refused-provider") {
            try {
                runRefusedProvider();
            } catch (e) {
                fail("harness threw: " + e);
                done = true;
            }
            return;
        }
        if (scenario === "stranded") {
            try {
                runStranded();
            } catch (e) {
                fail("harness threw: " + e);
                done = true;
            }
            return;
        }
        if (scenario === "unload") {
            try {
                runUnload();
            } catch (e) {
                fail("harness threw: " + e);
                done = true;
            }
            return;
        }
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
        setupView();
        // The real script (staged or checkout): its onCompleted adopts the open windows.
        const base = "file://" + packagesRoot + "/scripts/plasmafusion-placement/contents/ui/";
        const component = Qt.createComponent(base + "main.qml");
        if (component.status !== Component.Ready) {
            fail("main.qml did not load: " + component.errorString());
            return "";
        }
        return adopt(component.createObject(harness));
    }

    // The view and the three windows, before any script.
    function setupView() {
        const ws = KWinStubs.Workspace;
        // The stand-in Workspace is the engine's: every run starts from its declared outputs and
        // desktops, whatever an earlier run left (a second display, a desktop of an output's own).
        ws.screens = Qt.binding(() => [ws.activeScreen]);
        ws.outputDesktops = ({});
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
    }

    // The script made: the three windows adopted and the Tile Workspace shortcut registered.
    // The master's app key, or "" on failure.
    function adopt(made) {
        script = made;
        if (!script) {
            fail("the script was not made");
            return "";
        }
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
        trackProvider();
        return masterKey;
    }

    // The layout provider the script made: its states are recorded from now on, one entry
    // per revision, and its label kept for the driver.
    function trackProvider() {
        for (let i = 0; i < script.data.length; ++i) {
            if (script.data[i] && script.data[i].objectName === "layoutProvider") {
                provider = script.data[i];
            }
        }
        if (!provider) {
            fail("the script made a layout provider");
            return;
        }
        follow(provider);
    }

    function follow(made) {
        provider = made;
        providerLabel = made.label;
        const take = () => { providerStates = providerStates.concat([providerState()]); };
        take();
        made.revisionChanged.connect(take);
    }

    function providerState() {
        return provider ? { revision: provider.revision, online: provider.online, capable: provider.capable,
                            active: provider.active, desktopId: provider.desktopId,
                            activityId: provider.activityId, outputName: provider.outputName,
                            views: JSON.stringify(provider.views === undefined ? null : provider.views) } : null;
    }

    // The provider moved `moves` revisions since the state `before` and now reads `fields`.
    function expectProvider(what, before, moves, fields) {
        const now = providerState();
        if (!now || !before) {
            fail(what + ": the script's layout provider is there");
            return;
        }
        if (now.revision !== before.revision + moves) {
            fail(what + ": the provider's revision moved " + (now.revision - before.revision) + " time(s), not " + moves);
        }
        for (const field in fields) {
            if (now[field] !== fields[field]) {
                fail(what + ": the provider's " + field + " is " + JSON.stringify(now[field])
                     + ", not " + JSON.stringify(fields[field]));
            }
        }
    }

    // A provider's RequestName calls on the stand-in session bus. One engine runs every
    // scenario, so a run's own are those for its provider's name.
    function identityRequests(p) {
        return DBusStubs.SessionBus.calls.filter(c => c.message.member === "RequestName" && c.message.arguments
                                                 && c.message.arguments[0] === p.identityName);
    }

    // One RequestName, as the layout probe asks for its own name: for the name the lifetime
    // label makes, to the bus itself, without queueing (flag 4), with an explicit signature so
    // the plugin sends the flags as a uint32. The pending reply, for the test to answer.
    function expectIdentityRequest(what, p) {
        if (p.identityName !== "org.plasmafusion.LayoutProvider.p" + p.label) {
            fail(what + ": the identity name is the prefix and the lifetime label (got " + p.identityName + ")");
        }
        const requests = identityRequests(p);
        if (requests.length !== 1) {
            fail(what + ": one RequestName for the identity name (got " + requests.length + ")");
            return null;
        }
        const m = requests[0].message;
        if (m.service !== "org.freedesktop.DBus" || m.path !== "/org/freedesktop/DBus" || m.iface !== "org.freedesktop.DBus"
                || m.signature !== "(su)" || m.arguments.length !== 2 || m.arguments[1] !== 4) {
            fail(what + ": RequestName goes to the bus without queueing, (su) with flag 4 (got " + JSON.stringify(m) + ")");
        }
        return requests[0].reply;
    }

    // A lifetime label that owes nothing to the native token (P0's probe once derived it from
    // the token, so every refused lifetime shared one).
    function expectOwnLabel(what, token) {
        const bare = token.replace(/^\{|\}$/g, "");
        if (!/^[0-9a-f]{32}$/.test(providerLabel) || providerLabel === Qt.md5(token) || providerLabel === Qt.md5(bare)) {
            fail(what + ": the provider's label is its own, not the token's (got " + providerLabel + ")");
        }
    }

    // The layout provider's reader script as plasmashell runs it: `panels()` and `print()` are
    // the shell's, each panel lists its widgets by applet id, and a widget reads its saved
    // config. Fakes stand in for them; the script's printed answer, parsed.
    function runReaderScript(script, panelWidgets) {
        let printed = null;
        const panelsFake = () => panelWidgets.map(widgets => ({
            widgets: type => widgets.filter(w => w.type === type).map(w => ({
                id: w.id, currentConfigGroup: [],
                readConfig: function (key, fallback) {
                    return JSON.stringify(this.currentConfigGroup) === JSON.stringify(["General"]) && key === "layoutRequest"
                        ? w.text : fallback;
                }
            }))
        }));
        (new Function("panels", "print", script))(panelsFake, text => { printed = text; });
        return printed === null ? null : JSON.parse(printed);
    }

    function query(consumer, request, extra) {
        return JSON.stringify(Object.assign({ consumer: consumer, request: request, version: 1, intent: "query",
                                              outputName: "Virtual-1" }, extra || {}));
    }

    // The layout provider's writer script as plasmashell runs it: each panel lists its widgets
    // by applet id, and a widget writes its config in the group it was given. Fakes stand in
    // for them; what the script printed, and every write it made.
    function runWriterScript(script, panelWidgets) {
        let printed = null;
        const writes = [];
        const panelsFake = () => panelWidgets.map(widgets => ({
            widgets: type => widgets.filter(w => w.type === type).map(w => ({
                id: w.id, currentConfigGroup: [],
                writeConfig: function (key, value) {
                    writes.push({ id: w.id, group: JSON.stringify(this.currentConfigGroup), key: key, value: value });
                }
            }))
        }));
        (new Function("panels", "print", script))(panelsFake, text => { printed = text; });
        return { printed: printed, writes: writes };
    }

    // A value as JSON with its keys sorted at every level, to compare frames whatever order
    // their fields were made in.
    function canonical(value) {
        if (value === null || value === undefined || typeof value !== "object") {
            return JSON.stringify(value === undefined ? null : value);
        }
        if (Array.isArray(value)) {
            return "[" + value.map(canonical).join(",") + "]";
        }
        return "{" + Object.keys(value).sort().map(key => JSON.stringify(key) + ":" + canonical(value[key])).join(",") + "}";
    }

    // The frames the writer's call `index` carries, by widget, as the shell stores them when
    // the clock's widgets `ids` are on a panel.
    function framesOf(p, index, ids) {
        const frames = {};
        if (!p.writer || index >= p.writer.callLog.length) {
            return frames;
        }
        const run = runWriterScript(p.writer.callLog[index][0],
                                    [ids.map(id => ({ type: "org.plasmafusion.clockpill", id: id }))]);
        for (const write of run.writes) {
            frames[write.id] = JSON.parse(write.value);
        }
        return frames;
    }

    // The frame an online provider sends a row: the version, the request it answers, the
    // provider's lifetime and the state's order, then `fields` (the state, or the refusal).
    function frameWanted(p, row, fields) {
        return Object.assign({ version: 1, consumer: row.consumer, request: row.request, epoch: p.label,
                               identityName: p.identityName, backendOwner: ":1.42", revision: p.revision,
                               status: "online" }, fields);
    }

    // The publication side of the layout provider's pipeline, on the real script: each request
    // and refusal the last read found is answered in its clock's response field, by one shell
    // script call on the connection the requests came from; a frame says whether a session tiles
    // the bar's own view - its output, that output's current desktop, the current activity - and
    // no other; a widget is written again only when what its frame says changes - a new request,
    // a state change, its view, a new shell, or its return to the read - and never during a read
    // or another publication, the wakes and state changes meanwhile waiting and coalescing; a
    // failed publication changes no record and lets the pipeline go on; the retirement sends the
    // offline frame to every request and refusal it kept, then releases the name.
    function runPublication() {
        if (setup() === "") {
            done = true;
            return;
        }
        const ws = KWinStubs.Workspace;
        const p = provider;
        const w = p.writer;
        if (!w || w.calls !== 0 || !p.capable) {
            fail("publication: a capable provider whose writer has written nothing yet (writer " + (w ? w.calls : "none")
                 + ", capable " + p.capable + ")");
            done = true;
            return;
        }
        // A second output, on the same desktop and activity: a bar there shares everything with
        // the session's view but its output.
        const second = { name: "Virtual-2", geometry: Qt.rect(1440, 0, 1440, 900), devicePixelRatio: 1 };
        ws.screens = [ws.activeScreen, second];
        const otherDesktop = { id: 12 };
        const thirdDesktop = { id: 13 };
        DBusStubs.SessionBus.answer(expectIdentityRequest("publication", p), [{ value: 1 }]);
        p.identityLookup.finished([":1.42"]);
        p.shellLookup.finished([":1.9"]);
        const hostile = "q\"'\\\n</s>${x}\u2028\u2029";
        const rows = [
            { id: 1, consumer: "c1", request: 1, version: 1, intent: "query", outputName: "Virtual-1" },
            { id: 3, consumer: hostile, request: 3, version: 1, intent: "query", outputName: "Virtual-1" },
            { id: 5, consumer: "c5", request: 5, version: 1, intent: "query", outputName: "Gone-1" },
            { id: 12, consumer: "c12", request: 12, version: 2, intent: "query", outputName: "Virtual-1" },
            { id: 21, consumer: "c21", request: 21, version: 1, intent: "query", outputName: "Virtual-2" }
        ];
        // The rows as the clocks hold them now: a later step renews one request at a time.
        const current = rows.map(row => Object.assign({}, row));
        const renew = (id, request) => {
            current.find(row => row.id === id).request = request;
        };
        const retarget = (id, request, outputName) => {
            Object.assign(current.find(row => row.id === id), { request: request, outputName: outputName });
        };
        const now = () => JSON.stringify(current);
        const row = id => current.find(entry => entry.id === id);
        if (w.calls !== 0) {
            fail("publication: nothing is published before the read comes back (writes " + w.calls + ")");
        }
        p.reader.finished([now()]);
        // One publication, right after the read, to the connection the requests came from.
        if (w.calls !== 1 || w.service !== ":1.9" || w.path !== "/PlasmaShell" || w.dbusInterface !== "org.kde.PlasmaShell"
                || w.method !== "evaluateScript" || w.callLog[0].length !== 1) {
            fail("publication: the read's answers go out by evaluateScript on the connection the requests came from (got "
                 + w.calls + " " + w.service + " " + w.path + " " + w.dbusInterface + " " + w.method + ")");
            done = true;
            return;
        }
        // The writer script, run as the shell runs it: the clock's widgets only, each in the General
        // group's response field, the frames carried as data (no raw line separator in the code).
        const script = w.callLog[0][0];
        if (/[\u2028\u2029]/.test(script)) {
            fail("publication: the writer script carries no raw line separator: the frames travel as data");
        }
        const clock = "org.plasmafusion.clockpill";
        const run = runWriterScript(script, [
            [{ type: clock, id: 1 }, { type: "org.kde.plasma.digitalclock", id: 3 }, { type: clock, id: 3 }],
            [{ type: clock, id: 5 }, { type: clock, id: 12 }, { type: clock, id: 99 }, { type: clock, id: 21 }]
        ]);
        const general = JSON.stringify(["General"]);
        const targets = run.writes.map(write => [write.id, write.group, write.key]);
        if (JSON.stringify(targets) !== JSON.stringify([[1, general, "layoutResponse"], [3, general, "layoutResponse"],
                                                       [5, general, "layoutResponse"], [12, general, "layoutResponse"],
                                                       [21, general, "layoutResponse"]])
                || String(run.printed) !== "5") {
            fail("publication: the clock's widgets that asked are written, each in its response field, and counted (got "
                 + JSON.stringify(targets) + ", printed " + run.printed + ")");
        }
        // Each frame: the version, the request it answers, the provider's lifetime, the state's
        // order and the state - the capability, the bar's view as the provider resolves it from
        // the bar's output (none for an output it does not know) and whether a session tiles it;
        // a refusal carries its reason instead of the state. Nothing else.
        const view = { desktopId: "11", activityId: "a", outputName: "Virtual-1" };
        const secondView = { desktopId: "11", activityId: "a", outputName: "Virtual-2" };
        const first = {};
        for (const write of run.writes) {
            first[write.id] = JSON.parse(write.value);
        }
        const wanted = {
            1: frameWanted(p, rows[0], { capable: true, view: view, tiled: false }),
            3: frameWanted(p, rows[1], { capable: true, view: view, tiled: false }),
            5: frameWanted(p, rows[2], { capable: true, view: null, tiled: false }),
            12: frameWanted(p, rows[3], { refused: "version" }),
            21: frameWanted(p, rows[4], { capable: true, view: secondView, tiled: false })
        };
        for (const id of [1, 3, 5, 12, 21]) {
            if (canonical(first[id]) !== canonical(wanted[id])) {
                fail("publication: the frame for widget " + id + " (got " + canonical(first[id]) + ", not "
                     + canonical(wanted[id]) + ")");
            }
        }
        const atFirst = p.revision;
        // While it is outstanding a wake reads nothing and a state change publishes nothing.
        p.wake.activated();
        if (p.shellLookup.calls !== 1) {
            fail("publication: no read starts while a publication is outstanding (lookups " + p.shellLookup.calls + ")");
        }
        tileShortcut.activated();
        if (!p.active || p.revision !== atFirst + 1) {
            fail("publication: the toggle started a session (active " + p.active + ", revision " + p.revision + ")");
        }
        const all = [1, 3, 5, 12, 21];
        const ids = frames => JSON.stringify(Object.keys(frames).sort());
        // A session on Virtual-1 tiles widgets 1 and 3's view, never 21's on Virtual-2.
        const sessionTold = got => ids(got) === JSON.stringify(["1", "3"]) && got[1].tiled === true && got[3].tiled === true;
        let since = Date.now();
        // The revision before a view change, for the step that checks it moved once.
        let atView = 0;
        steps = [
            { name: "a state change waits for the publication", until: () => Date.now() - since >= 100, run: function () {
                if (w.calls !== 1) {
                    fail("publication: a state change waits for the outstanding publication (writes " + w.calls + ")");
                }
                // The shell says it wrote four of the five: the count is said with the publication.
                w.finished([4]);
                // Then it goes out, to the widgets it changes and only those: the bars on the
                // session's view, not the one on the other output.
                const got = framesOf(p, 1, all);
                if (w.calls !== 2 || !sessionTold(got)
                        || canonical(got[1]) !== canonical(frameWanted(p, rows[0], { capable: true, view: view, tiled: true }))
                        || canonical(got[3]) !== canonical(frameWanted(p, rows[1], { capable: true, view: view, tiled: true }))) {
                    fail("publication: a session on the bars' view is told to the widgets it changes, once the publication"
                         + " answered, and to no bar on another output (writes " + w.calls + ", got " + canonical(got) + ")");
                }
                since = Date.now();
            } },
            { name: "the wake waits for every publication", until: () => Date.now() - since >= 100, run: function () {
                if (p.shellLookup.calls !== 1) {
                    fail("publication: the wake waits while a publication is outstanding (lookups " + p.shellLookup.calls + ")");
                }
                w.finished([2]);
            } },
            { name: "the wake's read", until: () => p.shellLookup.calls === 2, run: function () {
                // The same requests and the same state: nothing is written again.
                p.shellLookup.finished([":1.9"]);
                p.reader.finished([now()]);
                if (w.calls !== 2 || p.reading || p.publishing) {
                    fail("publication: a read that finds nothing new publishes nothing (writes " + w.calls + ")");
                }
                p.wake.activated();
            } },
            { name: "a state change during a read", until: () => p.shellLookup.calls === 3, run: function () {
                p.shellLookup.finished([":1.9"]);
                // The read is in flight: the untoggle waits for its end.
                tileShortcut.activated();
                since = Date.now();
            } },
            { name: "the read's end releases it", until: () => Date.now() - since >= 100, run: function () {
                if (w.calls !== 2) {
                    fail("publication: a state change waits for the read in flight (writes " + w.calls + ")");
                }
                p.reader.finished([now()]);
                const got = framesOf(p, 2, all);
                if (w.calls !== 3 || ids(got) !== JSON.stringify(["1", "3"]) || got[1].tiled !== false || got[3].tiled !== false) {
                    fail("publication: the untoggle goes out at the read's end, to the widgets it changes (writes " + w.calls
                         + ", got " + canonical(got) + ")");
                }
                w.finished([2]);
                p.wake.activated();
            } },
            { name: "a widget that left the read", until: () => p.shellLookup.calls === 4, run: function () {
                // Widget 5 is not read (its request went): nothing to tell, and its record goes.
                p.shellLookup.finished([":1.9"]);
                p.reader.finished([JSON.stringify(current.filter(entry => entry.id !== 5))]);
                if (w.calls !== 3 || p.sent[5] !== undefined || p.sent[1] === undefined) {
                    fail("publication: a widget no longer read is told nothing and forgotten (writes " + w.calls + ", record "
                         + JSON.stringify(Object.keys(p.sent)) + ")");
                }
                p.wake.activated();
            } },
            { name: "a widget that came back", until: () => p.shellLookup.calls === 5, run: function () {
                // Read again, it is told again, and alone.
                p.shellLookup.finished([":1.9"]);
                p.reader.finished([now()]);
                const got = framesOf(p, 3, all);
                if (w.calls !== 4 || ids(got) !== JSON.stringify(["5"])
                        || canonical(got[5]) !== canonical(frameWanted(p, rows[2], { capable: true, view: null, tiled: false }))) {
                    fail("publication: a widget read again is told again, alone (writes " + w.calls + ", got " + canonical(got) + ")");
                }
                w.finished([1]);
                p.wake.activated();
            } },
            { name: "a new request", until: () => p.shellLookup.calls === 6, run: function () {
                p.shellLookup.finished([":1.9"]);
                renew(1, 2);
                p.reader.finished([now()]);
                // Answered alone, with the state as it stands (the revision has not moved).
                const got = framesOf(p, 4, all);
                if (w.calls !== 5 || ids(got) !== JSON.stringify(["1"])
                        || canonical(got[1]) !== canonical(frameWanted(p, row(1), { capable: true, view: view, tiled: false }))) {
                    fail("publication: a new request is answered alone, with the state as it stands (writes " + w.calls
                         + ", got " + canonical(got) + ")");
                }
                // A wake during it, then the publication fails: the failure changes no record and the
                // pipeline goes on - the wake's read follows, and writes the frame again.
                p.wake.activated();
                w.failed();
                if (p.publishing) {
                    fail("publication: a failed publication ends");
                }
            } },
            { name: "the read after a failed publication", until: () => p.shellLookup.calls === 7, run: function () {
                p.shellLookup.finished([":1.9"]);
                p.reader.finished([now()]);
                if (w.calls !== 6 || ids(framesOf(p, 5, all)) !== JSON.stringify(["1"])) {
                    fail("publication: what a failed publication said is written again (writes " + w.calls + ")");
                }
                w.finished([1]);
                p.wake.activated();
            } },
            { name: "a new shell", until: () => p.shellLookup.calls === 8, run: function () {
                // Another shell connection was told nothing: every frame goes to it.
                p.shellLookup.finished([":1.10"]);
                p.reader.finished([now()]);
                if (w.calls !== 7 || w.service !== ":1.10" || ids(framesOf(p, 6, all)) !== JSON.stringify(["1", "12", "21", "3", "5"])) {
                    fail("publication: a new shell is told every frame (writes " + w.calls + " to " + w.service + ")");
                }
                w.finished([5]);
                tileShortcut.activated();
                since = Date.now();
            } },
            { name: "the toggle", until: () => w.calls === 8 || Date.now() - since >= 300, run: function () {
                const got = framesOf(p, 7, all);
                if (w.calls !== 8 || !sessionTold(got)) {
                    fail("publication: the toggle is told to the bars on its view, not to the one on another output (writes "
                         + w.calls + ", got " + canonical(got) + ")");
                }
                w.finished([2]);
                // The session's output switches to another desktop (the session stays where it
                // was), as KWin says it - a signal for that output: the bars there are told at once,
                // at a newer revision, with no read.
                atView = p.revision;
                ws.outputDesktops = { "Virtual-1": otherDesktop };
                ws.currentDesktopChanged();
                since = Date.now();
            } },
            { name: "a desktop switch on the session's output", until: () => w.calls === 9 || Date.now() - since >= 300, run: function () {
                const got = framesOf(p, 8, all);
                if (w.calls !== 9 || p.shellLookup.calls !== 8 || p.revision !== atView + 1 || ids(got) !== JSON.stringify(["1", "3"])
                        || got[1].tiled !== false || got[3].tiled !== false || got[1].view.desktopId !== "12"
                        || got[3].view.desktopId !== "12" || got[1].revision !== p.revision) {
                    fail("publication: a desktop switch on the session's output is told at once, at a newer revision, to the"
                         + " bars there, none tiled (writes " + w.calls + ", lookups " + p.shellLookup.calls + ", revision "
                         + p.revision + " after " + atView + ", got " + canonical(got) + ")");
                }
                w.finished([2]);
                // Then widget 3 asks again: its answer alone - the others were told already.
                renew(3, 4);
                p.wake.activated();
            } },
            { name: "a request after the drift", until: () => p.shellLookup.calls === 9, run: function () {
                p.shellLookup.finished([":1.10"]);
                p.reader.finished([now()]);
                const got = framesOf(p, 9, all);
                if (w.calls !== 10 || ids(got) !== JSON.stringify(["3"]) || got[3].request !== 4 || got[3].view.desktopId !== "12"
                        || got[3].revision !== p.revision) {
                    fail("publication: after the drift a new request is answered alone, the drift told already (writes "
                         + w.calls + ", got " + canonical(got) + ")");
                }
                w.finished([1]);
                // A signal that changes no bar's view moves nothing.
                atView = p.revision;
                ws.currentDesktopChanged();
                since = Date.now();
            } },
            { name: "a signal that changes nothing", until: () => Date.now() - since >= 200, run: function () {
                if (p.revision !== atView || w.calls !== 10) {
                    fail("publication: a signal that changes no bar's view moves nothing (revision " + p.revision + " after "
                         + atView + ", writes " + w.calls + ")");
                }
                // Widget 1 asks again; its read will cross a view change.
                renew(1, 3);
                p.wake.activated();
            } },
            { name: "a read that crosses a view change", until: () => p.shellLookup.calls === 10, run: function () {
                p.shellLookup.finished([":1.10"]);
                // The desktop comes back while the read is out, and the read comes back in the same
                // turn, before the change is resolved: the answer carries the view as the state tells
                // it - the stored one, at the revision it goes with - never a newer one.
                atView = p.revision;
                ws.outputDesktops = ({});
                ws.currentDesktopChanged();
                p.reader.finished([now()]);
                const got = framesOf(p, 10, all);
                if (w.calls !== 11 || ids(got) !== JSON.stringify(["1"]) || got[1].request !== 3 || got[1].view.desktopId !== "12"
                        || got[1].revision !== atView) {
                    fail("publication: a read that crosses a view change answers with the view its revision tells (writes "
                         + w.calls + ", got " + canonical(got) + ")");
                }
                w.finished([1]);
                since = Date.now();
            } },
            { name: "the crossed change goes out", until: () => w.calls === 12 || Date.now() - since >= 300, run: function () {
                // Then the change: 1 and 3 back on the session's view, at a newer revision.
                const got = framesOf(p, 11, all);
                if (w.calls !== 12 || p.revision !== atView + 1 || ids(got) !== JSON.stringify(["1", "3"]) || got[1].tiled !== true
                        || got[3].tiled !== true || got[1].view.desktopId !== "11" || got[1].revision !== p.revision) {
                    fail("publication: the view change a read crossed goes out after it, at a newer revision (writes " + w.calls
                         + ", revision " + p.revision + " after " + atView + ", got " + canonical(got) + ")");
                }
                w.finished([2]);
                // The activity switched and the second output on a desktop of its own, in one turn:
                // one step, one publication.
                atView = p.revision;
                ws.currentActivity = "b";
                ws.outputDesktops = { "Virtual-2": otherDesktop };
                ws.currentDesktopChanged();
                since = Date.now();
            } },
            { name: "two view changes in one turn", until: () => w.calls === 13 || Date.now() - since >= 300, run: function () {
                const got = framesOf(p, 12, all);
                if (w.calls !== 13 || p.revision !== atView + 1 || ids(got) !== JSON.stringify(["1", "21", "3"])
                        || [1, 3, 21].some(id => got[id].tiled !== false || got[id].view.activityId !== "b")
                        || got[1].view.desktopId !== "11" || got[21].view.desktopId !== "12") {
                    fail("publication: two view changes in one turn go out once - a bar on the session's output and desktop"
                         + " but another activity is not tiled, the second output on its own desktop (writes " + w.calls
                         + ", revision " + p.revision + " after " + atView + ", got " + canonical(got) + ")");
                }
                w.finished([3]);
                // The activity back: 1 and 3 are on the session's view again.
                atView = p.revision;
                ws.currentActivity = "a";
                since = Date.now();
            } },
            { name: "the activity back", until: () => w.calls === 14 || Date.now() - since >= 300, run: function () {
                // 1 and 3 on the session's view again; 21 on its output's own desktop
                // (currentDesktopForScreen).
                const got = framesOf(p, 13, all);
                if (w.calls !== 14 || p.revision !== atView + 1 || ids(got) !== JSON.stringify(["1", "21", "3"])
                        || got[1].tiled !== true || got[3].tiled !== true
                        || canonical(got[21]) !== canonical(frameWanted(p, row(21), {
                            capable: true, view: { desktopId: "12", activityId: "a", outputName: "Virtual-2" }, tiled: false }))) {
                    fail("publication: the activity back tiles the session's view again, each bar on its own output's desktop"
                         + " (writes " + w.calls + ", got " + canonical(got) + ")");
                }
                w.finished([3]);
                // The second output unplugged: its bar's view is gone.
                atView = p.revision;
                ws.screens = [ws.activeScreen];
                since = Date.now();
            } },
            { name: "an output unplugged", until: () => w.calls === 15 || Date.now() - since >= 300, run: function () {
                const got = framesOf(p, 14, all);
                if (w.calls !== 15 || p.revision !== atView + 1 || ids(got) !== JSON.stringify(["21"]) || got[21].view !== null
                        || got[21].tiled !== false) {
                    fail("publication: an output unplugged leaves its bar with no view, told at once (writes " + w.calls + ", got "
                         + canonical(got) + ")");
                }
                w.finished([1]);
                // Plugged back, on its own desktop still: told again.
                atView = p.revision;
                ws.screens = [ws.activeScreen, second];
                since = Date.now();
            } },
            { name: "an output plugged back", until: () => w.calls === 16 || Date.now() - since >= 300, run: function () {
                const got = framesOf(p, 15, all);
                if (w.calls !== 16 || p.revision !== atView + 1 || ids(got) !== JSON.stringify(["21"]) || !got[21].view
                        || got[21].view.desktopId !== "12" || got[21].view.outputName !== "Virtual-2") {
                    fail("publication: an output plugged back gives its bar its view again (writes " + w.calls + ", got "
                         + canonical(got) + ")");
                }
                w.finished([1]);
                // Widget 21 leaves the read (its request went).
                p.wake.activated();
            } },
            { name: "a widget that left the read, its output moved", until: () => p.shellLookup.calls === 11, run: function () {
                p.shellLookup.finished([":1.10"]);
                p.reader.finished([JSON.stringify(current.filter(entry => entry.id !== 21))]);
                if (w.calls !== 16 || !p.views || p.views[21] !== undefined) {
                    fail("publication: a widget no longer read is told nothing, and its view is forgotten (writes " + w.calls
                         + ", views " + JSON.stringify(Object.keys(p.views || {})) + ")");
                }
                // Its output moves to a third desktop: no view that is kept changed, so nothing moves.
                atView = p.revision;
                ws.outputDesktops = { "Virtual-2": thirdDesktop };
                ws.currentDesktopChanged();
                since = Date.now();
            } },
            { name: "a change no kept view sees", until: () => Date.now() - since >= 200, run: function () {
                if (p.revision !== atView || w.calls !== 16) {
                    fail("publication: a change of an output no kept request is on moves nothing (revision " + p.revision
                         + " after " + atView + ", writes " + w.calls + ")");
                }
                // Widget 21 is read again: its view is resolved now - the third desktop.
                p.wake.activated();
            } },
            { name: "the widget back", until: () => p.shellLookup.calls === 12, run: function () {
                p.shellLookup.finished([":1.10"]);
                p.reader.finished([now()]);
                const got = framesOf(p, 16, all);
                if (w.calls !== 17 || ids(got) !== JSON.stringify(["21"]) || got[21].view.desktopId !== "13") {
                    fail("publication: a widget read again is told its view as it is now, not the one it left with (writes "
                         + w.calls + ", got " + canonical(got) + ")");
                }
                w.finished([1]);
                // Widget 1's panel moved to the second output: its next request names it.
                retarget(1, 4, "Virtual-2");
                p.wake.activated();
            } },
            { name: "a request for another output", until: () => p.shellLookup.calls === 13, run: function () {
                p.shellLookup.finished([":1.10"]);
                p.reader.finished([now()]);
                // Resolved for the output it names now: the second output's view, not tiled.
                const got = framesOf(p, 17, all);
                if (w.calls !== 18 || ids(got) !== JSON.stringify(["1"]) || canonical(got[1]) !== canonical(frameWanted(p, row(1), {
                        capable: true, view: { desktopId: "13", activityId: "a", outputName: "Virtual-2" }, tiled: false }))) {
                    fail("publication: a request that names another output is resolved for it (writes " + w.calls + ", got "
                         + canonical(got) + ")");
                }
                w.finished([1]);
                // Off and on in one turn: nothing new to tell (every view stays as it was told).
                tileShortcut.activated();
                tileShortcut.activated();
                since = Date.now();
            } },
            { name: "off and on in one turn", until: () => Date.now() - since >= 200, run: function () {
                if (w.calls !== 18) {
                    fail("publication: changes that end where they began tell nothing (writes " + w.calls + ")");
                }
                // The session's end and the capability lost in one turn: one publication, of the
                // state both left.
                tileShortcut.activated();
                p.nativeCapable = false;
                since = Date.now();
            } },
            { name: "two changes in one turn", until: () => w.calls > 18 || Date.now() - since >= 300, run: function () {
                const got = framesOf(p, 18, all);
                if (w.calls !== 19 || ids(got) !== JSON.stringify(["1", "21", "3", "5"]) || got[1].capable !== false
                        || got[1].tiled !== false || got[5].capable !== false || got[21].capable !== false
                        || got[1].revision !== p.revision) {
                    fail("publication: two changes in one turn go out once, as they left the state (writes " + w.calls
                         + ", got " + canonical(got) + ")");
                }
                since = Date.now();
            } },
            { name: "the retirement", until: () => Date.now() - since >= 100, run: function () {
                if (w.calls !== 19 || !p.publishing) {
                    fail("publication: one publication for two changes in one turn, still outstanding (writes " + w.calls + ")");
                }
                // With that publication outstanding, and a state change and a view change right
                // before it, the retirement ends the one and drops the others: it moves the revision,
                // sends the offline frame to every request and refusal it kept, on the connection
                // they came from - whatever is in flight there - then releases the name.
                const order = [];
                p.revisionChanged.connect(() => {
                    if (!p.online) {
                        order.push("revision");
                    }
                });
                w.callsChanged.connect(() => order.push("frame"));
                p.identityRelease.callsChanged.connect(() => order.push("release"));
                tileShortcut.activated();
                ws.outputDesktops = { "Virtual-1": otherDesktop };
                ws.currentDesktopChanged();
                p.retire();
                if (JSON.stringify(order) !== JSON.stringify(["revision", "frame", "release"])) {
                    fail("publication: the retirement moves the revision, then sends the offline frame, then releases the name"
                         + " (got " + JSON.stringify(order) + ")");
                }
                const got = framesOf(p, 19, all);
                for (const kept of current) {
                    const offline = { version: 1, consumer: kept.consumer, request: kept.request, epoch: p.label,
                                      identityName: p.identityName, backendOwner: ":1.42", revision: p.revision,
                                      status: "offline", capable: false, view: null, tiled: false };
                    if (canonical(got[kept.id]) !== canonical(offline)) {
                        fail("publication: the offline frame for widget " + kept.id + " (got " + canonical(got[kept.id])
                             + ", not " + canonical(offline) + ")");
                    }
                }
                if (w.calls !== 20 || w.service !== ":1.10" || p.publishing) {
                    fail("publication: the offline frame goes out once, where the requests came from, and ends the"
                         + " publication in flight (writes " + w.calls + " to " + w.service + ", publishing " + p.publishing + ")");
                }
                // Offline, the views are watched no more: neither the view change queued before the
                // retirement nor one after it moves or publishes anything.
                atView = p.revision;
                ws.outputDesktops = ({});
                ws.currentDesktopChanged();
                since = Date.now();
            } },
            { name: "after the retirement", until: () => Date.now() - since >= 200, run: function () {
                // The change queued before the retirement and the view change after it published
                // nothing, and late answers - the outstanding publication's among them - reach
                // nothing.
                if (w.calls !== 20 || p.revision !== atView) {
                    fail("publication: neither a change queued before the retirement nor a view change after it moves or"
                         + " publishes anything (writes " + w.calls + ", revision " + p.revision + " after " + atView + ")");
                }
                w.finished([4]);
                w.failed();
                p.shellLookup.failed();
                p.reader.finished([now()]);
                p.wake.activated();
                if (w.calls !== 20 || p.shellLookup.calls !== 13 || p.publishing || p.reading) {
                    fail("publication: after the retirement nothing is published or read (writes " + w.calls + ", lookups "
                         + p.shellLookup.calls + ")");
                }
                // The stand-in Workspace is the engine's: its outputs, desktops and activity as the
                // later runs expect them.
                ws.screens = Qt.binding(() => [ws.activeScreen]);
                ws.outputDesktops = ({});
                ws.currentActivity = "a";
            } }
        ];
        stepSince = Date.now();
        stepper.start();
    }

    // The read side of the layout provider's pipeline, on the real script: a dedicated wake
    // shortcut with no key; one read once the identity is ready and for each later wake, the
    // wakes during a read coalesced into one later read; the shell's owner looked up first and
    // the requests read from it; the shell side bounded and copying only what P1 needs, the
    // provider checking every row again with its version, intent and output.
    function runReadPipeline() {
        if (setup() === "") {
            done = true;
            return;
        }
        const p = provider;
        const clock = "org.plasmafusion.clockpill";
        // The wake: a shortcut of its own, needing no key, that toggles nothing.
        if (!p.wake || p.wake.name !== "Plasma Fusion: Refresh Layout Controls" || p.wake.sequence !== ""
                || typeof p.wake.text !== "string" || p.wake.text.length === 0) {
            fail("read-pipeline: the wake is the shortcut \"Plasma Fusion: Refresh Layout Controls\", with no key");
            done = true;
            return;
        }
        // Before the identity is ready a wake reads nothing; once it is, one read starts.
        p.wake.activated();
        p.wake.activated();
        if (p.shellLookup.calls !== 0 || calls("createTile").length !== 0) {
            fail("read-pipeline: a wake before the identity is ready reads nothing and toggles nothing");
        }
        DBusStubs.SessionBus.answer(expectIdentityRequest("read-pipeline", p), [{ value: 1 }]);
        p.identityLookup.finished([":1.42"]);
        if (JSON.stringify(p.shellLookup.callLog) !== JSON.stringify([["org.kde.plasmashell"]])
                || p.shellLookup.method !== "GetNameOwner") {
            fail("read-pipeline: one read once the identity is ready, starting with the shell's owner (got "
                 + JSON.stringify(p.shellLookup.callLog) + ")");
        }
        // The read goes to the shell's unique connection.
        p.shellLookup.finished([":1.9"]);
        const r = p.reader;
        if (r.calls !== 1 || r.service !== ":1.9" || r.path !== "/PlasmaShell" || r.dbusInterface !== "org.kde.PlasmaShell"
                || r.method !== "evaluateScript" || r.callLog[0].length !== 1) {
            fail("read-pipeline: the requests are read with evaluateScript on the shell's unique connection (got "
                 + r.calls + " " + r.service + " " + r.path + " " + r.dbusInterface + " " + r.method + ")");
            done = true;
            return;
        }
        // The shell side, run as plasmashell runs it: at most 16 widgets, at most 2048
        // characters, a well-formed consumer and request, the clock's widgets only, and only
        // the fields P1 needs; widget data travels as JSON, never as code.
        const script = r.callLog[0][0];
        // A request of exactly 2048 characters: the default outputName ("Virtual-1") replaced by
        // a pad that makes up the rest.
        const wide = query("c-wide", 7);
        const pad = "x".repeat(2048 - wide.length + "Virtual-1".length);
        const exact = query("c-wide", 7, { outputName: pad });
        const hostile = "q\"'\\\n</s>${x}";
        const rows = runReaderScript(script, [
            [{ type: clock, id: 1, text: query("c1", 1) },
             { type: "org.kde.plasma.digitalclock", id: 2, text: query("c2", 2) },
             { type: clock, id: 3, text: query(hostile, 3, { title: "not copied", token: "not copied" }) },
             { type: clock, id: 4, text: "{not json" },
             { type: clock, id: 5, text: query("", 5) },
             { type: clock, id: 6, text: query("c".repeat(129), 6) },
             { type: clock, id: 7, text: query("c7", 0) },
             { type: clock, id: 8, text: query("c8", 2147483647) },
             { type: clock, id: 9, text: query("c9", 1.5) },
             { type: clock, id: 10, text: exact },
             { type: clock, id: 11, text: exact + " " }],
            [{ type: clock, id: 12, text: query("c12", 12, { version: 2 }) }]
        ]);
        if (exact.length !== 2048) {
            fail("read-pipeline: the test's exact request is 2048 characters (got " + exact.length + ")");
        }
        const ids = rows ? rows.map(row => row.id) : null;
        if (JSON.stringify(ids) !== JSON.stringify([1, 3, 10, 12])) {
            fail("read-pipeline: the shell side keeps the clock's well-formed requests of at most 2048 characters (got "
                 + JSON.stringify(ids) + ")");
        }
        const third = rows ? rows.find(row => row.id === 3) : null;
        if (!third || third.consumer !== hostile || JSON.stringify(Object.keys(third).sort())
                !== JSON.stringify(["consumer", "id", "intent", "outputName", "request", "version"])) {
            fail("read-pipeline: a row carries the consumer as sent and only the fields P1 needs (got " + JSON.stringify(third) + ")");
        }
        const many = [];
        for (let i = 1; i <= 17; ++i) {
            many.push({ type: clock, id: 100 + i, text: query("m" + i, i) });
        }
        const bounded = runReaderScript(script, [many.slice(0, 9), many.slice(9)]);
        if (!bounded || bounded.length !== 16 || bounded[15].id !== 116) {
            fail("read-pipeline: the shell side reads at most 16 widgets (got " + (bounded ? bounded.length : null) + ")");
        }
        // The answer: the provider checks every row again; a query of version 1 for a named
        // output is a request, anything else with a well-formed identity a refusal, kept with its
        // reason; a row with no well-formed identity is dropped.
        const answer = JSON.stringify([
            { id: 1, consumer: "c1", request: 1, version: 1, intent: "query", outputName: "Virtual-1" },
            { id: 3, consumer: hostile, request: 3, version: 1, intent: "query", outputName: "Virtual-1" },
            { id: 12, consumer: "c12", request: 12, version: 2, intent: "query", outputName: "Virtual-1" },
            { id: 13, consumer: "c13", request: 13, intent: "query", outputName: "Virtual-1" },
            { id: 14, consumer: "c14", request: 14, version: 1, intent: "prepare", outputName: "Virtual-1" },
            { id: 15, consumer: "c15", request: 15, version: 1, intent: "query", outputName: "" },
            { id: 16, consumer: "c16", request: 16, version: 1, intent: "query", outputName: "o".repeat(129) },
            { id: 17, consumer: "", request: 17, version: 1, intent: "query", outputName: "Virtual-1" },
            { id: 18, consumer: "c18", request: 0, version: 1, intent: "query", outputName: "Virtual-1" }
        ]);
        r.finished([answer]);
        // The read's answers go out at once (the publication run checks them); answered here, so
        // the pipeline goes on.
        if (p.writer.calls !== 1) {
            fail("read-pipeline: the read's answers go out once (writes " + p.writer.calls + ")");
        }
        p.writer.finished([7]);
        const requests = JSON.stringify(p.requests.map(q => [q.id, q.consumer, q.request, q.outputName]));
        if (requests !== JSON.stringify([[1, "c1", 1, "Virtual-1"], [3, hostile, 3, "Virtual-1"]])) {
            fail("read-pipeline: the version-1 queries for a named output are the requests (got " + requests + ")");
        }
        const refusals = JSON.stringify(p.refusals.map(q => [q.id, q.reason]));
        if (refusals !== JSON.stringify([[12, "version"], [13, "version"], [14, "intent"], [15, "output"], [16, "output"]])) {
            fail("read-pipeline: every other row with a well-formed identity is refused with its reason (got " + refusals + ")");
        }
        let since = Date.now();
        // What a read that ends without an answer must keep: the last read's requests and
        // refusals, taken once the second read has stored them.
        const kept = () => JSON.stringify([p.requests, p.refusals]);
        let before = "";
        steps = [
            // The wakes that came before the identity were its read: nothing more follows.
            { name: "no read owed to the early wakes", until: () => Date.now() - since >= 300, run: function () {
                if (p.shellLookup.calls !== 1 || p.reading) {
                    fail("read-pipeline: the wakes before the identity are the identity's read (lookups "
                         + p.shellLookup.calls + ")");
                }
                // A wake reads; three more during that read make one later read.
                p.wake.activated();
                p.wake.activated();
                p.wake.activated();
                p.wake.activated();
                if (p.shellLookup.calls !== 2) {
                    fail("read-pipeline: a wake reads, and no second read starts while one runs (lookups "
                         + p.shellLookup.calls + ")");
                }
                p.shellLookup.finished([":1.9"]);
                p.reader.finished([answer]);
            } },
            { name: "the coalesced read", until: () => p.shellLookup.calls > 2, run: function () {
                if (p.shellLookup.calls !== 3) {
                    fail("read-pipeline: the wakes during a read make one later read (lookups " + p.shellLookup.calls + ")");
                }
                before = kept();
                if (p.requests.length !== 2 || p.refusals.length !== 5) {
                    fail("read-pipeline: the second read stored its requests and refusals (got " + before + ")");
                }
                // A shell owner that is no unique connection is not read from, and the read
                // keeps the lists.
                p.shellLookup.finished(["org.kde.plasmashell"]);
                if (p.reader.calls !== 2 || p.reading) {
                    fail("read-pipeline: a shell owner that is no unique connection is not read from");
                }
                if (kept() !== before) {
                    fail("read-pipeline: a read from no unique connection keeps the requests and refusals");
                }
                // A failed owner lookup ends the read and keeps the lists.
                p.wake.activated();
                p.shellLookup.failed();
                if (p.reading || kept() !== before) {
                    fail("read-pipeline: a failed lookup ends the read and keeps the requests and refusals");
                }
            } },
            { name: "a read after a failed lookup", until: () => !p.reading, run: function () {
                p.wake.activated();
                if (p.shellLookup.calls !== 5) {
                    fail("read-pipeline: a failed lookup ends the read, and the next wake reads (lookups "
                         + p.shellLookup.calls + ")");
                }
                p.shellLookup.finished([":1.9"]);
                // A failed or malformed answer ends the read and keeps the lists.
                p.reader.failed();
                if (p.reading || kept() !== before) {
                    fail("read-pipeline: a failed read ends the read and keeps the requests and refusals");
                }
                for (const answer of ["{not json", JSON.stringify({ rows: [] }),
                                      JSON.stringify(Array.from({ length: 17 }, (_, i) => ({
                                          id: i + 1, consumer: "c", request: i + 1, version: 1, intent: "query",
                                          outputName: "Virtual-1" })))]) {
                    p.wake.activated();
                    p.shellLookup.finished([":1.9"]);
                    p.reader.finished([answer]);
                    if (p.reading || kept() !== before) {
                        fail("read-pipeline: a malformed answer ends the read and keeps the requests and refusals ("
                             + answer.slice(0, 20) + ")");
                    }
                }
                // A retirement during a read: the answers that follow reach nothing, and the last
                // requests and refusals stay.
                p.wake.activated();
                const lookups = p.shellLookup.calls;
                const reads = p.reader.calls;
                p.retire();
                p.shellLookup.finished([":1.9"]);
                p.wake.activated();
                if (p.reading || p.reader.calls !== reads || p.shellLookup.calls !== lookups) {
                    fail("read-pipeline: after the retirement nothing is read");
                }
                if (kept() !== before) {
                    fail("read-pipeline: the retirement keeps the last requests and refusals");
                }
                // The shell's late answers - a read's and a failure - reach neither the lists nor
                // the journal (the driver counts its lines).
                p.reader.finished([JSON.stringify([])]);
                p.reader.failed();
                if (p.reading || kept() !== before) {
                    fail("read-pipeline: a late answer after the retirement reaches nothing");
                }
            } }
        ];
        stepSince = Date.now();
        stepper.start();
    }

    // The layout provider's own rules, on instances of its own (no script): nothing before
    // start(), a first state at revision 1, one move per change and only while online, start()
    // once, one move to go offline and nothing after it, and a label per instance.
    function runProviderRules() {
        const base = "file://" + packagesRoot + "/scripts/plasmafusion-placement/contents/ui/";
        const component = Qt.createComponent(base + "LayoutProvider.qml");
        if (component.status !== Component.Ready) {
            fail("provider-rules: LayoutProvider.qml did not load: " + component.errorString());
            done = true;
            return;
        }
        const p = component.createObject(harness);
        const state = () => [p.revision, p.online, p.capable, p.active, p.desktopId, p.activityId,
                             p.outputName].join("|");
        const expect = (what, wanted) => {
            if (state() !== wanted) {
                fail("provider-rules: " + what + ": got " + state() + ", not " + wanted);
            }
        };
        p.nativeCapable = true;
        p.setSession(true, "11", "a", "Virtual-1");
        expect("nothing before start()", "0|false|false|false|||");
        p.start();
        expect("start()", "1|true|true|false|||");
        follow(p);
        // A name the bus refuses (another connection holds it) is no identity: nothing is
        // looked up.
        DBusStubs.SessionBus.answer(expectIdentityRequest("provider-rules", p), [{ value: 3 }]);
        if (p.identityLookup.calls !== 0 || p.identityReady) {
            fail("provider-rules: a refused name is no identity, and nothing is looked up");
        }
        p.setSession(false, "", "", "");
        expect("a report that changes nothing", "1|true|true|false|||");
        p.setSession(true, "11", "a", "Virtual-1");
        expect("a session", "2|true|true|true|11|a|Virtual-1");
        p.start();
        expect("start() again", "2|true|true|true|11|a|Virtual-1");
        p.setSession(true, "12", "a", "Virtual-1");
        expect("the session on another view", "3|true|true|true|12|a|Virtual-1");
        p.nativeCapable = false;
        expect("capability lost", "4|true|false|true|12|a|Virtual-1");
        p.retire();
        expect("retire()", "5|false|false|false|||");
        p.retire();
        p.nativeCapable = true;
        p.setSession(true, "11", "a", "Virtual-1");
        p.start();
        expect("nothing after retire()", "5|false|false|false|||");
        // The name is released once, by the first retire(), granted or not.
        if (JSON.stringify(p.identityRelease.callLog) !== JSON.stringify([[p.identityName]])) {
            fail("provider-rules: retire() releases the name once (got " + JSON.stringify(p.identityRelease.callLog) + ")");
        }
        const other = component.createObject(harness);
        if (!/^[0-9a-f]{32}$/.test(p.label) || other.label === p.label) {
            fail("provider-rules: each instance draws a label of its own (" + p.label + ", " + other.label + ")");
        }
        if (identityRequests(other).length !== 0 || other.identityRelease.calls !== 0) {
            fail("provider-rules: a provider that never started asks for no name and releases none");
        }
        other.destroy();
        // A granted name whose owner cannot be read is no identity either.
        const unread = component.createObject(harness);
        unread.start();
        DBusStubs.SessionBus.answer(expectIdentityRequest("provider-rules (unread owner)", unread), [{ value: 1 }]);
        unread.identityLookup.failed();
        if (unread.identityLookup.calls !== 1 || unread.identityReady || unread.selfOwner !== "") {
            fail("provider-rules: a name whose owner cannot be read is no identity");
        }
        unread.retire();
        unread.destroy();
        // A bus error is no identity.
        const denied = component.createObject(harness);
        denied.start();
        DBusStubs.SessionBus.answer(expectIdentityRequest("provider-rules (bus error)", denied), [],
                                    "org.freedesktop.DBus.Error.AccessDenied");
        if (denied.identityLookup.calls !== 0 || denied.identityReady) {
            fail("provider-rules: a bus error is no identity, and nothing is looked up");
        }
        denied.retire();
        denied.destroy();
        // An owner that is no unique connection name is no identity.
        const odd = component.createObject(harness);
        odd.start();
        DBusStubs.SessionBus.answer(expectIdentityRequest("provider-rules (odd owner)", odd), [{ value: 1 }]);
        odd.identityLookup.finished(["org.example.NotUnique"]);
        if (odd.identityReady || odd.selfOwner !== "") {
            fail("provider-rules: an owner that is no unique connection name is no identity, and is not kept (got "
                 + odd.identityReady + ", " + odd.selfOwner + ")");
        }
        odd.retire();
        odd.destroy();
        // A held identity goes with the retirement, and an owner read that arrives after it
        // makes none.
        const held = component.createObject(harness);
        // The owner is set before the flag: whatever reacts to identityReady finds it.
        let ownerAtReady = null;
        held.identityReadyChanged.connect(() => {
            if (held.identityReady) {
                ownerAtReady = held.selfOwner;
            }
        });
        held.start();
        DBusStubs.SessionBus.answer(expectIdentityRequest("provider-rules (held)", held), [{ value: 1 }]);
        held.identityLookup.finished([":1.7"]);
        if (!held.identityReady || held.selfOwner !== ":1.7" || ownerAtReady !== ":1.7") {
            fail("provider-rules: a granted name with its owner is the identity, the owner set before the flag (got "
                 + held.identityReady + ", " + held.selfOwner + ", at the flag " + ownerAtReady + ")");
        }
        held.retire();
        if (held.identityReady || held.selfOwner !== "") {
            fail("provider-rules: the retirement ends the identity");
        }
        held.destroy();
        const lateOwner = component.createObject(harness);
        lateOwner.start();
        DBusStubs.SessionBus.answer(expectIdentityRequest("provider-rules (late owner)", lateOwner), [{ value: 1 }]);
        lateOwner.retire();
        lateOwner.identityLookup.finished([":1.8"]);
        if (lateOwner.identityReady || lateOwner.selfOwner !== "") {
            fail("provider-rules: an owner read after the retirement makes no identity");
        }
        lateOwner.destroy();
        // A retirement before the answer drops the pending request: a late answer reaches
        // nothing.
        const early = component.createObject(harness);
        early.start();
        const earlyReply = expectIdentityRequest("provider-rules (early retirement)", early);
        early.retire();
        DBusStubs.SessionBus.answer(earlyReply, [{ value: 1 }]);
        if (early.registration !== null || early.identityLookup.calls !== 0 || early.identityReady) {
            fail("provider-rules: a retirement drops the pending request, and a late answer reaches nothing");
        }
        early.destroy();
        done = true;
    }

    // The writer has no answer for the memory's first read, as at load time before its snapshot
    // is ready: the read retry (2 s) finds the memory. The layout provider starts incapable and
    // turns capable then, one revision later; a toggle before that starts nothing and moves
    // nothing, and one after it starts a session.
    function runLateMemory() {
        facade.snapshotSilences = 1;
        if (setup() === "") {
            done = true;
            return;
        }
        if (script.loaded) {
            fail("late-memory: the memory waits for the writer's answer");
        }
        expectProvider("late-memory: at start", { revision: 1 }, 0, { online: true, capable: false, active: false });
        expectIdentityRequest("late-memory: at start", provider);
        let before = providerState();
        steps = [
            { name: "a toggle before the memory loaded", run: function () {
                tileShortcut.activated();
                if (calls("createTile").length !== 0) {
                    fail("late-memory: no session before the memory loaded");
                }
                expectProvider("late-memory: a toggle before the memory loaded", before, 0, { capable: false, active: false });
            } },
            { name: "the memory's read retry", until: () => script.loaded, run: function () {
                expectProvider("late-memory: the memory loaded", before, 1, { online: true, capable: true, active: false });
                before = providerState();
                tileShortcut.activated();
                expectProvider("late-memory: a toggle once capable", before, 1, { active: true, desktopId: "11" });
            } }
        ];
        stepSince = Date.now();
        stepper.start();
    }

    // The writer refuses the provider registration as the fork does while another provider holds
    // its slot or the writer is busy: the facade answers a null QUuid's text. The memory stays
    // disabled for the session and takes no other transport: it never loads - the gate of every
    // write, record and toggle and of the teardown write - so no window is tracked or recorded,
    // no shell script call goes out, and a toggle starts no tree. A record an earlier instance
    // left stays held: settling it needs the registration. The run checks past the script's
    // longest delayed call (flush and readRetry, 2 s) that the writer heard nothing but the
    // registration, read-only calls included; the driver reads the calls again after the run.
    function runRefusedProvider() {
        facade.providerAnswer = "{00000000-0000-0000-0000-000000000000}";
        setupView();
        const floatA = facade.plain(winA.frameGeometry);
        const managed = facade.plain(facade.masterRect);
        winA.frameGeometry = Qt.rect(managed.x, managed.y, managed.width, managed.height);
        const held = facade.heldRecords;
        held.a = { target: managed, floating: floatA, placedByUser: false,
                   provider: "earlier-token" };
        facade.heldRecords = held;
        const floats = facade.floatings;
        floats.a = floatA;
        facade.floatings = floats;
        const base = "file://" + packagesRoot + "/scripts/plasmafusion-placement/contents/ui/";
        const component = Qt.createComponent(base + "main.qml");
        if (component.status !== Component.Ready) {
            fail("refused-provider: main.qml did not load: " + component.errorString());
            done = true;
            return;
        }
        script = component.createObject(harness);
        if (!script) {
            fail("refused-provider: the script was not made");
            done = true;
            return;
        }
        trackProvider();
        // The legacy transport's calls: the script's evaluateScript DBusCalls.
        const shellScriptCalls = () => {
            let count = 0;
            for (let i = 0; i < script.data.length; ++i) {
                const child = script.data[i];
                if (child && child.method === "evaluateScript") {
                    count += child.calls;
                }
            }
            return count;
        };
        for (let i = 0; i < script.data.length; ++i) {
            const child = script.data[i];
            if (child && child.name === "Plasma Fusion: Tile Workspace") {
                tileShortcut = child;
            }
        }
        if (!tileShortcut) {
            fail("refused-provider: the Tile Workspace shortcut was not registered");
            done = true;
            return;
        }
        let since = 0;
        steps = [
            { name: "a toggle", run: function () {
                tileShortcut.activated();
                since = Date.now();
            } },
            { name: "past the script's delayed calls", until: () => Date.now() - since >= 2500, run: function () {
                if (script.loaded || !script.nativeRefused) {
                    fail("refused-provider: the memory stays unloaded and refused (loaded " + script.loaded
                         + ", nativeRefused " + script.nativeRefused + ")");
                }
                const ops = JSON.stringify(facadeCalls.map(c => c.op));
                if (ops !== JSON.stringify(["registerProvider"])) {
                    fail("refused-provider: registerProvider is the only recorded facade call (got " + ops + ")");
                }
                if (readCalls.length !== 0) {
                    fail("refused-provider: a refused provider reads nothing of the writer (got "
                         + JSON.stringify(readCalls.map(c => c.op)) + ")");
                }
                if (shellScriptCalls() !== 0) {
                    fail("refused-provider: no shell script call replaces the refused native writer");
                }
                // The layout provider: online, never capable, nothing moved; a label of its own
                // (P0's probe had derived it from the token, so every refused lifetime shared
                // one), and the refusal's text is not kept as a token.
                expectProvider("refused-provider", { revision: 1 }, 0, { online: true, capable: false, active: false });
                expectOwnLabel("refused-provider", facade.providerAnswer);
                // The identity marks the lifetime, not the capability: an incapable provider
                // asks for its name all the same - and answers the bars all the same: online, not
                // capable, nothing tiled.
                DBusStubs.SessionBus.answer(expectIdentityRequest("refused-provider", provider), [{ value: 1 }]);
                provider.identityLookup.finished([":1.42"]);
                provider.shellLookup.finished([":1.9"]);
                const asked = { id: 1, consumer: "c1", request: 1, version: 1, intent: "query", outputName: "Virtual-1" };
                provider.reader.finished([JSON.stringify([asked])]);
                const told = framesOf(provider, 0, [1]);
                const unsupported = frameWanted(provider, asked, {
                    capable: false, view: { desktopId: "11", activityId: "a", outputName: "Virtual-1" }, tiled: false });
                if (!provider.writer || provider.writer.calls !== 1 || canonical(told[1]) !== canonical(unsupported)) {
                    fail("refused-provider: an incapable provider answers a request, online and not capable (got "
                         + canonical(told[1]) + ", not " + canonical(unsupported) + ")");
                }
                if (script.providerToken !== "") {
                    fail("refused-provider: a refused registration keeps no token (got " + script.providerToken + ")");
                }
            } }
        ];
        stepSince = Date.now();
        stepper.start();
    }

    // The script unloaded mid-session as KWin unloads a declarative script: the object that
    // owns it goes, and with it, first, the script's own context with the KWin context
    // property, so the script's Component.onDestruction runs while that context is being torn
    // down. Nothing of the script may answer the session's end from there: in KWin the stack's
    // float restore moved a window, the window's frameGeometryChanged reached the placement
    // memory's handler, the handler read a setting through the KWin context property and the
    // compositor crashed (2026-11-14). The session ends all the same - the stack back on its
    // float, the master restored, the tree released - and afterwards nothing of the script
    // answers a window or the facade. With unloadVacated the native layer has released the
    // master in between: the teardown takes that release (the master back to its float, its
    // record settled) and records nothing, the memory reading its settings to record.
    function runUnload() {
        setupView();
        scriptWanted = "file://" + packagesRoot + "/scripts/plasmafusion-placement/contents/ui/main.qml";
        const floatA = facade.plain(winA.frameGeometry);
        const floatMaster = facade.plain(master.frameGeometry);
        let cellA = null;
        let asked = 0;
        let toggledAt = 0;
        let revisionBeforeUnload = 0;
        let identityAtUnload = "";
        let releasedAtRetire = null;
        steps = [
            { name: "the script as KWin makes it", until: () => kwinScript !== null, run: function () {
                if (adopt(kwinScript) === "") {
                    throw "the script made as KWin makes it was not adopted";
                }
                tileShortcut.activated();
                if (calls("admitTile").length !== 1 || !master.tile) {
                    throw "unload: no session started (admissions " + calls("admitTile").length + ")";
                }
                expectProvider("unload: the session", { revision: 1 }, 1, { online: true, active: true });
                // The identity granted, so the unload has a name to release.
                DBusStubs.SessionBus.answer(expectIdentityRequest("unload", provider), [{ value: 1 }]);
                provider.identityLookup.finished([":1.42"]);
                cellA = facade.plain(winA.frameGeometry);
                if (facade.same(cellA, floatA)) {
                    throw "unload: the stack window was given no cell (at " + JSON.stringify(winA.frameGeometry) + ")";
                }
                toggledAt = Date.now();
            } },
            // Past the memory's quiet second after the toggle: a handler of the script that
            // answered the teardown's writes would record them now (the old order did).
            { name: "the quiet second after the toggle", until: () => Date.now() - toggledAt >= script.quietMillis + 200, run: function () {
                // The memory has other places for the apps now (a second window of each was
                // moved, say): a handler that answered the teardown's writes would record the
                // frames they return the windows to. (A stack member is never recorded while
                // its session lasts; the master is restored after the session's end.)
                const apps = script.apps;
                for (const id of ["a", "master"]) {
                    apps[calls("trackWindow").find(c => c.window === id).key] = { x: 10, y: 40, width: 280, height: 300 };
                }
                script.apps = apps;
                if (unloadVacated) {
                    // The release that leaves the window where it stands and holds its record,
                    // without the tree's end (facade.detach without its treeChanged).
                    const held = facade.heldRecords;
                    held.master = { target: facade.plain(master.frameGeometry), floating: floatMaster, placedByUser: false };
                    facade.heldRecords = held;
                    facade.vacate();
                }
                asked = facadeCalls.length;
                revisionBeforeUnload = provider ? provider.revision : 0;
                // What the retirement released, read as it releases (the provider is gone once the
                // unload is over): the revision already moved for the offline state, and no
                // offline frame went out, as no request was read.
                const retiring = provider;
                identityAtUnload = retiring.identityName;
                // (On callLogChanged: the stand-in counts a call before it logs its arguments.)
                retiring.identityRelease.callLogChanged.connect(() => {
                    releasedAtRetire = { log: [].concat(retiring.identityRelease.callLog), revision: retiring.revision,
                                         online: retiring.online, frames: retiring.writer ? retiring.writer.calls : -1 };
                });
                unloadWanted = true;
            } },
            { name: "the script unloaded as KWin unloads it", until: () => unloaded, run: function () {
                if (!facade.same(winA.frameGeometry, floatA)) {
                    fail("unload: the stack window is back on its float (at " + JSON.stringify(winA.frameGeometry)
                         + ", float " + JSON.stringify(floatA) + ")");
                }
                // The session's end and nothing else: no record (the floats are the memory's
                // already, and recording reads the settings), no second release.
                const ops = facadeCalls.slice(asked).map(c => c.op + (c.op === "settleWindow" ? "=" + c.result : ""));
                const wanted = unloadVacated ? ["settleWindow=0", "releaseTile"] : ["restoreWindow", "releaseTile"];
                if (JSON.stringify(ops) !== JSON.stringify(wanted)) {
                    fail("unload" + (unloadVacated ? " (vacated)" : "") + ": the script's end asks the facade for its session's end"
                         + " and nothing else (" + JSON.stringify(wanted) + "), got " + JSON.stringify(ops));
                }
                if (unloadVacated && !facade.same(master.frameGeometry, floatMaster)) {
                    fail("unload (vacated): the released master went back to its float (at " + JSON.stringify(master.frameGeometry) + ")");
                }
                // The provider went offline before the teardown, once, with no capability or
                // session left to report: the teardown's own untoggle moved nothing after that.
                const last = providerStates[providerStates.length - 1];
                if (!last || last.revision !== revisionBeforeUnload + 1 || last.online || last.capable || last.active
                        || last.desktopId !== "") {
                    fail("unload" + (unloadVacated ? " (vacated)" : "") + ": the provider went offline once, with no"
                         + " capability or session (before " + revisionBeforeUnload + ", got " + JSON.stringify(last) + ")");
                }
                // The identity name is released once, by the retirement, with the name it stored:
                // nothing of a torn-down context is looked up for it. It goes last, after the
                // offline state's revision.
                if (!releasedAtRetire || JSON.stringify(releasedAtRetire.log) !== JSON.stringify([[identityAtUnload]])
                        || releasedAtRetire.revision !== revisionBeforeUnload + 1 || releasedAtRetire.online
                        || releasedAtRetire.frames !== 0) {
                    fail("unload" + (unloadVacated ? " (vacated)" : "") + ": the retirement releases the identity name once,"
                         + " after the offline state's revision, with no frame to send (got " + JSON.stringify(releasedAtRetire) + ")");
                }
                // Nothing of the script answers anything any more.
                const gone = facadeCalls.length;
                winA.frameGeometry = Qt.rect(floatA.x + 20, floatA.y + 20, floatA.width, floatA.height);
                master.frameGeometry = Qt.rect(60, 90, 620, 420);
                master.interactiveMoveResizeFinished();
                facade.treeChanged();
                if (facadeCalls.length !== gone) {
                    fail("unload: a script that is gone answers nothing (calls " + JSON.stringify(facadeCalls.slice(gone)) + ")");
                }
            } }
        ];
        stepSince = Date.now();
        stepper.start();
    }

    // A window an earlier instance of the script left with a native record (plasma-fusion#175):
    // the record of a master the native layer released, held for a provider that is gone. The
    // new instance finds it when it starts. On a fork that lets the current provider settle
    // it, the window is the new instance's released master: back to its floating frame
    // (unless the user put it where it stands), settled, and a toggle can admit it again. On a
    // fork that keeps the record to the admitting provider the settle answers 2: the window
    // is left exactly where it stands, out of the tiling, and its admission stays busy.
    function runStranded() {
        setupView();
        const floatA = facade.plain(winA.frameGeometry);
        const managed = facade.plain(facade.masterRect);
        const placedAt = { x: 320, y: 200, width: floatA.width, height: floatA.height };
        const standing = strandedPlaced ? placedAt : managed;
        winA.frameGeometry = Qt.rect(standing.x, standing.y, standing.width, standing.height);
        const held = facade.heldRecords;
        held.a = { target: managed, floating: floatA, placedByUser: strandedPlaced, provider: "earlier-token" };
        facade.heldRecords = held;
        const floats = facade.floatings;
        floats.a = floatA;
        facade.floatings = floats;
        facade.successorSettle = strandedSuccessor;
        const base = "file://" + packagesRoot + "/scripts/plasmafusion-placement/contents/ui/";
        const component = Qt.createComponent(base + "main.qml");
        if (component.status !== Component.Ready) {
            fail("main.qml did not load: " + component.errorString());
            done = true;
            return;
        }
        if (adopt(component.createObject(harness)) === "") {
            done = true;
            return;
        }
        const settlesOfA = () => facadeCalls.filter(c => c.op === "settleWindow" && c.window === "a").map(c => c.result);
        const admitsOfA = () => facadeCalls.filter(c => c.op === "admitTile" && c.window === "a");
        const where = () => JSON.stringify(facade.plain(winA.frameGeometry));
        const wanted = strandedSuccessor ? (strandedPlaced ? "[0]" : "[4,0]") : "[2]";
        steps = [
            { name: "the record found at the start answered", until: () => JSON.stringify(settlesOfA()) === wanted, run: function () {
                if (strandedSuccessor) {
                    if (facade.heldRecords.a !== undefined) {
                        fail("stranded: the record is settled");
                    }
                    if (!facade.same(winA.frameGeometry, strandedPlaced ? placedAt : floatA)) {
                        fail("stranded: the window stands " + (strandedPlaced ? "where the user put it" : "on its floating frame")
                             + " (at " + where() + ")");
                    }
                } else {
                    if (facade.heldRecords.a === undefined) {
                        fail("stranded (old fork): the record is still held");
                    }
                    if (!facade.same(winA.frameGeometry, managed)) {
                        fail("stranded (old fork): the window is left where it stands (at " + where() + ")");
                    }
                }
                if (admitsOfA().length !== 0) {
                    fail("stranded: nothing is admitted at the start");
                }
                // A toggle with it as the active window.
                KWinStubs.Workspace.activeWindow = winA;
                tileShortcut.activated();
            } },
            { name: "the toggle answered", until: () => strandedSuccessor ? !!winA.tile : admitsOfA().length >= 1 + script.admitRetryLimit, run: function () {
                const answers = JSON.stringify(admitsOfA().map(c => c.token === facade.grantedToken));
                if (strandedSuccessor) {
                    if (!winA.tile || calls("admitTile").length !== 1) {
                        fail("stranded: the window is admitted at the first toggle (admissions " + calls("admitTile").length + ")");
                    }
                    tileShortcut.activated();
                } else {
                    if (winA.tile) {
                        fail("stranded (old fork): the window with a record it cannot end is not admitted");
                    }
                    if (!facade.same(winA.frameGeometry, managed)) {
                        fail("stranded (old fork): the toggle moved nothing (at " + where() + ")");
                    }
                }
            } },
            { name: "the session ended", until: () => !winA.tile, run: function () {
                if (strandedSuccessor && !facade.same(winA.frameGeometry, strandedPlaced ? placedAt : floatA)) {
                    fail("stranded: the untoggle returns the window to the place it was settled at (at " + where() + ")");
                }
            } }
        ];
        stepSince = Date.now();
        stepper.start();
    }

    function run() {
        const ws = KWinStubs.Workspace;
        const masterKey = setup();
        if (masterKey === "") {
            return;
        }
        const desktop = firstDesktop;
        // The layout provider as the script started: online, no session, and capable where the
        // writer accepted the registration, the memory loaded and the facade is complete - not
        // with a facade without restoreWindow, whatever the writer says; its label is its own.
        expectProvider("the provider at start", { revision: 1 }, 0,
                       { online: true, capable: !legacyFacade, active: false, desktopId: "", outputName: "" });
        expectOwnLabel("the provider at start", facade.grantedToken);
        let providerBefore = providerState();
        // The identity alias: requested once at start; its owner is looked up only once the
        // name is granted, then known - this connection, KWin's; none of it moves the revision.
        const identityReply = expectIdentityRequest("the provider at start", provider);
        if (provider.identityLookup.calls !== 0 || provider.identityReady) {
            fail("the identity's owner is looked up only once the name is granted");
        }
        DBusStubs.SessionBus.answer(identityReply, [{ value: 1 }]);
        if (JSON.stringify(provider.identityLookup.callLog) !== JSON.stringify([[provider.identityName]])) {
            fail("the granted name's owner is looked up once (got " + JSON.stringify(provider.identityLookup.callLog) + ")");
        }
        provider.identityLookup.finished([":1.42"]);
        if (!provider.identityReady || provider.selfOwner !== ":1.42") {
            fail("the identity is ready, with its owner (got " + provider.identityReady + ", " + provider.selfOwner + ")");
        }
        expectProvider("the identity granted", providerBefore, 0, {});

        if (legacyFacade) {
            // ---- a facade without restoreWindow: no session, the memory's transport intact ----
            // The untoggle is that restore: a session the tiler could start it could not end.
            tileShortcut.activated();
            if (calls("createTile").length !== 0) {
                fail("a facade without restoreWindow starts no session");
            }
            expectProvider("a facade without restoreWindow", providerBefore, 0, { capable: false, active: false });
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
            expectProvider("interim: a refused admission", providerBefore, 0, { capable: true, active: false });
            // And a session all the same where the memory has the window's own place.
            facade.entries[masterKey] = { x: 40, y: 80, width: 620, height: 420 };
            tileShortcut.activated();
            if (!master.tile || calls("record").filter(c => c.window === "master").length !== 0) {
                fail("the window is admitted from its own place there, with nothing recorded");
            }
            expectProvider("interim: the session", providerBefore, 1, { capable: true, active: true });
            tileShortcut.activated();
            expectProvider("interim: the untoggle", providerBefore, 2, { active: false });
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
        if (admitted[0].token !== facade.grantedToken) {
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
        // The provider: the session on, for the view it tiles as a bar names one.
        expectProvider("toggle on", providerBefore, 1,
                       { active: true, desktopId: "11", activityId: "a", outputName: "Virtual-1" });
        providerBefore = providerState();

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
        // A window joining and the relayout change nothing a bar is told.
        expectProvider("a live window joining", providerBefore, 0, { active: true });

        // ---- untoggle: the floats back, the master's native restore, the tree released ----
        tileShortcut.activated();
        expectProvider("the untoggle", providerBefore, 1,
                       { active: false, desktopId: "", activityId: "", outputName: "" });
        providerBefore = providerState();
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
        expectProvider("the second session", providerBefore, 1, { active: true, desktopId: "11" });
        providerBefore = providerState();
        facade.treeAlive = false;
        facade.treeChanged();
        if (!rectIs(winA.frameGeometry, 700, 120, 300, 320) || !rectIs(winB.frameGeometry, 760, 480, 300, 300)) {
            fail("the native teardown restored the stack floats");
        }
        if (calls("releaseTile").length !== 1) {
            fail("the native teardown does not release an already-ended tree");
        }
        expectProvider("the native teardown", providerBefore, 1,
                       { active: false, desktopId: "", activityId: "", outputName: "" });
        providerBefore = providerState();
        // the session is gone: the next toggle starts a session instead of un-toggling
        tileShortcut.activated();
        if (calls("createTile").length !== 3) {
            fail("a toggle after the native teardown lays out again (the session had ended)");
        }
        tileShortcut.activated(); // untoggle the third session (cleanup)
        if (calls("releaseTile").length !== 2) {
            fail("the third session released its tree");
        }
        expectProvider("the third session on and off", providerBefore, 2, { active: false });
        providerBefore = providerState();

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
        expectProvider("a refused tree", providerBefore, 0, { active: false });
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
        expectProvider("a refused admission", providerBefore, 0, { active: false });
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
        expectProvider("a session admitted on landing, on and off", providerBefore, 2, { active: false });
        providerBefore = providerState();

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
        expectProvider("the session on the first desktop", providerBefore, 1, { active: true, desktopId: "11" });
        providerBefore = providerState();
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
        // The provider: the first session's end, then the new one on the view the shortcut was
        // invoked on - not the desktop the old master's activation carried back.
        expectProvider("the invocation on the other desktop", providerBefore, 2,
                       { active: true, desktopId: "12", activityId: "a", outputName: "Virtual-1" });
        providerBefore = providerState();
        facade.onRestore = null;
        ws.currentDesktop = desktop2;
        tileShortcut.activated(); // untoggle it (still the invoked view)
        expectProvider("the untoggle on the other desktop", providerBefore, 1, { active: false, desktopId: "" });

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
                // Nor is such a window a member of anyone's stack: a cell would be one more
                // automatic rectangle for it, the frame it stands on would be saved as its
                // float, and its record would stay as it is.
                const standing = facade.plain(winA.frameGeometry);
                facade.keepRecord(winA, Qt.rect(300, 300, 300, 320));
                tileShortcut.activated();
                if (!master.tile || !inColumn(winB) || !facade.same(winA.frameGeometry, standing)) {
                    fail("released: a window the native layer keeps a record of is left out of the stack (master "
                         + (master.tile ? "admitted" : "not admitted") + ", the window at " + JSON.stringify(winA.frameGeometry) + ")");
                }
                tileShortcut.activated();
                if (!facade.same(winA.frameGeometry, standing)) {
                    fail("released: and the untoggle leaves it where it stands (at " + JSON.stringify(winA.frameGeometry) + ")");
                }
                // Minimized at the toggle, it is not waited for either.
                winA.minimized = true;
                master.frameGeometry = Qt.rect(40, 80, 620, 420);
                tileShortcut.activated();
                winA.minimized = false;
                if (!master.tile || !facade.same(winA.frameGeometry, standing)) {
                    fail("released: restored from minimized during the session, it joins no stack (at " + JSON.stringify(winA.frameGeometry) + ")");
                }
                tileShortcut.activated();
                facade.dropRecord(winA);
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
                // ---- a window on its way back counts where it is going ----
                // A new window of an app is not restored onto a spot one of the app's windows
                // holds. A stack window whose float is still on its way stands on its cell,
                // and the spot it holds is the float it is going back to.
                tileShortcut.activated();
                tileShortcut.activated();
                winA.requestedGeometry = Qt.rect(floatA.x, floatA.y, floatA.width, floatA.height);
                winA.frameGeometry = Qt.rect(cellA.x, cellA.y, cellA.width, cellA.height);
                facade.entries["org.fusion.editor"] = facade.image(floatA);
                const sibling = mk({ internalId: "a2", resourceClass: "org.fusion.editor",
                                     desktopFileName: "org.fusion.editor.desktop",
                                     frameGeometry: Qt.rect(200, 300, 300, 320) });
                sibling.desktops = [firstDesktop];
                sibling.output = ws.activeScreen;
                ws.windows = [sibling, winB, winA, master];
                ws.windowAdded(sibling);
                if (!rectIs(sibling.frameGeometry, 200, 300, 300, 320)) {
                    fail("released: a window is not restored onto the place a returning window of its app is going back to (at "
                         + JSON.stringify(sibling.frameGeometry) + ")");
                }
                sibling.deleted = true;
                ws.windows = [winB, winA, master];
                ws.windowRemoved(sibling);
                winA.frameGeometry = Qt.rect(floatA.x, floatA.y, floatA.width, floatA.height);
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
