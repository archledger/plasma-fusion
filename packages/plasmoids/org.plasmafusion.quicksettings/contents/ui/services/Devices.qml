// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "../../code/devices.js" as DeviceList

// Disks & Devices: removable devices from Plasma's hotplug, soliddevice and devicenotifications data
// engines (plasma5support), as Plasma 5's Disks & Devices widget used them. The engines push every
// change (no polling); mount, safely remove and open go through their services, the same Solid
// calls as the stock widget. The stock tray item is unloaded where quick settings is in the bar
// (desktop layout and fusion-config.sh), so its pop-up and its notifications are not doubled.
Item {
    id: devices

    // UDIs in the order the hotplug engine reported them (oldest first).
    property var order: []
    // Bumped on every engine change, so the list is computed again.
    property int revision: 0
    readonly property var list: {
        void revision;
        return DeviceList.entries(order, hotplug.data, solid.data, notes.data);
    }
    readonly property int count: list.length
    readonly property bool anyMounted: list.some(e => e.mounted)
    // UDIs listed now and already announced through deviceAdded (or present at start). A device
    // that leaves the list is forgotten, so plugging it back in announces it again.
    property var known: ({})

    // A device plugged in while the session runs (not one present at start).
    signal deviceAdded(string udi)

    function entry(udi: string): var {
        return list.find(e => e.udi === udi) || null;
    }
    // The device's default action: the file manager for a volume (Solid mounts it first), the
    // device's own action for a camera or a media player.
    function open(udi: string): void {
        const e = entry(udi);
        if (!e || e.openPredicate === "") {
            return;
        }
        const service = hotplug.serviceForSource(udi);
        const operation = service.operationDescription("invokeAction");
        operation.predicate = e.openPredicate;
        service.startOperationCall(operation);
    }
    function mount(udi: string): void {
        solidCall(udi, "mount");
    }
    // Safely remove: unmount (Solid teardown), or eject an optical disc.
    function unmount(udi: string): void {
        solidCall(udi, "unmount");
    }
    // Free space of the mounted devices, read again when the page is shown.
    function refresh(): void {
        for (const e of list) {
            if (e.mounted) {
                solidCall(e.udi, "updateFreespace");
            }
        }
    }
    function solidCall(udi: string, name: string): void {
        const service = solid.serviceForSource(udi);
        if (service) {
            service.startOperationCall(service.operationDescription(name));
        }
    }

    function syncOrder(): void {
        const now = hotplug.sources;
        const kept = order.filter(u => now.indexOf(u) !== -1);
        for (const u of now) {
            if (kept.indexOf(u) === -1) {
                kept.push(u);
            }
        }
        order = kept;
        revision++;
    }
    onListChanged: {
        const present = {};
        for (const e of list) {
            present[e.udi] = true;
            if (known[e.udi]) {
                continue;
            }
            known[e.udi] = true;
            const hp = hotplug.data[e.udi];
            if (hp && hp.added === true) {
                devices.deviceAdded(e.udi);
            }
        }
        for (const udi of Object.keys(known)) {
            if (!present[udi]) {
                delete known[udi];
            }
        }
    }

    P5Support.DataSource {
        id: hotplug
        engine: "hotplug"
        connectedSources: sources
        interval: 0
        onSourceAdded: source => {
            disconnectSource(source);
            connectSource(source);
        }
        onSourceRemoved: source => disconnectSource(source)
        onSourcesChanged: devices.syncOrder()
        onNewData: () => devices.revision++
    }
    P5Support.DataSource {
        id: solid
        engine: "soliddevice"
        connectedSources: hotplug.sources
        interval: 0
        onNewData: () => devices.revision++
    }
    P5Support.DataSource {
        id: notes
        engine: "devicenotifications"
        connectedSources: sources
        interval: 0
        onSourceAdded: source => {
            disconnectSource(source);
            connectSource(source);
        }
        onSourcesChanged: devices.revision++
        onNewData: () => devices.revision++
    }
}
