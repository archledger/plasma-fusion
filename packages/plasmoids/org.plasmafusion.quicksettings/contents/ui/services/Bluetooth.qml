// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.bluezqt as BluezQt
import org.kde.plasma.private.bluetooth as PlasmaBt

// Bluetooth through BluezQt, sharing bluedevil's device state model.
Item {
    id: bt

    readonly property bool available: BluezQt.Manager.adapters.length > 0 || BluezQt.Manager.bluetoothBlocked
    readonly property bool powered: BluezQt.Manager.bluetoothOperational
    readonly property bool blocked: BluezQt.Manager.bluetoothBlocked
    readonly property var connectedDevices: BluezQt.Manager.connectedDevices
    readonly property int connectedCount: connectedDevices.length
    readonly property string firstConnectedName: connectedCount > 0 ? (connectedDevices[0].name || "") : ""
    readonly property var devicesModel: devices

    function setEnabled(on: bool) {
        BluezQt.Manager.bluetoothBlocked = !on;
        BluezQt.Manager.adapters.forEach(adapter => {
            adapter.powered = on;
        });
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

    PlasmaBt.DevicesProxyModel {
        id: devices
        hideBlockedDevices: true
        sourceModel: PlasmaBt.SharedDevicesStateProxyModel
    }
}
