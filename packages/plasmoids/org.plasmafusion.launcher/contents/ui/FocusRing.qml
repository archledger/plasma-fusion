/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Keyboard focus indicator of the Controls board: 2 px accent ring with a 2 px gap.
Rectangle {
    id: ring

    property real baseRadius: 0
    property real gap: 2
    property color ringColor: "#8ab8ff"

    anchors.fill: parent
    anchors.margins: -(gap + 2)
    radius: baseRadius > 0 ? baseRadius + gap + 2 : 0
    color: "transparent"
    border.width: 2
    border.color: ringColor
    antialiasing: true
}
