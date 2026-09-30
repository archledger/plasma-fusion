/*
    A 40 px setting row with a switch on the right (Main board toggles): 13 px label, 1 px line
    under every row but the last (a CSS border-bottom, so those rows are 41 px apart); the switch
    is 40 x 22 with an 18 px knob. The whole row toggles.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

T.AbstractButton {
    id: row

    required property FusionPalette pal
    property bool last: false
    property string note

    implicitHeight: 40 + (last ? 0 : 1) + (noteLabel.visible ? noteLabel.implicitHeight + 2 : 0)
    implicitWidth: label.implicitWidth + 16 + 40
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.checked: checked
    Accessible.checkable: true
    Accessible.onPressAction: row.requestToggle()
    Accessible.onToggleAction: row.requestToggle()

    // The row is not checkable itself: changes go through the module, and checked is bound to
    // the module's value.
    signal toggleRequested
    function requestToggle() {
        if (enabled) {
            toggleRequested();
        }
    }
    onClicked: requestToggle()

    background: Item {
        Rectangle {
            visible: !row.last
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: row.pal.rowLine
        }
    }

    contentItem: Item {
        Text {
            id: label
            y: (40 - height) / 2
            anchors.left: parent.left
            anchors.right: track.left
            anchors.rightMargin: 16
            elide: Text.ElideRight
            text: row.text
            font.family: row.pal.family
            font.pixelSize: 13
            color: row.pal.text
        }
        Text {
            id: noteLabel
            visible: row.note !== ""
            anchors.left: parent.left
            anchors.right: track.left
            anchors.rightMargin: 16
            y: 30
            wrapMode: Text.WordWrap
            text: row.note
            font.family: row.pal.family
            font.pointSize: 8.625 // 11.5 px (pixelSize is an integer)
            color: row.pal.section
        }

        Rectangle {
            id: track
            anchors.right: parent.right
            y: (40 - height) / 2
            width: 40
            height: 22
            radius: 11
            color: row.checked ? row.pal.accent : row.pal.switchOff
            Behavior on color {
                ColorAnimation {
                    duration: Kirigami.Units.shortDuration
                }
            }

            Kirigami.ShadowedRectangle {
                width: 18
                height: 18
                radius: 9
                y: 2
                x: row.checked ? track.width - width - 2 : 2
                color: row.checked ? "#ffffff" : row.pal.knobOff
                // Light board: the knob of an unchecked switch has a small shadow.
                shadow.size: !row.pal.dark && !row.checked ? 3 : 0
                shadow.yOffset: 1
                shadow.color: Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.3)
                Behavior on x {
                    NumberAnimation {
                        duration: Kirigami.Units.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            // Keyboard focus ring around the switch.
            Rectangle {
                visible: row.visualFocus
                anchors.fill: parent
                anchors.margins: -4
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: row.pal.focusRing
            }
        }
    }
}
