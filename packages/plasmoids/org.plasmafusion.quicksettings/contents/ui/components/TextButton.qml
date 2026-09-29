// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// Rounded text button ("Clear all", "Disconnect", notification actions).
T.AbstractButton {
    id: button

    required property FusionPalette pal
    property bool primary: false
    property real radius: height / 2
    property real sidePadding: 12
    property real fontSize: 12
    property int fontWeight: Font.Bold
    property color fill: primary ? pal.accent : pal.overlay(0.1)
    property color textColor: primary ? pal.accentText : pal.text
    property string iconPath: ""

    implicitHeight: 26
    implicitWidth: label.implicitWidth + 2 * sidePadding + (iconPath.length > 0 ? 20 : 0)
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.name: text
    Accessible.role: Accessible.Button
    opacity: enabled ? 1 : 0.5

    Keys.onReturnPressed: button.clicked()
    Keys.onEnterPressed: button.clicked()

    background: Rectangle {
        radius: button.radius
        color: {
            if (button.primary) {
                return button.down ? Qt.darker(button.fill, 1.12) : (button.hovered ? Qt.lighter(button.fill, 1.1) : button.fill);
            }
            if (button.down) {
                return Qt.rgba(button.fill.r, button.fill.g, button.fill.b, Math.min(1, button.fill.a + 0.08));
            }
            return button.hovered ? Qt.rgba(button.fill.r, button.fill.g, button.fill.b, Math.min(1, button.fill.a + 0.05)) : button.fill;
        }
        Behavior on color { ColorAnimation { duration: 120 } }

        FocusRing {
            baseRadius: button.radius
            ringColor: button.pal.focus
            shown: button.visualFocus
        }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            LineIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.iconPath.length > 0
                size: 14
                path: button.iconPath
                color: button.textColor
            }
            FText {
                id: label
                pal: button.pal
                anchors.verticalCenter: parent.verticalCenter
                text: button.text
                color: button.textColor
                px: button.fontSize
                font.weight: button.fontWeight
                width: Math.min(implicitWidth, button.width - 2 * button.sidePadding - (button.iconPath.length > 0 ? 20 : 0))
            }
        }
    }
}
