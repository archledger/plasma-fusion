/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQml
import org.kde.kwin
import org.kde.plasma.workspace.dbus as DBus
import "Tiling.js" as Tiling

// What the placement script tells the bars' layout controls about tiling: whether supported
// tiling is available, whether a session is on and the view it tiles, in an order a reader can
// trust (the workspace layout control, P1). The script stays the only authority: it binds
// `nativeCapable` to its native verdict and hands the session in where the tiler starts or ends
// one (main.qml, tiler.reportSession). This object keeps that state, its revision, a lifetime
// label and the lifetime's identity name on the session bus, reads the bars' requests and
// answers them; it is never given the native token. A bar's menu prepares its action first (P5):
// the provider keeps the app the menu was opened from and the bar's view, inside KWin, in its one
// prepared slot, and the bar names that preparation by a handle when it sets a mode, which the
// script's tiler applies (main.qml, tiler.applyMode).
//
// Read the state on revisionChanged: a change sets the fields first and moves the revision
// last, once.
QtObject {
    id: provider

    // The native verdict, bound by the script: a registered provider, its memory loaded and the
    // tiler's facade complete. Anything less never reports ready.
    property bool nativeCapable: false

    // Written by start(), setSession(), retire() and a change of the verdict alone.
    // Whether the provider serves its state: from start() until retire().
    property bool online: false
    // Whether supported tiling is available: the verdict while online, false while offline, so
    // no state carries a capability that changed after its revision.
    property bool capable: false
    // The state's order: 1 at start(), then one step for each change of what a reader is told -
    // capability, the session or its view, a bar's own view (views), the end of a holder's
    // preparation, a set's completion decided after its read, going offline - and none
    // otherwise.
    property int revision: 0
    // The session, and the view it tiles as a bar names one.
    property bool active: false
    property string desktopId: ""
    property string activityId: ""
    property string outputName: ""

    // A public lifetime label, not a credential: drawn fresh for every provider lifetime, so a
    // refused or absent backend cannot share one (as the layout probe draws its own).
    readonly property string label: Qt.md5([Date.now(), Math.random(), Math.random(),
                                            Math.random(), Math.random()].join(":"))

    // The lifetime's identity name: a fence between provider lifetimes on the session bus, not
    // authentication (g0-decisions.md). It is asked for at start(), whatever the capability,
    // without queueing (flag 4: a name another connection holds is refused at once), and
    // released by retire() with the name it stored, so nothing of a torn-down context is
    // looked up; it exports no object. Its owner, once granted, is this connection - KWin's -
    // which a reader checks against the KWin service's owner. The layout probe proved this
    // transport in P0 (tools/tests/layout-control/provider.qml).
    readonly property string identityName: "org.plasmafusion.LayoutProvider.p" + label
    // Whether the name is held and its owner - a unique connection name, kept only then - is
    // known; the identity never moves the revision.
    property bool identityReady: false
    property string selfOwner: ""
    // The pending RequestName, until it is answered or the provider retires.
    property var registration: null

    property Connections registrationWatch: Connections {
        target: provider.registration
        function onFinished() {
            provider.registrationFinished();
        }
    }

    property DBusCall identityLookup: DBusCall {
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "GetNameOwner"
        onFinished: value => provider.ownerFound(String(value[0]))
        onFailed: console.warn("plasmafusion-placement: layout provider: the identity name's owner could not be"
                               + " read; nothing will be published this session")
    }

    property DBusCall identityRelease: DBusCall {
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "ReleaseName"
    }

    // Decision 1's time limit: the shell serves a script call on its main thread and takes no
    // input until the call answers - a click waits for it to end (the click reproduction,
    // g0-receipt.md) - so a read or a publication should keep the shell at most this many
    // milliseconds: a click that comes at the worst moment then still answers well within the
    // 100 ms at which a response stops feeling immediate. The scripts' own work is small and
    // bounded - one script, at most 16 widgets read or written, widget data as JSON - but a
    // publication also has the shell save its widget configuration to disk (writerScript), which
    // the provider cannot make shorter. So the limit is watched, not guaranteed: each call's
    // lengths are said, and one over the limit is said as such (report()).
    readonly property int shellLimit: 50

    // What the bars ask for, read from the shell (the layout probe's P0 transport): a bar's
    // clock saves its request in a field of its own and wakes the provider through a shortcut
    // with no key; the provider reads every clock's request with one shell script call on the
    // shell's unique connection. The reads are bounded as the probe's - at most 16 widgets,
    // requests of at most 2048 characters, a consumer label of 1 to 128 characters and a request
    // number of 1 to 2147483646 - copy only the fields the intents need (the epoch and the view's
    // two ids, which a prepare names, and a set's mode and handle), and carry widget data as JSON,
    // never as code. With the rows, the script says when it started, for the call's length, and
    // which widgets it saw: their ids, those whose request field is empty (a withdrawn request),
    // and whether there were more than it reads. A widget is gone, or its request withdrawn, only
    // by such a complete inventory; an unreadable request proves neither (the layout probe's
    // rule, testing.md).
    readonly property string requestApplet: "org.plasmafusion.clockpill"
    readonly property string readerScript: "var start=Date.now(),rows=[],widgets=[],empty=[],"
        + "truncated=false;"
        + "panels().forEach(function(p) {"
        + "p.widgets('" + requestApplet + "').forEach(function(w) {"
        + "if(widgets.length>=16){truncated=true;return;}widgets.push(w.id);"
        + "w.currentConfigGroup=['General'];try {var text=w.readConfig('layoutRequest','');"
        + "if(text===''){empty.push(w.id);return;}"
        + "if(text.length>2048)return;"
        + "var q=JSON.parse(text);"
        + "if(typeof q.consumer!=='string'||!q.consumer.length||q.consumer.length>128"
        + "||!Number.isInteger(q.request)||q.request<=0||q.request>2147483646)return;"
        + "var v=q.view;"
        + "rows.push({id:w.id,consumer:q.consumer,request:q.request,version:q.version,"
        + "intent:q.intent,outputName:q.outputName,epoch:q.epoch,mode:q.mode,handle:q.handle,"
        + "view:v!==null&&typeof v==='object'?{desktopId:v.desktopId,activityId:v.activityId}:v});"
        + "}catch(e){} }); });"
        + "print(JSON.stringify({start:start,rows:rows,widgets:widgets,empty:empty,"
        + "truncated:truncated}));"
    // What the last read found: the queries to answer, and the rows refused before any action,
    // each with its widget, consumer, request and reason. A failed read keeps them as they were.
    property var requests: []
    property var refusals: []
    // A read in flight, and whether a wake came meanwhile: one read at a time, and the wakes
    // during it make one more read after it. When its script call went out, for its length.
    property bool reading: false
    property bool again: false
    property real readAt: 0

    // The shell's process as the bus tells it for the connection read from: a shell surface
    // counts only with this PID, never by a class or app id (the layout probe's rule,
    // testing.md). Looked up once per shell connection, beside that connection's first read;
    // `pidFor` is the connection a lookup in flight is for. Each connection with a PID gets the
    // next shell serial, which a handle names.
    property int shellPid: 0
    property string shellPidOwner: ""
    property string pidFor: ""
    property int shellSerial: 0
    // Focus as KWin activates windows: the window that has it, the last eligible app (a shell
    // surface keeps it, any other window clears it), and the handoff the last focus change made,
    // if it was a shell applet popup opened straight from that app, or from a shell dock or
    // desktop surface on its output while the app was remembered: the app a bar's menu was opened
    // from. With no handoff, `missed` says why: no app to hand off, or focus that came from
    // elsewhere. Every change of focus replaces both, so a handoff is always the latest.
    property var lastFocused: null
    property var lastEligible: null
    property var handoff: null
    property string missed: "no-target"
    // The one prepared slot - the widget and request that hold it, its handle, the captured view
    // and target and the focus surface, all native references kept here - and the serial of its
    // handles, monotonic for the lifetime. Per widget, the last intent handled (its consumer,
    // request, payload and completion, decided once), and the preparation its frames carry.
    property var slot: null
    property int slotSerial: 0
    property var records: ({})
    property var preparations: ({})
    // The tiler's side of a set (main.qml): `applier(request, done)` applies a mode with a slot's
    // native references and calls done(result, reason) once, at once or when a retried start
    // ends; `startPending` says a start is being retried. The provider is never given the tiler.
    property var applier: null
    property bool startPending: false

    property DBusCall shellPidLookup: DBusCall {
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "GetConnectionUnixProcessID"
        onFinished: value => provider.shellPidFound(Number(value[0]))
        onFailed: provider.shellPidFound(0)
    }

    property Connections focusWatch: Connections {
        target: Workspace
        enabled: provider.online
        function onWindowActivated(window) {
            provider.activated(window);
        }
        function onWindowRemoved(window) {
            provider.revalidate();
        }
    }
    // The prepared target's own changes, as KWin notifies them: a desktop, activity or output it
    // leaves, or a state that makes it no eligible app - minimized, fullscreen, maximized, tiled,
    // out of the taskbar or the window switcher, modal - end the preparation. KWin notifies no
    // change of moveable or resizeable, and a mapped window seldom turns transient, which no
    // offline case can make happen (the stand-in windows cannot declare `transient`): those are
    // found by the slot's next check.
    property Connections targetWatch: Connections {
        target: provider.slot && provider.slot.window ? provider.slot.window : null
        function onDesktopsChanged() {
            provider.revalidate();
        }
        function onActivitiesChanged() {
            provider.revalidate();
        }
        function onOutputChanged() {
            provider.revalidate();
        }
        function onMinimizedChanged() {
            provider.revalidate();
        }
        function onFullScreenChanged() {
            provider.revalidate();
        }
        function onMaximizedChanged() {
            provider.revalidate();
        }
        function onTileChanged() {
            provider.revalidate();
        }
        function onSkipTaskbarChanged() {
            provider.revalidate();
        }
        function onSkipSwitcherChanged() {
            provider.revalidate();
        }
        function onModalChanged() {
            provider.revalidate();
        }
    }

    property ShortcutHandler wake: ShortcutHandler {
        name: "Plasma Fusion: Refresh Layout Controls"
        text: i18n("Refresh the layout controls on the bars (the bars use this; it needs no key)")
        sequence: ""
        onActivated: provider.scan()
    }

    property DBusCall shellLookup: DBusCall {
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "GetNameOwner"
        arguments: ["org.kde.plasmashell"]
        onFinished: value => provider.shellFound(String(value[0]))
        onFailed: provider.shellLost()
    }

    property DBusCall reader: DBusCall {
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: value => provider.readFinished(String(value[0]))
        onFailed: provider.readFailed()
    }

    // What the bars are told (the probe's transport, publication side): a frame per request in
    // the clock's own response field (`layoutResponse`, General group), all of them written by
    // one shell script call on the connection the requests came from. A frame names the protocol
    // version and the request it answers, the provider's lifetime - its label (`epoch`), identity
    // name and owner, which a bar checks against the bus - and the state's order and status; then
    // the capability and the bar's view as the provider resolves it from the bar's output, with
    // whether a session tiles it, or for a refused request its reason. Nothing of a window
    // travels, and never the native token.
    readonly property string responseField: "layoutResponse"
    // The connection the last read came from: its answers go there.
    property string replyOwner: ""
    // What each widget was last told there, without the revision: a widget whose frame would say
    // the same is not written again (decision 1: publish only for a new request or a changed
    // state). The connection it was told on; another is told everything.
    property var sent: ({})
    property string sentOwner: ""
    // Each request's view as the state tells it, by widget: the output it names and that output's
    // view as resolved then. A read resolves the view of a widget's first request, or of one that
    // names another output (a request renewed for the same output keeps its view); a change of a
    // desktop, the activity or the outputs resolves them all again, and moves the revision when
    // one differs - so a frame never carries a view newer than its revision.
    property var views: ({})
    // KWin says each output's change of desktop on its own (VirtualDesktopManager::currentChanged,
    // for every output whose desktop changed, with or without desktops per output - the same at
    // 6.7.5 and 6.8.3); the changes of one turn are resolved once.
    property Connections viewWatch: Connections {
        target: Workspace
        enabled: provider.online
        function onCurrentDesktopChanged() {
            Qt.callLater(provider.viewsMoved);
        }
        function onCurrentActivityChanged() {
            Qt.callLater(provider.viewsMoved);
        }
        function onScreensChanged() {
            Qt.callLater(provider.viewsMoved);
        }
    }
    // One publication at a time and never during a read: whether one is due, and the one in
    // flight - its frames and when it went out, for its length.
    property bool publishing: false
    property bool publicationDue: false
    property var pending: null

    property DBusCall writer: DBusCall {
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: value => provider.publicationFinished(String(value[0]))
        onFailed: provider.publicationFailed()
    }

    // A state change is told once the changes of its turn are done: the untoggle reports the
    // session's end before it restores the windows, and a press on another desktop ends one
    // session and starts the next - one publication says where they left the state.
    onRevisionChanged: {
        if (online) {
            publicationDue = true;
            Qt.callLater(provider.releaseDue);
        }
    }

    // The identity's arrival is the first read: the requests the clocks saved before this
    // lifetime are read too, and the wakes that came before it are that read.
    onIdentityReadyChanged: {
        if (identityReady) {
            again = false;
            scan();
        }
    }

    // A verdict that changes while online (a memory that loads late) is a new state; one that
    // changes while offline is no state at all.
    onNativeCapableChanged: {
        if (online) {
            capable = nativeCapable;
            revision += 1;
        }
    }

    // The script has started: the state as it stands is the first one, and the lifetime asks
    // for its identity name.
    function start(): void {
        if (online || revision > 0) {
            return;
        }
        online = true;
        capable = nativeCapable;
        revision = 1;
        // An explicit signature: the plugin then encodes each argument by its letter, so the
        // flags go out as a uint32 with no wrapper type (plasma-workspace components/dbus,
        // the same at 6.7.5 and 6.8.3: DBusPendingReply::callInternal, Encoder::encode).
        registration = DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "RequestName", signature: "(su)",
            arguments: [identityName, 4]
        });
    }

    // RequestName answered: only a primary ownership (1) is the name; its owner is read next.
    // retire() drops a pending request, so no answer arrives here once offline.
    function registrationFinished(): void {
        if (!registration || !registration.isFinished) {
            return;
        }
        // The plugin's decoder returns a uint32 as a value wrapper, not a plain number, and an
        // error's text as its value: an error is no grant.
        const granted = registration.isValid && registration.value.value === 1;
        const finished = registration;
        registration = null;
        finished.destroy();
        if (!granted) {
            console.warn("plasmafusion-placement: layout provider: the identity name was not granted;"
                         + " nothing will be published this session");
            return;
        }
        identityLookup.arguments = [identityName];
        identityLookup.call();
    }

    // Only a unique connection name is an owner; nothing else is kept as one. The owner is set
    // before the flag, so whatever reacts to identityReady finds it.
    function ownerFound(owner: string): void {
        if (!online) {
            return;
        }
        const unique = owner.startsWith(":");
        selfOwner = unique ? owner : "";
        identityReady = unique;
    }

    // A session started or ended; nothing moves when nothing changed.
    function setSession(on: bool, desktop: string, activity: string, output: string): void {
        if (!online || (active === on && desktopId === desktop && activityId === activity
                        && outputName === output)) {
            return;
        }
        active = on;
        desktopId = desktop;
        activityId = activity;
        outputName = output;
        revision += 1;
    }

    // A read: the shell's owner first, then the clocks' requests from that connection. None
    // before the identity is ready (its arrival reads) or once offline, and one at a time, never
    // during a publication (decision 1's serialized pipeline).
    function scan(): void {
        if (!online) {
            return;
        }
        if (!identityReady || reading || publishing) {
            again = true;
            return;
        }
        reading = true;
        shellLookup.call();
    }

    // The shell's owner: only a unique connection is read from. An answer that comes once the
    // read is over (retire() ends it) reaches nothing, here and below.
    function shellFound(owner: string): void {
        if (!reading) {
            return;
        }
        if (!owner.startsWith(":")) {
            finishRead();
            return;
        }
        if (owner !== shellPidOwner) {
            // Another shell connection: its surfaces are not the old one's, so the slot made under
            // the old one goes and the remembered app with it.
            if (shellPidOwner !== "") {
                if (slot) {
                    invalidate("shell-replaced");
                }
                lastEligible = null;
                handoff = null;
                missed = "no-target";
                shellPid = 0;
                shellPidOwner = "";
            }
            // Its PID is looked up beside the read, never before it: the queries do not wait for
            // the bus. A prepare read before the PID is known is refused, not held; the first read
            // on a connection comes as the shell or the provider starts, and a menu sends a new
            // prepare on its next input.
            if (pidFor === "") {
                pidFor = owner;
                shellPidLookup.arguments = [owner];
                shellPidLookup.call();
            }
        }
        readFrom(owner);
    }

    // The shell's PID for the connection asked about, or 0 when the bus could not tell. It counts
    // only while that connection is still the one read from; otherwise, or on a failure, the next
    // read asks again. With no PID no surface is the shell's, and every prepare is refused.
    function shellPidFound(pid: real): void {
        if (!online || pidFor === "") {
            return;
        }
        const owner = pidFor;
        pidFor = "";
        if (Number.isInteger(pid) && pid > 0 && owner === reader.service
                && shellSerial < 2147483646) {
            shellPid = pid;
            shellPidOwner = owner;
            shellSerial += 1;
        }
    }

    function readFrom(owner: string): void {
        reader.service = owner;
        reader.arguments = [readerScript];
        readAt = Date.now();
        reader.call();
    }

    function shellLost(): void {
        if (reading) {
            finishRead();
        }
    }

    function readFailed(): void {
        if (!reading) {
            return;
        }
        console.warn("plasmafusion-placement: layout provider: the bars' requests could not be read");
        finishRead();
    }

    // The shell's answer, checked again here: the script's start, at most 16 rows - bounded
    // before anything walks them - and, if it has an inventory, one consistent with the rows; an
    // answer that fails any of these is malformed as a whole. Then each row with a well-formed
    // identity (a row without one cannot be answered and is dropped) is a request if it is a
    // version-1 query, prepare or set for a named output, a prepare with its frozen context and a
    // set with its mode and handle; every other row is refused before any action, with its
    // reason.
    function readFinished(text: string): void {
        if (!reading) {
            return;
        }
        const answer = parsed(text);
        const rows = answer !== null && Array.isArray(answer.rows) && answer.rows.length <= 16
            ? answer.rows : null;
        const inventory = rows !== null ? inventoryOf(answer) : false;
        if (rows === null || !Number.isFinite(answer.start) || inventory === false) {
            console.warn("plasmafusion-placement: layout provider: the bars' requests came back malformed");
            finishRead();
            return;
        }
        const length = callLength(readAt, answer.start);
        const accepted = [];
        const refused = [];
        for (const row of answer.rows) {
            const checked = checkedRow(row);
            if (checked === null) {
                continue;
            }
            if (checked.reason !== undefined) {
                refused.push(checked);
            } else {
                accepted.push(checked);
            }
        }
        requests = accepted;
        refusals = refused;
        // The answers go where the requests came from, and the record keeps only the widgets
        // read; what is new goes out once the read is over.
        replyOwner = reader.service;
        const read = {};
        for (const row of accepted.concat(refused)) {
            if (sent[row.id] !== undefined) {
                read[row.id] = sent[row.id];
            }
        }
        sent = read;
        // A request keeps the view it was told while it names the same output; a widget's first
        // request, or one that names another output, is resolved now.
        const resolved = {};
        for (const row of accepted) {
            const kept = views[row.id];
            resolved[row.id] = kept && kept.outputName === row.outputName ? kept
                : { outputName: row.outputName, view: viewOf(row.outputName) };
        }
        views = resolved;
        settleIntents(accepted, refused, inventory);
        publicationDue = true;
        report("read", "read " + accepted.length + " request(s), " + refused.length + " refused", length);
        finishRead();
    }

    // The widgets a read saw, from its answer: null for an answer without an inventory (then no
    // widget is known gone), false for a malformed or inconsistent one - a row twice, or a row of
    // a widget it does not list or lists as empty, as the layout probe refused - else the ids,
    // those with an empty request field and whether the inventory is complete (no more widgets
    // than the reader reads).
    function inventoryOf(answer: var): var {
        if (answer.widgets === undefined && answer.empty === undefined
                && answer.truncated === undefined) {
            return null;
        }
        const ids = answer.rows.map(row => row !== null && typeof row === "object" ? row.id : null);
        if (!Array.isArray(answer.widgets) || answer.widgets.length > 16
                || !answer.widgets.every(id => Number.isInteger(id))
                || !Array.isArray(answer.empty)
                || !answer.empty.every(id => answer.widgets.indexOf(id) >= 0)
                || typeof answer.truncated !== "boolean"
                || ids.some((id, index) => ids.indexOf(id) !== index)
                || ids.some(id => answer.widgets.indexOf(id) < 0)
                || ids.some(id => answer.empty.indexOf(id) >= 0)) {
            return false;
        }
        return { widgets: answer.widgets, empty: answer.empty, complete: !answer.truncated };
    }

    // What a read means for the intents. A preparation, its slot and its frames, lasts until its
    // holder's next request: another request - refused or not, and a query reusing the prepare's
    // number too - or a withdrawal (an empty field); a complete inventory without the holder's
    // widget ends the slot as `consumer-retired`, told to no bar, since none is there to read it,
    // so it moves no revision. Such an inventory also drops the records of the widgets it did not
    // see, and nothing else does. The holder's set naming the slot's handle is the exception: it
    // is handled below against the slot, which it ends whatever its outcome (applySet); a set
    // with an older request number than the preparation's is not, and frees it as any other
    // request does. Then each intent is decided once per request identity: the same identity and
    // payload read again gets the completion recorded for it (none while a set is under way, whose
    // outcome is recorded when it comes), the same identity with another payload or a lower
    // request number is refused, and a new one is handled and recorded.
    function settleIntents(accepted: var, refused: var, inventory: var): void {
        const same = (held, row) => row.intent === "prepare" && held.consumer === row.consumer
            && held.request === row.request;
        const consumes = row => row.intent === "set" && slot.consumer === row.consumer
            && slot.handle === row.handle && row.request > slot.request;
        for (const row of accepted.concat(refused)) {
            if (slot && slot.id === row.id && !same(slot, row) && !consumes(row)) {
                slot = null;
            }
            const prep = preparations[row.id];
            if (prep && !same(prep, row)) {
                delete preparations[row.id];
            }
        }
        if (inventory !== null) {
            for (const id of inventory.empty) {
                delete preparations[id];
                if (slot && slot.id === id) {
                    slot = null;
                }
            }
        }
        if (inventory !== null && inventory.complete) {
            for (const id of Object.keys(records)) {
                if (inventory.widgets.indexOf(Number(id)) < 0) {
                    delete records[id];
                    delete preparations[id];
                }
            }
            // The holder has a record (its prepare made one), so its preparation went just now.
            if (slot && inventory.widgets.indexOf(slot.id) < 0) {
                invalidate("consumer-retired");
            }
        }
        for (const row of accepted) {
            if (row.intent === "query") {
                continue;
            }
            const payload = JSON.stringify(row.intent === "prepare"
                ? [row.intent, row.outputName, row.epoch, row.view.desktopId, row.view.activityId]
                : [row.intent, row.outputName, row.mode, row.handle]);
            const record = records[row.id];
            if (record && record.consumer === row.consumer && row.request <= record.request) {
                row.completion = row.request < record.request
                    ? refusal(row.intent, "stale-request")
                    : record.payload === payload ? record.completion
                    : refusal(row.intent, "conflicting-request");
                continue;
            }
            const entry = { consumer: row.consumer, request: row.request, payload: payload,
                            completion: undefined };
            records[row.id] = entry;
            const completion = row.intent === "prepare" ? prepare(row) : applySet(row);
            row.completion = completion;
            entry.completion = completion;
            if (row.intent === "prepare") {
                console.info("plasmafusion-placement: layout provider: a prepare "
                    + (completion.result !== "done" ? "was refused, " + completion.reason
                       : completion.target ? "is ready with its target"
                       : "is ready, " + completion.reason));
            } else {
                console.info("plasmafusion-placement: layout provider: a set (" + row.mode + ") "
                    + (completion === undefined ? "is under way"
                       : completion.result === "done" ? "is done"
                       : "was refused, " + completion.reason));
            }
        }
    }

    function refusal(intent: string, reason: string): var {
        return { intent: intent, result: "refused", reason: reason };
    }

    // A prepare handled for the first time. Refused, before any capture and in this order, when
    // the bar's frozen context is not this lifetime's or its output's view now (so a prepare saved
    // under another lifetime is stale whatever else holds), when the provider cannot prepare (no
    // capability, or no PID for the shell connection read from), when another widget holds the
    // slot, or when no verified shell applet popup on the bar's output holds focus. Otherwise the
    // slot is taken for the view, with a handle, and with the app the popup was opened from as its
    // target when that app is eligible and on the view; never another window.
    function prepare(row: var): var {
        const outputs = Workspace.screens.filter(output => String(output.name) === row.outputName);
        const view = viewOf(row.outputName);
        if (row.epoch !== label || outputs.length !== 1 || view === null
                || view.desktopId !== row.view.desktopId
                || view.activityId !== row.view.activityId) {
            return refusal("prepare", "stale-context");
        }
        if (!capable || shellPid <= 0 || shellPidOwner !== replyOwner) {
            return refusal("prepare", "unavailable");
        }
        if (slot && slot.id !== row.id) {
            return refusal("prepare", "busy");
        }
        const output = outputs[0];
        const active = Workspace.activeWindow;
        if (!shellOwnsFocus(active, output) || active.appletPopup !== true
                || lastFocused !== active) {
            return refusal("prepare", "popup-focus-unconfirmed");
        }
        if (slotSerial >= 2147483646) {
            return refusal("prepare", "unavailable");
        }
        const desktop = Workspace.currentDesktopForScreen(output);
        const activity = String(Workspace.currentActivity);
        let target = null;
        let reason = missed;
        if (handoff && handoff.popup === active) {
            if (Tiling.eligibleForMaster(handoff.window)
                    && Tiling.onWorkspace(handoff.window, desktop, activity, output)) {
                target = handoff.window;
            } else {
                reason = "no-target";
            }
        }
        slotSerial += 1;
        const handle = label + ":" + shellSerial + ":" + slotSerial;
        slot = { id: row.id, consumer: row.consumer, request: row.request, handle: handle,
                 owner: replyOwner, outputName: row.outputName, output: output, desktop: desktop,
                 activity: activity, window: target, focusSurface: active,
                 view: { desktopId: view.desktopId, activityId: view.activityId } };
        preparations[row.id] = { consumer: row.consumer, request: row.request, handle: handle,
                                 ready: true, reason: "" };
        const completion = { intent: "prepare", result: "done", handle: handle,
                             target: target !== null };
        if (target === null) {
            completion.reason = reason;
        }
        return completion;
    }

    // A set handled for the first time. It acts only through the slot its handle names - this
    // widget's, for the output it names, under this lifetime and shell - and, as its holder's
    // next request, ends it whatever its outcome. Refused before any action, in this order:
    // `stale-context` when the handle names no such slot; `unavailable` when the provider cannot
    // act and `busy` while the tiler retries a start, the shortcut's or another set's, both
    // freeing the slot as any next request does (the menu prepares again on its next input); or
    // the reason the preparation no longer holds, its focus surface included (the user's live
    // intent), with which the slot ends. Otherwise the set consumes the slot and the tiler
    // applies the mode with the slot's native references and decides the completion: returned
    // here when it decides at once, else undefined and told when its retried start ends. Each
    // retry re-checks only what the set itself does not move - the target, the captured view's
    // existence (its output, desktop and activity), the lifetime and the shell - not the focus
    // or which view is current, as the transfer moves both.
    function applySet(row: var): var {
        if (!slot || slot.id !== row.id || slot.consumer !== row.consumer
                || slot.handle !== row.handle || slot.outputName !== row.outputName) {
            // The holder's own set for another output still ends its preparation; another
            // widget's leaves the holder's slot alone.
            if (slot && slot.id === row.id) {
                slot = null;
            }
            return refusal("set", "stale-context");
        }
        if (!capable || shellPid <= 0 || shellPidOwner !== replyOwner
                || typeof applier !== "function") {
            slot = null;
            return refusal("set", "unavailable");
        }
        if (startPending) {
            slot = null;
            return refusal("set", "busy");
        }
        const trouble = slotTrouble(slot);
        if (trouble !== "") {
            invalidate(trouble);
            return refusal("set", trouble);
        }
        const s = slot;
        slot = null;
        const identity = { id: row.id, consumer: row.consumer, request: row.request };
        let deciding = true;
        let decided = undefined;
        let answered = false;
        const done = (result, reason) => {
            if (answered || !online) {
                return;
            }
            answered = true;
            const completion = result === "done" ? { intent: "set", result: "done" }
                : refusal("set", reason);
            if (deciding) {
                decided = completion;
            } else {
                setDecided(identity, completion);
            }
        };
        const check = () => {
            if (!online) {
                return "unavailable";
            }
            if (shellPidOwner !== s.owner || replyOwner !== s.owner) {
                return "shell-replaced";
            }
            if (Workspace.screens.indexOf(s.output) < 0
                    || !Workspace.desktops.some(d => Tiling.desktopMatches(d, s.desktop))
                    || (s.activity !== "" && Workspace.activities.indexOf(s.activity) < 0)) {
                return "view-changed";
            }
            if (!Tiling.eligibleForMaster(s.window)
                    || !Tiling.onWorkspace(s.window, s.desktop, s.activity, s.output)) {
                return "target-departed";
            }
            return "";
        };
        // A tiler that throws would leave the read unfinished and every bar unanswered: the set
        // is refused instead, unless the tiler had already answered it.
        try {
            applier({ mode: row.mode, window: s.window, output: s.output, desktop: s.desktop,
                      activity: s.activity, check: check }, done);
        } catch (e) {
            console.warn("plasmafusion-placement: layout provider: a set could not be applied: "
                         + e);
            done("refused", "unavailable");
        }
        deciding = false;
        return decided;
    }

    // A set's outcome that came after its read: kept for its identity, carried by its request's
    // frames while that request is the widget's, and told at a newer revision; a request no
    // longer read is told nothing.
    function setDecided(identity: var, completion: var): void {
        const record = records[identity.id];
        if (record && record.consumer === identity.consumer
                && record.request === identity.request) {
            record.completion = completion;
        }
        console.info("plasmafusion-placement: layout provider: a set "
            + (completion.result === "done" ? "is done" : "was refused, " + completion.reason));
        const row = requests.find(r => r.id === identity.id && r.consumer === identity.consumer
                                  && r.request === identity.request);
        if (row) {
            row.completion = completion;
            revision += 1;
        }
    }

    // A window counts as the shell's only with the shell's verified PID, on the output meant, as
    // an applet popup, dock or desktop window that is not a normal window (the layout probe's
    // rule); a class or app id would prove nothing.
    function shellOwnsFocus(window: var, output: var): bool {
        return !!output && Tiling.alive(window) && shellPid > 0 && shellPidOwner === replyOwner
            && window.pid === shellPid && window.output === output && !window.normalWindow
            && (window.appletPopup === true || window.dock === true
                || window.desktopWindow === true);
    }

    // A focus change: what the new window means for the app a menu can be opened from, the
    // handoff it makes or why it makes none, and the end of a preparation made before it. The
    // same window activated again is no change unless it is neither an app nor the shell's.
    function activated(window: var): void {
        const previous = lastFocused;
        const candidate = lastEligible;
        const output = Tiling.alive(window) ? window.output : null;
        const eligible = Tiling.eligibleForMaster(window);
        const shell = shellOwnsFocus(window, output);
        lastFocused = window;
        if (window === previous && (eligible || shell)) {
            return;
        }
        let next = null;
        let why = "focus-changed";
        if (shell && window.appletPopup === true) {
            if (!Tiling.eligibleForMaster(candidate) || candidate.output !== output) {
                why = "no-target";
            } else if (previous === candidate
                       || (shellOwnsFocus(previous, output)
                           && (previous.dock === true || previous.desktopWindow === true))) {
                next = { popup: window, window: candidate, output: output };
            }
        }
        handoff = next;
        missed = next ? "" : why;
        if (eligible) {
            lastEligible = window;
        } else if (!shell) {
            lastEligible = null;
        }
        if (slot) {
            invalidate("focus-changed");
        }
    }

    // What ends a slot now, or "" while it holds: another shell connection, the view (its output
    // gone, or not the output's current view), the target (closed, no eligible app, or off the
    // view) or the focus surface (closed, or no longer the active window).
    function slotTrouble(s: var): string {
        const view = viewOf(s.outputName);
        if (s.owner !== replyOwner || shellPidOwner !== s.owner) {
            return "shell-replaced";
        }
        if (Workspace.screens.indexOf(s.output) < 0 || view === null
                || view.desktopId !== s.view.desktopId || view.activityId !== s.view.activityId) {
            return "view-changed";
        }
        if (s.window !== null
                && (!Tiling.eligibleForMaster(s.window)
                    || !Tiling.onWorkspace(s.window, s.desktop, s.activity, s.output))) {
            return "target-departed";
        }
        if (!Tiling.alive(s.focusSurface) || Workspace.activeWindow !== s.focusSurface) {
            return "focus-changed";
        }
        return "";
    }

    // The slot checked again on an event that may end it: a window gone, a change of a desktop,
    // the activity or the outputs, or the target's own change.
    function revalidate(): void {
        if (!online || !slot) {
            return;
        }
        const reason = slotTrouble(slot);
        if (reason !== "") {
            invalidate(reason);
        }
    }

    // The slot ends with a reason, which its holder's frames carry, not ready, until the holder's
    // next request; what the holder is told changed, so the revision moves.
    function invalidate(reason: string): void {
        const s = slot;
        slot = null;
        const prep = preparations[s.id];
        if (prep && prep.handle === s.handle) {
            preparations[s.id] = Object.assign({}, prep, { ready: false, reason: reason });
            revision += 1;
        }
        console.info("plasmafusion-placement: layout provider: a preparation ended, " + reason);
    }

    function checkedRow(row) {
        if (row === null || typeof row !== "object" || !Number.isInteger(row.id)
                || typeof row.consumer !== "string" || row.consumer.length < 1 || row.consumer.length > 128
                || !Number.isInteger(row.request) || row.request < 1 || row.request > 2147483646) {
            return null;
        }
        const identity = { id: row.id, consumer: row.consumer, request: row.request };
        if (row.version !== 1) {
            return Object.assign(identity, { reason: "version" });
        }
        if (row.intent !== "query" && row.intent !== "prepare" && row.intent !== "set") {
            return Object.assign(identity, { reason: "intent" });
        }
        if (typeof row.outputName !== "string" || row.outputName.length < 1 || row.outputName.length > 128) {
            return Object.assign(identity, { reason: "output" });
        }
        if (row.intent === "query") {
            return Object.assign(identity, { intent: "query", outputName: row.outputName });
        }
        // A set names the mode and the handle its prepare's completion gave.
        if (row.intent === "set") {
            if ((row.mode !== "tiled" && row.mode !== "floating") || typeof row.handle !== "string"
                    || row.handle.length < 1 || row.handle.length > 128) {
                return Object.assign(identity, { reason: "malformed" });
            }
            return Object.assign(identity, { intent: "set", outputName: row.outputName,
                                             mode: row.mode, handle: row.handle });
        }
        // A prepare names the frozen context the bar holds: the lifetime and the view of its
        // answer.
        const view = row.view;
        if (typeof row.epoch !== "string" || row.epoch.length < 1 || row.epoch.length > 64
                || view === null || typeof view !== "object"
                || typeof view.desktopId !== "string" || view.desktopId.length < 1
                || view.desktopId.length > 128
                || typeof view.activityId !== "string" || view.activityId.length > 128) {
            return Object.assign(identity, { reason: "malformed" });
        }
        return Object.assign(identity, {
            intent: "prepare", outputName: row.outputName, epoch: row.epoch,
            view: { desktopId: view.desktopId, activityId: view.activityId } });
    }

    function finishRead(): void {
        reading = false;
        continuePipeline();
    }

    // The pipeline's next step once a read or a publication is over: a publication that is due,
    // then the read the wakes meanwhile asked for.
    function continuePipeline(): void {
        releaseDue();
        if (again) {
            again = false;
            Qt.callLater(provider.scan);
        }
    }

    function releaseDue(): void {
        if (!online || !identityReady || reading || publishing || !publicationDue) {
            return;
        }
        publicationDue = false;
        publish();
    }

    // The frames that say something new, in one call to the connection the requests came from.
    function publish(): void {
        if (!replyOwner.startsWith(":")) {
            return;
        }
        if (sentOwner !== replyOwner) {
            sent = ({});
            sentOwner = replyOwner;
        }
        const messages = [];
        for (const row of requests.concat(refusals)) {
            const frame = frameFor(row);
            const said = JSON.stringify(Object.assign({}, frame, { revision: 0 }));
            if (sent[row.id] !== said) {
                messages.push({ id: row.id, packet: JSON.stringify(frame), said: said });
            }
        }
        if (messages.length === 0) {
            return;
        }
        pending = { messages: messages, at: Date.now() };
        publishing = true;
        write(replyOwner, messages);
    }

    function frameFor(row: var): var {
        const frame = { version: 1, consumer: row.consumer, request: row.request, epoch: label,
                        identityName: identityName, backendOwner: selfOwner, revision: revision,
                        status: "online" };
        if (row.reason !== undefined) {
            frame.refused = row.reason;
            return frame;
        }
        const view = views[row.id] ? views[row.id].view : null;
        frame.capable = capable;
        frame.view = view;
        frame.tiled = active && view !== null && view.desktopId === desktopId
            && view.activityId === activityId && view.outputName === outputName;
        // An intent's frames add its completion, decided once, and while its preparation lasts
        // that preparation's handle and validity; a query's frames stay as they were.
        if (row.completion !== undefined) {
            frame.completion = row.completion;
        }
        const prep = preparations[row.id];
        if (prep && row.intent === "prepare" && prep.consumer === row.consumer
                && prep.request === row.request) {
            frame.prepared = prep.ready ? { handle: prep.handle, ready: true }
                : { handle: prep.handle, ready: false, reason: prep.reason };
        }
        return frame;
    }

    // A change of a desktop, the activity or the outputs: every request's view resolved again, and
    // one step of the revision when one of them differs (its publication follows). Nothing moves
    // for a change no bar's view sees.
    function viewsMoved(): void {
        if (!online) {
            return;
        }
        const now = {};
        let moved = false;
        for (const row of requests) {
            const view = viewOf(row.outputName);
            const kept = views[row.id];
            now[row.id] = { outputName: row.outputName, view: view };
            if (!kept || JSON.stringify(kept.view) !== JSON.stringify(view)) {
                moved = true;
            }
        }
        if (moved) {
            views = now;
            revision += 1;
        }
        revalidate();
    }

    // A bar's view as KWin has it now: the output of that name, its current desktop and the
    // current activity; none for an output KWin does not have.
    function viewOf(name: string): var {
        const outputs = Workspace.screens.filter(output => String(output.name) === name);
        if (outputs.length !== 1) {
            return null;
        }
        const desktop = Workspace.currentDesktopForScreen(outputs[0]);
        if (!desktop || desktop.id === undefined || desktop.id === null || String(desktop.id) === "") {
            return null;
        }
        return { desktopId: String(desktop.id), activityId: String(Workspace.currentActivity), outputName: name };
    }

    function write(destination: string, messages: var): void {
        writer.service = destination;
        writer.arguments = [writerScript(messages)];
        writer.call();
    }

    // The writer: the frames as data - JSON text, which is JavaScript but for the two line
    // separators an engine before ES2019 does not take raw in a string, so those go escaped -
    // matched to the clock's widgets by id. It prints how many it wrote and when it started. The
    // shell reloads each widget written once the script is done, before it answers
    // (plasma-workspace 6.8.3, Widget::~Widget), and the first reload saves the whole widget
    // configuration to disk, synced (libplasma's Applet::configChanged, KConfig's
    // reparseConfiguration): one save per publication while the clock's schema does not declare
    // the response field, and one per frame once it does, as the shell's writeConfig then saves
    // the schema at every write (KCoreConfigSkeleton::save). A script that reloaded each widget
    // itself would save once per widget even now - in a test session 16 frames then took a
    // median of 20 ms instead of 10 from call to answer - so it does not.
    function writerScript(messages: var): string {
        let data = JSON.stringify(messages.map(message => ({ id: message.id, packet: message.packet })));
        for (const code of [0x2028, 0x2029]) {
            data = data.split(String.fromCharCode(code)).join("\\" + "u" + code.toString(16));
        }
        return "var start=Date.now(),messages=" + data + ",written=0;"
            + "panels().forEach(function(p) {"
            + "p.widgets('" + requestApplet + "').forEach(function(w) {"
            + "messages.forEach(function(m) {"
            + "if(w.id===m.id){w.currentConfigGroup=['General'];w.writeConfig('" + responseField
            + "',m.packet);++written;}"
            + "}); }); });"
            + "print(JSON.stringify({start:start,written:written}));";
    }

    // A publication came back: what it carried is what those widgets were told. It is said with
    // how many the shell wrote - fewer, a widget had gone - and its length (report()). An answer
    // without the script's start, or with a count it cannot have, confirms nothing: it changes
    // no record, so what it carried goes out again with the next publication.
    function publicationFinished(text: string): void {
        if (!online || !publishing) {
            return;
        }
        const done = pending;
        pending = null;
        publishing = false;
        const answer = parsed(text);
        if (answer === null || !Number.isInteger(answer.written) || answer.written < 0
                || answer.written > done.messages.length || !Number.isFinite(answer.start)) {
            console.warn("plasmafusion-placement: layout provider: the bars' layout state came back malformed");
            continuePipeline();
            return;
        }
        const length = callLength(done.at, answer.start);
        const told = Object.assign({}, sent);
        for (const message of done.messages) {
            told[message.id] = message.said;
        }
        sent = told;
        report("publication", "published " + done.messages.length + " frame(s), " + answer.written + " written",
               length);
        continuePipeline();
    }

    // A script's answer as the object it printed, or null for anything else.
    function parsed(text: string): var {
        let value = null;
        try {
            value = JSON.parse(text);
        } catch (e) {
            return null;
        }
        return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null;
    }

    // How long a script call took: from when it went out (`at`) to its answer, an upper bound of
    // the time the shell spent on the call, and from the script's start in the shell (`start`)
    // to the answer. The second leaves out the time the call waited before the shell ran it and
    // the script engine's setup before the script's first statement, and still counts the
    // widgets' reloads after the script - the call's cost - and any delay before KWin handled the
    // answer. KWin and the shell read the same system clock; a start outside the call means the
    // clock moved between their readings, and there is no second length (null).
    function callLength(at: real, start: real): var {
        const answered = Date.now();
        return { total: answered - at, fromStart: start >= at && start <= answered ? answered - start : null };
    }

    // A call that came back is said with its lengths, and one over the limit is said as such, by
    // the length from its script's start when that lies within the call, else by its length from
    // call to answer - each named, as neither is the shell's time exactly.
    function report(what: string, line: string, length: var): void {
        const known = length.fromStart !== null;
        console.info("plasmafusion-placement: layout provider: " + line + ", in " + length.total + " ms"
                     + (known ? " (" + length.fromStart + " ms from its script's start)" : ""));
        const judged = known ? length.fromStart : length.total;
        if (judged > shellLimit) {
            console.warn("plasmafusion-placement: layout provider: a " + what + " took " + judged
                         + " ms from its " + (known ? "script's start" : "call") + " to its answer, over the "
                         + shellLimit + " ms limit");
        }
    }

    // A failed publication is said once and changes no record: what it carried goes out again
    // with the next publication.
    function publicationFailed(): void {
        if (!online || !publishing) {
            return;
        }
        pending = null;
        publishing = false;
        console.warn("plasmafusion-placement: layout provider: the bars' layout state could not be published");
        continuePipeline();
    }

    // The script is going: offline, with no capability or session left to report, the bars
    // told so, and the identity name released - a request still pending is dropped, so its
    // answer reaches nothing. Nothing moves after this.
    function retire(): void {
        if (!online) {
            return;
        }
        // The offline frame names the owner the lifetime's frames named; with no identity, none
        // went out.
        const owner = identityReady ? selfOwner : "";
        online = false;
        capable = false;
        active = false;
        desktopId = "";
        activityId = "";
        outputName = "";
        identityReady = false;
        selfOwner = "";
        // A read or a publication in flight ends here, and its answers reach nothing; the last
        // requests stay as the recipients of what is said at the end.
        reading = false;
        again = false;
        publishing = false;
        publicationDue = false;
        pending = null;
        // Nothing prepared outlives the lifetime: its handles name this label, which no later
        // provider has.
        slot = null;
        handoff = null;
        lastEligible = null;
        lastFocused = null;
        if (registration) {
            const request = registration;
            registration = null;
            request.destroy();
        }
        // The offline state, then its frame - to every request and refusal kept, on the
        // connection they came from, whatever is in flight there, which carries an older state -
        // and only then the name's release, as the layout probe did.
        revision += 1;
        if (owner !== "") {
            sendOffline(owner);
        }
        identityRelease.arguments = [identityName];
        identityRelease.call();
    }

    function sendOffline(owner: string): void {
        const rows = requests.concat(refusals);
        if (!replyOwner.startsWith(":") || rows.length === 0) {
            return;
        }
        write(replyOwner, rows.map(row => ({ id: row.id, packet: JSON.stringify({
            version: 1, consumer: row.consumer, request: row.request, epoch: label,
            identityName: identityName, backendOwner: owner, revision: revision, status: "offline",
            capable: false, view: null, tiled: false }) })));
        console.info("plasmafusion-placement: layout provider: sent " + rows.length + " offline frame(s)");
    }
}
