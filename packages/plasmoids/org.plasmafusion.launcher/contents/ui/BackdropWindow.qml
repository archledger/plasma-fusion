/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore

// Dim layer behind the open launcher (board: rgba(6,8,18,0.4) dark, rgba(221,230,244,0.35) light).
// A normal-layer window without decoration, so panels and the launcher stay above it.
PlasmaCore.Dialog {
    id: backdrop

    property rect area: Qt.rect(0, 0, 1, 1)
    property color dimColor: Qt.rgba(6 / 255, 8 / 255, 18 / 255, 0.4)

    signal clicked()

    type: PlasmaCore.Dialog.Normal
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    hideOnWindowDeactivate: false
    x: area.x
    y: area.y

    mainItem: Rectangle {
        width: Math.max(1, backdrop.area.width)
        height: Math.max(1, backdrop.area.height)
        Layout.minimumWidth: width
        Layout.maximumWidth: width
        Layout.minimumHeight: height
        Layout.maximumHeight: height
        color: backdrop.dimColor

        MouseArea {
            // A pointer convenience over the dimmed screen (Esc and the button close the launcher).
            Accessible.ignored: true
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: backdrop.clicked()
        }
    }
}
