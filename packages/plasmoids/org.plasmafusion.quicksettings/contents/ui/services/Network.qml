// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.networkmanagement as PlasmaNM

// NetworkManager state through plasma-nm's QML module (same objects the
// stock Networks applet uses).
Item {
    id: net

    // Set by the owner: scan and keep models live only while the list is shown.
    property bool listVisible: false

    readonly property bool available: true
    readonly property bool wifiDevice: availableDevices.wirelessDeviceAvailable
    readonly property bool wifiEnabled: enabledConnections.wirelessEnabled
    readonly property bool wifiHwEnabled: enabledConnections.wirelessHwEnabled
    readonly property bool airplane: PlasmaNM.Configuration.airplaneModeEnabled
    readonly property string ssid: wirelessStatus.wifiSSID
    readonly property bool connecting: connectionIcon.connecting
    readonly property string iconName: connectionIcon.connectionIcon

    // "wifi", "wired", "mobile", "airplane", "wifi-off", "wifi-idle" or "none"
    readonly property string kind: {
        const name = iconName;
        if (airplane || name.startsWith("network-flightmode")) {
            return "airplane";
        }
        if (name.startsWith("network-wired-activated") || name.startsWith("network-vpn")) {
            return "wired";
        }
        if (name.startsWith("network-mobile") && name !== "network-mobile-available") {
            return "mobile";
        }
        if (/^network-wireless-\d+/.test(name)) {
            return "wifi";
        }
        if (wifiDevice && !wifiEnabled) {
            return "wifi-off";
        }
        if (wifiDevice) {
            return "wifi-idle";
        }
        return "none";
    }
    // Signal bars 1..4 for the connected Wi-Fi network.
    readonly property int level: {
        const m = /^network-wireless-(\d+)/.exec(iconName);
        if (!m) {
            return 0;
        }
        const s = Number(m[1]);
        if (s >= 80) {
            return 4;
        }
        if (s >= 60) {
            return 3;
        }
        if (s >= 40) {
            return 2;
        }
        return 1;
    }
    readonly property bool limited: iconName.indexOf("limited") !== -1

    readonly property var activeModel: activeWifiModel
    readonly property var otherModel: otherWifiModel
    readonly property bool scanning: handler.scanning

    function setWifiEnabled(on: bool) {
        handler.enableWireless(on);
    }
    function scan() {
        handler.requestScan();
    }
    function activate(connectionPath: string, devicePath: string, specificPath: string) {
        handler.activateConnection(connectionPath, devicePath, specificPath);
    }
    function addAndActivate(devicePath: string, specificPath: string, password: string) {
        if (password && password.length > 0) {
            handler.addAndActivateConnection(devicePath, specificPath, password);
        } else {
            handler.addAndActivateConnection(devicePath, specificPath);
        }
    }
    function deactivate(connectionPath: string, devicePath: string) {
        handler.deactivateConnection(connectionPath, devicePath);
    }
    function setStatistics(devicePath: string, on: bool) {
        networkModel.setDeviceStatisticsRefreshRateMs(devicePath, on ? 2000 : 0);
    }

    PlasmaNM.EnabledConnections {
        id: enabledConnections
    }
    PlasmaNM.AvailableDevices {
        id: availableDevices
    }
    PlasmaNM.WirelessStatus {
        id: wirelessStatus
    }
    PlasmaNM.NetworkStatus {
        id: networkStatus
    }
    PlasmaNM.ConnectionIcon {
        id: connectionIcon
        connectivity: networkStatus.connectivity
    }
    PlasmaNM.Handler {
        id: handler
    }
    PlasmaNM.NetworkModel {
        id: networkModel
    }
    PlasmaNM.AppletProxyModel {
        id: appletModel
        sourceModel: networkModel
    }

    readonly property int typeRole: appletModel.KItemModels.KRoleNames.role("Type")
    readonly property int stateRole: appletModel.KItemModels.KRoleNames.role("ConnectionState")

    function wirelessRow(model, row, parent, wantActive) {
        const index = model.index(row, 0, parent);
        if (model.data(index, typeRole) !== PlasmaNM.Enums.Wireless) {
            return false;
        }
        const active = model.data(index, stateRole) === PlasmaNM.Enums.Activated
            || model.data(index, stateRole) === PlasmaNM.Enums.Activating;
        return active === wantActive;
    }

    KItemModels.KSortFilterProxyModel {
        id: activeWifiModel
        sourceModel: appletModel
        filterRowCallback: (row, parent) => net.wirelessRow(appletModel, row, parent, true)
    }
    KItemModels.KSortFilterProxyModel {
        id: otherWifiModel
        sourceModel: appletModel
        filterRowCallback: (row, parent) => net.wirelessRow(appletModel, row, parent, false)
    }

    Timer {
        interval: 10200
        repeat: true
        triggeredOnStart: true
        running: net.listVisible && net.wifiEnabled && !net.airplane
        onTriggered: handler.requestScan()
    }
}
