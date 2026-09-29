// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Controls board keyboard focus (dark scheme): a 2 px #8ab8ff ring 2 px outside the control.
Rectangle {
    id: ring

    property real controlRadius: height / 2

    anchors.fill: parent
    anchors.margins: -4
    radius: controlRadius + 4
    color: "transparent"
    border.width: 2
    border.color: PfStyle.focusRing
    antialiasing: true
}
