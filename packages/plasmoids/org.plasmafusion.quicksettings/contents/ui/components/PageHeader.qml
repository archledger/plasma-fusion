// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts

import "Icons.js" as Icons

// Header of a drill-down page: back button, title and an optional switch. The title and the
// gap follow the user's text size (`metrics`); the round back button and the switch do not.
RowLayout {
    id: header

    required property FusionPalette pal
    required property FusionMetrics metrics
    property string title: ""
    property bool hasSwitch: false
    property bool switchChecked: false
    property bool switchEnabled: true
    property string switchText: title

    readonly property alias backButton: backButton

    signal back()
    signal switchToggled(bool on)

    spacing: metrics.px(10)

    IconButton {
        id: backButton
        pal: header.pal
        size: 32
        iconSize: 15
        fill: header.pal.overlay(0.08)
        iconPath: Icons.chevronLeft
        text: i18nc("@action:button", "Back to quick settings")
        onClicked: header.back()
    }
    FText {
        Layout.fillWidth: true
        pal: header.pal
        metrics: header.metrics
        text: header.title
        px: 16
        font.weight: Font.ExtraBold
    }
    FusionSwitch {
        visible: header.hasSwitch
        pal: header.pal
        text: header.switchText
        checked: header.switchChecked
        enabled: header.switchEnabled
        onToggled: header.switchToggled(checked)
    }
}
