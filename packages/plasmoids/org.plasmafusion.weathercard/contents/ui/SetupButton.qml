/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

// "Set location" pill of the weather card (no board: a compact button in the card's own type
// and tint, keyboard reachable, with the boards' focus ring).
MouseArea {
    id: button

    required property CardPalette pal
    property string text

    signal triggered()

    implicitWidth: row.implicitWidth + 24
    implicitHeight: 30
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: button.triggered()
    onClicked: button.triggered()
    Keys.onPressed: event => {
        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select].indexOf(event.key) !== -1) {
            button.triggered();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        antialiasing: true
        color: button.pressed ? button.pal.tint(0.18) : button.containsMouse ? button.pal.tint(0.14) : button.pal.tint(0.09)
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        LineGlyph {
            anchors.verticalCenter: parent.verticalCenter
            size: 15
            color: button.pal.label
            path: "M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11zM9.8 10a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0-4.4 0"
        }
        CardText {
            anchors.verticalCenter: parent.verticalCenter
            pal: button.pal
            px: 12.5
            weight: 700
            text: button.text
        }
    }

    Rectangle {
        visible: button.activeFocus
        anchors.fill: parent
        anchors.margins: -3
        radius: 13
        color: "transparent"
        border.width: 2
        border.color: button.pal.focusRing
    }
}
