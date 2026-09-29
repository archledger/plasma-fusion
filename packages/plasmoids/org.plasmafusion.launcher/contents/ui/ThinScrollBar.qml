/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T

// Thin overlay scrollbar of the Controls board: 5 px handle at 30 % alpha.
T.ScrollBar {
    id: bar

    property FusionColors pal

    implicitWidth: 9
    padding: 2
    minimumSize: 0.08
    policy: T.ScrollBar.AsNeeded

    contentItem: Rectangle {
        implicitWidth: 5
        radius: 2.5
        color: bar.pal ? bar.pal.tint(bar.pressed ? 0.45 : 0.30) : "gray"
        opacity: bar.active || bar.hovered ? 1 : 0.6
        antialiasing: true
    }
}
