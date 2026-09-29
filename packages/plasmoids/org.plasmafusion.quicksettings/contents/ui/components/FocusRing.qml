// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Keyboard focus indicator of the design: a 2 px ring 2 px outside the control.
Rectangle {
    id: ring

    property real baseRadius: 0
    property color ringColor: "#8ab8ff"
    property bool shown: false

    anchors.fill: parent
    anchors.margins: -4
    radius: baseRadius > 0 ? baseRadius + 4 : 0
    color: "transparent"
    border.width: 2
    border.color: ringColor
    visible: shown
}
