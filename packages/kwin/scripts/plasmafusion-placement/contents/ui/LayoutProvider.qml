/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQml
import org.kde.kwin
import org.kde.plasma.workspace.dbus as DBus

// What the placement script tells the bars' layout controls about tiling: whether supported
// tiling is available, whether a session is on and the view it tiles, in an order a reader can
// trust (the workspace layout control, P1). The script stays the only authority: it binds
// `nativeCapable` to its native verdict and hands the session in where the tiler starts or ends
// one (main.qml, tiler.reportSession). This object keeps that state, its revision, a lifetime
// label and the lifetime's identity name on the session bus, reads the bars' requests and
// answers them; it is never given the native token.
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
    // The state's order: 1 at start(), then one step for each change of the provider's state -
    // capability, the session or its view, going offline - and none otherwise. A bar's frame
    // also carries the bar's own view, which for now changes without a step (a later step moves
    // the revision for it too).
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

    // What the bars ask for, read from the shell (the layout probe's P0 transport): a bar's
    // clock saves its request in a field of its own and wakes the provider through a shortcut
    // with no key; the provider reads every clock's request with one shell script call on the
    // shell's unique connection. The reads are bounded as the probe's - at most 16 widgets,
    // requests of at most 2048 characters, a consumer label of 1 to 128 characters and a request
    // number of 1 to 2147483646 - copy only the fields P1 needs, and carry widget data as JSON,
    // never as code.
    readonly property string requestApplet: "org.plasmafusion.clockpill"
    readonly property string readerScript: "var rows=[],seen=0;"
        + "panels().forEach(function(p) {"
        + "p.widgets('" + requestApplet + "').forEach(function(w) {"
        + "if(seen>=16){return;}++seen;"
        + "w.currentConfigGroup=['General'];try {var text=w.readConfig('layoutRequest','');"
        + "if(text.length>2048)return;"
        + "var q=JSON.parse(text);"
        + "if(typeof q.consumer!=='string'||!q.consumer.length||q.consumer.length>128"
        + "||!Number.isInteger(q.request)||q.request<=0||q.request>2147483646)return;"
        + "rows.push({id:w.id,consumer:q.consumer,request:q.request,version:q.version,"
        + "intent:q.intent,outputName:q.outputName});"
        + "}catch(e){} }); });"
        + "print(JSON.stringify(rows));"
    // What the last read found: the queries to answer, and the rows refused before any action,
    // each with its widget, consumer, request and reason. A failed read keeps them as they were.
    property var requests: []
    property var refusals: []
    // A read in flight, and whether a wake came meanwhile: one read at a time, and the wakes
    // during it make one more read after it.
    property bool reading: false
    property bool again: false

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
        reader.service = owner;
        reader.arguments = [readerScript];
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

    // The shell's answer, checked again here: at most 16 rows, each with a well-formed identity
    // (a row without one cannot be answered and is dropped), then a version-1 query for a named
    // output; every other row is refused before any action, with its reason.
    function readFinished(text: string): void {
        if (!reading) {
            return;
        }
        let rows = null;
        try {
            rows = JSON.parse(text);
        } catch (e) {
            rows = null;
        }
        if (!Array.isArray(rows) || rows.length > 16) {
            console.warn("plasmafusion-placement: layout provider: the bars' requests came back malformed");
            finishRead();
            return;
        }
        const accepted = [];
        const refused = [];
        for (const row of rows) {
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
        publicationDue = true;
        console.info("plasmafusion-placement: layout provider: read " + accepted.length + " request(s), "
                     + refused.length + " refused");
        finishRead();
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
        if (row.intent !== "query") {
            return Object.assign(identity, { reason: "intent" });
        }
        if (typeof row.outputName !== "string" || row.outputName.length < 1 || row.outputName.length > 128) {
            return Object.assign(identity, { reason: "output" });
        }
        return Object.assign(identity, { outputName: row.outputName });
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
        const view = viewOf(row.outputName);
        frame.capable = capable;
        frame.view = view;
        frame.tiled = active && view !== null && view.desktopId === desktopId
            && view.activityId === activityId && view.outputName === outputName;
        return frame;
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
    // matched to the clock's widgets by id. It prints how many it wrote.
    function writerScript(messages: var): string {
        let data = JSON.stringify(messages.map(message => ({ id: message.id, packet: message.packet })));
        for (const code of [0x2028, 0x2029]) {
            data = data.split(String.fromCharCode(code)).join("\\" + "u" + code.toString(16));
        }
        return "var messages=" + data + ",written=0;"
            + "panels().forEach(function(p) {"
            + "p.widgets('" + requestApplet + "').forEach(function(w) {"
            + "messages.forEach(function(m) {"
            + "if(w.id===m.id){w.currentConfigGroup=['General'];w.writeConfig('" + responseField
            + "',m.packet);++written;}"
            + "}); }); });"
            + "print(written);";
    }

    // A publication came back: what it carried is what those widgets were told. It is said with
    // how many the shell wrote - fewer, a widget had gone - and its length from call to answer,
    // an upper bound of the time the shell took no input (decision 1).
    function publicationFinished(written: string): void {
        if (!online || !publishing) {
            return;
        }
        const done = pending;
        pending = null;
        publishing = false;
        const told = Object.assign({}, sent);
        for (const message of done.messages) {
            told[message.id] = message.said;
        }
        sent = told;
        console.info("plasmafusion-placement: layout provider: published " + done.messages.length + " frame(s), "
                     + written + " written, in " + (Date.now() - done.at) + " ms");
        continuePipeline();
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
