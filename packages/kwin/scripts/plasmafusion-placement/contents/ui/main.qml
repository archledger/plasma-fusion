/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kwin
import "Placement.js" as Placement
import "Tiling.js" as Tiling

// Plasma Fusion window placement memory (bug 15329 - the desktop's most-duplicated open wish):
// each app's window is remembered where and how big it was left, and given back when the app
// opens again, like Windows and macOS do. A record only applies while its centre still lies on a
// screen the session has; a spot on a monitor that is gone is left to KWin's placement.
//
// - One record per app: its desktop file (stable across Wayland and X11), else the window class.
//   Several windows of one app share the record - the one the user moves (or closes) last sets
//   it, and a new window is not stacked exactly on the remembered spot when an instance of the
//   app already holds it (KWin's own placement then offsets it, and that record stays).
// - A window is remembered while it floats (not maximized, full screen or tiled), once shortly
//   after it opens and where it was when it closes; a window opened maximized keeps its last
//   floating record. A window KWin holds in place (a window rule that forces its position) is
//   left to KWin: the script's geometry write would bypass the rule.
// - A maximize KWin has asked for counts as maximized until the window has taken it: the commit
//   with which a Wayland client answers the request updates the frame before the maximize mode,
//   so the frame change already shows the maximized frame while maximizeMode still reads 0 (KWin
//   6.7.5, xdgshellwindow.cpp handleCommit; issue #128). The script mirrors KWin's requested mode
//   from maximizedAboutToChange (emitted with the request, Wayland and X11, and the last emission
//   is exactly what KWin keeps as the requested mode); at maximizedChanged, when a restore has
//   been taken, the floating frame the window went back to is recorded.
// - On a KWin with Window.requestedGeometry (the optional backport, packaging/patches/kwin), a
//   frame the client has not yet brought up to KWin's request is not recorded: after an untile it
//   can still have the tile's size (KDE bug 527821). Without the property every frame counts.
// - On a KWin with the native placement writer (the fork's Workspace.placementWriter()), the
//   script registers as the provider and submits typed records; on stock KWin it falls back to
//   the legacy D-Bus file transport.
//
// Dynamic tiling (issue #115, Option A): the master window rides the native transient
// ownership; the stack windows are placed by direct frameGeometry writes with their
// pre-tiling floats saved for the untoggle. The tiler lives inside this package because
// the writer takes exactly one provider and the tiler IS that provider's policy consumer.
//
// Settings (kwinrc [Script-plasmafusion-placement], contents/config/main.xml): RememberSize,
// IgnoreApps, Tiling.MasterFraction, Tiling.StackGap.
//
// No timer runs while idle: one shot per window open, one for a pending memory write.
Item {
    id: root

    // ---------------------------------------------------------------- memory state

    // app id -> {x, y, width, height}: the memory file's [Windows] group, one JSON entry.
    property var apps: ({})
    property bool loaded: false
    property int revision: 0 // bumped by every memory change
    property int sentRevision: 0 // the revision the last write carried
    property int sendingRevision: -1
    property bool sending: false
    property int readTries: 0
    // How long after an open the memory ignores geometry changes: the restore itself and an app's
    // own late repositioning must not churn the record before the window settles.
    readonly property int quietMillis: 1000

    readonly property string memoryFile: "plasmafusion-placementrc"
    readonly property string memoryGroup: "Windows"
    readonly property string memoryKey: "windows"

    function log(message) {
        console.info("plasmafusion-placement: " + message);
    }

    // ---------------------------------------------------------------- settings

    function setting(key, fallback) {
        const value = KWin.readConfig(key, fallback);
        if (typeof fallback === "boolean") {
            return value === true || value === "true";
        }
        return value === undefined || value === null ? fallback : String(value);
    }
    function rememberSize() {
        return setting("RememberSize", true);
    }
    function ignoreList() {
        return setting("IgnoreApps", "");
    }
    function tilingMasterFraction() {
        return parseFloat(setting("Tiling.MasterFraction", 0.5));
    }
    function tilingStackGap() {
        return parseInt(setting("Tiling.StackGap", 8));
    }

    // ---------------------------------------------------------------- the memory writer
    // The compositor's placement writer (docs/NATIVE-TILING-CONTRACT.md): typed native calls
    // replace the legacy plasmashell D-Bus file transport. The token is opaque text to QML; the
    // writer validates every submission natively. On a KWin without Workspace.placementWriter
    // (stock or older forks) the script falls back to the legacy transport below.

    property bool nativeWriter: false
    property bool nativeRefused: false // registration refused: no legacy fallback
    property var writer: null
    property string providerToken: ""
    property int writerRevision: 0
    property var eventSequences: ({})

    function detectNativeWriter() {
        try {
            nativeWriter = typeof Workspace.placementWriter === "function";
        } catch (e) {
            nativeWriter = false;
        }
        if (!nativeWriter) {
            log("no native placement writer; using the legacy transport");
        }
        return nativeWriter;
    }

    function registerWithWriter() {
        if (!nativeWriter || writer) {
            return;
        }
        writer = Workspace.placementWriter();
        if (!writer) {
            nativeWriter = false;
            return;
        }
        providerToken = String(writer.registerProvider(root));
        if (providerToken === "" || providerToken === "undefined") {
            // A native session must not bypass the sole native writer: the memory stays
            // disabled rather than falling back to a transport the contract retires.
            log("the writer refused the provider registration; the memory stays disabled this session");
            nativeWriter = false;
            writer = null;
            nativeRefused = true;
            return;
        }
        log("registered as the placement provider");
    }

    function trackWithWriter(w) {
        if (!nativeWriter || !writer || !w) {
            return;
        }
        const key = appIdOf(w);
        if (key === "") {
            return;
        }
        writer.trackWindow(w.internalId, key);
        if (!eventSequences[String(w.internalId)]) {
            eventSequences[String(w.internalId)] = 0;
        }
    }

    function recordWithWriter(w, frame) {
        if (!nativeWriter || !writer || !w || providerToken === "") {
            return;
        }
        const id = String(w.internalId);
        const seq = (eventSequences[id] || 0) + 1;
        // The first argument is the provider incarnation token (the opaque text from
        // registerProvider); the writer rejects submissions from retired incarnations.
        writer.record(providerToken, ++writerRevision, w.internalId,
                      Qt.rect(Math.round(frame.x), Math.round(frame.y),
                              Math.round(frame.width), Math.round(frame.height)),
                      seq, 0); // Origin.Manual
        eventSequences[id] = seq;
        // Reconcile the cache with the writer's decision: when the submission was suppressed
        // (a restore watermark) or deferred (an active reservation), the writer's entry for
        // this key is the authority, not the in-memory cache the policy just wrote.
        reconcileKeyWithWriter(appIdOf(w));
    }

    function reconcileKeyWithWriter(key) {
        if (!nativeWriter || !writer || key === "") {
            return;
        }
        const snap = writer.snapshot();
        if (!snap || !snap.entries) {
            return;
        }
        const entry = snap.entries[key];
        if (entry !== undefined) {
            apps[key] = { x: entry.x, y: entry.y, width: entry.width, height: entry.height };
        }
    }

    function readFromWriter() {
        if (!nativeWriter || !writer || loaded) {
            return;
        }
        const snap = writer.snapshot();
        if (!snap) {
            // The writer may not be ready at script-load time; retry like the legacy path.
            if (readTries < 10) {
                readTries++;
                readRetry.start();
            } else {
                log("the native writer did not answer; this session runs without the window memory");
            }
            return;
        }
        const entries = snap.entries;
        const out = {};
        for (const key in entries) {
            const r = entries[key];
            out[key] = { x: r.x, y: r.y, width: r.width, height: r.height };
        }
        apps = out;
        loaded = true;
        log("memory loaded from the native writer: " + Object.keys(apps).length + " app(s)");
    }

    // ---------------------------------------------------------------- the legacy transport
    // Used when the session's KWin does not expose the placement writer (stock or older forks).

    function readScript() {
        return "var out = '';\n"
            + "try {\n"
            + "    var c = ConfigFile('" + memoryFile + "', '" + memoryGroup + "');\n"
            + "    var v = c.readEntry('" + memoryKey + "');\n"
            + "    if (typeof v === 'string') { out = v; }\n"
            + "} catch (e) {}\n"
            + "print(out);";
    }

    function writeScript(text) {
        return "var c = ConfigFile('" + memoryFile + "', '" + memoryGroup + "');\n"
            + "c.writeEntry('" + memoryKey + "', " + JSON.stringify(text) + ");";
    }

    function read() {
        if (loaded || nativeRefused) {
            return;
        }
        if (nativeWriter) {
            readFromWriter();
            return;
        }
        readTries++;
        readCall.arguments = [readScript()];
        readCall.call();
    }

    function readDone(text) {
        if (loaded) {
            return;
        }
        apps = Placement.parse(text);
        loaded = true;
        log("memory loaded: " + Object.keys(apps).length + " app(s)");
    }

    DBusCall {
        id: readCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: returnValue => root.readDone(returnValue.length > 0 ? String(returnValue[0]) : "")
        onFailed: {
            if (root.readTries < 10) {
                readRetry.start();
            } else {
                root.log("plasmashell did not answer; this session runs without the window memory");
            }
        }
    }

    Timer {
        id: readRetry
        interval: 2000
        onTriggered: root.read()
    }

    function write() {
        if (!loaded || sending || sentRevision === revision) {
            return;
        }
        if (nativeWriter) {
            sentRevision = revision;
            return;
        }
        sending = true;
        sendingRevision = revision;
        writeCall.arguments = [writeScript(Placement.serialize(apps))];
        writeCall.call();
    }

    DBusCall {
        id: writeCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: {
            root.sending = false;
            root.sentRevision = root.sendingRevision;
            if (root.revision !== root.sentRevision) {
                flush.interval = 2000;
                flush.restart();
            }
        }
        onFailed: {
            root.sending = false;
            root.log("the memory file could not be written (plasmashell down?); trying again shortly");
            flush.interval = 15000;
            flush.restart();
        }
    }

    Timer {
        id: flush
        interval: 2000
        onTriggered: root.write()
    }

    function changed() {
        revision++;
        if (!nativeWriter && !sending) {
            flush.interval = 2000;
            flush.restart();
        }
    }

    // ---------------------------------------------------------------- windows

    // internalId -> {w, onGeometry, onAboutToMaximize, onMaximized, quietUntil, settleSkip, held,
    // maximizeRequested}: every ordinary window under watch.
    property var watched: ({})
    // Windows whose settling pass is still due (compared by identity).
    property var settling: []

    // The window's state for the pure rules. entry: its watch entry, which carries the maximize
    // mode KWin asked for (Placement.maximized); without one the mode taken alone counts.
    function stateOf(w, entry) {
        return {
            normal: w.normalWindow,
            transient: w.transient,
            modal: w.modal,
            fullScreen: w.fullScreen,
            tiled: !!w.tile,
            minimized: w.minimized,
            maximizeMode: w.maximizeMode,
            maximizeRequested: entry ? entry.maximizeRequested : undefined,
            movable: w.moveable,
            resizable: w.resizeable
        };
    }

    function frameRect(w) {
        const g = w.frameGeometry;
        return { x: g.x, y: g.y, width: g.width, height: g.height };
    }

    // The geometry KWin last asked the window to take, or null on a KWin without the property
    // (Placement.settled).
    function requestedRect(w) {
        const g = w.requestedGeometry;
        return g ? { x: g.x, y: g.y, width: g.width, height: g.height } : null;
    }

    function appIdOf(w) {
        return Placement.appId(String(w.resourceClass || ""), String(w.desktopFileName || ""));
    }

    // IgnoreApps is matched against the app id and the window class (Placement.identities).
    function ignoredWindow(w) {
        return Placement.ignored(Placement.identities(String(w.resourceClass || ""), String(w.desktopFileName || "")), ignoreList());
    }

    function screenRects() {
        const out = [];
        const screens = Workspace.screens;
        for (let i = 0; i < screens.length; ++i) {
            const g = screens[i].geometry;
            out.push({ x: g.x, y: g.y, width: g.width, height: g.height });
        }
        return out;
    }

    // The desktop and activity views the pure guard takes (Placement.sameDesktop/sameActivity).
    function desktopView(w) {
        return { allDesktops: w.onAllDesktops, desktops: w.desktops };
    }
    function activityView(w) {
        return { activities: w.activities };
    }

    // The open windows of the same app on the same desktop and activity (the stack guard's input).
    function siblings(id, w) {
        const out = [];
        const windows = Workspace.stackingOrder;
        for (let i = 0; i < windows.length; ++i) {
            const o = windows[i];
            if (o === w || o.deleted || !o.normalWindow || appIdOf(o) !== id) {
                continue;
            }
            if (!Placement.sameDesktop(desktopView(w), desktopView(o)) || !Placement.sameActivity(activityView(w), activityView(o))) {
                continue;
            }
            out.push(frameRect(o));
        }
        return out;
    }

    // The callers decide whether the window may still be read: the close path records a window KWin
    // already marked deleted (its geometry and state stay readable for the close animation).
    function record(w, id) {
        if (!loaded || !w || ignoredWindow(w)) {
            return;
        }
        // The tiler's managed windows are not the user's floating placement (invariant 7).
        if (tiler.session.active && (w === tiler.session.master || tiler.manages(w))) {
            return;
        }
        if (!Placement.eligible(stateOf(w, watched[String(w.internalId)]))) {
            return;
        }
        // A frame the client has not brought up to KWin's request yet is not the window's place
        // (the late tile-sized commit after an untile); the change that settles it records it.
        if (!Placement.settled(requestedRect(w), frameRect(w))) {
            return;
        }
        if (Placement.remember(apps, id, frameRect(w))) {
            changed();
        }
        recordWithWriter(w, frameRect(w));
    }

    // A geometry change the memory was told about (never during the quiet window after a restore;
    // the settling pass reads the window then instead).
    function geometryChanged(key) {
        const entry = watched[key];
        if (!entry || !loaded || !entry.w || entry.w.deleted || Date.now() < entry.quietUntil) {
            return;
        }
        record(entry.w, appIdOf(entry.w));
    }

    function windowOpened(w, restoreAllowed) {
        const key = String(w.internalId);
        if (watched[key]) {
            return;
        }
        const id = appIdOf(w);
        // held: KWin holds the window in place (a forced-position rule), taken now because an X11
        // window's rules are already dropped when it closes.
        // maximizeRequested: the maximize mode KWin asked for, mirrored from maximizedAboutToChange
        // (Placement.requestedMode); the mode taken to begin with. It is not reset from the mode
        // taken: with two requests in flight (a restore, then a maximize) a client that answers
        // them one by one takes the restore first, and the mirror must still say maximized when the
        // maximized frame follows. Only a signal without a usable mode (-1) is settled by
        // maximizedChanged.
        const entry = {
            w: w, quietUntil: 0, settleSkip: false, held: w.moveable === false,
            maximizeRequested: w.maximizeMode
        };
        const onGeometry = function () {
            root.geometryChanged(key);
        };
        entry.onGeometry = onGeometry;
        w.frameGeometryChanged.connect(onGeometry);
        const onAboutToMaximize = function (mode) {
            entry.maximizeRequested = Placement.requestedMode(mode);
        };
        // The mode is taken: a restore leaves the window floating at a frame the commit brought
        // before this signal, so the state that settled it records that frame (never during the
        // quiet second, like any geometry change).
        const onMaximized = function () {
            if (entry.maximizeRequested === -1) {
                entry.maximizeRequested = w.maximizeMode;
            }
            root.geometryChanged(key);
        };
        entry.onAboutToMaximize = onAboutToMaximize;
        entry.onMaximized = onMaximized;
        // Both signals exist on every KWin this script runs on (6.7 and later), so unlike
        // requestedGeometryChanged they are connected without a check.
        w.maximizedAboutToChange.connect(onAboutToMaximize);
        w.maximizedChanged.connect(onMaximized);
        // A KWin with requestedGeometry: the request can catch up with the frame without a frame
        // change (a commit that answers the last configure at the size already shown).
        if (w.requestedGeometryChanged) {
            w.requestedGeometryChanged.connect(onGeometry);
            entry.onRequested = true;
        }
        watched[key] = entry;
        trackWithWriter(w);

        const state = stateOf(w, entry);
        // The tiler's managed windows: a new window on the tiled desktop joins the stack, not
        // the placement memory's restore.
        if (tiler.session.active && tiler.managesDesktop(w)) {
            tiler.addWindow(w);
            return;
        }
        if (restoreAllowed && loaded && id !== "" && !ignoredWindow(w) && Placement.eligible(state)) {
            const saved = apps[id];
            const current = frameRect(w);
            const screens = screenRects();
            const others = siblings(id, w);
            const rect = Placement.restoreFor(id, state, saved, screens, others, ignoreList(), rememberSize(), current);
            if (rect) {
                entry.quietUntil = Date.now() + quietMillis;
                w.frameGeometry = Qt.rect(rect.x, rect.y, rect.width, rect.height);
                log("restored " + id + " to " + rect.x + "," + rect.y + " " + rect.width + "x" + rect.height);
            } else if (saved) {
                // Another instance of the app holds the spot: its record stays, and this window's
                // placement is not recorded as the new one - neither by the settling pass nor by
                // the window's own geometry changes while it opens (the quiet second, as after a
                // restore); the user's later moves are. (When the spot itself is unusable - off a
                // screen - the settle pass heals the record to where KWin placed it.)
                const finalRect = Placement.restoreRect(saved, current, Placement.restoreSize(state, rememberSize()));
                if (Placement.onScreen(finalRect, screens) && Placement.collides(finalRect, others)) {
                    entry.settleSkip = true;
                    entry.quietUntil = Date.now() + quietMillis;
                }
            }
        }
        // An adopted window is not settled: the user has not touched it, and recording every open
        // window when the script loads would replace the records they left (the last window of an
        // app in stacking order winning). Its moves and its close record it.
        if (restoreAllowed) {
            settling.push(w);
            settle.restart();
        }
    }

    // Every handler the entry put on its window (the close path and the teardown).
    function disconnectHandlers(entry) {
        const w = entry.w;
        if (!w) {
            return;
        }
        if (entry.onGeometry) {
            w.frameGeometryChanged.disconnect(entry.onGeometry);
            if (entry.onRequested) {
                w.requestedGeometryChanged.disconnect(entry.onGeometry);
            }
        }
        if (entry.onAboutToMaximize) {
            w.maximizedAboutToChange.disconnect(entry.onAboutToMaximize);
        }
        if (entry.onMaximized) {
            w.maximizedChanged.disconnect(entry.onMaximized);
        }
    }

    function windowClosed(w) {
        const key = String(w.internalId);
        const entry = watched[key];
        if (!entry) {
            return;
        }
        // The tiler: a closed managed window leaves the layout.
        if (tiler.session.active) {
            tiler.removeWindow(w);
        }
        // The last place before the window went. KWin marks a closing window deleted before
        // windowRemoved (Wayland and X11), so the window is read as it is: its frame geometry,
        // maximize mode and tile stay as they were (requestTile is a no-op once deleted).
        if (loaded && !entry.held && Date.now() >= entry.quietUntil) {
            record(w, appIdOf(w));
        }
        disconnectHandlers(entry);
        delete watched[key];
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) {
            if (!w || w.deleted || !w.normalWindow || w.transient || w.modal) {
                return;
            }
            root.windowOpened(w, true);
        }
        function onWindowRemoved(w) {
            if (w) {
                root.windowClosed(w);
            }
        }
    }

    // The settling pass: what a window's geometry is shortly after it opens is the record (the
    // restored spot unless the app moved itself again). One shot per burst of opens.
    Timer {
        id: settle
        interval: 1000
        onTriggered: {
            const list = root.settling;
            root.settling = [];
            for (let i = 0; i < list.length; ++i) {
                const w = list[i];
                if (!w || w.deleted) {
                    continue;
                }
                const entry = root.watched[String(w.internalId)];
                if (!entry || entry.settleSkip) {
                    continue;
                }
                root.record(w, root.appIdOf(w));
            }
        }
    }

    // ---------------------------------------------------------------- dynamic tiling (issue #115)

    // The tiler's session state. One session at a time: the controller holds one tree, the
    // TileManager allows one transient root per desktop. The master window rides the native
    // transient ownership; the stack windows are script-placed with saved floats.
    QtObject {
        id: tiler

        property var session: Tiling.createSession()
        // The facade (present only on the fork with TransientTilingApi).
        property var api: null
        property bool apiAvailable: false

        function detectApi() {
            try {
                apiAvailable = typeof Workspace.transientTiling === "function";
            } catch (e) {
                apiAvailable = false;
            }
            if (apiAvailable) {
                api = Workspace.transientTiling();
                // The native teardown: the facade forwards the controller's treeChanged; a
                // change with no live tree is session-end (master close, output removal,
                // desktop removal, provider retirement, key conflict, a manual quick-tile
                // or move of the master, an output transfer — every native path at once).
                api.treeChanged.connect(tiler.onTreeChanged);
            }
            return apiAvailable;
        }

        function onTreeChanged() {
            if (!session.active || !apiAvailable || !api) {
                return;
            }
            if (!api.hasTree()) {
                // The tree is gone: restore the stack floats (the master's own restore
                // already ran through the native layer — this is its aftermath).
                log("tiling: the tree ended natively; restoring the stack");
                for (let i = 0; i < session.stack.length; ++i) {
                    const w = session.stack[i];
                    const saved = session.savedFloats[String(w.internalId)];
                    if (saved && !w.deleted) {
                        w.frameGeometry = Qt.rect(saved.x, saved.y, saved.width, saved.height);
                    }
                }
                session = Tiling.createSession();
                log("tiling: off (native teardown)");
            }
        }

        // Whether a window is one of this session's managed windows.
        function manages(w) {
            if (!session.active || !w) {
                return false;
            }
            if (w === session.master) {
                return true;
            }
            return session.stack.indexOf(w) >= 0;
        }

        // Whether a window is on the session's desktop.
        function managesDesktop(w) {
            if (!session.active || !w || !session.desktop) {
                return false;
            }
            return !w.onAllDesktops && w.desktops && w.desktops.length === 1
                && String(w.desktops[0]) === String(session.desktop);
        }

        // Toggle the tiling on or off.
        function toggle() {
            if (session.active) {
                untoggle();
            } else {
                start();
            }
        }

        function start() {
            if (session.active || !loaded) {
                return;
            }
            const w = Workspace.activeWindow;
            if (!Tiling.eligibleForMaster(w)) {
                log("tiling: the active window is not eligible");
                return;
            }
            const output = Workspace.activeScreen;
            const desktop = Workspace.currentDesktop;
            if (!output || !desktop) {
                return;
            }

            // The stack candidates (before the master is admitted).
            const candidates = Tiling.stackCandidates(Workspace.stackingOrder, w, desktop);

            // The native admission first (invariant 8: before any stack write).
            if (apiAvailable && api) {
                const fraction = Tiling.masterFraction({ masterFraction: tilingMasterFraction() });
                const tileRect = Tiling.masterTileRect(fraction);
                const result = api.createTile(output, desktop, Qt.rect(tileRect.x, tileRect.y, tileRect.width, tileRect.height));
                if (!result || result.result !== 0) { // 0 = Accepted
                    log("tiling: the tree was refused");
                    return;
                }
                const gen = result.generation;
                const key = appIdOf(w);
                const admitResult = api.admitTile(gen, w, key, providerToken);
                if (admitResult !== 0) { // 0 = Accepted
                    log("tiling: the admission was refused (" + admitResult + ")");
                    api.releaseTile(gen);
                    return;
                }
                session.generation = gen;
            } else {
                log("tiling: the native facade is not available; the tiler needs the fork");
                return;
            }

            session.active = true;
            session.master = w;
            session.masterKey = appIdOf(w);
            session.output = output;
            session.desktop = desktop;
            session.stack = [];
            session.savedFloats = {};

            // The work area and the divider.
            const area = Workspace.clientArea(Workspace.MaximizeArea, output, desktop);
            session.dividerX = area.x + Math.round(area.width * Tiling.masterFraction({ masterFraction: tilingMasterFraction() }));

            // Save every candidate's float, then layout.
            const eligible = [];
            for (let i = 0; i < candidates.length; ++i) {
                if (Tiling.eligibleForStack(candidates[i])) {
                    eligible.push(candidates[i]);
                    const g = candidates[i].frameGeometry;
                    session.savedFloats[String(candidates[i].internalId)] =
                        { x: g.x, y: g.y, width: g.width, height: g.height };
                }
            }
            session.stack = eligible;
            relayout();
            log("tiling: on (" + eligible.length + " stack window(s))");
        }

        function untoggle() {
            if (!session.active) {
                return;
            }
            // The stack windows return to their saved floats.
            for (let i = 0; i < session.stack.length; ++i) {
                const w = session.stack[i];
                const saved = session.savedFloats[String(w.internalId)];
                if (saved && !w.deleted) {
                    w.frameGeometry = Qt.rect(saved.x, saved.y, saved.width, saved.height);
                }
            }
            // The master's native restore (Meta+Backspace equivalent).
            if (session.master && !session.master.deleted) {
                Workspace.activeWindow = session.master;
                Workspace.slotWindowRestore();
            }
            // Release the tree (an empty tree blocks future createTile).
            if (apiAvailable && api && session.generation > 0) {
                api.releaseTile(session.generation);
            }
            session = Tiling.createSession();
            log("tiling: off");
        }

        function relayout() {
            if (!session.active) {
                return;
            }
            const area = Workspace.clientArea(Workspace.MaximizeArea, session.output, session.desktop);
            const gap = tilingStackGap();
            const result = Tiling.layoutStack(session.stack, area, session.dividerX, gap);
            // Place the feasible windows.
            for (let i = 0; i < result.placed.length; ++i) {
                const p = result.placed[i];
                if (!p.window.deleted) {
                    p.window.frameGeometry = Qt.rect(p.rect.x, p.rect.y, p.rect.width, p.rect.height);
                }
            }
        }

        function addWindow(w) {
            if (!session.active || !w || manages(w)) {
                return;
            }
            if (!managesDesktop(w) || !Tiling.eligibleForStack(w)) {
                return;
            }
            const g = w.frameGeometry;
            session.savedFloats[String(w.internalId)] = { x: g.x, y: g.y, width: g.width, height: g.height };
            session.stack.push(w);
            relayout();
        }

        function removeWindow(w) {
            if (!session.active || !w) {
                return;
            }
            const idx = session.stack.indexOf(w);
            if (idx >= 0) {
                session.stack.splice(idx, 1);
                delete session.savedFloats[String(w.internalId)];
                relayout();
            }
        }

        function focusMaster() {
            if (session.active && session.master && !session.master.deleted) {
                Workspace.activeWindow = session.master;
            }
        }

        function focusNext() {
            if (!session.active) {
                return;
            }
            const next = Tiling.nextInCycle(session, Workspace.activeWindow);
            if (next && !next.deleted) {
                Workspace.activeWindow = next;
            }
        }

        function focusPrevious() {
            if (!session.active) {
                return;
            }
            const prev = Tiling.previousInCycle(session, Workspace.activeWindow);
            if (prev && !prev.deleted) {
                Workspace.activeWindow = prev;
            }
        }
    }

    // The tiler's shortcuts (sequence-less: the user assigns them; none claims a default key
    // from another action).
    ShortcutHandler {
        name: "Plasma Fusion: Tile Workspace"
        text: i18n("Toggle dynamic tiling on this workspace")
        sequence: ""
        onActivated: tiler.toggle()
    }
    ShortcutHandler {
        name: "Plasma Fusion: Tile Focus Master"
        text: i18n("Focus the tiling master window")
        sequence: ""
        onActivated: tiler.focusMaster()
    }
    ShortcutHandler {
        name: "Plasma Fusion: Tile Focus Next"
        text: i18n("Focus the next window in the tiling cycle")
        sequence: ""
        onActivated: tiler.focusNext()
    }
    ShortcutHandler {
        name: "Plasma Fusion: Tile Focus Previous"
        text: i18n("Focus the previous window in the tiling cycle")
        sequence: ""
        onActivated: tiler.focusPrevious()
    }

    // ---------------------------------------------------------------- start and stop

    Component.onCompleted: {
        log("started");
        detectNativeWriter();
        registerWithWriter();
        tiler.detectApi();
        read();
        // Windows already open when the script (re)loads - a Fusion setup enables it in a running
        // session, a reconfigure can reload it - are watched so their moves and closes are
        // remembered; they are never moved by the script itself (KWin placed them already) and not
        // recorded until the user moves or closes them.
        const windows = Workspace.stackingOrder;
        let adopted = 0;
        for (let i = 0; i < windows.length; ++i) {
            const w = windows[i];
            if (!w || w.deleted || !w.normalWindow || w.transient || w.modal) {
                continue;
            }
            if (!watched[String(w.internalId)]) {
                windowOpened(w, false);
                adopted++;
            }
        }
        if (adopted > 0) {
            log("adopted " + adopted + " open window(s)");
        }
    }

    // Disabled or KWin going away: the newest record goes out one last time, best effort (the D-Bus
    // message is on its way before the object dies) - also when an earlier write is still in
    // flight, as that one carries an older snapshot. Then the geometry handlers are disconnected:
    // KWin keeps one QML engine for its scripts and the windows outlive this object, so a handler
    // left connected would call into a destroyed context, and every disable/enable cycle would add
    // another.
    Component.onDestruction: {
        // The tiler's teardown: restore the stack floats before the script dies.
        if (tiler.session.active) {
            tiler.untoggle();
        }
        if (!nativeWriter && Placement.teardownWrite(loaded, revision, sentRevision, sending, sendingRevision)) {
            writeCall.arguments = [writeScript(Placement.serialize(apps))];
            writeCall.call();
        }
        for (const key in watched) {
            disconnectHandlers(watched[key]);
        }
    }
}
