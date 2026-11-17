/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: probe
    implicitWidth: 24
    implicitHeight: 24
    // Probe-only correlation, not a production identity or authentication mechanism.
    readonly property string boot: Date.now() + ":" + Math.random()
    property string phase: "unknown"
    property string epoch: ""
    property int revision: -1
    property int accepted: 0
    property int requestNumber: 1
    property string boundEpoch: ""
    property string boundOwner: ""
    property string boundIdentity: ""
    property bool stopped: false
    property bool verifying: false
    property var pendingPacket: null

    function finishVerification(): void {
        verifying = false;
        if (pendingPacket) {
            Qt.callLater(verifyPending);
        }
    }

    function verifyPending(): void {
        if (stopped || verifying || !pendingPacket) {
            return;
        }
        const packet = pendingPacket;
        pendingPacket = null;
        verifying = true;
        DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "GetNameOwner", arguments: ["org.kde.KWin"]
        }, reply => {
            if (String(reply.value) !== packet.backendOwner) {
                console.info("layout-probe-rejected backend owner ", probe.boot);
                probe.finishVerification();
                return;
            }
            if (packet.status === "offline") {
                if (packet.backendOwner === probe.boundOwner
                        && packet.identityName === probe.boundIdentity) {
                    probe.acceptPacket(packet);
                }
                probe.finishVerification();
                return;
            }
            DBus.SessionBus.asyncCall({
                service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
                iface: "org.freedesktop.DBus", member: "GetNameOwner", arguments: [packet.identityName]
            }, identity => {
                if (String(identity.value) === packet.backendOwner) {
                    probe.acceptPacket(packet);
                }
                probe.finishVerification();
            }, () => probe.finishVerification());
        }, () => probe.finishVerification());
    }

    function acceptPacket(packet: var): void {
        // Recheck after asynchronous lookups: retirement may have advanced the query meanwhile.
        if (stopped || packet.request !== requestNumber) {
            return;
        }
        if (boundEpoch !== "" && packet.epoch !== boundEpoch) {
            freshQuery(true);
            return;
        }
        if (packet.revision <= revision) {
            return;
        }
        boundEpoch = packet.epoch;
        boundOwner = packet.backendOwner;
        boundIdentity = packet.identityName;
        phase = packet.status === "online" && !packet.capable ? "unsupported" : packet.status;
        epoch = packet.epoch;
        revision = packet.revision;
        ++accepted;
        observe(packet);
        if (packet.status === "offline") {
            freshQuery(false);
        }
    }

    function sendQuery(): void {
        Plasmoid.configuration.layoutRequest = JSON.stringify({consumer: boot, request: requestNumber});
        // Desktop scripting reads the saved group, not this unsaved property map.
        Plasmoid.configuration.writeConfig();
        DBus.SessionBus.asyncCall({
            service: "org.kde.kglobalaccel", path: "/component/kwin",
            iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
            arguments: ["Plasma Fusion: Layout Probe Wake"]
        }, () => console.info("layout-probe: wake dispatched"),
           error => console.warn("layout-probe: wake failed", error.name));
    }

    function freshQuery(showUnknown: bool): void {
        if (requestNumber >= 2147483646) {
            stopped = true;
            phase = "unknown";
            observe(null);
            return;
        }
        const requested = ++requestNumber;
        boundEpoch = "";
        boundOwner = "";
        boundIdentity = "";
        pendingPacket = null;
        revision = -1;
        if (showUnknown) {
            phase = "unknown";
            observe(null);
        }
        // Leave the configuration-change stack before publishing another query.
        Qt.callLater(() => {
            if (!probe.stopped && probe.requestNumber === requested) {
                probe.sendQuery();
            }
        });
    }

    function observe(packet: var): void {
        console.info("layout-probe-observation", JSON.stringify({
            boot: boot, phase: phase, epoch: epoch, revision: revision,
            accepted: accepted, packet: packet
        }));
    }
    Connections {
        target: Plasmoid.configuration
        function onLayoutResponseChanged() {
            let packet;
            try {
                packet = JSON.parse(Plasmoid.configuration.layoutResponse);
            } catch (error) {
                return;
            }
            if (probe.stopped || !packet || packet.consumer !== probe.boot
                    || packet.request !== probe.requestNumber
                    || typeof packet.epoch !== "string"
                    || !/^:[0-9]+\.[0-9]+$/.test(packet.backendOwner)
                    || packet.identityName !== "org.plasmafusion.LayoutProbe.p" + packet.epoch
                    || typeof packet.capable !== "boolean"
                    || !["online", "offline"].includes(packet.status)
                    || typeof packet.revision !== "number" || packet.revision % 1 !== 0
                    || packet.revision < 1 || packet.revision > 2147483646) {
                return;
            }
            probe.pendingPacket = packet;
            probe.verifyPending();
        }
    }
    Component.onCompleted: {
        observe(null);
        sendQuery();
    }
    Component.onDestruction: stopped = true
}
