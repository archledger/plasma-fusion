/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import org.kde.kwin
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
    property var recipients: []
    property string lastApplication: ""
    property QtObject competingProvider: QtObject {}
    property bool competingProviderRejected: false

    function providerAccepted(token: string): bool {
        // Qt's default UUID text includes braces, including for a refused/null UUID.
        const text = token.startsWith("{") && token.endsWith("}") ? token.slice(1, -1) : token;
        return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
            && text !== "00000000-0000-0000-0000-000000000000";
    }

    function publish(status: string, rows: var): void {
        const messages = rows.map(row => ({
            id: row.id,
            packet: JSON.stringify({
                consumer: row.consumer, epoch: epoch, revision: ++revision,
                status: status, capable: capable, refusal: refusal,
                request: row.request, application: lastApplication,
                competingProviderRejected: competingProviderRejected
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
        if (reading) {
            again = true;
            return;
        }
        reading = true;
        reader.arguments = ["var rows=[];panels().forEach(function(p) {"
            + "p.widgets('org.plasmafusion.layoutprobe').forEach(function(w) {"
            + "w.currentConfigGroup=['General'];try { var q=JSON.parse(w.readConfig('layoutRequest',''));"
            + "rows.push({id:w.id,consumer:q.consumer,request:q.request}); }catch(e){} }); });"
            + "print(JSON.stringify(rows));"];
        reader.call();
    }

    DBusCall {
        id: reader
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: value => {
            probe.reading = false;
            probe.recipients = JSON.parse(String(value[0]));
            console.info("layout-probe: mailbox rows", probe.recipients.length);
            probe.publish("online", probe.recipients);
            if (probe.again) {
                probe.again = false;
                probe.scan();
            }
        }
        onFailed: {
            probe.reading = false;
            console.warn("layout-probe: mailbox read failed");
        }
    }
    DBusCall {
        id: writer
        service: "org.kde.plasmashell"
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
    }
    Component.onDestruction: probe.publish("offline", probe.recipients)
}
