// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.bluezqt as BluezQt
import org.kde.plasma.private.bluetooth as PlasmaBt

// Bluetooth through BluezQt, sharing bluedevil's device state model. The device list model is
// created only while the Bluetooth page is shown (`listVisible`, BACKLOG S2).
Item {
    id: bt

    property bool listVisible: false

    readonly property bool available: BluezQt.Manager.adapters.length > 0 || BluezQt.Manager.bluetoothBlocked
    readonly property bool powered: BluezQt.Manager.bluetoothOperational
    readonly property bool blocked: BluezQt.Manager.bluetoothBlocked
    readonly property var connectedDevices: BluezQt.Manager.connectedDevices
    readonly property int connectedCount: connectedDevices.length
    readonly property string firstConnectedName: connectedCount > 0 ? (connectedDevices[0].name || "") : ""
    readonly property var devicesModel: devices.object

    function setEnabled(on: bool) {
        BluezQt.Manager.bluetoothBlocked = !on;
        BluezQt.Manager.adapters.forEach(adapter => {
            adapter.powered = on;
        });
    }
    // Clears a soft rfkill block and calls done once BluezQt sees it gone (the block is written
    // from a thread; BlueZ then powers the adapters it had on), or after a moment when it stays:
    // a hard block, which only the hardware switch clears.
    property var unblockDone: null
    function unblock(done): void {
        if (!BluezQt.Manager.bluetoothBlocked) {
            done();
            return;
        }
        unblockDone = done;
        BluezQt.Manager.bluetoothBlocked = false;
        unblockWait.restart();
    }
    function unblocked(): void {
        unblockWait.stop();
        const done = unblockDone;
        unblockDone = null;
        if (done) {
            done();
        }
    }
    Connections {
        target: BluezQt.Manager
        function onBluetoothBlockedChanged() {
            if (!BluezQt.Manager.bluetoothBlocked && bt.unblockDone) {
                bt.unblocked();
            }
        }
    }
    Timer {
        id: unblockWait
        interval: 2000
        onTriggered: bt.unblocked()
    }
    function toggleDevice(device, ubi: string, connected: bool) {
        if (!device) {
            return;
        }
        if (connected) {
            const call = device.disconnectFromDevice();
            PlasmaBt.SharedDevicesStateProxyModel.registerDisconnectingCallForDeviceUbi(call, ubi);
        } else {
            const call = device.connectToDevice();
            PlasmaBt.SharedDevicesStateProxyModel.registerConnectingCallForDeviceUbi(call, ubi);
        }
    }
    function pairNew() {
        PlasmaBt.LaunchApp.launchWizard();
    }

    Instantiator {
        id: devices
        active: bt.listVisible
        model: 1
        delegate: PlasmaBt.DevicesProxyModel {
            hideBlockedDevices: true
            sourceModel: PlasmaBt.SharedDevicesStateProxyModel
        }
    }
}
