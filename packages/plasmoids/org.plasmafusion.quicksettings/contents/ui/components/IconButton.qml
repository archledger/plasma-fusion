// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T
import org.kde.plasma.core as PlasmaCore

// Round button with a line icon (header buttons, chevrons, media controls).
T.AbstractButton {
    id: button

    required property FusionPalette pal
    property string iconPath: ""
    property string iconFillPath: ""
    property real iconSize: 17
    property real size: 34
    property color fill: pal.overlay(0.07)
    property color hoverFill: pal.overlay(0.12)
    property color pressFill: pal.overlay(0.16)
    property color iconColor: pal.controlText
    property string toolTip: text

    implicitWidth: size
    implicitHeight: size
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.name: text
    Accessible.role: Accessible.Button
    opacity: enabled ? 1 : 0.45

    Keys.onReturnPressed: button.clicked()
    Keys.onEnterPressed: button.clicked()

    background: Rectangle {
        radius: height / 2
        color: button.down ? button.pressFill : (button.hovered ? button.hoverFill : button.fill)
        Behavior on color { ColorAnimation { duration: 120 } }

        FocusRing {
            baseRadius: parent.radius
            ringColor: button.pal.focus
            shown: button.visualFocus
        }
    }

    contentItem: Item {
        LineIcon {
            anchors.centerIn: parent
            size: button.iconSize
            path: button.iconPath
            fillPath: button.iconFillPath
            fillStroked: true
            color: button.iconColor
        }
    }

    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: button.toolTip
        active: button.toolTip.length > 0
        location: PlasmaCore.Types.Floating
    }
}
