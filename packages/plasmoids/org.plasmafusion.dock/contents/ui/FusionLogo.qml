/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick

// The Plasma Fusion mark: three overlapping circles (viewBox 24, r 5.5).
Item {
    id: logo

    property real size: 28
    readonly property real unit: size / 24

    width: size
    height: size

    component Disc: Rectangle {
        required property real cx
        required property real cy
        x: (cx - 5.5) * logo.unit
        y: (cy - 5.5) * logo.unit
        width: 11 * logo.unit
        height: width
        radius: width / 2
        antialiasing: true
    }

    Disc { cx: 12; cy: 8.5; color: Qt.rgba(91 / 255, 157 / 255, 1, 0.9) }
    Disc { cx: 8; cy: 15; color: Qt.rgba(242 / 255, 166 / 255, 90 / 255, 0.9) }
    Disc { cx: 16; cy: 15; color: Qt.rgba(60 / 255, 196 / 255, 176 / 255, 0.85) }
}
