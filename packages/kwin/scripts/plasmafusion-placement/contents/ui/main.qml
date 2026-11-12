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
// - The memory lives in ~/.config/plasmafusion-placementrc [Windows] and is written and read
//   through plasmashell's desktop scripting: the KWin scripting API has no file write (only
//   readConfig). The file is read once at start (with a few retries while plasmashell comes up);
//   windows opened before that answer keep KWin's placement.
// - Settings (kwinrc [Script-plasmafusion-placement], contents/config/main.xml): RememberSize,
//   IgnoreApps (app ids or window classes) and the tiler's MasterFraction and StackGap. The KWin
//   Scripts KCM writes them; KWin's reconfigure reloads them in place.
//
// Dynamic tiling (issue #115, Option A): the master window rides the native transient
// ownership; the stack windows are placed by direct frameGeometry writes with their
// pre-tiling floats saved for the untoggle. The tiler lives inside this package because
// the writer takes exactly one provider and the tiler IS that provider's policy consumer.
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
    // The tiler's settings: the keys are flat (no group) because KWin.readConfig reads the
    // script's own kwinrc group and nothing below it - a KConfigXT <group> would write the
    // KCM's values where readConfig cannot see them.
    function tilingMasterFraction() {
        return parseFloat(setting("MasterFraction", 0.5));
    }
    function tilingStackGap() {
        return parseInt(setting("StackGap", 8));
    }

    // ---------------------------------------------------------------- the memory writer
    // The compositor's placement writer (docs/NATIVE-TILING-CONTRACT.md): typed native calls
    // replace the legacy plasmashell D-Bus file transport. The writer's own C++ methods are not
    // callable from QML (its QUuid tokens and struct arguments do not cross that boundary), so
    // every call goes through Workspace.transientTiling(), the facade the fork exposes for the
    // provider side (fork PRs #17-#19). The token is opaque text to QML; the writer validates
    // every submission natively. On a KWin without the facade (stock or older forks) the script
    // falls back to the legacy transport below.

    property bool nativeWriter: false
    property bool nativeRefused: false // registration refused: no legacy fallback
    property var api: null // the transientTiling() facade
    property string providerToken: ""
    property int writerRevision: 0
    // app id -> the last event sequence submitted for it: the writer orders a key's events
    // globally, so every window of one app draws from the same counter.
    property var eventSequences: ({})
    // window internalId -> the app id the writer holds the window under (one key per window
    // for the window's whole lifetime; the writer refuses a second trackWindow). false marks a
    // binding the writer holds under another key (an identity that changed across a reload):
    // the window is never recorded natively again.
    property var trackedKeys: ({})

    // TransientPlacementWriter::Result, in its enum order (the type itself is not a QML enum):
    // OutdatedEvent is not a policy decision but the reload signal the sequence catch-up
    // handles; the three outcomes that are the writer's own policy decisions follow.
    readonly property var writerResult: ({ "Accepted": 0, "OutdatedEvent": 5,
                                            "Deferred": 10, "Suppressed": 11 })

    function detectNativeWriter() {
        try {
            nativeWriter = typeof Workspace.transientTiling === "function";
        } catch (e) {
            nativeWriter = false;
        }
        if (!nativeWriter) {
            log("no native placement writer; using the legacy transport");
        }
        return nativeWriter;
    }

    function registerWithWriter() {
        if (!nativeWriter || api) {
            return;
        }
        api = Workspace.transientTiling();
        if (!api) {
            // The facade exists (the detection saw the function) but answers nothing: a broken
            // compositor side. The retired legacy transport must not write behind the sole
            // native writer, so the session runs without the memory, like a refused provider.
            log("the native facade did not answer; the memory stays disabled this session");
            nativeWriter = false;
            nativeRefused = true;
            return;
        }
        providerToken = String(api.registerProvider(root));
        if (Placement.providerRefused(providerToken)) {
            // A native session must not bypass the sole native writer: the memory stays
            // disabled rather than falling back to a transport the contract retires.
            log("the writer refused the provider registration; the memory stays disabled this session");
            nativeWriter = false;
            api = null;
            nativeRefused = true;
            return;
        }
        log("registered as the placement provider");
    }

    // Bind the window to the writer under its app id (Placement.trackingDecision): a window
    // that opens before its identity is usable (no desktop file and no class yet) is bound at
    // its first record instead, and an identity that changed after the binding is never
    // rebound - the writer would file every later record under the app the window no longer is.
    function trackWithWriter(w) {
        if (!nativeWriter || !api || !w) {
            return;
        }
        const id = String(w.internalId);
        const key = appIdOf(w);
        const decision = Placement.trackingDecision(trackedKeys[id], key);
        if (decision === "track") {
            if (api.trackWindow(w, key)) {
                trackedKeys[id] = key;
                return;
            }
            // The refusal cannot be told apart on its own, so the writer is asked which key it
            // holds the window under (windowBinding, fork PR #20): a record files under the
            // binding's key, never under a key the caller passes, so writing on an assumed key
            // after an identity changed across a reload would overwrite that app's entry where
            // no comparison could detect or undo it.
            if (typeof api.windowBinding !== "function") {
                // An older fork's facade has no question to ask: the record stays in the
                // session cache rather than being filed under an assumed key.
                trackedKeys[id] = false;
                log("the writer refused the track for " + key + " and cannot be asked for its binding; it is not recorded natively");
                return;
            }
            const outcome = Placement.refusedBindingDecision(String(api.windowBinding(w)), key);
            if (outcome === "confirmed") {
                // The reload case: the binding an earlier incarnation of this script left is
                // the one to keep writing through.
                trackedKeys[id] = key;
            } else if (outcome === "changed") {
                trackedKeys[id] = false;
                log("the writer holds this window of " + key + " under an earlier key; it is not recorded natively");
            }
            // "retry": the writer was busy and holds nothing - the next record tries the track
            // again, and until then the record lives in the session cache only.
        }
    }

    function recordWithWriter(w, frame) {
        if (!nativeWriter || !api || !w || providerToken === "") {
            return;
        }
        trackWithWriter(w);
        const key = appIdOf(w);
        if (trackedKeys[String(w.internalId)] !== key) {
            // The window has no identity yet, its identity changed after the writer bound it,
            // or the writer holds it under an earlier key (an identity that changed across a
            // script reload): a submission would be filed under the wrong key, so the record
            // lives in the session cache only.
            return;
        }
        const rect = Qt.rect(frame.x, frame.y, frame.width, frame.height);
        let seq = Placement.nextEventSequence(eventSequences, key);
        // The facade call: the provider incarnation token first (the writer rejects submissions
        // from retired incarnations), then the revision, the window, the already rounded
        // rectangle, the key's event sequence and the origin (0 = Manual).
        let result = api.record(providerToken, ++writerRevision, w, rect, seq, 0);
        // A reload left the writer holding this key's watermark (the writer outlives provider
        // incarnations, and its watermarks are not readable through the facade), so the
        // submission is rejected as outdated until the counter passes it. The same rectangle is
        // resubmitted with exponentially increasing sequences - they only have to be strictly
        // increasing - so the record that finally passes carries today's frame, not a lost one;
        // the bound keeps the sequence inside the facade's int and the loop short.
        while (result === writerResult.OutdatedEvent && seq < 0x40000000) {
            seq = Placement.caughtUpSequence(seq);
            result = api.record(providerToken, ++writerRevision, w, rect, seq, 0);
        }        eventSequences[key] = seq;
        // Accepted, Deferred (an active reservation) and Suppressed (a restore watermark) are
        // the writer's decisions; anything else is a contract violation worth a line.
        if (result !== writerResult.Accepted && result !== writerResult.Deferred
                && result !== writerResult.Suppressed) {
            log("the writer refused a record for " + key + " (result " + result + ")");
        }
        // Reconcile the cache with the writer's decision: when the submission was suppressed or
        // deferred, the writer's entry for this key is the authority, not the in-memory cache
        // the policy just wrote.
        reconcileKeyWithWriter(key);
    }

    function reconcileKeyWithWriter(key) {
        if (!nativeWriter || !api || key === "") {
            return;
        }
        const snap = api.snapshot();
        if (!snap || !snap.entries) {
            return;
        }
        // Placement.reconciled adopts the writer's entry: a deferred same-key update only
        // becomes visible in the snapshot after its barrier ended, later than the cache's own
        // write, and a suppressed or deferred submission leaves the entry at the writer's
        // decision.
        apps = Placement.reconciled(apps, snap.entries, key);
    }

    function readFromWriter() {
        if (!nativeWriter || !api || loaded) {
            return;
        }
        const snap = api.snapshot();
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
        // The tiler's managed windows are not the user's floating placement (invariant 7) - but
        // a stack window the user moved or resized by hand has just left the session (the master
        // has its own native teardown for that): the tiler never fights the user for a cell, the
        // move is the window's new floating placement, and the untoggle cannot write the saved
        // float over it. The tiler's own writes never read as this hand: they run under placing,
        // and they land exactly on the cell the layout assigned (the synchronous write and the
        // client's late commit of it alike).
        if (tiler.manualMoveOf(w)) {
            tiler.detachManual(w);
            log("tiling: a member was moved by hand; it floats");
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
        const frame = frameRect(w);
        if (!Placement.settled(requestedRect(w), frame)) {
            return;
        }
        if (Placement.remember(apps, id, frame)) {
            changed();
        }
        // The writer's contract takes an already rounded rectangle within the size limits: a
        // frame it could not represent (fractional on a scaled output) is not submitted.
        const submission = Placement.valid(frame);
        if (submission) {
            recordWithWriter(w, submission);
        }
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
        // The remembered floating placement, computed once: the tiler path saves it as the
        // window's float (the untoggle returns the app to its remembered spot, as the memory
        // would have placed it), the ordinary path applies it as before.
        let remembered = null;
        if (restoreAllowed && loaded && id !== "" && !ignoredWindow(w) && Placement.eligible(state)) {
            // A deferred same-key update (an active reservation held the key) only becomes
            // visible in the writer's snapshot after its barrier ended - later than the last
            // reconciliation. The writer's entry decides the restore, not a stale mirror.
            reconcileKeyWithWriter(id);
            const saved = apps[id];
            const current = frameRect(w);
            const screens = screenRects();
            const others = siblings(id, w);
            remembered = Placement.restoreFor(id, state, saved, screens, others, ignoreList(), rememberSize(), current);
        }
        // The tiler's managed windows: a new window on the tiled workspace joins the stack,
        // not the placement memory's restore - and only when the stack really took it: a
        // window the stack cannot manage (not resizable, a minimum size above any cell it
        // would get) falls through to the ordinary restore and settle path like any
        // unmanaged window.
        if (tiler.session.active && tiler.managesDesktop(w) && tiler.addWindow(w, remembered)) {
            return;
        }
        if (remembered) {
            entry.quietUntil = Date.now() + quietMillis;
            w.frameGeometry = Qt.rect(remembered.x, remembered.y, remembered.width, remembered.height);
            log("restored " + id + " to " + remembered.x + "," + remembered.y + " " + remembered.width + "x" + remembered.height);
        } else if (remembered === null && restoreAllowed && loaded && id !== "" && !ignoredWindow(w) && Placement.eligible(state) && apps[id]) {
            // No place to restore to, but a record exists: another instance of the app may hold
            // the spot - its record stays, and this window's placement is not recorded as the new
            // one - neither by the settling pass nor by the window's own geometry changes while it
            // opens (the quiet second, as after a restore); the user's later moves are. (When the
            // spot itself is unusable - off a screen - the settle pass heals the record to where
            // KWin placed it.)
            const saved = apps[id];
            const current = frameRect(w);
            const screens = screenRects();
            const others = siblings(id, w);
            const finalRect = Placement.restoreRect(saved, current, Placement.restoreSize(state, rememberSize()));
            if (Placement.onScreen(finalRect, screens) && Placement.collides(finalRect, others)) {
                entry.settleSkip = true;
                entry.quietUntil = Date.now() + quietMillis;
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
        // The tiler: a closed managed window leaves the layout. The close record is skipped
        // for it (invariant 7 again - the stack cell it died in is not the app's floating
        // place), so the managed verdict is taken before the removal erases it.
        const wasManaged = tiler.session.active
                && (w === tiler.session.master || tiler.manages(w));
        if (tiler.session.active) {
            tiler.removeWindow(w);
        }
        // The last place before the window went. KWin marks a closing window deleted before
        // windowRemoved (Wayland and X11), so the window is read as it is: its frame geometry,
        // maximize mode and tile stay as they were (requestTile is a no-op once deleted).
        if (loaded && !entry.held && !wasManaged && Date.now() >= entry.quietUntil) {
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
        function onScreensChanged() {
            // The output geometry moved (a screen changed): the master's tile is relative to
            // the output's root, so the native layer rescales it, and the stack's divider
            // follows the master's new right edge instead of the stale stored one.
            if (tiler.session.active) {
                tiler.relayout();
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
        // window internalId -> {w, handler}: the minimize watch the tiler keeps on every
        // session member. The set doubles as the live membership list: floated and closed
        // windows are unwatched, minimized ones stay watched for the rejoin.
        property var minimizeHandlers: ({})
        // window internalId -> the cell the last layout assigned (the frame the tiler wrote):
        // a geometry change landing exactly there is the tiler's own write arriving, anything
        // else is the user's hand moving a stack window.
        property var cellRects: ({})
        // True while the tiler writes its own placements (the relayout, the float restores):
        // those writes must not read as the user's manual moves.
        property bool placing: false

        function detectApi() {
            try {
                apiAvailable = typeof Workspace.transientTiling === "function";
            } catch (e) {
                apiAvailable = false;
            }
            if (apiAvailable) {
                api = Workspace.transientTiling();
                if (!api) {
                    // The facade exists (the detection saw the function) but answers nothing:
                    // leave the tiler off without interrupting the script - the placement
                    // memory keeps working, as it does through a refused provider.
                    apiAvailable = false;
                    log("tiling: the native facade did not answer; the tiler stays off this session");
                    return apiAvailable;
                }
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
                restoreStackFloats();
                disconnectMinimizeHandlers();
                session = Tiling.createSession();
                cellRects = {};
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

        // Whether a window is on the session's workspace: the one rule (Tiling.onWorkspace)
        // the candidates, the managed windows and the leavers read - desktop, activity, and
        // the session's output (the session tiles its own screen).
        function managesDesktop(w) {
            return session.active && Tiling.onWorkspace(w, session.desktop, session.activity, session.output);
        }

        // Toggle the tiling on or off. The one-tree contract allows one session at a time, so
        // a toggle on another workspace ends that session first (its floats restore there)
        // and lays out the current one: the action always applies to the workspace it was
        // invoked on, never by untoggling a desktop the user left behind.
        function toggle() {
            if (session.active) {
                const same = Tiling.desktopMatches(session.desktop, Workspace.currentDesktop)
                        && (session.activity === "" || session.activity === String(Workspace.currentActivity));
                untoggle();
                if (same) {
                    return;
                }
            }
            start();
        }

        // The master's right edge from the facade when it answers, else the configured
        // fraction of the work area (the tree's first moments). Read at every relayout: the
        // tile is relative to the output's root, so the native layer rescales it when the
        // area changes, and the stack column follows the master instead of a stale stored x.
        function masterRightEdge(area) {
            if (apiAvailable && api) {
                const master = api.masterWindowRect();
                if (master && master.width > 0) {
                    return master.x + master.width;
                }
            }
            const fraction = Tiling.masterFraction({ masterFraction: tilingMasterFraction() });
            return area.x + Math.round(area.width * fraction);
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
            const activity = String(Workspace.currentActivity);
            if (!output || !desktop) {
                return;
            }

            // The stack candidates (before the master is admitted): this workspace's, this
            // output's, stacking order top first.
            const candidates = Tiling.stackCandidates(Workspace.stackingOrder, w, desktop, activity, output);

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
            session.activity = activity;
            session.stack = [];
            session.savedFloats = {};

            // Save every candidate's float, then layout (the divider follows the master).
            const area = Workspace.clientArea(Workspace.MaximizeArea, output, desktop);
            for (let i = 0; i < candidates.length; ++i) {
                const g = candidates[i].frameGeometry;
                session.savedFloats[String(candidates[i].internalId)] =
                    { x: g.x, y: g.y, width: g.width, height: g.height };
            }
            session.stack = candidates;
            for (let i = 0; i < session.stack.length; ++i) {
                watchMinimize(session.stack[i]);
            }
            // The workspace's minimized windows are members-to-be: their floats are saved and
            // they are watched now, because restoring one during the session emits no
            // windowAdded - it was there all along - and without a watch it would float over
            // the managed layout until the next relayout never comes for it.
            const dormant = Tiling.dormantCandidates(Workspace.stackingOrder, w, desktop, activity, output);
            for (let i = 0; i < dormant.length; ++i) {
                const g = dormant[i].frameGeometry;
                session.savedFloats[String(dormant[i].internalId)] =
                    { x: g.x, y: g.y, width: g.width, height: g.height };
                watchMinimize(dormant[i]);
            }
            relayout();
            log("tiling: on (" + session.stack.length + " stack window(s))");
        }

        // Give every session member back its saved float - but only a float that still lands
        // on a screen the session has: an output that went away takes its coordinates with it,
        // and KWin has already evacuated such a window, which a stale absolute rectangle would
        // drag offscreen. The minimize watches are the live membership: minimized members are
        // out of the layout but keep their floats, while floated and closed windows were
        // unwatched and their floats dropped with them.
        function restoreStackFloats() {
            placing = true;
            const screens = screenRects();
            for (const id in minimizeHandlers) {
                const w = minimizeHandlers[id].w;
                const saved = session.savedFloats[id];
                if (w && !w.deleted && saved && Placement.onScreen(saved, screens)) {
                    w.frameGeometry = Qt.rect(saved.x, saved.y, saved.width, saved.height);
                }
                // The restored window's own late commits of a cell must not record: the
                // geometry settles after the client acknowledges, and the quiet window the
                // restore path uses after moving a window is the tiler's here too.
                const entry = watched[id];
                if (entry) {
                    entry.quietUntil = Date.now() + quietMillis;
                }
            }
            placing = false;
        }

        function untoggle() {
            if (!session.active) {
                return;
            }
            restoreStackFloats();
            // The master's native restore (Meta+Backspace equivalent).
            if (session.master && !session.master.deleted) {
                Workspace.activeWindow = session.master;
                Workspace.slotWindowRestore();
            }
            // Release the tree (an empty tree blocks future createTile).
            if (apiAvailable && api && session.generation > 0) {
                api.releaseTile(session.generation);
            }
            disconnectMinimizeHandlers();
            session = Tiling.createSession();
            cellRects = {};
            log("tiling: off");
        }

        function relayout() {
            if (!session.active) {
                return;
            }
            const area = Workspace.clientArea(Workspace.MaximizeArea, session.output, session.desktop);
            session.dividerX = masterRightEdge(area);
            const gap = tilingStackGap();
            const result = Tiling.layoutStack(session.stack, area, session.dividerX, gap);
            // The tiler's own writes: while these run, a geometry change is not the user's
            // hand (the manual-move detach reads this).
            placing = true;
            // Place the feasible windows and remember each cell: a later change landing
            // exactly there is this write arriving (the synchronous one or the client's late
            // commit of it), not a manual move.
            for (let i = 0; i < result.placed.length; ++i) {
                const p = result.placed[i];
                if (!p.window.deleted) {
                    p.window.frameGeometry = Qt.rect(p.rect.x, p.rect.y, p.rect.width, p.rect.height);
                }
                cellRects[String(p.window.internalId)] = p.rect;
            }
            // A window whose minimum size does not fit its cell stops being managed. One the
            // layout had placed sits at a cell no untoggle can undo, so its saved float goes
            // back first; one the layout never placed already sits at its own float (the
            // geometry it keeps is its own). Either way the tiler never wrote anything it
            // owns, its moves reach the placement memory again, and the untoggle does not
            // drag it back to a rectangle it left before the session.
            const restores = Tiling.floatRestores(result.floated, session.savedFloats, cellRects);
            for (let i = 0; i < restores.length; ++i) {
                if (!restores[i].window.deleted) {
                    restores[i].window.frameGeometry =
                        Qt.rect(restores[i].rect.x, restores[i].rect.y, restores[i].rect.width, restores[i].rect.height);
                }
            }
            placing = false;
            for (let i = 0; i < result.floated.length; ++i) {
                detachWindow(result.floated[i], false);
            }
        }

        // Take a window out of the stack without touching the layout (a relayout that
        // floats windows is already computing the new column). keepFloat is the minimize
        // case: the window stays a member (it rejoins on restore, and the untoggle still
        // puts it back where it floated before the session).
        function detachWindow(w, keepFloat) {
            const idx = session.stack.indexOf(w);
            if (idx >= 0) {
                session.stack.splice(idx, 1);
            }
            if (!keepFloat) {
                delete session.savedFloats[String(w.internalId)];
                delete cellRects[String(w.internalId)];
                unwatchMinimize(w);
            }
        }

        // A new window joins the stack; true when it did. True also for a window that arrives
        // already minimized: it is enrolled as a member-to-be (watched, not stacked - its
        // restore enrolls it). False leaves the window to the ordinary paths (restore,
        // settle): the stack only keeps what it can manage, and a candidate the first layout
        // floats is handed back untouched. The saved float is the remembered placement when
        // the memory has one (the untoggle returns the app to its remembered spot, as the
        // memory would have placed it), else the window's current geometry.
        function addWindow(w, remembered) {
            if (!session.active || !w || manages(w)) {
                return false;
            }
            if (!managesDesktop(w)) {
                return false;
            }
            // A window that arrives minimized is the same member-to-be the toggle-on scan
            // watches (Tiling.eligibleDormant, the one rule): for it too, a later restore
            // emits no windowAdded - it was there all along - so the watch must go on now or
            // its restore floats over the managed column. The watch's restore path enrolls
            // it, with the eligibility recheck, and the float is the remembered placement
            // when the memory has one, as for every new member.
            if (Tiling.eligibleDormant(w)) {
                const g = remembered || w.frameGeometry;
                session.savedFloats[String(w.internalId)] = { x: g.x, y: g.y, width: g.width, height: g.height };
                watchMinimize(w);
                return true;
            }
            if (!Tiling.eligibleForStack(w)) {
                return false;
            }
            const g = remembered || w.frameGeometry;
            session.savedFloats[String(w.internalId)] = { x: g.x, y: g.y, width: g.width, height: g.height };
            session.stack.push(w);
            watchMinimize(w);
            relayout();
            return session.stack.indexOf(w) >= 0;
        }

        // A stack window the user moved or resized by hand leaves the session: the move is its
        // new floating placement (recorded by the caller), the tiler never fights the user for
        // a cell, and the untoggle cannot write the saved float over the move. The master is
        // not this: its manual teardown is native (a manual move ends the tree), and a
        // maximize or full-screen frame of the master is a mode change, not a hand - cellRects
        // holds stack cells only, so including the master here would read its full-area frame
        // as a move and relayout the stack to nothing.
        function manualMoveOf(w) {
            return tiler.session.active && !tiler.placing && tiler.manages(w)
                    && w !== tiler.session.master
                    && !Tiling.isOwnCell(tiler.cellRects[String(w.internalId)], frameRect(w));
        }

        // The user's manual move or resize of a stack member: it leaves the session (the
        // cell refills) and the move stands - the caller records it as the floating
        // placement the window now is.
        function detachManual(w) {
            detachWindow(w, false);
            relayout();
        }

        // A closed window leaves the session for good.
        function removeWindow(w) {
            if (!session.active || !w) {
                return;
            }
            detachWindow(w, false);
            relayout();
        }

        // The membership watch on every session member (and every dormant one): a window
        // that minimizes leaves the layout (its cell refills) and rejoins on restore - the
        // saved float survives both, so the untoggle still restores it - and a window that
        // moves to another desktop or activity during the session stops being managed:
        // the session is per-workspace, its cell belongs to the workspace it left, and the
        // move itself is the user's (the geometry it carries over stays its own; the float
        // is dropped so the untoggle cannot drag it back).
        function watchMinimize(w) {
            const id = String(w.internalId);
            if (!w || minimizeHandlers[id] || !w.minimizedChanged) {
                return;
            }
            const handler = function () {
                if (!session.active) {
                    return;
                }
                if (w.minimized) {
                    if (session.stack.indexOf(w) >= 0) {
                        detachWindow(w, true);
                        relayout();
                    }
                    return;
                }
                if (session.stack.indexOf(w) < 0 && managesDesktop(w) && Tiling.eligibleForStack(w)
                        && session.savedFloats[String(w.internalId)] !== undefined) {
                    session.stack.push(w);
                    relayout();
                }
            };
            // The leave check: a member that moved to another desktop, another activity or
            // another output stops being managed - the session is per-workspace and
            // per-screen, its cell belongs where the window no longer is, and the move
            // itself is the user's (the geometry it carries stays its own; the float is
            // dropped so the untoggle cannot drag it back). A dormant member-to-be (minimized
            // at toggle-on, not yet in the stack) has no cell, but its saved float belongs to
            // the view it left: drop it too, or the untoggle would drag the window back to a
            // desktop, activity or output it was moved away from while minimized.
            const workspaceLeft = function () {
                if (!session.active) {
                    return;
                }
                if (session.stack.indexOf(w) >= 0) {
                    if (!managesDesktop(w)) {
                        detachWindow(w, false);
                        relayout();
                        log("tiling: a member left the workspace");
                    }
                    return;
                }
                if (session.savedFloats[String(w.internalId)] !== undefined && !managesDesktop(w)) {
                    delete session.savedFloats[String(w.internalId)];
                    unwatchMinimize(w);
                }
            };
            minimizeHandlers[id] = { w: w, handler: handler, onWorkspace: workspaceLeft };
            w.minimizedChanged.connect(handler);
            if (w.desktopsChanged) {
                w.desktopsChanged.connect(workspaceLeft);
            }
            if (w.activitiesChanged) {
                w.activitiesChanged.connect(workspaceLeft);
            }
            if (w.outputChanged) {
                w.outputChanged.connect(workspaceLeft);
            }
        }

        function unwatchMinimize(w) {
            const id = String(w.internalId);
            const entry = minimizeHandlers[id];
            if (entry && entry.w) {
                if (entry.w.minimizedChanged) {
                    entry.w.minimizedChanged.disconnect(entry.handler);
                }
                if (entry.onWorkspace) {
                    if (entry.w.desktopsChanged) {
                        entry.w.desktopsChanged.disconnect(entry.onWorkspace);
                    }
                    if (entry.w.activitiesChanged) {
                        entry.w.activitiesChanged.disconnect(entry.onWorkspace);
                    }
                    if (entry.w.outputChanged) {
                        entry.w.outputChanged.disconnect(entry.onWorkspace);
                    }
                }
            }
            delete minimizeHandlers[id];
        }

        function disconnectMinimizeHandlers() {
            for (const id in minimizeHandlers) {
                unwatchMinimize(minimizeHandlers[id].w);
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
