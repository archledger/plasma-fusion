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
            if (packet.consumer !== probe.boot || packet.revision <= probe.revision) {
                return;
            }
            probe.phase = packet.status;
            probe.epoch = packet.epoch;
            probe.revision = packet.revision;
            ++probe.accepted;
            probe.observe(packet);
        }
    }
    Component.onCompleted: {
        observe(null);
        Plasmoid.configuration.layoutRequest = JSON.stringify({consumer: boot, request: 1});
        // Shell scripting reads the saved group, not this widget's unsaved property map.
        Plasmoid.configuration.writeConfig();
        DBus.SessionBus.asyncCall({
            service: "org.kde.kglobalaccel", path: "/component/kwin",
            iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
            arguments: ["Plasma Fusion: Layout Probe Wake"]
        }, () => console.info("layout-probe: wake dispatched"),
           error => console.warn("layout-probe: wake failed", error.name));
    }
}
