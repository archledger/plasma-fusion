/*
    One Style choice: a 124 x 72 preview of the desktop (top bar, window, dock) with its name
    below (Main board "Style": Light, Dark, Follow sunset).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

T.AbstractButton {
    id: card

    required property FusionPalette pal
    // 0 light, 1 dark, 2 follow sunset (light and dark halves)
    property int variant: 0
    property bool selected: false

    implicitWidth: 124
    // card, 6 px gap, one 12 px line (17 px)
    implicitHeight: 72 + 6 + 17
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.RadioButton
    Accessible.name: text
    Accessible.checked: selected
    Accessible.onPressAction: card.clicked()

    contentItem: Item {
        Item {
            id: frame
            width: 124
            height: 72

            // The CSS background runs under the 2 px border.
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: card.variant === 0 ? "#e9ecf3" : card.variant === 1 ? "#1d2440" : "transparent"
            }
            // Contents are placed in the padding box (inside the border), corners 8 px.
            Item {
                x: 2
                y: 2
                width: 120
                height: 68

                // Light / dark: top bar, a window, the dock.
                Rectangle {
                    visible: card.variant !== 2
                    width: 120
                    height: 8
                    topLeftRadius: 8
                    topRightRadius: 8
                    color: card.variant === 0 ? "#ffffff" : "#11152a"
                }
                Kirigami.ShadowedRectangle {
                    visible: card.variant !== 2
                    x: 14
                    y: 16
                    width: 62
                    height: 36
                    radius: 5
                    color: card.variant === 0 ? "#ffffff" : "#2a3150"
                    shadow.size: 6
                    shadow.yOffset: 2
                    shadow.color: card.variant === 0 ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(0, 0, 0, 0.3)
                }
                Rectangle {
                    visible: card.variant !== 2
                    x: 36
                    y: 68 - 5 - 8
                    width: 48
                    height: 8
                    radius: 4
                    color: card.variant === 0 ? "#ffffff" : "#2a3150"
                }

                // Follow sunset: light half, dark half, a window across both.
                Rectangle {
                    visible: card.variant === 2
                    width: 60
                    height: 68
                    topLeftRadius: 8
                    bottomLeftRadius: 8
                    color: "#e9ecf3"
                }
                Rectangle {
                    visible: card.variant === 2
                    x: 60
                    width: 60
                    height: 68
                    topRightRadius: 8
                    bottomRightRadius: 8
                    color: "#1d2440"
                }
                Rectangle {
                    visible: card.variant === 2
                    x: 38
                    y: 16
                    width: 46
                    height: 36
                    radius: 5
                    color: "#6b7390"
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                border.width: 2
                border.color: card.selected ? card.pal.cardSelected
                    : (card.hovered || card.down) ? card.pal.cardHover : card.pal.cardBorder
                Behavior on border.color {
                    ColorAnimation {
                        duration: Kirigami.Units.shortDuration
                    }
                }
            }
            // Keyboard focus: a 2 px ring 2 px outside the card.
            Rectangle {
                visible: card.visualFocus
                anchors.fill: parent
                anchors.margins: -4
                radius: 14
                color: "transparent"
                border.width: 2
                border.color: card.pal.focusRing
            }
        }

        Text {
            id: nameLabel
            anchors.horizontalCenter: frame.horizontalCenter
            y: frame.height + 6
            text: card.text
            font.family: card.pal.family
            font.pixelSize: 12
            font.weight: card.selected ? Font.ExtraBold : Font.Normal
            color: card.selected ? card.pal.labelSelected : card.pal.label
        }
    }
}
