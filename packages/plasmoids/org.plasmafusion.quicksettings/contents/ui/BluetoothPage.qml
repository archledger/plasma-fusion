// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "components"
import "components/Icons.js" as Icons

// Bluetooth drill-down: switch, paired devices (click to connect or
// disconnect), pairing and settings links. Same layout as the Wi-Fi panel.
ColumnLayout {
    id: page

    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    property real listMaxHeight: metrics.px(230)

    signal back()

    readonly property Item firstFocusItem: header.backButton

    spacing: metrics.px(12)

    PageHeader {
        id: header
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        title: i18nc("@title", "Bluetooth")
        hasSwitch: true
        switchChecked: page.backend.bt.enabled
        switchEnabled: page.backend.bt.available
        onBack: page.back()
        onSwitchToggled: on => page.backend.bt.setEnabled(on)
    }

    FText {
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        leftPadding: page.metrics.px(4)
        visible: list.visible
        text: i18nc("@title:group", "Devices").toUpperCase()
        color: page.pal.tertiary
        px: 11
        font.weight: Font.ExtraBold
        font.letterSpacing: page.metrics.font(0.88)
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(contentHeight, page.listMaxHeight)
        Layout.maximumHeight: contentHeight
        visible: page.backend.bt.enabled && count > 0
        clip: true
        spacing: page.metrics.px(2)
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: page.backend.bt.enabled ? page.backend.bt.devicesModel : null

        delegate: ListRow {
            required property var model
            required property int index

            width: ListView.view.width
            pal: page.pal
            metrics: page.metrics
            text: model.DeviceFullName || model.Name || ""
            iconName: model.Icon || "preferences-system-bluetooth"
            selected: !!model.Connected
            busy: !!model.Connecting || !!model.Disconnecting
            status: {
                if (model.Connecting) {
                    return i18nc("@info:status", "Connecting…");
                }
                if (model.Disconnecting) {
                    return i18nc("@info:status", "Disconnecting…");
                }
                if (model.Connected) {
                    return model.Battery ? i18nc("@info:status %1 battery percent", "Connected · %1%", model.Battery.percentage)
                                         : i18nc("@info:status", "Connected");
                }
                return "";
            }
            trailingPath: model.Connected ? Icons.check : ""
            onClicked: page.backend.bt.toggleDevice(model.Device, model.Ubi, !!model.Connected)
        }
    }

    FText {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: page.metrics.px(44)
        pal: page.pal
        metrics: page.metrics
        visible: !list.visible
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: page.pal.secondary
        text: {
            if (!page.backend.bt.available) {
                return i18nc("@info", "No Bluetooth adapter found");
            }
            if (!page.backend.bt.enabled) {
                return i18nc("@info", "Bluetooth is off");
            }
            return i18nc("@info", "No paired devices");
        }
    }

    Item {
        Layout.fillHeight: true
        visible: list.visible
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: page.pal.overlay(0.08)
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: page.metrics.px(8)

        TextButton {
            pal: page.pal
            metrics: page.metrics
            implicitHeight: page.metrics.px(32)
            sidePadding: 0
            fill: "transparent"
            textColor: page.pal.link
            fontSize: 12.5
            enabled: page.backend.bt.enabled
            text: i18nc("@action:button", "Pair a new device…")
            onClicked: page.backend.bt.pairNew()
        }
        Item {
            Layout.fillWidth: true
        }
        TextButton {
            pal: page.pal
            metrics: page.metrics
            implicitHeight: page.metrics.px(32)
            radius: height / 2
            sidePadding: page.metrics.px(14)
            fill: page.pal.overlay(0.08)
            fontSize: 12.5
            iconPath: Icons.settingsSmall
            text: i18nc("@action:button", "Bluetooth settings")
            onClicked: page.backend.bt.openSettings()
        }
    }
}
