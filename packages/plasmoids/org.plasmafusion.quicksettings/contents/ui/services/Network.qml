// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.networkmanagement as PlasmaNM

import "../global"

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
    readonly property bool hotspotSupported: handler.hotspotSupported
    // The widgets' shared state (Instances), not this widget's handler: a handler made while the
    // hotspot ran does not learn of its end.
    readonly property bool hotspotActive: Instances.hotspotActive
    onHotspotActiveChanged: {
        refreshHotspotSettings();
        activeWifiModel.invalidateFilter();
        otherWifiModel.invalidateFilter();
    }
    // From a start request until the hotspot has stayed up for hotspotStartTimer: plasma-nm reports
    // it active once NetworkManager accepts it, and inactive again when the activation fails.
    property bool hotspotStarting: false
    property string hotspotName: ""
    property bool hotspotFailedToStart: false

    function toggleHotspot(): void {
        if (hotspotActive || Boolean(PlasmaNM.Configuration.hotspotConnectionPath)) {
            hotspotFailedToStart = false;
            hotspotStarting = false;
            hotspotStartTimer.stop();
            handler.stopHotspot();
            // Off either way: stopped here, or no longer running (a hotspot found running when
            // the widgets were made has no handler that sees it end).
            Instances.hotspotActive = false;
        } else if (!hotspotStarting && wifiEnabled && wifiHwEnabled && !airplane && hotspotSupported) {
            hotspotFailedToStart = false;
            hotspotStarting = true;
            hotspotStartTimer.restart();
            handler.createHotspot();
        }
    }
    function hotspotFailed(): void {
        hotspotStarting = false;
        hotspotStartTimer.stop();
        hotspotFailedToStart = true;
    }
    function refreshHotspotSettings(): void {
        hotspotName = PlasmaNM.Configuration.hotspotName;
    }
    // Read on request only: plasma-nm generates and saves a password the first time it is read.
    function hotspotPassword(): string {
        return PlasmaNM.Configuration.hotspotPassword;
    }
    // The same settings as the stock Networks applet; an empty password keeps the saved one.
    function configureHotspot(name: string, password: string): bool {
        const trimmed = name.trim();
        if (trimmed === "" || (password !== "" && (password.length < 8 || password.length > 63))) {
            return false;
        }
        PlasmaNM.Configuration.hotspotName = trimmed;
        if (password !== "") {
            PlasmaNM.Configuration.hotspotPassword = password;
        }
        refreshHotspotSettings();
        return true;
    }
    Component.onCompleted: refreshHotspotSettings()

    Timer {
        id: hotspotStartTimer
        interval: 20000
        onTriggered: {
            if (net.hotspotActive) {
                net.hotspotStarting = false;
            } else {
                net.hotspotFailed();
            }
        }
    }

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
        // A new handler looks the hotspot's connection up (running or not): the shared state follows.
        Component.onCompleted: Instances.hotspotActive = handler.hotspotActive
        onHotspotActiveChanged: {
            Instances.hotspotActive = handler.hotspotActive;
            if (!handler.hotspotActive && net.hotspotStarting) {
                net.hotspotFailed();
            }
        }
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
    readonly property int nameRole: appletModel.KItemModels.KRoleNames.role("Name")
    readonly property int ssidRole: appletModel.KItemModels.KRoleNames.role("Ssid")

    function wirelessRow(model, row, parent, wantActive) {
        const index = model.index(row, 0, parent);
        if (model.data(index, typeRole) !== PlasmaNM.Enums.Wireless) {
            return false;
        }
        const active = model.data(index, stateRole) === PlasmaNM.Enums.Activated
            || model.data(index, stateRole) === PlasmaNM.Enums.Activating;
        // The running hotspot is this computer's own network, not one it is connected to.
        if (active && hotspotActive && (model.data(index, nameRole) === hotspotName || model.data(index, ssidRole) === hotspotName)) {
            return false;
        }
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
