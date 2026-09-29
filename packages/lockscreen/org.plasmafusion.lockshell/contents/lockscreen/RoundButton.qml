// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// A round icon button (Login board: 36 px reveal/submit buttons in the password pill,
// 38 px play button on the media card).
T.AbstractButton {
    id: button

    property string iconPath: ""
    property string glyphPath: ""
    property real iconSize: 18
    property color fillColor: "transparent"
    property color hoverFillColor: PfStyle.chipFillHover
    property color foreground: PfStyle.textMuted

    implicitWidth: 36
    implicitHeight: 36
    hoverEnabled: true
    focusPolicy: Qt.TabFocus

    Accessible.name: text

    background: Rectangle {
        radius: height / 2
        antialiasing: true
        color: button.hovered || button.visualFocus ? button.hoverFillColor : button.fillColor
        opacity: button.down ? 0.8 : 1

        FocusRing {
            visible: button.visualFocus
        }
    }

    contentItem: Item {
        LineIcon {
            anchors.centerIn: parent
            size: button.iconSize
            path: button.iconPath
            fillPath: button.glyphPath
            color: button.foreground
            fillColor: button.foreground
        }
    }

    Keys.onEnterPressed: clicked()
    Keys.onReturnPressed: clicked()
}
