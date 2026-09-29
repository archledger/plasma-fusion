// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.private.brightnesscontrolplugin
import org.kde.plasma.workspace.dbus as DBus

// Screen brightness, Night Light and the light/dark Global Theme pairing,
// through PowerDevil's brightness plugin and KWin's NightLight D-Bus object.
Item {
    id: display

    property bool silent: false

    // ---- Brightness (first display in PowerDevil's list, internal panels first)
    readonly property bool brightnessAvailable: screenBrightness.isBrightnessAvailable && brightnessInfo.valid
    readonly property real brightness: brightnessInfo.valid && brightnessInfo.max > 0 ? brightnessInfo.value / brightnessInfo.max : 0
    readonly property string displayLabel: brightnessInfo.label

    function setBrightness(fraction: real) {
        if (!brightnessInfo.valid) {
            return;
        }
        const f = Math.max(0.01, Math.min(1, fraction));
        screenBrightness.setBrightness(brightnessInfo.displayName, Math.round(f * brightnessInfo.max));
    }

    ScreenBrightnessControl {
        id: screenBrightness
        isSilent: display.silent
    }

    QtObject {
        id: brightnessInfo
        property bool valid: false
        property string displayName: ""
        property string label: ""
        property int value: 0
        property int max: 0
    }

    Connections {
        id: displayWatcher
        target: screenBrightness.displays

        function update() {
            const model = screenBrightness.displays;
            if (!model || model.rowCount() === 0) {
                brightnessInfo.valid = false;
                return;
            }
            const roles = model.KItemModels.KRoleNames;
            let row = 0;
            const internalRole = roles.role("isInternal");
            if (internalRole >= 0) {
                for (let i = 0; i < model.rowCount(); ++i) {
                    if (model.data(model.index(i, 0), internalRole)) {
                        row = i;
                        break;
                    }
                }
            }
            const index = model.index(row, 0);
            brightnessInfo.displayName = model.data(index, roles.role("displayName")) || "";
            brightnessInfo.label = model.data(index, roles.role("label")) || "";
            brightnessInfo.value = model.data(index, roles.role("brightness")) || 0;
            brightnessInfo.max = model.data(index, roles.role("maxBrightness")) || 0;
            brightnessInfo.valid = brightnessInfo.displayName.length > 0 && brightnessInfo.max > 0;
        }
        function onDataChanged() { update(); }
        function onModelReset() { update(); }
        function onRowsInserted() { update(); }
        function onRowsRemoved() { update(); }
        function onRowsMoved() { update(); }
    }
    Component.onCompleted: displayWatcher.update()

    // ---- Night Light (KWin)
    DBus.Properties {
        id: nightLight
        busType: DBus.BusType.Session
        service: "org.kde.KWin.NightLight"
        path: "/org/kde/KWin/NightLight"
        iface: "org.kde.KWin.NightLight"
    }

    readonly property bool nightAvailable: Boolean(nightLight.properties.available)
    readonly property bool nightEnabled: Boolean(nightLight.properties.enabled)
    readonly property bool nightRunning: Boolean(nightLight.properties.running)
    readonly property bool nightInhibited: Boolean(nightLight.properties.inhibited)
    readonly property bool nightInhibitedHere: NightLightInhibitor.inhibited
    readonly property int nightMode: Number(nightLight.properties.mode)
    readonly property bool nightDaylight: Boolean(nightLight.properties.daylight)
    readonly property int nightCurrentTemperature: Number(nightLight.properties.currentTemperature)
    readonly property int nightTargetTemperature: Number(nightLight.properties.targetTemperature)
    readonly property double nightTransitionEnd: Number(nightLight.properties.previousTransitionDateTime) * 1000 + Number(nightLight.properties.previousTransitionDuration)
    readonly property double nightNextTransition: Number(nightLight.properties.scheduledTransitionDateTime) * 1000
    readonly property bool nightActive: nightRunning && nightCurrentTemperature !== 6500 && nightCurrentTemperature > 0

    function toggleNightLightInhibition() {
        NightLightInhibitor.toggleInhibition();
    }

    // ---- Light / dark Global Theme pairing (kdeglobals [KDE] DefaultLight/DarkLookAndFeel)
    readonly property bool darkModeFromPairing: DarkModeControl.darkMode
    readonly property string currentTheme: DarkModeControl.currentTheme
    readonly property string otherTheme: DarkModeControl.otherTheme

    function setDarkMode(on: bool) {
        DarkModeControl.darkMode = on;
    }
}
