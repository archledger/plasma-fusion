/*
    One accent colour: a 26 px disc; the chosen one has the board's double ring
    (box-shadow 0 0 0 2px page, 0 0 0 4px colour).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

T.AbstractButton {
    id: swatch

    required property FusionPalette pal
    property color color: "#5b9dff"
    property bool selected: false

    implicitWidth: 26
    implicitHeight: 26
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.RadioButton
    Accessible.name: text
    Accessible.checked: selected
    Accessible.onPressAction: swatch.clicked()

    QQC2.ToolTip.text: text
    QQC2.ToolTip.visible: hovered
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

    background: Item {
        // Selection: outer ring in the swatch colour, gap in the page colour.
        Rectangle {
            visible: swatch.selected
            anchors.centerIn: parent
            width: 34
            height: 34
            radius: 17
            color: swatch.color
        }
        Rectangle {
            visible: swatch.selected
            anchors.centerIn: parent
            width: 30
            height: 30
            radius: 15
            color: swatch.pal.pageBackground
        }
        Rectangle {
            anchors.centerIn: parent
            width: 26
            height: 26
            radius: 13
            color: swatch.color
            scale: swatch.down ? 0.92 : (swatch.hovered && !swatch.selected ? 1.08 : 1)
            Behavior on scale {
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        // Keyboard focus: a ring in the focus colour, outside the selection ring when both show.
        Rectangle {
            visible: swatch.visualFocus
            anchors.centerIn: parent
            width: swatch.selected ? 40 : 34
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: swatch.pal.focusRing
        }
    }
}
