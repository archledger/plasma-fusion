/* SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * The board's session pill (Login.dc.html, bottom left): the Fusion three-circle mark, the chosen
 * session's name and a chevron opening the list (sessionModel: name, exec, comment, lastIndex).
 * The name is read in the delegates (the model is a QAbstractItemModel; no get()).
 */

import QtQuick 2.15
import "palette.js" as Palette

Item {
    id: session
    width: pill.width
    height: 40

    property int index: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property string selectedName: ""

    function choose(i, name) {
        index = i;
        selectedName = name;
        menu.open = false;
    }

    Rectangle {
        id: pill
        height: 40
        radius: 20
        color: Palette.fill
        border.color: Palette.stroke
        border.width: 1
        width: row.implicitWidth + 26
        Accessible.name: qsTr("Session: %1", "the chosen session's name").arg(session.selectedName)

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10

            // The Fusion mark: three overlapping circles (the board's session logo)
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                Rectangle { x: 3; y: 0; width: 11; height: 11; radius: 6; color: Palette.accent; opacity: 0.9 }
                Rectangle { x: 0; y: 6; width: 11; height: 11; radius: 6; color: "#f2a65a"; opacity: 0.9 }
                Rectangle { x: 8; y: 6; width: 11; height: 11; radius: 6; color: "#3cc4b0"; opacity: 0.85 }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Palette.bodyFont
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Palette.ink
                text: session.selectedName !== "" ? session.selectedName : qsTr("Session")
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Palette.bodyFont
                font.pixelSize: 12
                color: Palette.inkSoft
                text: "\u25be"
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: menu.open = !menu.open
        }
    }

    // The session list (the board's chevron menu)
    Rectangle {
        id: menu
        property bool open: false
        visible: open
        anchors.bottom: pill.top
        anchors.bottomMargin: 8
        anchors.horizontalCenter: pill.horizontalCenter
        width: 240
        height: list.implicitHeight + 8
        radius: 12
        color: "#f2141a2e"
        border.color: Palette.stroke
        border.width: 1

        Column {
            id: list
            x: 4
            y: 4
            width: parent.width - 8
            Repeater {
                model: sessionModel
                delegate: Rectangle {
                    width: list.width
                    height: 32
                    radius: 8
                    color: session.index === index ? Palette.fill : "transparent"

                    Accessible.name: String(model.name || "")
                    Component.onCompleted: {
                        // The model's first answer names the pill (lastIndex, else the first)
                        if (session.selectedName === "" && index === session.index) {
                            session.selectedName = String(model.name || "");
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        font.family: Palette.bodyFont
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Palette.ink
                        text: String(model.name || "")
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: session.choose(index, String(model.name || ""))
                    }
                }
            }
        }
    }
}
