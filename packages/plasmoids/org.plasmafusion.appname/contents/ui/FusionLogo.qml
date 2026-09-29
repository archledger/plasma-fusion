/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// The Plasma Fusion mark: three overlapping circles on a 24x24 grid (r 5.5 at
// 12,8.5 #5b9dff .9; 8,15 #f2a65a .9; 16,15 #3cc4b0 .85).
Item {
    id: logo

    property real size: 24
    readonly property real unit: size / 24

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    component Dot: Rectangle {
        required property real cx
        required property real cy
        required property real unit
        x: (cx - 5.5) * unit
        y: (cy - 5.5) * unit
        width: 11 * unit
        height: width
        radius: width / 2
        antialiasing: true
    }

    Dot { cx: 12; cy: 8.5; unit: logo.unit; color: "#5b9dff"; opacity: 0.9 }
    Dot { cx: 8; cy: 15; unit: logo.unit; color: "#f2a65a"; opacity: 0.9 }
    Dot { cx: 16; cy: 15; unit: logo.unit; color: "#3cc4b0"; opacity: 0.85 }
}
