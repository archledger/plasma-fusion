/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import org.kde.kwin
import org.kde.plasma.workspace.dbus as DBus
import "Tiling.js" as Tiling

// Test-only provider. It never admits a window or writes geometry or placement records.
Item {
    id: probe
    property string epoch: "stock"
    property bool capable: false
    property int refusal: 0
    property int revision: 0
    property bool reading: false
    property bool again: false
    property string readOwner: ""
    property string replyOwner: ""
    property var recipients: []
    property string lastApplication: ""
    property QtObject competingProvider: QtObject {}
    property bool competingProviderRejected: false
    property bool authorized: false
    property bool stopping: false
    property bool identityReady: false
    property string identityName: ""
    property string selfOwner: ""
    property var registration: null
    property bool registrationHandled: false

    function registrationFinished(): void {
        if (!registration || !registration.isFinished || registrationHandled || stopping) {
            return;
        }
        registrationHandled = true;
        // The workspace decoder returns a uint32 value wrapper, not a plain JS number.
        const granted = registration.isValid && registration.value.value === 1;
        const finished = registration;
        registration = null;
        finished.destroy();
        if (!granted) {
            console.warn("layout-probe: identity name not granted; transport stays unavailable");
            return;
        }
        identityLookup.arguments = [identityName];
        identityLookup.call();
    }
    onRegistrationChanged: registrationFinished()
    Connections {
        target: probe.registration
        function onFinished() { probe.registrationFinished(); }
    }
    DBusCall {
        id: identityLookup
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "GetNameOwner"
        onFinished: value => {
            probe.selfOwner = String(value[0]);
            probe.identityReady = probe.selfOwner.startsWith(":");
            if (probe.identityReady) {
                probe.again = false;
                probe.scan();
            }
        }
    }
    DBusCall {
        id: identityRelease
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "ReleaseName"
    }

    function providerAccepted(token: string): bool {
        // Qt's default UUID text includes braces, including for a refused/null UUID.
        const text = token.startsWith("{") && token.endsWith("}") ? token.slice(1, -1) : token;
        return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
            && text !== "00000000-0000-0000-0000-000000000000";
    }

    function publish(status: string, rows: var): void {
        if (replyOwner === "" || rows.length === 0) {
            return;
        }
        const messages = rows.map(row => ({
            id: row.id,
            packet: JSON.stringify({
                consumer: row.consumer, epoch: epoch, revision: ++revision,
                status: status, capable: capable, refusal: refusal,
                request: row.request, application: lastApplication,
                competingProviderRejected: competingProviderRejected,
                backendOwner: selfOwner, identityName: identityName
            })
        }));
        writer.arguments = ["var messages = " + JSON.stringify(messages) + ";var written=0;"
            + "panels().forEach(function(p) { p.widgets('org.plasmafusion.layoutprobe').forEach(function(w) {"
            + "messages.forEach(function(m) { if(w.id === m.id) { w.currentConfigGroup=['General'];"
            + "w.writeConfig('layoutResponse',m.packet); ++written; } }); }); });print(written);"];
        writer.call();
        console.info("layout-probe: publication", status, messages.length);
    }

    function scan(): void {
        if (!authorized || stopping) {
            return;
        }
        if (!identityReady) {
            again = true;
            return;
        }
        if (reading) {
            again = true;
            return;
        }
        reading = true;
        ownerLookup.call();
    }

    function finishRead(): void {
        reading = false;
        if (again) {
            again = false;
            Qt.callLater(probe.scan);
        }
    }

    DBusCall {
        id: ownerLookup
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "GetNameOwner"
        arguments: ["org.kde.plasmashell"]
        onFinished: value => {
            probe.readOwner = String(value[0]);
            probe.readMailboxes();
        }
        onFailed: probe.finishRead()
    }

    function readMailboxes(): void {
        reader.arguments = ["var rows=[];panels().forEach(function(p) {"
            + "p.widgets('org.plasmafusion.layoutprobe').forEach(function(w) {"
            + "w.currentConfigGroup=['General'];try { var q=JSON.parse(w.readConfig('layoutRequest',''));"
            + "rows.push({id:w.id,consumer:q.consumer,request:q.request}); }catch(e){} }); });"
            + "print(JSON.stringify(rows));"];
        reader.call();
    }

    DBusCall {
        id: reader
        service: probe.readOwner
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: value => {
            probe.replyOwner = probe.readOwner;
            probe.recipients = JSON.parse(String(value[0]));
            console.info("layout-probe: mailbox rows", probe.recipients.length);
            probe.publish("online", probe.recipients);
            probe.finishRead();
        }
        onFailed: {
            probe.finishRead();
            console.warn("layout-probe: mailbox read failed");
        }
    }
    DBusCall {
        id: writer
        // A cached unique name cannot auto-start a new shell during retirement.
        service: probe.replyOwner
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: value => console.info("layout-probe: publication writes", String(value[0]))
        onFailed: console.warn("layout-probe: publication failed")
    }
    ShortcutHandler {
        name: "Plasma Fusion: Layout Probe Wake"
        text: i18n("Wake the isolated layout transport probe")
        sequence: ""
        onActivated: {
            console.info("layout-probe: wake received");
            probe.scan();
        }
    }
    Connections {
        target: Workspace
        function onWindowActivated(window) {
            if (Tiling.eligibleForMaster(window)) {
                probe.lastApplication = String(window.internalId);
            }
        }
    }
    Component.onCompleted: {
        authorized = KWin.readConfig("ProbeAuthorized", false) === true;
        if (!authorized) {
            console.warn("layout-probe: authorization marker absent; probe stays inert");
            return;
        }
        if (typeof Workspace.transientTiling === "function") {
            const api = Workspace.transientTiling();
            if (api) {
                const token = String(api.registerProvider(probe));
                // A public lifecycle label, not authentication; never publish the ownership token.
                epoch = Qt.md5(token);
                capable = providerAccepted(token);
                competingProviderRejected = !providerAccepted(String(api.registerProvider(competingProvider)));
                refusal = api.createTile(null, Workspace.currentDesktop, Qt.rect(0, 0, 0, 0)).result;
            }
        }
        console.info("layout-probe: initialized", capable, refusal);
        identityName = "org.plasmafusion.LayoutProbe.p" + epoch;
        // Only an alias on the existing connection: no objects or methods are exported.
        registration = DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "RequestName", signature: "(su)",
            arguments: [identityName, new DBus.uint32(4)]
        });
    }
    Component.onDestruction: {
        stopping = true;
        probe.publish("offline", probe.recipients);
        if (identityName !== "") {
            identityRelease.arguments = [identityName];
            identityRelease.call();
        }
        if (registration) {
            registration.destroy();
        }
    }
}
